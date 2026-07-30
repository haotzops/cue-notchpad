import CueCore
import Foundation

struct InlineCompletionRequest: Sendable {
    let context: InlineCompletionContext
    let model: String
    let maxTokens: Int
}

protocol InlineCompletionProvider: Sendable {
    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<String, Error>
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

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(apiKey: String) async throws {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(DeepSeekFIMRequest(
            model: "deepseek-v4-pro",
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

    func streamCompletion(_ request: InlineCompletionRequest, apiKey: String) async -> AsyncThrowingStream<String, Error> {
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
                        maxTokens: request.maxTokens
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
                            for choice in chunk.choices {
                                if let text = choice.text, !text.isEmpty { continuation.yield(text) }
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
