import Foundation

/// Loads CUE_DEEPSEEK_API_KEY first, then a user-owned local configuration file.
/// The file is deliberately restricted to the current user (0600); it is not Keychain-backed.
enum CueAPIKeyStoreError: LocalizedError {
    case unsupportedSchema

    var errorDescription: String? {
        "This configuration was created by a newer version of Cue."
    }
}

enum CueAPIKeyStore {
    private static let currentSchemaVersion = 1
    /// Test-only override; production always uses the stable Application Support path.
    static var configurationURLOverride: URL?

    private static var fileURL: URL {
        if let configurationURLOverride { return configurationURLOverride }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cue Notchpad", isDirectory: true)
        return directory.appendingPathComponent("config.json")
    }

    static func loadDeepSeekAPIKey() throws -> String? {
        if let value = ProcessInfo.processInfo.environment["CUE_DEEPSEEK_API_KEY"], !value.isEmpty { return value }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try configuration(at: fileURL)["deepSeekAPIKey"] as? String
    }

    static func saveDeepSeekAPIKey(_ key: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Preserve additive fields in supported documents. Future schemas are
        // read-only so this release can never overwrite unknown data.
        var document = (try? configuration(at: fileURL)) ?? [:]
        let storedVersion = document["schemaVersion"] as? Int ?? 0
        guard storedVersion <= currentSchemaVersion else {
            throw CueAPIKeyStoreError.unsupportedSchema
        }
        document["schemaVersion"] = currentSchemaVersion
        document["deepSeekAPIKey"] = key

        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func removeDeepSeekAPIKey() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var document = try configuration(at: fileURL)
        let storedVersion = document["schemaVersion"] as? Int ?? 0
        guard storedVersion <= currentSchemaVersion else {
            throw CueAPIKeyStoreError.unsupportedSchema
        }
        document.removeValue(forKey: "deepSeekAPIKey")
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func configuration(at url: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let document = object as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }
}
