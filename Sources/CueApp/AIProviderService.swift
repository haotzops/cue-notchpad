import CueCore
import Foundation

struct CueProviderBalance: Equatable, Sendable {
    let amount: Double
    let currency: String?
}

protocol AIProviderService: Sendable {
    func availableModels(provider: CueAIProvider, apiKey: String?) async throws -> [String]
    func balance(provider: CueAIProvider, apiKey: String?) async throws -> CueProviderBalance
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
    case invalidBalanceResponse
    case balanceUnavailable
    case httpStatus(Int)
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The model provider returned an invalid response."
        case .invalidBalanceResponse: "The balance response does not contain a numeric balance."
        case .balanceUnavailable: "Balance detection is not configured for this provider."
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
        case .openAICompletions, .openAIResponses, .anthropicMessages:
            discovered = try JSONDecoder().decode(OpenAIModelList.self, from: data).data.map(\.id)
        }
        return uniqueSorted(provider.knownModels + discovered)
    }

    func balance(provider: CueAIProvider, apiKey: String?) async throws -> CueProviderBalance {
        guard let endpoint = provider.balanceURL else {
            throw AIProviderError.balanceUnavailable
        }
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let amount = numericValue(at: provider.balanceJSONPointer, in: object) else {
            throw AIProviderError.invalidBalanceResponse
        }
        let currency = value(at: "/balance_infos/0/currency", in: object) as? String
            ?? value(at: "/currency", in: object) as? String
            ?? value(at: "/data/currency", in: object) as? String
        return CueProviderBalance(amount: amount, currency: currency)
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
        case .openAIResponses:
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
        }
        guard let content, !content.isEmpty else { throw AIProviderError.invalidResponse }
        return content
    }

    private func makeModelsRequest(provider: CueAIProvider, apiKey: String?) throws -> URLRequest {
        let endpoint: URL
        if let modelsURL = provider.modelsURL {
            endpoint = modelsURL
        } else {
            switch provider.api {
            case .anthropicMessages:
                endpoint = provider.baseURL.appendingPathComponent("v1/models")
            case .openAICompletions, .openAIResponses:
                endpoint = provider.baseURL.appendingPathComponent("models")
            }
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
        case .openAIResponses:
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
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(provider: provider, apiKey: apiKey, to: &request)
        request.httpBody = body
        return request
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
        case .apiDefault:
            switch provider.api {
            case .anthropicMessages:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            case .openAICompletions, .openAIResponses:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
    }

    private func uniqueSorted(_ models: [String]) -> [String] {
        Array(Set(models.filter { !$0.isEmpty })).sorted()
    }

    private func numericValue(at pointer: String, in object: Any) -> Double? {
        switch value(at: pointer, in: object) {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            nil
        }
    }

    private func value(at pointer: String, in object: Any) -> Any? {
        guard pointer.isEmpty || pointer.first == "/" else { return nil }
        var current: Any = object
        for component in pointer.split(separator: "/", omittingEmptySubsequences: true) {
            let key = component
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            if let dictionary = current as? [String: Any] {
                guard let next = dictionary[String(key)] else { return nil }
                current = next
            } else if let array = current as? [Any], let index = Int(key), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
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
