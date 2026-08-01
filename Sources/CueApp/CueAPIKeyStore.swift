import Foundation

/// Loads CUE_DEEPSEEK_API_KEY first, then a user-owned local configuration file.
/// The file is deliberately restricted to the current user (0600); it is not Keychain-backed.
enum CueAPIKeyStore {
    private struct Configuration: Codable { var deepSeekAPIKey: String? }

    private static var fileURL: URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cue Notchpad", isDirectory: true)
        return directory.appendingPathComponent("config.json")
    }

    static func loadDeepSeekAPIKey() throws -> String? {
        if let value = ProcessInfo.processInfo.environment["CUE_DEEPSEEK_API_KEY"], !value.isEmpty { return value }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: fileURL)).deepSeekAPIKey
    }

    static func saveDeepSeekAPIKey(_ key: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Configuration(deepSeekAPIKey: key))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func removeDeepSeekAPIKey() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
