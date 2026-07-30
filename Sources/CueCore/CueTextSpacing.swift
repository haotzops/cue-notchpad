import Foundation

/// Applies a minimal Chinese-English spacing rule without altering punctuation,
/// existing whitespace, or text that does not cross a Han/ASCII word boundary.
public enum CueTextSpacing {
    public static func insertingSpacesBetweenChineseAndEnglish(in text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = String()
        var previousKind: CharacterKind?

        for scalar in text.unicodeScalars {
            let kind = kind(of: scalar)
            if (previousKind == .han && kind == .asciiWord)
                || (previousKind == .asciiWord && kind == .han)
            {
                result.append(" ")
            }
            result.unicodeScalars.append(scalar)
            previousKind = kind
        }

        return result
    }

    private enum CharacterKind {
        case han
        case asciiWord
        case other
    }

    private static func kind(of scalar: UnicodeScalar) -> CharacterKind {
        switch scalar.value {
        case 0x3400 ... 0x4DBF,       // CJK Unified Ideographs Extension A
             0x4E00 ... 0x9FFF,       // CJK Unified Ideographs
             0xF900 ... 0xFAFF,       // CJK Compatibility Ideographs
             0x20000 ... 0x2EBEF:     // CJK Unified Ideographs Extensions B–I
            return .han
        case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
            return .asciiWord
        default:
            return .other
        }
    }
}
