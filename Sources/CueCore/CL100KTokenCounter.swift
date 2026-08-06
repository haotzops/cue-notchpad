import Foundation

/// Counts `cl100k_base` tokens locally. The vocabulary is bundled with the app,
/// so counting never sends prompt text over the network.
public final class CL100KTokenCounter: @unchecked Sendable {
    public static let shared = CL100KTokenCounter()

    private let vocabulary: CueTokenVocabulary?
    private let pattern: Regex<AnyRegexOutput>?

    public var isAvailable: Bool { vocabulary != nil && pattern != nil }

    private init() {
        vocabulary = CueTokenVocabulary.loadBundled()
        pattern = try? Regex(
            #"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s+$|\s*[\r\n]|\s+(?!\S)|\s"#
        )
    }

    public func count(_ text: String) -> Int {
        count(text, cancellingWhen: { false }) ?? 0
    }

    /// Returns nil when a superseding edit cancels the operation. Cancellation
    /// is checked between regex pieces and BPE merge passes so stale counts do
    /// not continue occupying the shared tokenizer worker.
    public func count(
        _ text: String,
        cancellingWhen shouldCancel: () -> Bool
    ) -> Int? {
        guard !shouldCancel() else { return nil }
        guard !text.isEmpty else { return 0 }
        guard let vocabulary, let pattern else { return nil }

        return vocabulary.withLookup { lookup in
            var result = 0
            for match in text.matches(of: pattern) {
                guard !shouldCancel() else { return nil }
                let bytes = Array(text[match.range].utf8)
                if lookup.rank(of: bytes, in: 0 ..< bytes.count) != nil {
                    result += 1
                } else {
                    guard let pieceCount = bytePairCount(
                        bytes,
                        lookup: lookup,
                        shouldCancel: shouldCancel
                    ) else { return nil }
                    result += pieceCount
                }
            }
            return result
        }
    }

    /// BPE parts always remain contiguous slices of `bytes`. Keeping only their
    /// boundaries avoids allocating a tiny `[UInt8]` for every part and every
    /// candidate pair during each merge pass.
    private func bytePairCount(
        _ bytes: [UInt8],
        lookup: CueTokenVocabulary.Lookup,
        shouldCancel: () -> Bool
    ) -> Int? {
        guard bytes.count > 1 else { return bytes.isEmpty ? 0 : 1 }

        var boundaries = Array(0 ... bytes.count)
        while boundaries.count > 2 {
            guard !shouldCancel() else { return nil }
            var bestBoundaryIndex: Int?
            var bestRank = UInt32.max

            for partIndex in 0 ..< boundaries.count - 2 {
                let range = boundaries[partIndex] ..< boundaries[partIndex + 2]
                guard let rank = lookup.rank(of: bytes, in: range), rank < bestRank else {
                    continue
                }
                bestRank = rank
                bestBoundaryIndex = partIndex + 1
            }

            guard let bestBoundaryIndex else { break }
            boundaries.remove(at: bestBoundaryIndex)
        }
        return boundaries.count - 1
    }
}

/// A compact chained hash index backed by one read-only binary resource.
///
/// The previous `Dictionary<[UInt8], Int>` representation allocated one Swift
/// Array for each of 100,256 tokens. This format stores bucket heads, entries,
/// and all token bytes contiguously, then verifies hash matches against the byte
/// blob so collisions cannot change token ranks.
private final class CueTokenVocabulary {
    private static let magic = Array("CUEBPE01".utf8)
    private static let version: UInt32 = 1
    private static let expectedTokenCount: UInt32 = 100_256
    private static let headerSize = 32
    private static let entrySize = 16

    private let storage: Data
    private let bucketCount: Int
    private let tokenCount: Int
    private let entryOffset: Int
    private let blobOffset: Int
    private let blobSize: Int

