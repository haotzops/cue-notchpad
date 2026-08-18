import CueCore
import Foundation

protocol AIProviderService: Sendable {
    func availableModels(provider: CueAIProvider, apiKey: String?) async throws -> [String]
    func validate(provider: CueAIProvider, apiKey: String?, model: String) async throws
    func rewritePrompt(
        _ text: String,
        instruction: String,
        provider: CueAIProvider,
        model: String,
        apiKey: String?
    ) async throws -> String
}

enum AIProviderError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The model provider returned an invalid response."
        case .httpStatus(let status): "The model provider returned HTTP \(status)."
        case .invalidBaseURL: "The provider base URL is invalid."
        }
    }
}

actor HTTPAIProviderService: AIProviderService {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: configuration)
        }
    }

    func availableModels(provider: CueAIProvider, apiKey: String?) async throws -> [String] {
        guard provider.supportsModelDiscovery else { return provider.knownModels }
        let request = try makeModelsRequest(provider: provider, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let discovered: [String]
        switch provider.api {
        case .googleGenerativeAI:
            let list = try JSONDecoder().decode(GoogleModelList.self, from: data)
            discovered = list.models.compactMap { model in
                let id = model.name.removingPrefix("models/")
                guard !id.isEmpty,
                      model.supportedGenerationMethods?.contains("generateContent") != false
                else { return nil }
                return id
            }
        case .openAICompletions, .openAIResponses, .anthropicMessages:
            discovered = try JSONDecoder().decode(OpenAIModelList.self, from: data).data.map(\.id)
        case .azureOpenAIResponses, .googleVertexAI, .bedrockConverse:
            discovered = []
        }
        return uniqueSorted(provider.knownModels + discovered)
    }

    func validate(provider: CueAIProvider, apiKey: String?, model: String) async throws {
        _ = try await rewritePrompt(
            "OK",
            instruction: "Reply with OK only.",
            provider: provider,
            model: model,
            apiKey: apiKey
        )
    }

    func rewritePrompt(
        _ text: String,
        instruction: String,
        provider: CueAIProvider,
        model: String,
        apiKey: String?
    ) async throws -> String {
        let request = try makeRewriteRequest(
            provider: provider,
            apiKey: apiKey,
            model: model,
            instruction: instruction,
            text: text
        )
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let content: String?
        switch provider.api {
        case .openAICompletions:
            content = try JSONDecoder().decode(OpenAIChatCompletion.self, from: data)
                .choices.first?.message.content
        case .openAIResponses, .azureOpenAIResponses:
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            content = response.output
                .filter { $0.type == "message" && $0.role == "assistant" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap(\.text)
                .joined()
        case .anthropicMessages:
            content = try JSONDecoder().decode(AnthropicMessage.self, from: data)
                .content.filter { $0.type == "text" }.compactMap(\.text).joined()
        case .googleGenerativeAI, .googleVertexAI:
            content = try JSONDecoder().decode(GoogleGenerateContentResponse.self, from: data)
                .candidates.first?.content.parts.compactMap(\.text).joined()
        case .bedrockConverse:
            content = try JSONDecoder().decode(BedrockConverseResponse.self, from: data)
                .output.message.content.compactMap(\.text).joined()
        }
        guard let content, !content.isEmpty else { throw AIProviderError.invalidResponse }
        return content
    }

    private func makeModelsRequest(provider: CueAIProvider, apiKey: String?) throws -> URLRequest {
        let endpoint: URL
        switch provider.api {
        case .googleGenerativeAI:
            endpoint = provider.baseURL.appendingPathComponent("models")
        case .anthropicMessages:
            endpoint = provider.baseURL.appendingPathComponent("v1/models")
        case .openAICompletions, .openAIResponses:
            endpoint = provider.baseURL.appendingPathComponent("models")
        case .azureOpenAIResponses, .googleVertexAI, .bedrockConverse:
            throw AIProviderError.invalidBaseURL
        }
        var request = URLRequest(url: endpoint)
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        return request
    }

    private func makeRewriteRequest(
        provider: CueAIProvider,
        apiKey: String?,
        model: String,
        instruction: String,
        text: String
    ) throws -> URLRequest {
        let endpoint: URL
        let body: Data
        switch provider.api {
        case .openAICompletions:
            endpoint = provider.baseURL.appendingPathComponent("chat/completions")
            body = try JSONEncoder().encode(OpenAIChatRequest(
                model: model,
                messages: [
                    .init(role: "system", content: instruction),
                    .init(role: "user", content: text),
                ]
            ))
        case .openAIResponses, .azureOpenAIResponses:
            endpoint = provider.baseURL.appendingPathComponent("responses")
            body = try JSONEncoder().encode(OpenAIResponsesRequest(
                model: model,
                instructions: instruction,
                input: text
            ))
        case .anthropicMessages:
            endpoint = provider.baseURL.appendingPathComponent("v1/messages")
            body = try JSONEncoder().encode(AnthropicMessagesRequest(
                model: model,
                system: instruction,
                messages: [.init(role: "user", content: text)]
            ))
        case .googleGenerativeAI:
            endpoint = provider.baseURL
                .appendingPathComponent("models")
                .appendingPathComponent("\(model):generateContent")
            body = try googleRequestBody(instruction: instruction, text: text)
        case .googleVertexAI:
            endpoint = provider.baseURL
                .appendingPathComponent("models")
                .appendingPathComponent("\(model):generateContent")
            body = try googleRequestBody(instruction: instruction, text: text)
        case .bedrockConverse:
            endpoint = provider.baseURL
                .appendingPathComponent("model")
                .appendingPathComponent(model)
                .appendingPathComponent("converse")
            body = try JSONEncoder().encode(BedrockConverseRequest(
                system: [.init(text: instruction)],
                messages: [.init(role: "user", content: [.init(text: text)])]
            ))
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        request.httpBody = body
        return request
    }

    private func googleRequestBody(instruction: String, text: String) throws -> Data {
        try JSONEncoder().encode(GoogleGenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: instruction)]),
            contents: [.init(role: "user", parts: [.init(text: text)])]
        ))
    }

    private func applyAuthentication(
        provider: CueAIProvider,
        apiKey: String?,
        to request: inout URLRequest
    ) {
        if provider.api == .anthropicMessages {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        guard let apiKey, !apiKey.isEmpty else { return }
        switch provider.authentication {
        case .none:
            break
        case .azureAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        case .cloudflareAIGateway:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "cf-aig-authorization")
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .googleAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .apiDefault:
            switch provider.api {
            case .anthropicMessages:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            case .googleGenerativeAI, .googleVertexAI:
                request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            case .openAICompletions, .openAIResponses, .azureOpenAIResponses, .bedrockConverse:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func uniqueSorted(_ models: [String]) -> [String] {
        Array(Set(models.filter { !$0.isEmpty })).sorted()
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AIProviderError.httpStatus(http.statusCode)
        }
    }
}

private struct OpenAIModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct GoogleModelList: Decodable {
    struct Model: Decodable {
        let name: String
        let supportedGenerationMethods: [String]?
    }
    let models: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream = false
}

private struct OpenAIChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct OpenAIResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
    let stream = false
}

