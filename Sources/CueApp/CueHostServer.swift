import CueCore
import Darwin
import Foundation

protocol CueHostServerDelegate: AnyObject {
    func hostServer(_ server: CueHostServer, received request: CueSessionRequest, fileDescriptor: Int32)
}

final class CueHostServer {
    weak var delegate: CueHostServerDelegate?
    private var listenFD: Int32 = -1
    private var serverThread: Thread?
    private var ownsSocket = false

    func start() throws {
        let socketURL = URL(fileURLWithPath: CueIPC.socketPath)
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        if FileManager.default.fileExists(atPath: socketURL.path) {
            if canConnectToExistingHost() {
                throw POSIXError(.EADDRINUSE)
            }
            var status = stat()
            guard lstat(socketURL.path, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFSOCK
            else {
                throw POSIXError(.EEXIST)
            }
            guard unlink(socketURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTSOCK) }
        do {
            try bindAndListen(fd)
        } catch {
            close(fd)
            throw error
        }
        listenFD = fd
        ownsSocket = true
        serverThread = Thread { [weak self] in self?.acceptPendingClients() }
        serverThread?.start()
    }

    func stop() {
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        serverThread = nil
        if ownsSocket {
            unlink(CueIPC.socketPath)
            ownsSocket = false
        }
    }

    deinit { stop() }

    private func bindAndListen(_ fd: Int32) throws {
        let path = CueIPC.socketPath.utf8CString
        var address = sockaddr_un()
        address.sun_len = UInt8(2 + path.count)
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        let addressLength = socklen_t(address.sun_len)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard chmod(CueIPC.socketPath, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func canConnectToExistingHost() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let path = CueIPC.socketPath.utf8CString
        guard path.count <= MemoryLayout<sockaddr_un>.size - 2 else { return false }
        var address = sockaddr_un()
        address.sun_len = UInt8(2 + path.count)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: path.map { UInt8(bitPattern: $0) })
        }
        let addressLength = socklen_t(address.sun_len)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addressLength) == 0
            }
        }
    }

    private func acceptPendingClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.readRequest(from: fd) }
        }
    }

    private func readRequest(from fd: Int32) {
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while bytes.count < CueIPC.maximumMessageBytes {
            let maximumRead = min(buffer.count, CueIPC.maximumMessageBytes - bytes.count)
            let count = Darwin.read(fd, &buffer, maximumRead)
            guard count > 0 else { close(fd); return }
            bytes.append(buffer, count: count)
            guard let terminator = bytes.firstIndex(of: 0x0A) else { continue }
            guard terminator == bytes.index(before: bytes.endIndex) else { close(fd); return }
            guard let request = try? JSONDecoder().decode(CueSessionRequest.self, from: bytes),
                  CueIPC.supports(version: request.version)
            else {
                Self.reply(.failed("Unsupported or invalid Cue IPC request."), to: fd)
                return
            }
            DispatchQueue.main.async { self.delegate?.hostServer(self, received: request, fileDescriptor: fd) }
            return
        }
        close(fd)
    }

    static func reply(_ response: CueSessionResponse, to fd: Int32) {
        guard let data = try? CueIPC.encode(response) else { close(fd); return }
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var remaining = raw.count
            while remaining > 0 {
                let count = Darwin.write(fd, pointer, remaining)
                guard count > 0 else { break }
                pointer = pointer.advanced(by: count)
                remaining -= count
            }
        }
        close(fd)
    }
}
