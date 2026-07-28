import CueCore
import Darwin
import Foundation

protocol CueHostServerDelegate: AnyObject { func hostServer(_ server: CueHostServer, received request: CueSessionRequest, fileDescriptor: Int32) }

final class CueHostServer {
    weak var delegate: CueHostServerDelegate?
    private var listenFD: Int32 = -1
    private var serverThread: Thread?

    func start() throws {
        let directory = URL(fileURLWithPath: CueIPC.socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        unlink(CueIPC.socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.ENOTSOCK) }
        let path = CueIPC.socketPath.utf8CString
        var address = sockaddr_un(); address.sun_len = UInt8(2 + path.count); address.sun_family = sa_family_t(AF_UNIX)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.map { UInt8(bitPattern: $0) }) }
        let addressLength = socklen_t(address.sun_len)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, addressLength) } }
        guard bound == 0, listen(listenFD, 32) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        chmod(CueIPC.socketPath, 0o600)
        serverThread = Thread { self.acceptPendingClients() }
        serverThread?.start()
    }

    func stop() { if listenFD >= 0 { close(listenFD); listenFD = -1 }; serverThread = nil; unlink(CueIPC.socketPath) }
    deinit { stop() }

    private func acceptPendingClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.readRequest(from: fd) }
        }
    }

    private func readRequest(from fd: Int32) {
        defer { }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while bytes.count <= CueIPC.maximumMessageBytes {
            let n = Darwin.read(fd, &buffer, buffer.count)
            guard n > 0 else { close(fd); return }
            bytes.append(buffer, count: n)
            if bytes.last == 0x0A { break }
        }
        guard bytes.count <= CueIPC.maximumMessageBytes, let request = try? JSONDecoder().decode(CueSessionRequest.self, from: bytes) else { close(fd); return }
        DispatchQueue.main.async { self.delegate?.hostServer(self, received: request, fileDescriptor: fd) }
    }

    static func reply(_ response: CueSessionResponse, to fd: Int32) {
        guard let data = try? CueIPC.encode(response) else { close(fd); return }
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var remaining = raw.count
            while remaining > 0 { let n = Darwin.write(fd, pointer, remaining); guard n > 0 else { break }; pointer = pointer.advanced(by: n); remaining -= n }
        }
        close(fd)
    }
}