private struct OpenAIResponse: Decodable {
    struct Output: Decodable {
        struct Content: Decodable {
            let type: String
            let text: String?
        }
        let type: String
        let role: String?
        let content: [Content]?
    }
    let output: [Output]
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let system: String
    let messages: [Message]
    let maxTokens = 4096

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Decodable {
    struct Content: Decodable { let type: String; let text: String? }
    let content: [Content]
}

private struct GoogleGenerateContentRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable { let text: String }
        let role: String?
        let parts: [Part]

        init(role: String? = nil, parts: [Part]) {
            self.role = role
            self.parts = parts
        }
    }
    let systemInstruction: Content
    let contents: [Content]
}

private struct GoogleGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}

private struct BedrockConverseRequest: Encodable {
    struct Content: Encodable { let text: String }
    struct Message: Encodable {
        let role: String
        let content: [Content]
    }
    let system: [Content]
    let messages: [Message]
    let inferenceConfig = InferenceConfig(maxTokens: 4096)

    struct InferenceConfig: Encodable { let maxTokens: Int }
}

private struct BedrockConverseResponse: Decodable {
    struct Output: Decodable {
        struct Message: Decodable {
            struct Content: Decodable { let text: String? }
            let content: [Content]
        }
        let message: Message
    }
    let output: Output
}

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
