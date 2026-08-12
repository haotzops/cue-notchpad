import AppKit
@testable import CueApp
import CoreGraphics
import CueCore
import Darwin
import Foundation

private struct FixedTokenCounter: TextTokenCounting {
    func count(
        _ text: String,
        for target: TokenCountingTarget,
        cancellingWhen shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) -> TokenCountEstimate? {
        guard !shouldCancel(), text == "draft" else { return nil }
        return .init(count: 13, tokenizer: target.tokenizer, accuracy: target.accuracy)
    }
}

private var failureCount = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

private func expectThrows<Result>(
    _ body: @autoclosure () throws -> Result,
    _ message: String
) {
    do {
        _ = try body()
        failureCount += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    } catch {
        // Expected.
    }
}

private func fixtureData(named name: String) throws -> Data {
    let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(contentsOf: testsDirectory.appendingPathComponent("Fixtures/Persistence/\(name)"))
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
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryFile.path)
    let snapshot = try CueFileWriter.snapshot(at: temporaryFile)
    try CueFileWriter.replace(with: "after", matching: snapshot)
    let writtenText = try String(contentsOf: temporaryFile, encoding: .utf8)
    expect(writtenText == "after", "file writer replaces unchanged file")
    let permissions = try FileManager.default.attributesOfItem(atPath: temporaryFile.path)[.posixPermissions] as? NSNumber
    expect(permissions?.intValue == 0o600, "file writer preserves permissions")
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
    EditorHeightPolicy.panelHeight(
        basePanelHeight: 150,
        currentPanelHeight: 150,
        editorViewportHeight: 75,
        requiredEditorContentHeight: 72
    ) == 150,
    "editor height policy retains the user-selected base height"
)
expect(
    EditorHeightPolicy.panelHeight(
        basePanelHeight: 150,
        currentPanelHeight: 150,
        editorViewportHeight: 75,
        requiredEditorContentHeight: 90
    ) == 165,
    "editor height policy grows from a measured 3.2-line viewport to four lines"
)
expect(
    EditorHeightPolicy.panelHeight(
        basePanelHeight: 150,
        currentPanelHeight: 165,
        editorViewportHeight: 90,
        requiredEditorContentHeight: 108
    ) == 183,
    "editor height policy keeps chrome stable after a prior growth"
)

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

expect(
    PromptRewriteTemplate.render("Before\n${message}\nAfter", message: "agent turn")
        == "Before\nagent turn\nAfter",
    "rewrite template inserts the Pi message at an arbitrary position"
)
expect(
    PromptRewriteTemplate.render("${message} / ${message}", message: "reply") == "reply / reply",
    "rewrite template replaces every message variable"
)
expect(
    PromptRewriteTemplate.render("No context variable", message: "must not be injected")
        == "No context variable",
    "rewrite template does not inject Pi context without an explicit variable"
)
expect(
    PromptRewriteTemplate.render("Context: ${message}", message: nil) == "Context: ",
    "missing Pi context expands safely to an empty string"
)

let modelsJSON = """
{"object":"list","data":[{"id":"deepseek-chat","object":"model","owned_by":"deepseek"}]}
"""
if let modelList = try? JSONDecoder().decode(DeepSeekModelList.self, from: Data(modelsJSON.utf8)) {
    expect(modelList.data.map(\.id) == ["deepseek-chat"], "DeepSeek model list decoding")
} else {
    expect(false, "DeepSeek model list should decode")
}

