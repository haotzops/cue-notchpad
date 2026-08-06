import CryptoKit
import Foundation

/// Installation state of the Cue-managed Pi integration extension.
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
            "\(url.path) exists without a valid Cue manifest; Cue never modifies or deletes it."
        case .uninstallRequiresVerifiedInstall:
            "Uninstall only removes a checksum-verified Cue installation. Repair the installation first."
        case .bundledExtensionMissing:
            "The bundled Pi integration extension resource is missing."
        }
    }
}

/// Installs, verifies and removes the Cue-owned Pi integration extension in
/// the global Pi agent directory. Every operation is an explicit user action
/// from Settings; nothing here rewrites Pi's settings.json or environment.
public final class CuePiIntegrationService: @unchecked Sendable {
    public static let shared = CuePiIntegrationService()
    public static let extensionName = "pi-cue-context"
    public static let integrationVersion = 1
    static let manifestSchemaVersion = 1
    static let manifestFileName = "manifest.json"
    static let extensionFileName = "index.ts"
    static let resourceSubdirectory = "PiIntegration/pi-cue-context"

    private let agentDirectory: URL
    private let bundle: Bundle

    public init(
        agentDirectory: URL? = nil,
        bundle: Bundle? = nil
    ) {
        self.agentDirectory = agentDirectory ?? Self.defaultAgentDirectory()
        self.bundle = bundle ?? CueResources.bundle
    }

    /// The global Pi agent directory: `PI_CODING_AGENT_DIR` when set, otherwise
    /// `~/.pi/agent`. Finder-launched Cue cannot inherit Pi's environment, so
    /// the effective path is always shown in Settings.
    public static func defaultAgentDirectory() -> URL {
        let environment = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]
        if let environment, !environment.isEmpty {
            return URL(fileURLWithPath: environment, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent", isDirectory: true)
    }

    /// `extensions/pi-cue-context` under the agent directory.
    public var integrationDirectory: URL {
        agentDirectory
            .appendingPathComponent("extensions", isDirectory: true)
            .appendingPathComponent(Self.extensionName, isDirectory: true)
    }

    /// Read-only inspection. Never mutates the file system.
    public func state() -> PiIntegrationState {
        guard FileManager.default.fileExists(atPath: integrationDirectory.path) else {
            return .notInstalled
        }

        guard let manifest = loadManifest() else { return .foreign }
        guard manifest.schemaVersion <= Self.manifestSchemaVersion else {
            // Future schema is read-only: never overwrite data we may not understand.
            return .foreign
        }
        guard manifest.integration == Self.extensionName,
              manifest.version <= Self.integrationVersion
        else { return .foreign }

        let verified = manifest.files.allSatisfy { path, expectedDigest in
            let url = integrationDirectory.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else { return false }
            return digest(of: data) == expectedDigest
        }
        return verified
            ? .installed(version: manifest.version)
            : .needsRepair(installedVersion: manifest.version)
    }

    /// Installs or refreshes the Cue-owned extension. Refuses to touch a
    /// foreign directory.
    @discardableResult
    public func install() throws -> PiIntegrationState {
        try writeManagedFiles()
        return state()
    }

    /// User-initiated recovery for a checksum mismatch; shares the install
    /// write path, so foreign directories are still refused.
    @discardableResult
    public func repair() throws -> PiIntegrationState {
        try writeManagedFiles()
        return state()
    }

    /// Removes only a checksum-verified Cue installation.
    public func uninstall() throws {
        guard case .installed = state() else {
            throw CuePiIntegrationError.uninstallRequiresVerifiedInstall
        }
        try FileManager.default.removeItem(at: integrationDirectory)
    }

    private func writeManagedFiles() throws {
        guard state() != .foreign else {
            throw CuePiIntegrationError.foreignDirectory(integrationDirectory)
        }

        // SwiftPM flattens non-lproj resources into the bundle root, while
        // assembled app bundles keep the source directory layout. Try both.
        guard let sourceURL = bundle.url(
            forResource: "index",
            withExtension: "ts",
            subdirectory: Self.resourceSubdirectory
        ) ?? bundle.url(forResource: "index", withExtension: "ts") else {
            throw CuePiIntegrationError.bundledExtensionMissing
        }
        let source = try Data(contentsOf: sourceURL)

        try FileManager.default.createDirectory(
            at: integrationDirectory,
            withIntermediateDirectories: true
        )

        let extensionURL = integrationDirectory
            .appendingPathComponent(Self.extensionFileName)
        try writeAtomically(source, to: extensionURL)

        let manifest = PiIntegrationManifest(
            schemaVersion: Self.manifestSchemaVersion,
            integration: Self.extensionName,
            version: Self.integrationVersion,
            files: [Self.extensionFileName: digest(of: source)]
        )
        let manifestData = try JSONEncoder()
            .withSortedKeys()
            .encode(manifest)
        try writeAtomically(
            manifestData,
            to: integrationDirectory.appendingPathComponent(Self.manifestFileName)
        )
    }

    private func loadManifest() -> PiIntegrationManifest? {
        let url = integrationDirectory.appendingPathComponent(Self.manifestFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PiIntegrationManifest.self, from: data)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
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
    func withSortedKeys() -> JSONEncoder {
        outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return self
    }
}
