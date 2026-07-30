import CoreGraphics
import CueCore
import Darwin
import Foundation

private var failureCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

do {
    let arguments = try CueArguments(arguments: ["--wait"])
    expect(arguments.waitsForEditing, "--wait should enable waiting")
} catch {
    expect(false, "--wait should parse: \(error)")
}

do {
    let waitFile = try CueArguments(arguments: ["--wait", "prompt.md"])
    let editorFile = try CueArguments(arguments: ["prompt.md"])
    let dashFile = try CueArguments(arguments: ["--wait", "--", "-prompt.md"])
    expect(waitFile.filePath == "prompt.md", "--wait file should parse")
    expect(editorFile.filePath == "prompt.md", "$EDITOR file form should parse")
    expect(dashFile.filePath == "-prompt.md", "-- should accept dash path")
} catch { expect(false, "file argument should parse: \(error)") }

for arguments in [[], ["-w"], ["--wait", "a", "b"], ["--help"], ["-file.txt"]] {
    do {
        _ = try CueArguments(arguments: arguments)
        expect(false, "unexpectedly accepted \(arguments)")
    } catch is CueArgumentError {
        // Expected.
    } catch {
        expect(false, "unexpected parser error: \(error)")
    }
}

let notchedLayout = NotchLayout(screen: NotchScreenGeometry(
    screenWidth: 1512,
    safeAreaTop: 32,
    menuBarHeight: 32,
    leftAuxiliaryWidth: 664,
    rightAuxiliaryWidth: 664
))
expect(notchedLayout.closedSize == CGSize(width: 188, height: 32), "physical notch measurement")
expect(notchedLayout.openSize == CGSize(width: 550, height: 150), "standard open size")
expect(notchedLayout.contentTopInset == 32, "physical notch content inset")

let plainLayout = NotchLayout(screen: NotchScreenGeometry(
    screenWidth: 1920,
    safeAreaTop: 0,
    menuBarHeight: 25
))
expect(plainLayout.closedSize == CGSize(width: 185, height: 28), "display fallback size")
expect(plainLayout.contentTopInset == 28, "minimum content inset")

let narrowLayout = NotchLayout(screen: NotchScreenGeometry(
    screenWidth: 390,
    safeAreaTop: 30,
    menuBarHeight: 30
))
expect(narrowLayout.openSize.width == 360, "narrow display width")

let customLayout = NotchLayout(
    screen: NotchScreenGeometry(screenWidth: 1512, safeAreaTop: 32, menuBarHeight: 32),
    preferredOpenWidth: 800,
    preferredOpenHeight: 400
)
expect(customLayout.openSize == CGSize(width: 800, height: 400), "custom open size")

let minimumHeightLayout = NotchLayout(
    screen: NotchScreenGeometry(screenWidth: 1512, safeAreaTop: 32, menuBarHeight: 32),
    preferredOpenHeight: 130
)
expect(minimumHeightLayout.openSize.height == 130, "minimum height")

expect(
    CueLocalization.string(.promptPlaceholder, fallback: "missing", localization: "en")
        == "Write a prompt…",
    "English prompt localization"
)
expect(
    CueLocalization.string(.actionDone, fallback: "missing", localization: "zh-Hans")
        == "完成",
    "Simplified Chinese action localization"
)
expect(
    CueLocalization.string(.promptLabel, fallback: "missing", localization: "zh-Hans")
        == "PROMPT",
    "Simplified Chinese prompt label"
)
expect(
    CueLocalization.characterCount(1, localization: "en") == "characters: 1",
    "English character count"
)
expect(
    CueLocalization.characterCount(3, localization: "zh-Hans") == "字符: 3",
    "Simplified Chinese character count"
)
expect(
    CueLocalization.tokenCount(7, localization: "en") == "token: 7"
        && CueLocalization.tokenCount(7, localization: "zh-Hans") == "token: 7",
    "language-independent token label"
)

let spacingVectors: [(String, String)] = [
    ("中文English", "中文 English"),
    ("English中文", "English 中文"),
    ("版本2.0", "版本 2.0"),
    ("v2版本", "v2 版本"),
    ("中文 English", "中文 English"),
    ("中文，English", "中文，English"),
    ("中文\nEnglish", "中文\nEnglish"),
    (" 中文", " 中文"),
]
for (input, expected) in spacingVectors {
    expect(
        CueTextSpacing.insertingSpacesBetweenChineseAndEnglish(in: input) == expected,
        "Chinese-English spacing: \(input.debugDescription)"
    )
}

let tokenCounter = CueTokenCounter.shared
expect(tokenCounter.count("") == 0, "empty token count")
expect(tokenCounter.count("hello world") == 2, "basic cl100k token count")
expect(tokenCounter.count("Hello, world!") == 4, "punctuated cl100k token count")
expect(
    tokenCounter.count("The quick brown fox jumps over the lazy dog") == 9,
    "sentence cl100k token count"
)
let tokenVectors: [(String, Int)] = [
    ("你好，世界！", 7),
    ("emoji: 👨‍👩‍👧‍👦 🚀✨", 24),
    ("line one\n第二行\n\nend", 9),
    ("don't we'll they've", 6),
    ("   \n\t  ", 2),
    ("1234567890", 4),
    ("中文 English mixed 42%", 7),
]
for (text, expectedCount) in tokenVectors {
    expect(tokenCounter.count(text) == expectedCount, "cl100k vector: \(text.debugDescription)")
}
expect(
    tokenCounter.count("cancel me", cancellingWhen: { true }) == nil,
    "cancelled token count"
)

if failureCount == 0 {
    print("All CueCore tests passed")
    exit(EXIT_SUCCESS)
}

exit(EXIT_FAILURE)
