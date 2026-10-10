import Foundation

public enum CueAIAPI: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompletions: "OpenAI Chat Completions"
        case .openAIResponses: "OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        }
    }
}

public enum CueAIProviderCategory: String, CaseIterable, Sendable {
    case directAPI
    case custom

    public var displayName: String {
        switch self {
        case .directAPI: "Direct APIs"
        case .custom: "Custom"
        }
    }
}

public enum CueAIProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepSeek = "deepseek"
    case openAI = "openai"
    case anthropic
    case custom

    public var id: String { rawValue }

    public var descriptor: CueAIProviderDescriptor {
        CueAIProviderCatalog.provider(self)
    }

    public var displayName: String { descriptor.name }
    public var requiresAPIKey: Bool { self != .custom && descriptor.authentication != .none }
}

public enum CueAIAuthentication: Equatable, Sendable {
    case none
    case apiDefault
}

public struct CueAIEndpoint: Equatable, Sendable {
    public let api: CueAIAPI
    public let baseURL: URL?
    public let supportsModelDiscovery: Bool
    public let knownModels: [String]

    public init(
        api: CueAIAPI,
        baseURL: URL?,
        supportsModelDiscovery: Bool,
        knownModels: [String] = []
    ) {
        self.api = api
        self.baseURL = baseURL
        self.supportsModelDiscovery = supportsModelDiscovery
        self.knownModels = knownModels
    }
}

public struct CueAIProviderDescriptor: Equatable, Sendable, Identifiable {
    public let id: CueAIProviderID
    public let name: String
    public let category: CueAIProviderCategory
    public let authentication: CueAIAuthentication
    public let endpoints: [CueAIEndpoint]
    public let allowsBaseURLOverride: Bool

    public var defaultAPI: CueAIAPI { endpoints[0].api }
    public var supportedAPIs: [CueAIAPI] { endpoints.map(\.api) }

    public func endpoint(for api: CueAIAPI) -> CueAIEndpoint? {
        endpoints.first { $0.api == api }
    }
}

public struct CueAIProvider: Equatable, Sendable {
    public let id: CueAIProviderID
    public let name: String
    public let api: CueAIAPI
    public let baseURL: URL
    public let authentication: CueAIAuthentication
    public let supportsModelDiscovery: Bool
    public let knownModels: [String]
    public let modelsURL: URL?
    public let balanceURL: URL?
    public let balanceJSONPointer: String

    public init(
        id: CueAIProviderID,
        name: String,
        api: CueAIAPI,
        baseURL: URL,
        authentication: CueAIAuthentication,
        supportsModelDiscovery: Bool,
        knownModels: [String],
        modelsURL: URL? = nil,
        balanceURL: URL? = nil,
        balanceJSONPointer: String = "/balance"
    ) {
        self.id = id
        self.name = name
        self.api = api
        self.baseURL = baseURL
        self.authentication = authentication
        self.supportsModelDiscovery = supportsModelDiscovery
        self.knownModels = knownModels
        self.modelsURL = modelsURL
        self.balanceURL = balanceURL
        self.balanceJSONPointer = balanceJSONPointer
    }

    public static func builtIn(
        _ id: CueAIProviderID,
        api: CueAIAPI? = nil,
        baseURLOverride: URL? = nil
    ) -> CueAIProvider? {
        guard id != .custom else { return nil }
        return make(id: id, api: api, baseURLOverride: baseURLOverride)
    }

    public static func custom(
        baseURL: URL,
        api: CueAIAPI,
        name: String = "Custom",
        modelsURL: URL? = nil,
        balanceURL: URL? = nil,
        balanceJSONPointer: String = "/balance"
    ) -> CueAIProvider {
        return CueAIProvider(
            id: .custom,
            name: name,
            api: api,
            baseURL: baseURL,
            authentication: .apiDefault,
            supportsModelDiscovery: modelsURL != nil,
            knownModels: [],
            modelsURL: modelsURL,
            balanceURL: balanceURL,
            balanceJSONPointer: balanceJSONPointer
        )
    }

    private static func make(
        id: CueAIProviderID,
        api: CueAIAPI?,
        baseURLOverride: URL?
    ) -> CueAIProvider? {
        let descriptor = CueAIProviderCatalog.provider(id)
        let selectedAPI = api.flatMap { descriptor.supportedAPIs.contains($0) ? $0 : nil }
            ?? descriptor.defaultAPI
        guard let endpoint = descriptor.endpoint(for: selectedAPI),
              let baseURL = baseURLOverride ?? endpoint.baseURL
        else { return nil }
        return CueAIProvider(
            id: id,
            name: descriptor.name,
            api: selectedAPI,
            baseURL: baseURL,
            authentication: descriptor.authentication,
            supportsModelDiscovery: endpoint.supportsModelDiscovery,
            knownModels: endpoint.knownModels
        )
    }
}

public enum CueAIProviderCatalog {
    public static let providers: [CueAIProviderDescriptor] = [
        descriptor(
            .deepSeek, "DeepSeek", .directAPI, .apiDefault,
            [endpoint(.openAICompletions, "https://api.deepseek.com", discovery: true)]
        ),
        descriptor(
            .openAI, "OpenAI", .directAPI, .apiDefault,
            [endpoint(.openAIResponses, "https://api.openai.com/v1", discovery: true)]
        ),
        descriptor(
            .anthropic, "Anthropic", .directAPI, .apiDefault,
            [endpoint(.anthropicMessages, "https://api.anthropic.com", discovery: true)]
        ),
        descriptor(
            .custom, "Custom", .custom, .apiDefault,
            [
                CueAIAPI.openAICompletions,
                .openAIResponses,
                .anthropicMessages,
            ].map { CueAIEndpoint(api: $0, baseURL: nil, supportsModelDiscovery: false) },
            allowsBaseURLOverride: true
        ),
    ]

    private static let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })

    public static func provider(_ id: CueAIProviderID) -> CueAIProviderDescriptor {
        providersByID[id]!
    }

    public static func providers(in category: CueAIProviderCategory) -> [CueAIProviderDescriptor] {
        providers.filter { $0.category == category }
    }

    private static func descriptor(
        _ id: CueAIProviderID,
        _ name: String,
        _ category: CueAIProviderCategory,
        _ authentication: CueAIAuthentication,
        _ endpoints: [CueAIEndpoint],
        allowsBaseURLOverride: Bool = false
    ) -> CueAIProviderDescriptor {
        CueAIProviderDescriptor(
            id: id,
            name: name,
            category: category,
            authentication: authentication,
            endpoints: endpoints,
            allowsBaseURLOverride: allowsBaseURLOverride
        )
    }

    private static func endpoint(
        _ api: CueAIAPI,
        _ baseURL: String?,
        discovery: Bool,
        models: [String] = []
    ) -> CueAIEndpoint {
        CueAIEndpoint(
            api: api,
            baseURL: baseURL.flatMap(URL.init(string:)),
            supportsModelDiscovery: discovery,
            knownModels: models
        )
    }
}
