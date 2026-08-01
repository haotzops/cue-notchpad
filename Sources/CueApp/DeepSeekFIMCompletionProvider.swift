import CueCore
import Foundation

struct InlineCompletionRequest: Sendable {
    let context: InlineCompletionContext
    let model: String
    let maxTokens: Int
    let stop: [String]?
}

enum InlineCompletionEvent: Sendable {
    case text(String)
    case usage(DeepSeekFIMUsage)
    case finished(reason: String?)
}

protocol InlineCompletionProvider: Sendable {
    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<InlineCompletionEvent, Error>
}

protocol DeepSeekService: Sendable {
    func availableModels(apiKey: String) async throws -> [String]
    func validate(apiKey: String, model: String) async throws
}

enum DeepSeekFIMError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The completion service returned an invalid response."
        case .httpStatus(let status): "The completion service returned HTTP \(status)."
        }
    }
}

actor DeepSeekFIMCompletionProvider: InlineCompletionProvider, DeepSeekService {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/beta/completions")!
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
        var request = makeFIMRequest(apiKey: apiKey, body: DeepSeekFIMRequest(
            model: model,
            prompt: "Cue",
            suffix: "",
            maxTokens: 1,
            stream: false,
            streamOptions: nil
        ))
        request.timeoutInterval = 30
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func expandPrompt(_ text: String, instruction: String, model: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(DeepSeekChatRequest(
            model: model,
            messages: [.init(role: "system", content: instruction), .init(role: "user", content: text)]
        ))
        let (data, response) = try await session.data(for: request)
        try validate(response)
        let completion = try JSONDecoder().decode(DeepSeekChatCompletion.self, from: data)
        guard let content = completion.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekFIMError.invalidResponse
        }
        return content
    }

    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<InlineCompletionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = DeepSeekFIMRequest(
                        model: request.model,
                        prompt: request.context.prefix,
                        suffix: request.context.suffix,
                        maxTokens: request.maxTokens,
                        stop: request.stop
                    )
                    let (bytes, response) = try await session.bytes(for: makeFIMRequest(apiKey: apiKey, body: body))
                    try validate(response)

                    var parser = DeepSeekFIMSSEParser()
                    var packet = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        packet.append(byte)
                        guard byte == 0x0A else { continue }
                        try emit(parser.append(packet), to: continuation)
                        packet.removeAll(keepingCapacity: true)
                    }
                    if !packet.isEmpty { try emit(parser.append(packet), to: continuation) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeFIMRequest(apiKey: String, body: DeepSeekFIMRequest) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DeepSeekFIMError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw DeepSeekFIMError.httpStatus(http.statusCode) }
    }

    private func emit(
        _ events: [String],
        to continuation: AsyncThrowingStream<InlineCompletionEvent, Error>.Continuation
    ) throws {
        for event in events {
            if event == "[DONE]" {
                continuation.finish()
                return
            }
            let chunk = try JSONDecoder().decode(DeepSeekFIMStreamChunk.self, from: Data(event.utf8))
            if let usage = chunk.usage { continuation.yield(.usage(usage)) }
            for choice in chunk.choices {
                if let text = choice.text, !text.isEmpty { continuation.yield(.text(text)) }
                if choice.finishReason != nil { continuation.yield(.finished(reason: choice.finishReason)) }
            }
        }
    }
}

private struct DeepSeekChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream = false
}

private struct DeepSeekChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
