import Darwin
import Foundation

/// Serializes independent `cue --wait` processes so only one notch editor is
/// visible at a time. Every process retains its own stdin/stdout and waits for
/// the previous session to finish or be cancelled.
final class CueSessionLock {
    private let fileDescriptor: Int32

    init() throws {
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("dev.zen1th.cue-notepad", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        let path = cacheDirectory.appendingPathComponent("session.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        fileDescriptor = descriptor

        while flock(fileDescriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                close(fileDescriptor)
                throw error
            }
        }
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
