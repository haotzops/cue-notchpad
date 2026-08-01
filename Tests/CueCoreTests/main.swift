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

expect(CueIPC.supports(version: CueIPC.protocolVersion), "current IPC version is supported")
expect(!CueIPC.supports(version: CueIPC.protocolVersion + 1), "future IPC version is rejected")

let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("cue-core-tests-\(UUID().uuidString)")
let temporaryFile = temporaryDirectory.appendingPathComponent("prompt.txt")
do {
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try Data("before".utf8).write(to: temporaryFile)
    let snapshot = try CueFileWriter.snapshot(at: temporaryFile)
    try CueFileWriter.replace(with: "after", matching: snapshot)
    let writtenText = try String(contentsOf: temporaryFile, encoding: .utf8)
    expect(writtenText == "after", "file writer replaces unchanged file")
    try Data("external".utf8).write(to: temporaryFile)
    do {
        try CueFileWriter.replace(with: "lost", matching: snapshot)
        expect(false, "file writer must reject an externally changed file")
    } catch CueFileWriteError.changedByAnotherProcess {
        // Expected.
    }
} catch {
    expect(false, "file writer should preserve unchanged files: \(error)")
}
try? FileManager.default.removeItem(at: temporaryDirectory)

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
    CueLocalization.string(.promptPlaceholder,  localization: "en")
        == "Write a prompt…",
    "English prompt localization"
)
expect(
    CueLocalization.string(.actionDone,  localization: "zh-Hans")
        == "完成",
    "Simplified Chinese action localization"
)
expect(
    CueLocalization.string(.promptLabel,  localization: "zh-Hans")
        == "PROMPT",
    "Simplified Chinese prompt label"
)
expect(
    CueLocalization.characterCount(1, localization: "en") == "ch: 1",
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
for localization in ["en", "zh-Hans"] {
    for key in CueLocalizedKey.allCases {
        expect(
            CueLocalization.string(key, localization: localization) != key.rawValue,
            "\(localization) is missing \(key.rawValue)"
        )
    }
}
expect(
    String(
        format: CueLocalization.string(.fimUsage,  localization: "en"),
        locale: Locale(identifier: "en_US_POSIX"),
        Int64(12),
        Int64(34)
    ) == "FIM: 12/34",
    "English FIM usage format"
)
expect(
    String(
        format: CueLocalization.string(.fimUsage,  localization: "zh-Hans"),
        locale: Locale(identifier: "zh_Hans_CN"),
        Int64(12),
        Int64(34)
    ) == "FIM：12/34",
    "Simplified Chinese FIM usage format"
)

let spacingVectors: [(String, String)] = [
    ("中文English", "中文 English"),
    ("English中文", "English 中文"),
    ("版本2.0", "版本 2.0"),
    ("v2版本", "v2 版本"),
    ("中文 English", "中文 English"),
    ("中文，English", "中文，English"),
    ("English，中文", "English，中文"),
    ("中文（English）", "中文（English）"),
    ("中文\nEnglish", "中文\nEnglish"),
    (" 中文", " 中文"),
]
for (input, expected) in spacingVectors {
    expect(
        CueTextSpacing.insertingSpacesBetweenChineseAndEnglish(in: input) == expected,
        "Chinese-English spacing: \(input.debugDescription)"
    )
}

let inlineDocument = "你好 👨‍👩‍👧‍👦hello世界"
let inlineCaret = NSRange(location: ("你好 👨‍👩‍👧‍👦hello" as NSString).length, length: 0)
let inlineContext = InlineCompletionContextBuilder.make(document: inlineDocument, selection: inlineCaret)
expect(inlineContext?.prefix == "你好 👨‍👩‍👧‍👦hello", "inline completion prefix preserves grapheme clusters")
expect(inlineContext?.suffix == "世界", "inline completion suffix")
expect(InlineCompletionContextBuilder.make(document: inlineDocument, selection: NSRange(location: 1, length: 1)) == nil, "inline completion rejects selected text")

let fimRequest = DeepSeekFIMRequest(model: "deepseek-v4-pro", prompt: "before", suffix: "after")
if let encodedRequest = try? JSONEncoder().encode(fimRequest),
   let requestObject = try? JSONSerialization.jsonObject(with: encodedRequest) as? [String: Any]
{
    expect(requestObject["max_tokens"] as? Int == 64, "FIM request max_tokens encoding")
    expect(requestObject["stream"] as? Bool == true, "FIM request streaming encoding")
    expect((requestObject["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true, "FIM usage stream option")
} else {
    expect(false, "FIM request should encode")
}

let modelsJSON = """
{"object":"list","data":[{"id":"deepseek-v4-pro","object":"model","owned_by":"deepseek"}]}
"""
if let modelList = try? JSONDecoder().decode(DeepSeekModelList.self, from: Data(modelsJSON.utf8)) {
    expect(modelList.data.map(\.id) == ["deepseek-v4-pro"], "DeepSeek model list decoding")
} else {
    expect(false, "DeepSeek model list should decode")
}

var sseParser = DeepSeekFIMSSEParser()
do {
    let partialEvents = try sseParser.append(Data("data: {\"choices\":[{\"text\":\"hel".utf8))
    expect(partialEvents.isEmpty, "SSE partial event waits for terminator")
    let events = try sseParser.append(Data("lo\"}]}\n\ndata: [DONE]\n\n".utf8))
    expect(events == ["{\"choices\":[{\"text\":\"hello\"}]}", "[DONE]"], "SSE parser combines chunked events")
} catch {
    expect(false, "SSE parser should parse: \(error)")
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
