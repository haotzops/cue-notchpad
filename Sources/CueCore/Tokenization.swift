import Foundation

/// Identifies a locally bundled tokenizer implementation.
public enum TokenizerDescriptor: String, CaseIterable, Sendable, Equatable {
    case cl100kBase
}

/// States whether a local count is exact for its declared tokenizer or an
/// estimate used to budget a provider request.
public enum TokenCountAccuracy: Sendable, Equatable {
    case exact
    case estimated
}

public enum TokenCountingTarget: Sendable, Equatable {
    case editorDisplay(tokenizer: TokenizerDescriptor)
    case apiInput(model: String, tokenizer: TokenizerDescriptor, accuracy: TokenCountAccuracy)

    public static let editorDisplay: Self = .editorDisplay(tokenizer: .cl100kBase)

    public var tokenizer: TokenizerDescriptor {
        switch self {
        case .editorDisplay(let tokenizer), .apiInput(_, let tokenizer, _):
            tokenizer
        }
    }

    public var accuracy: TokenCountAccuracy {
        switch self {
        case .editorDisplay:
            .exact
        case .apiInput(_, _, let accuracy):
            accuracy
        }
    }
}

public struct TokenCountEstimate: Sendable, Equatable {
    public let count: Int
    public let tokenizer: TokenizerDescriptor
    public let accuracy: TokenCountAccuracy

    public init(count: Int, tokenizer: TokenizerDescriptor, accuracy: TokenCountAccuracy) {
        self.count = max(count, 0)
        self.tokenizer = tokenizer
        self.accuracy = accuracy
    }
}

/// Counts text locally for a declared target. A nil result means counting was
/// unavailable or cancelled; it never represents an API-reported usage value.
public protocol TextTokenCounting: Sendable {
    /// Whether a count can be produced right now. Consumers keep the previous
    /// estimate while a count is in flight and only surface "unavailable"
    /// when this is false, so typing does not flash a misleading state.
    var isAvailable: Bool { get }

    func count(
        _ text: String,
        for target: TokenCountingTarget,
        cancellingWhen shouldCancel: @escaping @Sendable () -> Bool
    ) -> TokenCountEstimate?
}

public extension TextTokenCounting {
    /// Custom counters are considered available unless they declare otherwise.
    var isAvailable: Bool { true }
}

/// Resolves local tokenizers for UI display and request budgeting. It never
/// sends text to a provider and never substitutes local estimates for API usage.
public final class TokenCounterRegistry: TextTokenCounting, @unchecked Sendable {
    public static let shared = TokenCounterRegistry()

    private let cl100kBase = CL100KTokenCounter.shared

    public init() {}

    public var isAvailable: Bool { cl100kBase.isAvailable }

    public func count(
        _ text: String,
        for target: TokenCountingTarget,
        cancellingWhen shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) -> TokenCountEstimate? {
        guard !shouldCancel() else { return nil }

        let count: Int?
        switch target.tokenizer {
        case .cl100kBase:
            count = cl100kBase.count(text, cancellingWhen: shouldCancel)
        }

        guard let count else { return nil }
        return TokenCountEstimate(
            count: count,
            tokenizer: target.tokenizer,
            accuracy: target.accuracy
        )
    }
}

/// Token usage returned by an LLM provider. Unlike `TokenCountEstimate`, this
/// is authoritative accounting for one completed API request.
public struct LLMAPIUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = max(inputTokens, 0)
        self.outputTokens = max(outputTokens, 0)
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}