let piContext = PiRewriteContext(
    version: PiSessionBridge.protocolVersion,
    sessionID: "session-1",
    leafID: "leaf-1",
    message: "latest agent turn"
)
expect(piContext.isValid, "bounded current Pi rewrite context is valid")
expect(
    !PiRewriteContext(version: PiSessionBridge.protocolVersion + 1, sessionID: "session", leafID: nil, message: "text").isValid,
    "future Pi bridge protocol is rejected"
)
let attachedRequest = CueSessionRequest(
    initialText: "draft",
    document: .standardInput,
    callerPID: 1,
    callerName: "Pi",
    workingDirectory: "/tmp",
    piRewriteContext: piContext
)
do {
    let encoded = try JSONEncoder().encode(attachedRequest)
    let decoded = try JSONDecoder().decode(CueSessionRequest.self, from: encoded)
    expect(decoded.piRewriteContext == piContext, "Cue IPC preserves the session-scoped Pi rewrite context")
} catch {
    expect(false, "Cue IPC should encode Pi rewrite context: \(error)")
}

let tokenCounter = CL100KTokenCounter.shared
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

let tokenCounters = TokenCounterRegistry.shared
let editorEstimate = tokenCounters.count("hello world", for: .editorDisplay)
expect(
    editorEstimate == .init(count: 2, tokenizer: .cl100kBase, accuracy: .exact),
    "editor display uses an exact local tokenizer count"
)
let apiEstimate = tokenCounters.count(
    "hello world",
    for: .apiInput(model: "user-selected-model", tokenizer: .cl100kBase, accuracy: .estimated)
)
expect(
    apiEstimate == .init(count: 2, tokenizer: .cl100kBase, accuracy: .estimated),
    "API input budgeting preserves its estimated accuracy"
)
expect(
    tokenCounters.count("cancel me", for: .editorDisplay, cancellingWhen: { true }) == nil,
    "registry propagates cancellation"
)
expect(
    LLMAPIUsage(inputTokens: -1, outputTokens: 7) == .init(inputTokens: 0, outputTokens: 7),
    "API usage is a bounded, independent accounting value"
)

