import CueCore
import Foundation

/// Resolves provider credentials from the provider's environment variables first,
/// then the user-owned local configuration file. The file remains at the stable
/// Cue path and is restricted to the current user (0600).
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
    case environment(String)
    case configuration
}

enum CueAPIKeyStore {
    static let currentSchemaVersion = 2
    /// Test-only overrides; production uses the stable Application Support path
    /// and the process environment.
    static var configurationURLOverride: URL?
    static var environmentOverride: [String: String]?

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var document = try writableConfiguration()
        var keys = try providerKeys(in: document) ?? [:]
        keys.removeValue(forKey: provider.rawValue)
        document["providerAPIKeys"] = keys
        try persist(document)
    }

    private static func resolveAPIKey(
        for provider: CueAIProviderID
    ) throws -> (key: String, source: CueAPIKeySource)? {
        let environment = environmentOverride ?? ProcessInfo.processInfo.environment
        for environmentKey in provider.environmentKeys {
            if let value = environment[environmentKey], !value.isEmpty {
                return (value, .environment(environmentKey))
            }
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let document = try configuration(at: fileURL)
        if let keys = try providerKeys(in: document),
           let key = keys[provider.rawValue] as? String,
           !key.isEmpty
        {
            return (key, .configuration)
        }
        // Schema v1 compatibility. Once a v2 document exists, providerAPIKeys
        // is authoritative so deleting DeepSeek does not revive this legacy copy.
        let version = document["schemaVersion"] as? Int ?? 0
        if version < currentSchemaVersion,
           provider == .deepSeek,
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
