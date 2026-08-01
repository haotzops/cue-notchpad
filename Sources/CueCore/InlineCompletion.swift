import Foundation

public struct InlineCompletionContext: Equatable, Sendable {
    public let prefix: String
    public let suffix: String

    public init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }
}

public enum InlineCompletionContextBuilder {
    /// Splits at an NSTextView UTF-16 selection offset without splitting an
    /// extended grapheme cluster, then keeps the nearest safe context.
    public static func make(
        document: String,
        selection: NSRange,
        maximumPrefixCharacters: Int = 6_000,
        maximumSuffixCharacters: Int = 2_000
    ) -> InlineCompletionContext? {
        guard selection.length == 0,
              let caret = Range(selection, in: document)
        else { return nil }

        let prefix = String(document[..<caret.lowerBound])
        let suffix = String(document[caret.upperBound...])
        return InlineCompletionContext(
            prefix: String(prefix.suffix(maximumPrefixCharacters)),
            suffix: String(suffix.prefix(maximumSuffixCharacters))
        )
    }
}

public enum DeepSeekFIM {
    public static let defaultMaximumTokens = 64
    public static let maximumTokens = 4_096
}

public struct DeepSeekFIMRequest: Codable, Equatable, Sendable {
    public let model: String
    public let prompt: String
    public let suffix: String
    public let maxTokens: Int
    public let temperature: Double
    public let stream: Bool
    public let streamOptions: StreamOptions?
    public let stop: [String]?

    public struct StreamOptions: Codable, Equatable, Sendable {
        public let includeUsage: Bool

        public init(includeUsage: Bool) {
            self.includeUsage = includeUsage
        }

        enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
    }

    public init(
        model: String,
        prompt: String,
        suffix: String,
        maxTokens: Int = DeepSeekFIM.defaultMaximumTokens,
        temperature: Double = 0.2,
        stream: Bool = true,
        streamOptions: StreamOptions? = .init(includeUsage: true),
        stop: [String]? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.suffix = suffix
        self.maxTokens = min(max(maxTokens, 1), DeepSeekFIM.maximumTokens)
        self.temperature = min(max(temperature, 0), 2)
        self.stream = stream
        self.streamOptions = streamOptions
        self.stop = stop.map { Array($0.prefix(16)) }
    }

    enum CodingKeys: String, CodingKey {
        case model, prompt, suffix, temperature, stream, stop
        case maxTokens = "max_tokens"
        case streamOptions = "stream_options"
    }
}

public struct DeepSeekModelList: Decodable, Sendable {
    public struct Model: Decodable, Sendable {
        public let id: String
        public let object: String
        public let ownedBy: String
        enum CodingKeys: String, CodingKey { case id, object; case ownedBy = "owned_by" }
    }
    public let object: String
    public let data: [Model]
}

public struct DeepSeekFIMUsage: Decodable, Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct DeepSeekFIMStreamChunk: Decodable, Sendable {
    public struct Choice: Decodable, Sendable {
        public let text: String?
        public let finishReason: String?
        enum CodingKeys: String, CodingKey { case text; case finishReason = "finish_reason" }
    }
    public let choices: [Choice]
    public let usage: DeepSeekFIMUsage?
}

public enum DeepSeekFIMSSEParserError: Error, Equatable { case invalidEvent }

/// Incrementally parses SSE lines. This handles arbitrary network boundaries
/// without rescanning the complete buffered response for every incoming byte.
public struct DeepSeekFIMSSEParser: Sendable {
    private var line = Data()
    private var payloadLines = [String]()

    public init() {}

    public mutating func append(_ data: Data) throws -> [String] {
        var events = [String]()
        for byte in data {
            if byte == 0x0A {
                if line.last == 0x0D { line.removeLast() }
                if line.isEmpty {
                    if !payloadLines.isEmpty {
                        events.append(payloadLines.joined(separator: "\n"))
                        payloadLines.removeAll(keepingCapacity: true)
                    }
                } else {
                    guard let value = String(data: line, encoding: .utf8) else {
                        throw DeepSeekFIMSSEParserError.invalidEvent
                    }
                    if value.hasPrefix("data:") {
                        payloadLines.append(String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    }
                }
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        return events
    }
}
