import CueCore
import Foundation

/// Resolves provider credentials from the user-owned local configuration file.
/// The file remains at the stable Cue path and is restricted to the current user (0600).
enum CueAPIKeyStoreError: LocalizedError {
    case corruptConfiguration

    var errorDescription: String? {
        switch self {
        case .corruptConfiguration:
            "The Cue configuration is corrupt and was left unchanged."
        }
    }
}

enum CueAPIKeySource: Equatable {
    case configuration
}

enum CueAPIKeyStore {
    /// Test-only override; production uses the stable Application Support path.
    static var configurationURLOverride: URL?

    private static var fileURL: URL {
        if let configurationURLOverride { return configurationURLOverride }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cue Notchpad", isDirectory: true)
        return directory.appendingPathComponent("config.json")
    }

    static func loadAPIKey(for provider: CueAIProviderID) throws -> String? {
        try resolveAPIKey(for: provider)?.key
    }

    static func source(for provider: CueAIProviderID) throws -> CueAPIKeySource? {
        try resolveAPIKey(for: provider)?.source
    }

    static func hasStoredAPIKey(for provider: CueAIProviderID) throws -> Bool {
        try loadAPIKey(for: provider) != nil
    }

    static func saveAPIKey(_ key: String, for provider: CueAIProviderID) throws {
        try saveAPIKey(key, forProfileID: provider.rawValue)
    }

    static func removeAPIKey(for provider: CueAIProviderID) throws {
        try removeAPIKey(forProfileID: provider.rawValue)
    }

    static func loadAPIKey(forProfileID profileID: String) throws -> String? {
        try resolveAPIKey(forProfileID: profileID)?.key
    }

    static func source(forProfileID profileID: String) throws -> CueAPIKeySource? {
        try resolveAPIKey(forProfileID: profileID)?.source
    }

    static func hasStoredAPIKey(forProfileID profileID: String) throws -> Bool {
        try loadAPIKey(forProfileID: profileID) != nil
    }

    static func saveAPIKey(_ key: String, forProfileID profileID: String) throws {
        var document = try writableConfiguration()
        var keys = try providerKeys(in: document) ?? [:]
        keys[profileID] = key
        document["providerAPIKeys"] = keys
        try persist(document)
    }

    static func removeAPIKey(forProfileID profileID: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var document = try writableConfiguration()
        var keys = try providerKeys(in: document) ?? [:]
        keys.removeValue(forKey: profileID)
        document["providerAPIKeys"] = keys
        try persist(document)
    }

    private static func resolveAPIKey(
        for provider: CueAIProviderID
    ) throws -> (key: String, source: CueAPIKeySource)? {
        try resolveAPIKey(forProfileID: provider.rawValue, legacyProvider: provider)
    }

    private static func resolveAPIKey(
        forProfileID profileID: String,
        legacyProvider: CueAIProviderID? = nil
    ) throws -> (key: String, source: CueAPIKeySource)? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let document = try configuration(at: fileURL)
        if let keys = try providerKeys(in: document),
           let key = keys[profileID] as? String,
           !key.isEmpty
        {
            return (key, .configuration)
        }
        if legacyProvider == .deepSeek,
           let key = try legacyDeepSeekKey(in: document),
           !key.isEmpty
        {
            return (key, .configuration)
        }
        return nil
    }

    private static func writableConfiguration() throws -> [String: Any] {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ["providerAPIKeys": [:]]
        }

        var document = try configuration(at: fileURL)
        var keys = try providerKeys(in: document) ?? [:]
        if let legacyKey = try legacyDeepSeekKey(in: document),
           keys[CueAIProviderID.deepSeek.rawValue] == nil
        {
            keys[CueAIProviderID.deepSeek.rawValue] = legacyKey
        }
        document["providerAPIKeys"] = keys
        document.removeValue(forKey: "deepSeekAPIKey")
        document.removeValue(forKey: "schemaVersion")
        return document
    }

    private static func providerKeys(in document: [String: Any]) throws -> [String: Any]? {
        guard let value = document["providerAPIKeys"] else { return nil }
        guard let keys = value as? [String: Any] else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        return keys
    }

    private static func legacyDeepSeekKey(in document: [String: Any]) throws -> String? {
        guard let value = document["deepSeekAPIKey"] else { return nil }
        guard let key = value as? String else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        return key
    }

    private static func persist(_ document: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(document) else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func configuration(at url: URL) throws -> [String: Any] {
        try configuration(from: Data(contentsOf: url))
    }

    private static func configuration(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        guard let document = object as? [String: Any] else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        return document
    }
}
