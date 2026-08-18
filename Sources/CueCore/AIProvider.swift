import Foundation

public enum CueAIAPI: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompletions = "openai-completions"
    case openAIResponses = "openai-responses"
    case anthropicMessages = "anthropic-messages"
    case googleGenerativeAI = "google-generative-ai"
    case azureOpenAIResponses = "azure-openai-responses"
    case googleVertexAI = "google-vertex"
    case bedrockConverse = "bedrock-converse"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompletions: "OpenAI Chat Completions"
        case .openAIResponses: "OpenAI Responses"
        case .anthropicMessages: "Anthropic Messages"
        case .googleGenerativeAI: "Google Generative AI"
        case .azureOpenAIResponses: "Azure OpenAI Responses"
        case .googleVertexAI: "Google Vertex AI"
        case .bedrockConverse: "Amazon Bedrock Converse"
        }
    }
}

public enum CueAIProviderCategory: String, CaseIterable, Sendable {
    case directAPI
    case codingPlan
    case platform
    case local
    case custom

    public var displayName: String {
        switch self {
        case .directAPI: "Direct APIs"
        case .codingPlan: "Coding Plans"
        case .platform: "Platforms & Gateways"
        case .local: "Local"
        case .custom: "Custom"
        }
    }
}

public enum CueAIProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepSeek = "deepseek"
    case openAI = "openai"
    case anthropic
    case google
    case openRouter = "openrouter"
    case moonshotAICN = "moonshotai-cn"
    case zAI = "zai"
    case miniMax = "minimax"
    case xiaomi
    case antLing = "ant-ling"
    case aliyunBailian = "dashscope"
    case volcengineArk = "ark"
    case tencentHunyuan = "hunyuan"
    case baiduQianfan = "qianfan"
    case siliconFlow = "siliconflow"
    case miniMaxTokenPlanCN = "minimax-cn"
    case xiaomiTokenPlanCN = "xiaomi-token-plan-cn"
    case openCode = "opencode"
    case openCodeGo = "opencode-go"
    case azureOpenAI = "azure-openai-responses"
    case googleVertex = "google-vertex"
    case amazonBedrock = "amazon-bedrock"
    case together
    case fireworks
    case groq
    case huggingFace = "huggingface"
    case nvidia
    case vercelAIGateway = "vercel-ai-gateway"
    case cloudflareAIGateway = "cloudflare-ai-gateway"
    case xAI = "xai"
    case ollama
    case lmStudio = "lm-studio"
    case vllm
    case llamaCpp = "llama-cpp"
    case localAI = "localai"
    case mlx
    case jan
    case gpt4All = "gpt4all"
    case koboldCpp = "koboldcpp"
    case msty
    case custom

    public var id: String { rawValue }

    public var descriptor: CueAIProviderDescriptor {
        CueAIProviderCatalog.provider(self)
    }

    public var displayName: String { descriptor.name }
    public var environmentKeys: [String] { descriptor.environmentKeys }
    public var requiresAPIKey: Bool { self != .custom && descriptor.authentication != .none }
}

public enum CueAIAuthentication: Equatable, Sendable {
    case none
    case apiDefault
    case azureAPIKey
    case googleAPIKey
    case cloudflareAIGateway
    case bearer
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
    public let environmentKeys: [String]
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

    public init(
        id: CueAIProviderID,
        name: String,
        api: CueAIAPI,
        baseURL: URL,
        authentication: CueAIAuthentication,
        supportsModelDiscovery: Bool,
        knownModels: [String]
    ) {
        self.id = id
        self.name = name
        self.api = api
        self.baseURL = baseURL
        self.authentication = authentication
        self.supportsModelDiscovery = supportsModelDiscovery
        self.knownModels = knownModels
    }

    public static func builtIn(
        _ id: CueAIProviderID,
        api: CueAIAPI? = nil,
        baseURLOverride: URL? = nil
    ) -> CueAIProvider? {
        guard id != .custom else { return nil }
        return make(id: id, api: api, baseURLOverride: baseURLOverride)
    }

