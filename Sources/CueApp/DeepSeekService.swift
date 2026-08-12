import CueCore
import Foundation

protocol DeepSeekService: Sendable {
    func availableModels(apiKey: String) async throws -> [String]
    func validate(apiKey: String, model: String) async throws
    func rewritePrompt(
        _ text: String,
        instruction: String,
        model: String,
        apiKey: String
    ) async throws -> String
}

enum DeepSeekError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The rewrite service returned an invalid response."
        case .httpStatus(let status): "The rewrite service returned HTTP \(status)."
        }
    }
}

actor DeepSeekChatService: DeepSeekService {
    private let session: URLSession
    private let modelsEndpoint = URL(string: "https://api.deepseek.com/models")!
    private let chatEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!

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

    func availableModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: modelsEndpoint)
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let list = try JSONDecoder().decode(DeepSeekModelList.self, from: data)
        return Array(Set(list.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    func validate(apiKey: String, model: String) async throws {
        let request = try makeChatRequest(
            apiKey: apiKey,
            model: model,
            instruction: "Reply with OK only.",
            text: "OK"
        )
        let (data, response) = try await session.data(for: request)
        try validate(response)
        _ = try decodeCompletion(data)
    }

    func rewritePrompt(
        _ text: String,
        instruction: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        let request = try makeChatRequest(
            apiKey: apiKey,
            model: model,
            instruction: instruction,
            text: text
        )
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decodeCompletion(data)
    }

    private func makeChatRequest(
        apiKey: String,
        model: String,
        instruction: String,
        text: String
    ) throws -> URLRequest {
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(DeepSeekChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: instruction),
                .init(role: "user", content: text),
            ]
        ))
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw DeepSeekError.httpStatus(http.statusCode) }
    }

    private func decodeCompletion(_ data: Data) throws -> String {
        let completion = try JSONDecoder().decode(DeepSeekChatCompletion.self, from: data)
        guard let content = completion.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.invalidResponse
        }
        return content
    }
}

private struct DeepSeekChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream = false
}

private struct DeepSeekChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
