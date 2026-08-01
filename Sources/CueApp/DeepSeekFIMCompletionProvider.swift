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
}

protocol InlineCompletionProvider: Sendable {
    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<InlineCompletionEvent, Error>
}

enum DeepSeekFIMError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The completion service returned an invalid response."
        case .httpStatus(let status): "The completion service returned HTTP \(status)."
        }
    }
}

actor DeepSeekFIMCompletionProvider: InlineCompletionProvider {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.deepseek.com/beta/completions")!
    private let modelsEndpoint = URL(string: "https://api.deepseek.com/models")!
    private let chatEndpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func availableModels(apiKey: String) async throws -> [String] {
        var urlRequest = URLRequest(url: modelsEndpoint)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekFIMError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DeepSeekFIMError.httpStatus(httpResponse.statusCode)
        }
        let list = try JSONDecoder().decode(DeepSeekModelList.self, from: data)
        return Array(Set(list.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    func validate(apiKey: String, model: String) async throws {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(DeepSeekFIMRequest(
            model: model,
            prompt: "Cue",
            suffix: "",
            maxTokens: 1,
            stream: false,
            streamOptions: nil
        ))
        let (_, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekFIMError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DeepSeekFIMError.httpStatus(httpResponse.statusCode)
        }
    }

    func expandPrompt(_ text: String, instruction: String, model: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role": "system", "content": instruction], ["role": "user", "content": text]], "stream": false])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekFIMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw DeepSeekFIMError.httpStatus(http.statusCode) }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String, !content.isEmpty else { throw DeepSeekFIMError.invalidResponse }
        return content
    }

    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<InlineCompletionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: endpoint)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(DeepSeekFIMRequest(
                        model: request.model,
                        prompt: request.context.prefix,
                        suffix: request.context.suffix,
                        maxTokens: request.maxTokens,
                        stop: request.stop
                    ))

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw DeepSeekFIMError.invalidResponse
                    }
                    guard (200 ..< 300).contains(httpResponse.statusCode) else {
                        throw DeepSeekFIMError.httpStatus(httpResponse.statusCode)
                    }

                    var parser = DeepSeekFIMSSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        let events = try parser.append(Data([byte]))
                        for event in events {
                            if event == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            let chunk = try JSONDecoder().decode(DeepSeekFIMStreamChunk.self, from: Data(event.utf8))
                            if let usage = chunk.usage { continuation.yield(.usage(usage)) }
                            for choice in chunk.choices {
                                if let text = choice.text, !text.isEmpty { continuation.yield(.text(text)) }
                            }
                        }
                    }
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

}
