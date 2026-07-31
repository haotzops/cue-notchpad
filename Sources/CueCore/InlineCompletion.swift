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

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    public init(
        model: String,
        prompt: String,
        suffix: String,
        maxTokens: Int = 64,
        temperature: Double = 0.2,
        stream: Bool = true,
        streamOptions: StreamOptions? = .init(includeUsage: true),
        stop: [String]? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.suffix = suffix
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.stream = stream
        self.streamOptions = streamOptions
        self.stop = stop
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

        enum CodingKeys: String, CodingKey {
            case id, object
            case ownedBy = "owned_by"
        }
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
    }

    public let choices: [Choice]
    public let usage: DeepSeekFIMUsage?
}

public enum DeepSeekFIMSSEParserError: Error, Equatable {
    case invalidEvent
}

/// A byte-buffering SSE parser. Network chunks are not guaranteed to line up
/// with SSE events or UTF-8 scalar boundaries, so parsing happens only after a
/// complete blank-line-delimited event is buffered.
public struct DeepSeekFIMSSEParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [String] {
        buffer.append(data)
        var events: [String] = []

        while let range = eventTerminator(in: buffer) {
            let eventData = buffer.subdata(in: 0 ..< range.lowerBound)
            buffer.removeSubrange(0 ..< range.upperBound)
            guard let event = String(data: eventData, encoding: .utf8) else {
                throw DeepSeekFIMSSEParserError.invalidEvent
            }

            let payload = event
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    guard line.hasPrefix("data:") else { return nil }
                    return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: "\n")
            if !payload.isEmpty { events.append(payload) }
        }
        return events
    }

    private func eventTerminator(in data: Data) -> Range<Int>? {
        let lf = Data([0x0A, 0x0A])
        if let range = data.range(of: lf) { return range }
        let crlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        return data.range(of: crlf)
    }
}
