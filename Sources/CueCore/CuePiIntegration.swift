import CryptoKit
import Foundation

public enum PiIntegrationState: Equatable, Sendable {
    case notInstalled
    case installed(version: Int)
    case needsRepair(installedVersion: Int)
    case foreign
}

public enum CuePiIntegrationError: LocalizedError, Equatable {
    case foreignDirectory(URL)
    case uninstallRequiresVerifiedInstall
    case bundledExtensionMissing

    public var errorDescription: String? {
        switch self {
        case .foreignDirectory(let url):
            "\(url.path) contains files Cue cannot verify; Cue left it unchanged."
        case .uninstallRequiresVerifiedInstall:
            "Uninstall only removes a checksum-verified Cue installation with no additional files."
        case .bundledExtensionMissing:
            "The bundled Pi integration extension resource is missing."
        }
    }
}

/// Owns exactly the files declared by `managedFileNames` under the global Pi
/// extension directory. Unknown, additional, linked, or future-schema content
/// is always read-only.
public final class CuePiIntegrationService: @unchecked Sendable {
    public static let shared = CuePiIntegrationService()
    public static let extensionName = "pi-cue-context"
    public static let integrationVersion = 1
    static let manifestSchemaVersion = 1
    static let manifestFileName = "manifest.json"
    static let extensionFileName = "index.ts"
    static let resourceSubdirectory = "PiIntegration/pi-cue-context"
    static let managedFileNames: Set<String> = [extensionFileName]
    static let managedFileNamesByVersion: [Int: Set<String>] = [
        integrationVersion: managedFileNames,
    ]

    private let agentDirectory: URL
    private let bundle: Bundle
    private let fileManager: FileManager

    public init(
        agentDirectory: URL? = nil,
        bundle: Bundle? = nil,
        fileManager: FileManager = .default
    ) {
        self.agentDirectory = agentDirectory ?? Self.defaultAgentDirectory()
        self.bundle = bundle ?? CueResources.bundle
        self.fileManager = fileManager
    }

    public static func defaultAgentDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        if let environment, !environment.isEmpty {
            return URL(fileURLWithPath: environment, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent", isDirectory: true)
    }

    public var integrationDirectory: URL {
        agentDirectory
            .appendingPathComponent("extensions", isDirectory: true)
            .appendingPathComponent(Self.extensionName, isDirectory: true)
    }

    public func state() -> PiIntegrationState {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: integrationDirectory.path, isDirectory: &isDirectory) else {
            return .notInstalled
        }
        guard isDirectory.boolValue,
              !isSymbolicLink(at: integrationDirectory),
              let manifest = loadManifest(),
              manifest.schemaVersion <= Self.manifestSchemaVersion,
              manifest.integration == Self.extensionName,
              manifest.version <= Self.integrationVersion,
              let expectedManagedFiles = Self.managedFileNamesByVersion[manifest.version],
              Set(manifest.files.keys) == expectedManagedFiles,
              directoryContainsNoUnmanagedEntries(expectedManagedFiles: expectedManagedFiles)
        else { return .foreign }

        let verified = manifest.files.allSatisfy { fileName, expectedDigest in
            guard Self.isSafeManagedFileName(fileName) else { return false }
            let url = integrationDirectory.appendingPathComponent(fileName, isDirectory: false)
            guard !isSymbolicLink(at: url), let data = try? Data(contentsOf: url) else { return false }
            return digest(of: data) == expectedDigest
        }
        guard verified, manifest.version == Self.integrationVersion else {
            return .needsRepair(installedVersion: manifest.version)
        }
        return .installed(version: manifest.version)
    }

    @discardableResult
    public func install() throws -> PiIntegrationState {
        try replaceManagedInstallation()
        return state()
    }

    @discardableResult
    public func repair() throws -> PiIntegrationState {
        try replaceManagedInstallation()
        return state()
    }

    public func uninstall() throws {
        guard case .installed = state(),
              directoryContainsExactlyManagedEntries(expectedManagedFiles: Self.managedFileNames)
        else {
            throw CuePiIntegrationError.uninstallRequiresVerifiedInstall
        }

        for fileName in Self.managedFileNames.sorted() {
            try fileManager.removeItem(at: integrationDirectory.appendingPathComponent(fileName))
        }
        try fileManager.removeItem(
            at: integrationDirectory.appendingPathComponent(Self.manifestFileName)
        )
        let remaining = try fileManager.contentsOfDirectory(
            at: integrationDirectory,
            includingPropertiesForKeys: nil
        )
        guard remaining.isEmpty else {
            throw CuePiIntegrationError.uninstallRequiresVerifiedInstall
        }
        try fileManager.removeItem(at: integrationDirectory)
    }

