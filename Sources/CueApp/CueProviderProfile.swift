import CueCore
import Foundation

struct CueProviderProfile: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case builtIn
        case custom
    }

    let id: String
    var kind: Kind
    var name: String
    var providerID: CueAIProviderID?
    var api: CueAIAPI
    var baseURL: String
    var modelID: String?
    var manualModelsURL: String?
    var manualBalanceURL: String?
    var balanceJSONPointer: String

    var isCustom: Bool { kind == .custom }
    var credentialID: String { isCustom ? "custom:\(id)" : id }
    var requiresAPIKey: Bool {
        guard !isCustom else { return false }
        return providerID.map { $0.descriptor.authentication != .none } ?? false
    }

    static let defaults: [CueProviderProfile] = [
        CueProviderProfile(
            id: CueAIProviderID.deepSeek.rawValue,
            kind: .builtIn,
            name: "DeepSeek",
            providerID: .deepSeek,
            api: .openAICompletions,
            baseURL: "https://api.deepseek.com",
            modelID: nil,
            manualModelsURL: nil,
            manualBalanceURL: nil,
            balanceJSONPointer: "/balance_infos/0/total_balance"
        ),
        CueProviderProfile(
            id: CueAIProviderID.openAI.rawValue,
            kind: .builtIn,
            name: "OpenAI",
            providerID: .openAI,
            api: .openAIResponses,
            baseURL: "https://api.openai.com/v1",
            modelID: nil,
            manualModelsURL: nil,
            manualBalanceURL: nil,
            balanceJSONPointer: "/balance"
        ),
        CueProviderProfile(
            id: CueAIProviderID.anthropic.rawValue,
            kind: .builtIn,
            name: "Anthropic",
            providerID: .anthropic,
            api: .anthropicMessages,
            baseURL: "https://api.anthropic.com",
            modelID: nil,
            manualModelsURL: nil,
            manualBalanceURL: nil,
            balanceJSONPointer: "/balance"
        ),
    ]
}

struct CueProviderProfilesDocument: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeProfileID: String
    var profiles: [CueProviderProfile]

    static var defaults: Self {
        let profiles = CueProviderProfile.defaults
        return Self(
            schemaVersion: currentSchemaVersion,
            activeProfileID: profiles[0].id,
            profiles: profiles
        )
    }
}

struct CueEndpointResolution: Equatable {
    let modelsURL: URL?
    let balanceURL: URL?
    let balanceJSONPointer: String
    let isKnown: Bool

    var supportsModelDiscovery: Bool { modelsURL != nil }
    var supportsBalance: Bool { balanceURL != nil }
}

enum CueProviderEndpointCatalog {
    private struct Entry {
        let api: CueAIAPI
        let baseURL: String
        let modelsPath: String
        let balancePath: String?
        let balanceJSONPointer: String
    }

    private static let entries: [Entry] = [
        Entry(
            api: .openAICompletions,
            baseURL: "https://api.deepseek.com",
            modelsPath: "models",
            balancePath: "user/balance",
            balanceJSONPointer: "/balance_infos/0/total_balance"
        ),
        Entry(
            api: .openAIResponses,
            baseURL: "https://api.openai.com/v1",
            modelsPath: "models",
            balancePath: nil,
            balanceJSONPointer: "/balance"
        ),
        Entry(
            api: .anthropicMessages,
            baseURL: "https://api.anthropic.com",
            modelsPath: "v1/models",
            balancePath: nil,
            balanceJSONPointer: "/balance"
        ),
    ]

    static func resolve(for profile: CueProviderProfile) -> CueEndpointResolution {
        guard !profile.isCustom, let baseURL = normalizedURL(profile.baseURL) else {
            return manualResolution(for: profile)
        }

        if let entry = entries.first(where: {
            $0.api == profile.api && normalizedURL($0.baseURL) == baseURL
        }) {
            return CueEndpointResolution(
                modelsURL: baseURL.appendingPathComponent(entry.modelsPath),
                balanceURL: entry.balancePath.map { baseURL.appendingPathComponent($0) },
                balanceJSONPointer: entry.balanceJSONPointer,
                isKnown: true
            )
        }

        return manualResolution(for: profile)
    }

    private static func manualResolution(for profile: CueProviderProfile) -> CueEndpointResolution {
        CueEndpointResolution(
            modelsURL: normalizedURL(profile.manualModelsURL),
            balanceURL: normalizedURL(profile.manualBalanceURL),
            balanceJSONPointer: profile.balanceJSONPointer,
            isKnown: false
        )
    }

    private static func normalizedURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return normalizedURL(value)
    }

    private static func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased()
        else { return nil }

        components.scheme = scheme
        components.host = host
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443)
        {
            components.port = nil
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "" : "/\(path)"
        return components.url
    }
}
