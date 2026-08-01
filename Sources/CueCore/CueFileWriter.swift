import Foundation

/// Captures a file's original bytes before an interactive Cue session. The CLI
/// verifies this snapshot immediately before replacing the file, preventing a
/// silent overwrite of changes made by another editor while Cue was open.
public struct CueFileSnapshot: Sendable, Equatable {
    public let url: URL
    public let contents: Data

    public init(url: URL, contents: Data) {
        self.url = url
        self.contents = contents
    }
}

public enum CueFileWriteError: LocalizedError, Equatable {
    case changedByAnotherProcess

    public var errorDescription: String? {
        switch self {
        case .changedByAnotherProcess:
            "The file changed while it was being edited; Cue did not overwrite it."
        }
    }
}

public enum CueFileWriter {
    public static func snapshot(at url: URL) throws -> CueFileSnapshot {
        let targetURL = url.resolvingSymlinksInPath()
        return try CueFileSnapshot(url: targetURL, contents: Data(contentsOf: targetURL))
    }

    /// Atomically replaces the snapshot target only when it still contains the
    /// original bytes. `replaceItemAt` preserves destination metadata on macOS,
    /// including its permissions and extended attributes.
    public static func replace(
        with text: String,
        matching snapshot: CueFileSnapshot
    ) throws {
        let targetURL = snapshot.url
        guard try Data(contentsOf: targetURL) == snapshot.contents else {
            throw CueFileWriteError.changedByAnotherProcess
        }

        let directory = targetURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".cue-write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try Data(text.utf8).write(to: temporaryURL, options: [.withoutOverwriting])
        _ = try FileManager.default.replaceItemAt(
            targetURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )
    }
}