    private init?(storage: Data) {
        guard storage.count >= Self.headerSize else { return nil }

        let header = storage.withUnsafeBytes { bytes -> Header in
            Header(
                magic: Array(bytes[0 ..< 8]),
                version: Self.readUInt32(bytes, at: 8),
                bucketCount: Self.readUInt32(bytes, at: 12),
                tokenCount: Self.readUInt32(bytes, at: 16),
                entryOffset: Self.readUInt32(bytes, at: 20),
                blobOffset: Self.readUInt32(bytes, at: 24),
                blobSize: Self.readUInt32(bytes, at: 28)
            )
        }

        let bucketCount = Int(header.bucketCount)
        let tokenCount = Int(header.tokenCount)
        let entryOffset = Int(header.entryOffset)
        let blobOffset = Int(header.blobOffset)
        let blobSize = Int(header.blobSize)
        guard header.magic == Self.magic,
              header.version == Self.version,
              header.tokenCount == Self.expectedTokenCount,
              bucketCount > 0,
              bucketCount.isPowerOfTwo,
              entryOffset == Self.headerSize + bucketCount * MemoryLayout<UInt32>.size,
              blobOffset == entryOffset + tokenCount * Self.entrySize,
              blobSize >= 0,
              blobOffset <= storage.count,
              blobSize <= storage.count - blobOffset,
              blobOffset + blobSize == storage.count
        else { return nil }

        self.storage = storage
        self.bucketCount = bucketCount
        self.tokenCount = tokenCount
        self.entryOffset = entryOffset
        self.blobOffset = blobOffset
        self.blobSize = blobSize
    }

    static func loadBundled() -> CueTokenVocabulary? {
        let bundle = CueResources.bundle
        let url = bundle.url(
            forResource: "cl100k_base",
            withExtension: "cuebpe",
            subdirectory: "Tokenizer"
        ) ?? bundle.url(forResource: "cl100k_base", withExtension: "cuebpe")

        guard let url,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else { return nil }
        return CueTokenVocabulary(storage: data)
    }

    func withLookup<Result>(_ body: (Lookup) -> Result) -> Result {
        storage.withUnsafeBytes { bytes in
            body(Lookup(
                bytes: bytes,
                bucketMask: bucketCount - 1,
                tokenCount: tokenCount,
                entryOffset: entryOffset,
                blobOffset: blobOffset,
                blobSize: blobSize
            ))
        }
    }

    struct Lookup {
        fileprivate let bytes: UnsafeRawBufferPointer
        fileprivate let bucketMask: Int
        fileprivate let tokenCount: Int
        fileprivate let entryOffset: Int
        fileprivate let blobOffset: Int
        fileprivate let blobSize: Int

        @inline(__always)
        func rank(of token: [UInt8], in range: Range<Int>) -> UInt32? {
            guard !range.isEmpty,
                  range.lowerBound >= 0,
                  range.upperBound <= token.count,
                  range.count <= UInt8.max
            else { return nil }

            let hash = Self.fnv1a32(token, range: range)
            let bucket = Int(hash) & bucketMask
            var entryReference = CueTokenVocabulary.readUInt32(
                bytes,
                at: CueTokenVocabulary.headerSize + bucket * MemoryLayout<UInt32>.size
            )

            while entryReference != 0 {
                let index = Int(entryReference - 1)
                guard index < tokenCount else { return nil }
                let entry = entryOffset + index * CueTokenVocabulary.entrySize
                let entryHash = CueTokenVocabulary.readUInt32(bytes, at: entry)
                let offsetAndLength = CueTokenVocabulary.readUInt32(bytes, at: entry + 4)
                let rank = CueTokenVocabulary.readUInt32(bytes, at: entry + 8)
                let next = CueTokenVocabulary.readUInt32(bytes, at: entry + 12)
                let tokenOffset = Int(offsetAndLength & 0x00FF_FFFF)
                let tokenLength = Int(offsetAndLength >> 24)

                if entryHash == hash,
                   tokenLength == range.count,
                   tokenOffset <= blobSize - tokenLength,
                   bytesEqual(token, range: range, blobOffset: tokenOffset)
                {
                    return rank
                }
                entryReference = next
            }
            return nil
        }

        @inline(__always)
        private func bytesEqual(
            _ token: [UInt8],
            range: Range<Int>,
            blobOffset tokenOffset: Int
        ) -> Bool {
            let storedStart = blobOffset + tokenOffset
            for relativeOffset in 0 ..< range.count {
                if token[range.lowerBound + relativeOffset] != bytes[storedStart + relativeOffset] {
                    return false
                }
            }
            return true
        }

        @inline(__always)
        private static func fnv1a32(_ token: [UInt8], range: Range<Int>) -> UInt32 {
            var result: UInt32 = 0x811C_9DC5
            for index in range {
                result = (result ^ UInt32(token[index])) &* 0x0100_0193
            }
            return result
        }
    }

    private struct Header {
        let magic: [UInt8]
        let version: UInt32
        let bucketCount: UInt32
        let tokenCount: UInt32
        let entryOffset: UInt32
        let blobOffset: UInt32
        let blobSize: UInt32
    }

    @inline(__always)
    private static func readUInt32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}

private extension Int {
    var isPowerOfTwo: Bool { self > 0 && self & (self - 1) == 0 }
}
