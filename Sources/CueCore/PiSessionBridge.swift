import Darwin
import Foundation

public struct PiRewriteContext: Codable, Equatable, Sendable {
    public let version: Int
    public let sessionID: String
    public let leafID: String?
    public let message: String

    public init(version: Int, sessionID: String, leafID: String?, message: String) {
        self.version = version
        self.sessionID = sessionID
        self.leafID = leafID
        self.message = message
    }

    public var isValid: Bool {
        version == PiSessionBridge.protocolVersion
            && !sessionID.isEmpty
            && sessionID.utf8.count <= 128
            && (leafID?.utf8.count ?? 0) <= 128
            && message.utf8.count <= PiSessionBridge.maximumMessageBytes
    }
}

public enum PiSessionBridge {
    public static let protocolVersion = 1
    public static let socketEnvironmentKey = "CUE_PI_BRIDGE_SOCKET"
    public static let tokenEnvironmentKey = "CUE_PI_BRIDGE_TOKEN"
    public static let maximumMessageBytes = 256 * 1024
    // JSON escaping can expand control-heavy source text beyond its UTF-8 size.
    public static let maximumResponseBytes = 2 * 1024 * 1024

    public static func capture(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PiRewriteContext? {
        guard let socketPath = environment[socketEnvironmentKey],
              !socketPath.isEmpty,
              let token = environment[tokenEnvironmentKey],
              token.utf8.count == 64,
              token.allSatisfy(\.isHexDigit),
              let descriptor = connect(to: socketPath)
        else { return nil }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        let request: [String: Any] = ["version": protocolVersion, "token": token]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              writeAll(requestData + Data([0x0A]), to: descriptor),
              let responseData = readLine(from: descriptor),
              let context = try? JSONDecoder().decode(PiRewriteContext.self, from: responseData),
              context.isValid
        else { return nil }
        return context
    }

    private static func connect(to path: String) -> Int32? {
        let pathBytes = path.utf8CString
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_len = UInt8(2 + pathBytes.count)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes.map { UInt8(bitPattern: $0) })
        }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        let addressLength = socklen_t(address.sun_len)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { return false }
                pointer = pointer.advanced(by: count)
                remaining -= count
            }
            return true
        }
    }

    private static func readLine(from descriptor: Int32) -> Data? {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while result.count < maximumResponseBytes {
            let maximumRead = min(buffer.count, maximumResponseBytes - result.count)
            let count = Darwin.read(descriptor, &buffer, maximumRead)
            guard count > 0 else { return nil }
            result.append(buffer, count: count)
            guard let newline = result.firstIndex(of: 0x0A) else { continue }
            guard newline == result.index(before: result.endIndex) else { return nil }
            result.removeLast()
            return result
        }
        return nil
    }
}
