import CueCore
import Foundation

/// Resolves provider credentials from the user-owned local configuration file.
/// The file remains at the stable Cue path and is restricted to the current user (0600).
enum CueAPIKeyStoreError: LocalizedError {
    case unsupportedSchema
    case corruptConfiguration

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "This configuration was created by a newer version of Cue."
        case .corruptConfiguration:
            "The Cue configuration is corrupt and was left unchanged."
        }
    }
}

enum CueAPIKeySource: Equatable {
    case configuration
}

enum CueAPIKeyStore {
    static let currentSchemaVersion = 2
    /// Test-only override; production uses the stable Application Support path.
    static var configurationURLOverride: URL?

    private static var fileURL: URL {
        if let configurationURLOverride { return configurationURLOverride }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cue Notchpad", isDirectory: true)
        return directory.appendingPathComponent("config.json")
    }

    private static var versionOneBackupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("config.v1.backup.json")
    }

    static func loadAPIKey(for provider: CueAIProviderID) throws -> String? {
        try resolveAPIKey(for: provider)?.key
    }

    static func source(for provider: CueAIProviderID) throws -> CueAPIKeySource? {
        try resolveAPIKey(for: provider)?.source
    }

    static func hasStoredAPIKey(for provider: CueAIProviderID) throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let document = try configuration(at: fileURL)
        if let keys = try providerKeys(in: document),
           let key = keys[provider.rawValue] as? String,
           !key.isEmpty
        {
            return true
        }
        let version = document["schemaVersion"] as? Int ?? 0
        return version < currentSchemaVersion
            && provider == .deepSeek
            && (document["deepSeekAPIKey"] as? String)?.isEmpty == false
    }

    static func saveAPIKey(_ key: String, for provider: CueAIProviderID) throws {
        var document = try writableConfiguration()
        var keys = try providerKeys(in: document) ?? [:]
        keys[provider.rawValue] = key
        document["providerAPIKeys"] = keys
        try persist(document)
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        let document = try configuration(at: fileURL)
        guard let keys = try providerKeys(in: document),
              let key = keys[profileID] as? String
        else { return false }
        return !key.isEmpty
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
        // The legacy field remains readable only for the existing provider API.
        let version = document["schemaVersion"] as? Int ?? 0
        if version < currentSchemaVersion,
           legacyProvider == .deepSeek,
           let key = document["deepSeekAPIKey"] as? String,
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
            return ["schemaVersion": currentSchemaVersion, "providerAPIKeys": [:]]
        }
        let sourceData = try Data(contentsOf: fileURL)
        var document = try configuration(from: sourceData)
        let storedVersion = document["schemaVersion"] as? Int ?? 0
        guard storedVersion <= currentSchemaVersion else {
            throw CueAPIKeyStoreError.unsupportedSchema
        }
        if storedVersion < currentSchemaVersion {
            try migrateVersionOne(&document, sourceData: sourceData)
        } else {
            _ = try providerKeys(in: document)
        }
        return document
    }

    private static func migrateVersionOne(
        _ document: inout [String: Any],
        sourceData: Data
    ) throws {
        guard (document["schemaVersion"] as? Int ?? 0) == 1 else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        if !FileManager.default.fileExists(atPath: versionOneBackupURL.path) {
            let temporaryURL = versionOneBackupURL
                .deletingLastPathComponent()
                .appendingPathComponent(".config.v1.backup.\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try sourceData.write(to: temporaryURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporaryURL.path
            )
            do {
                // Publishing a hard link is atomic and refuses to overwrite a
                // backup another Cue process may have created concurrently.
                try FileManager.default.linkItem(at: temporaryURL, to: versionOneBackupURL)
            } catch CocoaError.fileWriteFileExists {
                // Another process completed the same idempotent migration.
            }
        }
        var keys = try providerKeys(in: document) ?? [:]
        if keys[CueAIProviderID.deepSeek.rawValue] == nil,
           let legacyKey = document["deepSeekAPIKey"] as? String
        {
            keys[CueAIProviderID.deepSeek.rawValue] = legacyKey
        }
        document["providerAPIKeys"] = keys
        document["schemaVersion"] = currentSchemaVersion
    }

    private static func providerKeys(in document: [String: Any]) throws -> [String: Any]? {
        guard let value = document["providerAPIKeys"] else { return nil }
        guard let keys = value as? [String: Any] else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        return keys
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
        guard let document = object as? [String: Any],
              document["schemaVersion"] is Int
        else {
            throw CueAPIKeyStoreError.corruptConfiguration
        }
        return document
    }
}
