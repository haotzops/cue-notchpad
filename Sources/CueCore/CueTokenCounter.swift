import Foundation

/// Counts `cl100k_base` tokens locally. The vocabulary is bundled with the app,
/// so counting never sends prompt text over the network.
public final class CueTokenCounter: @unchecked Sendable {
    public static let shared = CueTokenCounter()

    private let ranks: [[UInt8]: Int]
    private let pattern: Regex<AnyRegexOutput>

    private init() {
        ranks = Self.loadRanks()
        pattern = try! Regex(
            #"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s+$|\s*[\r\n]|\s+(?!\S)|\s"#
        )
    }

    public func count(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var result = 0
        for match in text.matches(of: pattern) {
            let bytes = Array(text[match.range].utf8)
            if ranks[bytes] != nil {
                result += 1
            } else {
                result += bytePairCount(bytes)
            }
        }
        return result
    }

    private func bytePairCount(_ bytes: [UInt8]) -> Int {
        guard bytes.count > 1 else { return bytes.isEmpty ? 0 : 1 }

        var parts = bytes.map { [$0] }
        while parts.count > 1 {
            var bestIndex: Int?
            var bestRank = Int.max

            for index in 0 ..< parts.count - 1 {
                let rank = ranks[parts[index] + parts[index + 1]] ?? Int.max
                if rank < bestRank {
                    bestRank = rank
                    bestIndex = index
                }
            }

            guard let bestIndex else { break }
            parts[bestIndex].append(contentsOf: parts[bestIndex + 1])
            parts.remove(at: bestIndex + 1)
        }
        return parts.count
    }

    private static func loadRanks() -> [[UInt8]: Int] {
        let bundle = CueResources.bundle
        let url = bundle.url(
            forResource: "cl100k_base",
            withExtension: "tiktoken",
            subdirectory: "Tokenizer"
        ) ?? bundle.url(forResource: "cl100k_base", withExtension: "tiktoken")

        guard let url,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("Bundled cl100k_base vocabulary is missing")
        }

        var result: [[UInt8]: Int] = [:]
        result.reserveCapacity(100_256)

        for line in contents.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1)
            guard fields.count == 2,
                  let data = Data(base64Encoded: String(fields[0])),
                  let rank = Int(fields[1])
            else { continue }
            result[Array(data)] = rank
        }

        precondition(result.count == 100_256, "Invalid cl100k_base vocabulary")
        return result
    }
}