private let injectedCounter = FixedTokenCounter()
expect(
    injectedCounter.count("draft", for: .editorDisplay) == .init(
        count: 13,
        tokenizer: .cl100kBase,
        accuracy: .exact
    ),
    "callers can inject a text token counter without a bundled vocabulary"
)
expect(injectedCounter.isAvailable, "custom counters are available by default")
expect(TokenCounterRegistry.shared.isAvailable, "bundled registry reports availability")

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cue-pi-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let piService = CuePiIntegrationService(agentDirectory: root)
    expect(piService.state() == .notInstalled, "fresh agent directory reports not installed")

    let linkedAgentDirectory = root.appendingPathComponent("linked-agent")
    let realExtensionDirectory = root.appendingPathComponent("real-extension")
    try FileManager.default.createDirectory(
        at: linkedAgentDirectory.appendingPathComponent("extensions"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: realExtensionDirectory,
        withIntermediateDirectories: true
    )
    let linkedIntegrationDirectory = linkedAgentDirectory
        .appendingPathComponent("extensions/pi-cue-context")
    try FileManager.default.createSymbolicLink(
        at: linkedIntegrationDirectory,
        withDestinationURL: realExtensionDirectory
    )
    let linkedService = CuePiIntegrationService(agentDirectory: linkedAgentDirectory)
    expect(linkedService.state() == .foreign, "a linked integration root is foreign")
    expectThrows(try linkedService.install(), "install refuses a linked integration root")

    try piService.install()
    expect(
        piService.state() == .installed(version: CuePiIntegrationService.integrationVersion),
        "install produces a checksum-verified installation"
    )

    try piService.install()
    expect(
        piService.state() == .installed(version: CuePiIntegrationService.integrationVersion),
        "reinstall stays verified"
    )

    let extensionURL = piService.integrationDirectory.appendingPathComponent("index.ts")
    let extraURL = piService.integrationDirectory.appendingPathComponent("user-notes.txt")
    try Data("user-owned".utf8).write(to: extraURL)
    expect(piService.state() == .foreign, "additional files make an installation foreign")
    expectThrows(try piService.uninstall(), "uninstall refuses additional user files")
    expect(FileManager.default.fileExists(atPath: extraURL.path), "refused uninstall preserves user files")
    try FileManager.default.removeItem(at: extraURL)
    expect(
        piService.state() == .installed(version: CuePiIntegrationService.integrationVersion),
        "removing an additional file restores verification"
    )

    try Data("tampered".utf8).write(to: extensionURL)
    expect(
        piService.state() == .needsRepair(installedVersion: CuePiIntegrationService.integrationVersion),
        "modified managed files require repair"
    )

    try piService.repair()
    expect(
        piService.state() == .installed(version: CuePiIntegrationService.integrationVersion),
        "repair restores a verified installation"
    )

    try FileManager.default.removeItem(at: extensionURL)
    expect(
        piService.state() == .needsRepair(installedVersion: CuePiIntegrationService.integrationVersion),
        "missing managed files require repair"
    )
    try piService.repair()
    expect(
        piService.state() == .installed(version: CuePiIntegrationService.integrationVersion),
        "repair restores a missing managed file"
    )

    try FileManager.default.removeItem(
        at: piService.integrationDirectory.appendingPathComponent("manifest.json")
    )
    expect(piService.state() == .foreign, "missing manifest is a foreign directory")
    expectThrows(try piService.install(), "install refuses a foreign directory")
    expectThrows(try piService.uninstall(), "uninstall refuses a foreign directory")

    // A foreign directory is read-only; simulate manual cleanup before
    // reinstalling.
    try FileManager.default.removeItem(at: piService.integrationDirectory)
    try piService.install()
    let manifestURL = piService.integrationDirectory.appendingPathComponent("manifest.json")
    var futureManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        as? [String: Any] ?? [:]
    futureManifest["schemaVersion"] = CuePiIntegrationService.integrationVersion + 1
    try JSONSerialization.data(withJSONObject: futureManifest).write(to: manifestURL)
    expect(piService.state() == .foreign, "future manifest schema is read-only")

    // A future-schema directory is read-only; simulate the manual cleanup a
    // user would do before reinstalling.
    try FileManager.default.removeItem(at: piService.integrationDirectory)
    try piService.install()
    var emptyFilesManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        as? [String: Any] ?? [:]
    emptyFilesManifest["files"] = [:]
    try JSONSerialization.data(withJSONObject: emptyFilesManifest).write(to: manifestURL)
    expect(piService.state() == .foreign, "empty managed file lists are not trusted")
    expectThrows(try piService.uninstall(), "empty managed file lists cannot authorize uninstall")

    try FileManager.default.removeItem(at: piService.integrationDirectory)
    try piService.install()
    var unsafeManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        as? [String: Any] ?? [:]
    unsafeManifest["files"] = ["../user-file": "invalid"]
    try JSONSerialization.data(withJSONObject: unsafeManifest).write(to: manifestURL)
    expect(piService.state() == .foreign, "unsafe manifest paths are not trusted")

    try FileManager.default.removeItem(at: piService.integrationDirectory)
    try piService.install()
    try piService.uninstall()
    expect(piService.state() == .notInstalled, "uninstall removes a verified installation")
    expect(
        !FileManager.default.fileExists(atPath: piService.integrationDirectory.path),
        "uninstall deletes the managed directory"
    )

    try piService.install()
    try Data("tampered".utf8).write(to: extensionURL)
    expectThrows(try piService.uninstall(), "uninstall refuses modified files until repaired")
} catch {
    expect(false, "pi integration service should not throw: \(error)")
}