    public static func custom(baseURL: URL, api: CueAIAPI) -> CueAIProvider {
        make(id: .custom, api: api, baseURLOverride: baseURL)!
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
            ["CUE_DEEPSEEK_API_KEY", "DEEPSEEK_API_KEY"],
            [endpoint(.openAICompletions, "https://api.deepseek.com", discovery: true)]
        ),
        descriptor(
            .openAI, "OpenAI", .directAPI, .apiDefault,
            ["OPENAI_API_KEY"],
            [endpoint(.openAIResponses, "https://api.openai.com/v1", discovery: true)]
        ),
        descriptor(
            .anthropic, "Anthropic", .directAPI, .apiDefault,
            ["ANTHROPIC_API_KEY"],
            [endpoint(.anthropicMessages, "https://api.anthropic.com", discovery: true)]
        ),
        descriptor(
            .google, "Google Gemini", .directAPI, .googleAPIKey,
            ["GEMINI_API_KEY"],
            [endpoint(.googleGenerativeAI, "https://generativelanguage.googleapis.com/v1beta", discovery: true)]
        ),
        descriptor(
            .openRouter, "OpenRouter", .directAPI, .apiDefault,
            ["OPENROUTER_API_KEY"],
            [endpoint(.openAICompletions, "https://openrouter.ai/api/v1", discovery: true)]
        ),
        descriptor(
            .moonshotAICN, "Moonshot AI CN", .directAPI, .apiDefault,
            ["MOONSHOT_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.moonshot.cn/v1",
                discovery: true,
                models: [
                    "kimi-k3", "kimi-k2.7-code", "kimi-k2.7-code-highspeed",
                    "kimi-k2.6", "kimi-k2.5", "kimi-k2-thinking",
                    "kimi-k2-thinking-turbo", "kimi-k2-turbo-preview",
                ]
            )]
        ),
        descriptor(
            .zAI, "Z.AI", .directAPI, .apiDefault,
            ["ZAI_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.z.ai/api/paas/v4",
                discovery: true,
                models: ["glm-5.2", "glm-5.2-highspeed", "glm-5-turbo", "glm-4.7"]
            )]
        ),
        descriptor(
            .miniMax, "MiniMax", .directAPI, .apiDefault,
            ["MINIMAX_API_KEY"],
            [endpoint(
                .anthropicMessages,
                "https://api.minimax.io/anthropic",
                discovery: false,
                models: ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.7-highspeed"]
            )]
        ),
        descriptor(
            .xiaomi, "Xiaomi MiMo", .directAPI, .apiDefault,
            ["XIAOMI_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.xiaomimimo.com/v1",
                discovery: true,
                models: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2-flash", "mimo-v2.5-pro-ultraspeed"]
            )]
        ),
        descriptor(
            .antLing, "Ant Ling", .directAPI, .apiDefault,
            ["ANT_LING_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.ant-ling.com/v1",
                discovery: true,
                models: ["Ling-2.6-1T", "Ling-2.6-flash", "Ring-2.6-1T"]
            )]
        ),
        descriptor(
            .aliyunBailian, "Aliyun Bailian", .directAPI, .apiDefault,
            ["DASHSCOPE_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
                discovery: true,
                models: ["qwen-max", "qwen-plus", "qwen-turbo", "qwen-flash", "deepseek-v3", "deepseek-r1"]
            )]
        ),
        descriptor(
            .volcengineArk, "Volcengine Ark", .directAPI, .apiDefault,
            ["ARK_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://ark.cn-beijing.volces.com/api/v3",
                discovery: true,
                models: ["doubao-seed-1.6-flash", "doubao-1.5-pro-32k", "doubao-1.5-lite-32k", "deepseek-v3.2", "deepseek-r1"]
            )]
        ),
        descriptor(
            .tencentHunyuan, "Tencent Hunyuan", .directAPI, .apiDefault,
            ["HUNYUAN_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.hunyuan.cloud.tencent.com/v1",
                discovery: true,
                models: ["hunyuan-turbo-latest", "hunyuan-turbos-latest", "hunyuan-t1-latest", "hunyuan-lite", "hunyuan-standard-latest"]
            )]
        ),
        descriptor(
            .baiduQianfan, "Baidu Qianfan", .directAPI, .apiDefault,
            ["QIANFAN_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://qianfan.baidubce.com/v2",
                discovery: true,
                models: ["ernie-4.5-8k", "ernie-x1-32k-preview", "ernie-3.5-8k", "deepseek-v3.1", "deepseek-r1"]
            )]
        ),
        descriptor(
            .siliconFlow, "SiliconFlow", .directAPI, .apiDefault,
            ["SILICONFLOW_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://api.siliconflow.cn/v1",
                discovery: true,
                models: [
                    "deepseek-ai/DeepSeek-V3", "Qwen/Qwen3-235B-A22B-Instruct",
                    "THUDM/GLM-4.7", "moonshotai/Kimi-K2",
                ]
            )]
        ),
        descriptor(
            .miniMaxTokenPlanCN, "MiniMax Token Plan CN", .codingPlan, .apiDefault,
            ["MINIMAX_CN_API_KEY"],
            [endpoint(
                .anthropicMessages,
                "https://api.minimaxi.com/anthropic",
                discovery: true,
                models: ["MiniMax-M3", "MiniMax-M2.7-highspeed", "MiniMax-M2.7"]
            )]
        ),
        descriptor(
            .xiaomiTokenPlanCN, "Xiaomi MiMo Token Plan CN", .codingPlan, .apiDefault,
            ["XIAOMI_TOKEN_PLAN_CN_API_KEY"],
            [endpoint(
                .openAICompletions,
                "https://token-plan-cn.xiaomimimo.com/v1",
                discovery: true,
                models: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2-pro"]
            )]
        ),
        descriptor(
            .openCode, "OpenCode Zen", .platform, .bearer,
            ["OPENCODE_API_KEY"],
            [
                endpoint(
                    .openAICompletions,
                    "https://opencode.ai/zen/v1",
                    discovery: false,
                    models: ["deepseek-v4-flash", "deepseek-v4-pro", "glm-5", "glm-5.2", "kimi-k2.7-code"]
                ),
                endpoint(
                    .openAIResponses,
                    "https://opencode.ai/zen/v1",
                    discovery: false,
                    models: ["gpt-5", "gpt-5.1-codex", "gpt-5.2", "gpt-5.2-codex"]
                ),
                endpoint(
                    .anthropicMessages,
                    "https://opencode.ai/zen",
                    discovery: false,
                    models: ["claude-haiku-4-5", "claude-sonnet-4", "claude-sonnet-4-6", "claude-opus-4-6"]
                ),
                endpoint(
                    .googleGenerativeAI,
                    "https://opencode.ai/zen/v1",
                    discovery: false,
                    models: ["gemini-3-flash", "gemini-3.1-pro", "gemini-3.5-flash"]
                ),
            ]
        ),
        descriptor(
            .openCodeGo, "OpenCode Go", .platform, .bearer,
            ["OPENCODE_API_KEY"],
            [
                endpoint(
                    .openAICompletions,
                    "https://opencode.ai/zen/go/v1",
                    discovery: false,
                    models: ["deepseek-v4-flash", "deepseek-v4-pro", "glm-5.2", "kimi-k2.7-code", "kimi-k3"]
                ),
                endpoint(
                    .openAIResponses,
                    "https://opencode.ai/zen/go/v1",
                    discovery: false,
                    models: ["gpt-5.6-luna", "grok-4.5"]
                ),
                endpoint(
                    .anthropicMessages,
                    "https://opencode.ai/zen/go",
                    discovery: false,
                    models: ["minimax-m3", "qwen3.7-max", "qwen3.7-plus", "qwen3.8-max"]
                ),
            ]
        ),
        descriptor(
            .azureOpenAI, "Azure OpenAI", .platform, .azureAPIKey,
            ["AZURE_OPENAI_API_KEY"],
            [endpoint(.azureOpenAIResponses, nil, discovery: false)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .googleVertex, "Google Vertex AI", .platform, .googleAPIKey,
            ["GOOGLE_CLOUD_API_KEY"],
            [endpoint(
                .googleVertexAI,
                nil,
                discovery: false,
                models: [
                    "gemini-3.5-flash", "gemini-3.1-pro-preview", "gemini-3-flash-preview",
                    "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite",
                ]
            )],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .amazonBedrock, "Amazon Bedrock", .platform, .bearer,
            ["AWS_BEARER_TOKEN_BEDROCK"],
            [endpoint(
                .bedrockConverse,
                "https://bedrock-runtime.us-east-1.amazonaws.com",
                discovery: false,
                models: [
                    "amazon.nova-2-lite-v1:0", "amazon.nova-pro-v1:0",
                    "anthropic.claude-sonnet-4-20250514-v1:0",
                ]
            )],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .together, "Together AI", .platform, .apiDefault,
            ["TOGETHER_API_KEY"],
            [endpoint(.openAICompletions, "https://api.together.ai/v1", discovery: true)]
        ),
        descriptor(
            .fireworks, "Fireworks AI", .platform, .bearer,
            ["FIREWORKS_API_KEY"],
            [
                endpoint(
                    .openAICompletions,
                    "https://api.fireworks.ai/inference/v1",
                    discovery: false,
                    models: [
                        "accounts/fireworks/models/glm-5p2",
                        "accounts/fireworks/models/kimi-k3",
                        "accounts/fireworks/routers/glm-5p2-fast",
                        "accounts/fireworks/routers/kimi-k3-fast",
                    ]
                ),
                endpoint(
                    .anthropicMessages,
                    "https://api.fireworks.ai/inference",
                    discovery: false,
                    models: [
                        "accounts/fireworks/models/deepseek-v4-flash",
                        "accounts/fireworks/models/deepseek-v4-pro",
                        "accounts/fireworks/models/kimi-k2p7-code",
                        "accounts/fireworks/models/minimax-m2p7",
                    ]
                ),
            ]
        ),
        descriptor(
            .groq, "Groq", .platform, .apiDefault,
            ["GROQ_API_KEY"],
            [endpoint(.openAICompletions, "https://api.groq.com/openai/v1", discovery: true)]
        ),
        descriptor(
            .huggingFace, "Hugging Face", .platform, .apiDefault,
            ["HF_TOKEN"],
            [endpoint(.openAICompletions, "https://router.huggingface.co/v1", discovery: true)]
        ),
        descriptor(
            .nvidia, "NVIDIA NIM", .platform, .apiDefault,
            ["NVIDIA_API_KEY"],
            [endpoint(.openAICompletions, "https://integrate.api.nvidia.com/v1", discovery: true)]
        ),
        descriptor(
            .vercelAIGateway, "Vercel AI Gateway", .platform, .bearer,
            ["AI_GATEWAY_API_KEY"],
            [endpoint(
                .anthropicMessages,
                "https://ai-gateway.vercel.sh",
                discovery: false,
                models: [
                    "anthropic/claude-sonnet-4.5", "openai/gpt-5.2",
                    "google/gemini-3.1-pro", "alibaba/qwen3-coder",
                ]
            )]
        ),
        descriptor(
            .cloudflareAIGateway, "Cloudflare AI Gateway", .platform, .cloudflareAIGateway,
            ["CLOUDFLARE_API_KEY"],
            [
                endpoint(.openAICompletions, nil, discovery: false),
                endpoint(.openAIResponses, nil, discovery: false),
                endpoint(.anthropicMessages, nil, discovery: false),
            ],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .xAI, "xAI API", .platform, .apiDefault,
            ["XAI_API_KEY"],
            [
                endpoint(
                    .openAICompletions,
                    "https://api.x.ai/v1",
                    discovery: false,
                    models: ["grok-4.3", "grok-build-0.1"]
                ),
                endpoint(
                    .openAIResponses,
                    "https://api.x.ai/v1",
                    discovery: false,
                    models: ["grok-4.5"]
                ),
            ]
        ),
        descriptor(
            .ollama, "Ollama", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:11434/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .lmStudio, "LM Studio", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:1234/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .vllm, "vLLM", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:8000/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .llamaCpp, "llama.cpp", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:8080/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .localAI, "LocalAI", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:8080/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .mlx, "MLX", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:8080/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .jan, "Jan", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:1337/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .gpt4All, "GPT4All", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:4891/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .koboldCpp, "KoboldCpp", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:5001/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .msty, "Msty", .local, .none,
            [],
            [endpoint(.openAICompletions, "http://localhost:3000/v1", discovery: true)],
            allowsBaseURLOverride: true
        ),
        descriptor(
            .custom, "Custom", .custom, .apiDefault,
            ["CUE_CUSTOM_API_KEY"],
            [
                CueAIAPI.openAICompletions,
                .openAIResponses,
                .anthropicMessages,
                .googleGenerativeAI,
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
        _ environmentKeys: [String],
        _ endpoints: [CueAIEndpoint],
        allowsBaseURLOverride: Bool = false
    ) -> CueAIProviderDescriptor {
        CueAIProviderDescriptor(
            id: id,
            name: name,
            category: category,
            authentication: authentication,
            environmentKeys: environmentKeys,
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