    private func replaceManagedInstallation() throws {
        switch state() {
        case .foreign:
            throw CuePiIntegrationError.foreignDirectory(integrationDirectory)
        case .notInstalled, .installed, .needsRepair:
            break
        }

        let source = try bundledExtensionData()
        let extensionsDirectory = integrationDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)

        let stagingDirectory = extensionsDirectory.appendingPathComponent(
            ".\(Self.extensionName)-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)

        try source.write(
            to: stagingDirectory.appendingPathComponent(Self.extensionFileName),
            options: [.atomic]
        )
        let manifest = PiIntegrationManifest(
            schemaVersion: Self.manifestSchemaVersion,
            integration: Self.extensionName,
            version: Self.integrationVersion,
            files: [Self.extensionFileName: digest(of: source)]
        )
        try JSONEncoder.sorted.encode(manifest).write(
            to: stagingDirectory.appendingPathComponent(Self.manifestFileName),
            options: [.atomic]
        )

        // The temporary name differs from the public extension name, so verify
        // its bytes directly before the directory swap.
        guard verify(directory: stagingDirectory, manifest: manifest) else {
            throw CuePiIntegrationError.bundledExtensionMissing
        }

        if fileManager.fileExists(atPath: integrationDirectory.path) {
            _ = try fileManager.replaceItemAt(
                integrationDirectory,
                withItemAt: stagingDirectory,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: stagingDirectory, to: integrationDirectory)
        }
    }

    private func bundledExtensionData() throws -> Data {
        guard let sourceURL = bundle.url(
            forResource: "index",
            withExtension: "ts",
            subdirectory: Self.resourceSubdirectory
        ) ?? bundle.url(forResource: "index", withExtension: "ts") else {
            throw CuePiIntegrationError.bundledExtensionMissing
        }
        return try Data(contentsOf: sourceURL)
    }

    private func loadManifest() -> PiIntegrationManifest? {
        let url = integrationDirectory.appendingPathComponent(Self.manifestFileName)
        guard !isSymbolicLink(at: url), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PiIntegrationManifest.self, from: data)
    }

    private func directoryContainsNoUnmanagedEntries(
        expectedManagedFiles: Set<String>
    ) -> Bool {
        guard let entries = integrationEntries() else { return false }
        let allowed = expectedManagedFiles.union([Self.manifestFileName])
        let names = Set(entries.map(\.lastPathComponent))
        return names.contains(Self.manifestFileName)
            && names.isSubset(of: allowed)
            && entries.allSatisfy { !isSymbolicLink(at: $0) }
    }

    private func directoryContainsExactlyManagedEntries(
        expectedManagedFiles: Set<String>
    ) -> Bool {
        guard let entries = integrationEntries() else { return false }
        let expected = expectedManagedFiles.union([Self.manifestFileName])
        return Set(entries.map(\.lastPathComponent)) == expected
            && entries.allSatisfy { !isSymbolicLink(at: $0) }
    }

    private func integrationEntries() -> [URL]? {
        try? fileManager.contentsOfDirectory(
            at: integrationDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        )
    }

    private func verify(directory: URL, manifest: PiIntegrationManifest) -> Bool {
        let expectedEntries = Self.managedFileNames.union([Self.manifestFileName])
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              Set(entries.map(\.lastPathComponent)) == expectedEntries,
              Set(manifest.files.keys) == Self.managedFileNames
        else { return false }
        return manifest.files.allSatisfy { fileName, expectedDigest in
            guard Self.isSafeManagedFileName(fileName),
                  let data = try? Data(contentsOf: directory.appendingPathComponent(fileName))
            else { return false }
            return digest(of: data) == expectedDigest
        }
    }

    private static func isSafeManagedFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName == URL(fileURLWithPath: fileName).lastPathComponent
            && !fileName.contains("/")
            && !fileName.contains("\\")
            && fileName != "."
            && fileName != ".."
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return true }
        return values.isSymbolicLink == true
    }

    private func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct PiIntegrationManifest: Codable {
    var schemaVersion: Int
    var integration: String
    var version: Int
    var files: [String: String]
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