@MainActor
private func runAppTests() async {
    do {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-api-key-tests-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        CueAPIKeyStore.configurationURLOverride = url
        defer { CueAPIKeyStore.configurationURLOverride = nil }

        try fixtureData(named: "config-v1.json").write(to: url)
        try CueAPIKeyStore.saveDeepSeekAPIKey("replacement-key")
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        expect(document?["schemaVersion"] as? Int == 1, "API key schema remains supported")
        expect(document?["deepSeekAPIKey"] as? String == "replacement-key", "API key is replaced")
        expect(
            document?["futureField"] as? String == "must-survive-a-supported-write",
            "API key writes preserve unknown fields"
        )

        var futureDocument = document ?? [:]
        futureDocument["schemaVersion"] = 2
        let futureData = try JSONSerialization.data(withJSONObject: futureDocument)
        try futureData.write(to: url)
        expectThrows(
            try CueAPIKeyStore.saveDeepSeekAPIKey("must-not-write"),
            "API key writes reject future schemas"
        )
        let unchangedFutureData = try Data(contentsOf: url)
        expect(unchangedFutureData == futureData, "future API key config remains unchanged")

        let corruptData = try fixtureData(named: "config-corrupt.json")
        try corruptData.write(to: url)
        expectThrows(
            try CueAPIKeyStore.saveDeepSeekAPIKey("must-not-write"),
            "API key writes reject corrupt config"
        )
        let unchangedCorruptData = try Data(contentsOf: url)
        expect(unchangedCorruptData == corruptData, "corrupt API key config remains unchanged")
    } catch {
        expect(false, "API key persistence tests should not throw: \(error)")
    }

    do {
        let suiteName = "cue-usage-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try fixtureData(named: "usage-v1.json"), forKey: CueUsageStore.archiveKey)
        let usage = CueUsageStore(defaults: defaults)
        expect(usage.records.count == 1, "legacy FIM usage fixture remains readable")
        expect(usage.records.first?.totalTokens == 46, "usage fixture token total")

        let storedData = defaults.data(forKey: CueUsageStore.archiveKey) ?? Data()
        let stored = try JSONSerialization.jsonObject(with: storedData) as? [String: Any]
        let storedRecords = stored?["records"] as? [[String: Any]]
        expect(
            stored?["futureArchiveField"] as? String == "must-survive-a-supported-write",
            "usage writes preserve unknown archive fields"
        )
        expect(
            storedRecords?.first?["futureRecordField"] as? String == "must-survive-a-supported-write",
            "usage writes preserve unknown record fields"
        )

        usage.clearUsageStatistics()
        let clearedData = defaults.data(forKey: CueUsageStore.archiveKey) ?? Data()
        let cleared = try JSONSerialization.jsonObject(with: clearedData) as? [String: Any]
        expect((cleared?["records"] as? [Any])?.isEmpty == true, "usage clear empties records")
        expect(cleared?["schemaVersion"] as? Int == CueUsageStore.schemaVersion, "usage clear preserves schema")
        expect(
            cleared?["futureArchiveField"] as? String == "must-survive-a-supported-write",
            "usage clear preserves unknown archive fields"
        )

        for fixture in ["usage-future.json", "usage-corrupt.json"] {
            let protectedData = try fixtureData(named: fixture)
            defaults.set(protectedData, forKey: CueUsageStore.archiveKey)
            let protectedStore = CueUsageStore(defaults: defaults)
            protectedStore.recordCueOpen()
            protectedStore.clearUsageStatistics()
            expect(
                defaults.data(forKey: CueUsageStore.archiveKey) == protectedData,
                "\(fixture) remains read-only"
            )
        }

        let activityDocument: [String: Any] = [
            "schemaVersion": CueUsageStore.schemaVersion,
            "records": [],
            "cueOpenCount": 3,
            "cueOpenDates": [0.0, 3_600.0, 86_400.0],
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: activityDocument),
            forKey: CueUsageStore.archiveKey
        )
        let activityStore = CueUsageStore(defaults: defaults)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let activityStart = Date(timeIntervalSinceReferenceDate: 0)
        let activity = activityStore.activity(
            from: activityStart,
            through: activityStart.addingTimeInterval(2 * 86_400),
            calendar: utcCalendar
        )
        expect(activity.totalOpens == 3, "usage activity counts opens in the selected range")
        expect(activity.activeDays == 2, "usage activity deduplicates active days")
        expect(activity.dayCount == 3, "usage activity includes both boundary days")
        expect(activity.averageOpens == 1, "usage activity averages over selected days")
        expect(activity.buckets.map(\.opens) == [2, 1, 0], "multi-day activity uses daily buckets")
        let hourlyActivity = activityStore.activity(
            from: activityStart,
            through: activityStart.addingTimeInterval(3 * 3_600),
            calendar: utcCalendar
        )
        expect(hourlyActivity.buckets.count == 4, "single-day activity uses hourly buckets")
        expect(hourlyActivity.buckets.map(\.opens) == [1, 1, 0, 0], "hourly activity counts each open")
        let longActivity = activityStore.activity(
            from: activityStart,
            through: activityStart.addingTimeInterval(89 * 86_400),
            calendar: utcCalendar
        )
        expect(longActivity.buckets.count <= 30, "long activity ranges use at most thirty buckets")
    } catch {
        expect(false, "usage persistence tests should not throw: \(error)")
    }

    let englishSuite = "cue-settings-en-\(UUID().uuidString)"
    let englishDefaults = UserDefaults(suiteName: englishSuite)!
    defer { englishDefaults.removePersistentDomain(forName: englishSuite) }
    englishDefaults.set(CueLanguage.english.rawValue, forKey: "language")
    englishDefaults.set(true, forKey: "inlineCompletionEnabled")
    englishDefaults.set("legacy-model", forKey: "inlineCompletionModel")
    let english = CueSettings(defaults: englishDefaults)
    expect(
        english.promptExpansionInstruction
            == CueLocalization.string(.settingsAIRewriteDefaultPrompt, localization: "en"),
        "English settings use the English rewrite prompt"
    )
    english.restoreAllSettings()
    expect(
        englishDefaults.bool(forKey: "inlineCompletionEnabled")
            && englishDefaults.string(forKey: "inlineCompletionModel") == "legacy-model",
        "removing FIM keeps legacy user-owned settings keys untouched"
    )

    let chineseSuite = "cue-settings-zh-\(UUID().uuidString)"
    let chineseDefaults = UserDefaults(suiteName: chineseSuite)!
    defer { chineseDefaults.removePersistentDomain(forName: chineseSuite) }
    chineseDefaults.set(CueLanguage.simplifiedChinese.rawValue, forKey: "language")
    let chinese = CueSettings(defaults: chineseDefaults)
    expect(
        chinese.promptExpansionInstruction
            == CueLocalization.string(.settingsAIRewriteDefaultPrompt, localization: "zh-Hans"),
        "Chinese settings use the Chinese rewrite prompt"
    )
    chineseDefaults.set("user-owned instruction", forKey: "promptExpansionInstruction")
    expect(
        CueSettings(defaults: chineseDefaults).promptExpansionInstruction == "user-owned instruction",
        "settings preserve a user-owned rewrite prompt"
    )

    let model = PromptModel(text: "old", tokenCounter: CharacterTokenCounter())
    model.acceptCommittedText("latest")
    try? await Task.sleep(for: .milliseconds(300))
    expect(model.editorTokenEstimate?.count == 6, "prompt model publishes the latest token count")
}

private struct CharacterTokenCounter: TextTokenCounting {
    func count(
        _ text: String,
        for target: TokenCountingTarget,
        cancellingWhen shouldCancel: @escaping @Sendable () -> Bool
    ) -> TokenCountEstimate? {
        guard !shouldCancel() else { return nil }
        return TokenCountEstimate(count: text.count, tokenizer: target.tokenizer, accuracy: target.accuracy)
    }
}

await runAppTests()

if failureCount == 0 {
    print("All Cue tests passed")
    exit(EXIT_SUCCESS)
}
exit(EXIT_FAILURE)
