import AppKit
@testable import CueApp
import CoreGraphics
import CueCore
import Darwin
import Foundation
import SwiftUI

private struct StubAIProviderService: AIProviderService {
    func availableModels(provider: CueAIProvider, apiKey: String?) async throws -> [String] { [] }
    func balance(provider: CueAIProvider, apiKey: String?) async throws -> CueProviderBalance {
        CueProviderBalance(amount: 0, currency: nil)
    }
    func validate(provider: CueAIProvider, apiKey: String?, model: String) async throws {}
    func rewritePrompt(
        _ text: String,
        instruction: String,
        provider: CueAIProvider,
        model: String,
        apiKey: String?
    ) async throws -> String { text }
}

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

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw AIProviderError.invalidResponse }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockProviderService(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> HTTPAIProviderService {
    MockURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return HTTPAIProviderService(session: URLSession(configuration: configuration))
}

private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}

private func successfulResponse(for request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
    (
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(json.utf8)
    )
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

private func installSettingsFixture(named name: String, into defaults: UserDefaults) throws {
    let data = try fixtureData(named: name)
    guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    for (key, value) in document {
        defaults.set(value, forKey: key)
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
expect(notchedLayout.openSize == CGSize(width: 600, height: 150), "standard open size")
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

expect(CueAIProvider.builtIn(.deepSeek)?.api == .openAICompletions, "DeepSeek uses OpenAI completions")
expect(CueAIProvider.builtIn(.openAI)?.api == .openAIResponses, "OpenAI uses Responses like Pi")
expect(CueAIProvider.builtIn(.anthropic)?.api == .anthropicMessages, "Anthropic uses Messages")
expect(
    CueAIProvider.custom(
        baseURL: URL(string: "http://localhost:11434/v1")!,
        api: .openAICompletions
    ).api == .openAICompletions,
    "custom providers use the selected API"
)
expect(
    CueAIProviderCatalog.providers.map(\.id) == CueAIProviderID.allCases,
    "the provider catalog has exactly one ordered descriptor for every provider ID"
)
expect(
    Set(CueAIProviderCatalog.providers.map { $0.id.rawValue }).count
        == CueAIProviderCatalog.providers.count,
    "provider IDs are unique persistence identities"
)
expect(
    CueAIProviderCatalog.providers.allSatisfy { !$0.endpoints.isEmpty },
    "every provider declares endpoints"
)
expect(CueAIProviderID.deepSeek.requiresAPIKey, "cloud providers require credentials")
expect(CueAIProviderID.custom.requiresAPIKey == false, "custom providers may run keyless")

let pointStack = PointFieldStack()
pointStack.numberField.stringValue = "600"
pointStack.unitLabel.stringValue = "pt"
pointStack.spacing = 4
pointStack.layoutSubtreeIfNeeded()
expect(
    pointStack.numberField.baselineOffsetFromBottom == pointStack.unitLabel.baselineOffsetFromBottom,
    "native number and unit controls share a text baseline"
)
expect(pointStack.fittingSize.height == pointStack.numberField.fittingSize.height, "unit does not increase row height")
var editedPointSize = 16.0
let pointCoordinator = CuePointField.Coordinator(value: Binding(
    get: { editedPointSize },
    set: { editedPointSize = $0 }
))
pointStack.numberField.stringValue = "24"
pointCoordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: pointStack.numberField))
expect(editedPointSize == 24, "point field commits a valid number")
pointStack.numberField.stringValue = "invalid"
pointCoordinator.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: pointStack.numberField))
expect(editedPointSize == 24 && pointStack.numberField.stringValue == "24", "invalid input keeps the last value")

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
        let openAI = CueAIProvider.builtIn(.openAI)!
        let openAIService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://api.openai.com/v1/responses", "OpenAI uses Responses endpoint")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-key", "OpenAI uses bearer auth")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            expect(body?["instructions"] as? String == "system", "OpenAI Responses sends instructions")
            expect(body?["input"] as? String == "draft", "OpenAI Responses sends user input")
            return successfulResponse(
                for: request,
                json: #"{"output":[{"type":"reasoning"},{"type":"message","role":"assistant","content":[{"type":"output_text","text":"openai rewrite"}]}]}"#
            )
        }
        let openAIResult = try await openAIService.rewritePrompt(
            "draft", instruction: "system", provider: openAI, model: "gpt-test", apiKey: "openai-key"
        )
        expect(openAIResult == "openai rewrite", "OpenAI Responses text is decoded")

        let deepSeek = CueAIProvider.builtIn(.deepSeek)!
        let completionService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions", "DeepSeek uses completions endpoint")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            let messages = body?["messages"] as? [[String: Any]]
            expect(messages?.map { $0["role"] as? String } == ["system", "user"], "Chat Completions sends system and user roles")
            return successfulResponse(
                for: request,
                json: #"{"choices":[{"message":{"content":"chat rewrite"}}]}"#
            )
        }
        let completionResult = try await completionService.rewritePrompt(
            "draft", instruction: "system", provider: deepSeek, model: "deepseek-v3", apiKey: "deepseek-key"
        )
        expect(completionResult == "chat rewrite", "DeepSeek completions text is decoded")

        let balanceProvider = CueAIProvider.custom(
            baseURL: URL(string: "https://api.deepseek.com")!,
            api: .openAICompletions,
            balanceURL: URL(string: "https://api.deepseek.com/user/balance")!,
            balanceJSONPointer: "/balance_infos/0/total_balance"
        )
        let balanceService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://api.deepseek.com/user/balance", "DeepSeek uses the user balance endpoint")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-key", "DeepSeek balance uses bearer auth")
            expect(request.value(forHTTPHeaderField: "Accept") == "application/json", "Balance requests accept JSON")
            return successfulResponse(
                for: request,
                json: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00"}]}"#
            )
        }
        let balance = try await balanceService.balance(provider: balanceProvider, apiKey: "deepseek-key")
        expect(balance.amount == 110, "DeepSeek string balance is decoded as a number")
        expect(balance.currency == "CNY", "DeepSeek balance currency is decoded from balance_infos")

        let anthropic = CueAIProvider.builtIn(.anthropic)!
        let anthropicService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages", "Anthropic uses Messages endpoint")
            expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-key", "Anthropic uses x-api-key")
            expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "Anthropic version header")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            expect(body?["system"] as? String == "system", "Anthropic sends top-level system prompt")
            return successfulResponse(
                for: request,
                json: #"{"content":[{"type":"text","text":"anthropic rewrite"}]}"#
            )
        }
        let anthropicResult = try await anthropicService.rewritePrompt(
            "draft", instruction: "system", provider: anthropic, model: "claude-test", apiKey: "anthropic-key"
        )
        expect(anthropicResult == "anthropic rewrite", "Anthropic text blocks are decoded")

        let modelService = makeMockProviderService { request in
            return successfulResponse(for: request, json: #"{"data":[{"id":"model-b"},{"id":"model-a"}]}"#)
        }
        let deepSeekModels = try await modelService.availableModels(provider: deepSeek, apiKey: "deepseek-key")
        expect(deepSeekModels == ["model-a", "model-b"], "model discovery sorts model identifiers")

        let anthropicModelsService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models", "Anthropic model discovery uses v1")
            expect(request.value(forHTTPHeaderField: "x-api-key") == "anthropic-key", "Anthropic model discovery uses x-api-key")
            return successfulResponse(for: request, json: #"{"data":[{"id":"claude-test"}]}"#)
        }
        let anthropicModels = try await anthropicModelsService.availableModels(
            provider: anthropic,
            apiKey: "anthropic-key"
        )
        expect(anthropicModels == ["claude-test"], "Anthropic model discovery decodes identifiers")
    } catch {
        expect(false, "provider adapter tests should not throw: \(error)")
    }

    do {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-api-key-tests-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        CueAPIKeyStore.configurationURLOverride = url
        defer { CueAPIKeyStore.configurationURLOverride = nil }

        let legacyData = try fixtureData(named: "config-legacy.json")
        try legacyData.write(to: url)
        let legacyDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        expect(
            legacyDeepSeekKey == "fixture-key",
            "legacy DeepSeek key remains readable without a schema version"
        )
        try CueAPIKeyStore.saveAPIKey("openai-key", for: .openAI)
        let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let migratedKeys = migrated?["providerAPIKeys"] as? [String: Any]
        expect(migrated?["schemaVersion"] == nil, "API key config does not write a schema version")
        expect(migrated?["deepSeekAPIKey"] == nil, "legacy DeepSeek field is removed after migration")
        expect(migratedKeys?["deepseek"] as? String == "fixture-key", "legacy DeepSeek key is normalized")
        expect(migratedKeys?["openai"] as? String == "openai-key", "provider keys are stored independently")

        try fixtureData(named: "config-provider-keys.json").write(to: url)
        let storedOpenAIKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let storedDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        expect(storedOpenAIKey == "openai-key", "provider key config is readable")
        expect(storedDeepSeekKey == "deepseek-key", "DeepSeek provider key is readable")
        try CueAPIKeyStore.saveAPIKey("anthropic-key", for: .anthropic)
        try CueAPIKeyStore.removeAPIKey(for: .deepSeek)
        let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let updatedKeys = updated?["providerAPIKeys"] as? [String: Any]
        expect(updatedKeys?["deepseek"] == nil, "removing a provider key removes its entry")
        expect(updatedKeys?["openai"] as? String == "openai-key", "removing one key preserves other providers")
        expect(updatedKeys?["anthropic"] as? String == "anthropic-key", "new providers persist in the config")
        expect(updated?["schemaVersion"] == nil, "provider key writes remain unversioned")
        let removedDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        expect(removedDeepSeekKey == nil, "a removed DeepSeek key is not revived")
        expect(
            updated?["futureField"] as? String == "must-survive-a-supported-write",
            "config writes preserve unrelated fields"
        )

        for fixture in ["config-corrupt.json", "config-corrupt-provider-keys.json"] {
            let corruptData = try fixtureData(named: fixture)
            try corruptData.write(to: url)
            expectThrows(
                try CueAPIKeyStore.saveAPIKey("must-not-write", for: .openAI),
                "\(fixture) rejects writes"
            )
            expectThrows(
                try CueAPIKeyStore.removeAPIKey(for: .deepSeek),
                "\(fixture) rejects removal"
            )
            let unchangedCorruptData = try Data(contentsOf: url)
            expect(unchangedCorruptData == corruptData, "\(fixture) remains unchanged")
        }

        try fixtureData(named: "config-provider-keys.json").write(to: url)
        let originalEnvironmentKey = getenv("OPENAI_API_KEY").map { String(cString: $0) }
        defer {
            if let originalEnvironmentKey {
                setenv("OPENAI_API_KEY", originalEnvironmentKey, 1)
            } else {
                unsetenv("OPENAI_API_KEY")
            }
        }
        setenv("OPENAI_API_KEY", "environment-openai-key", 1)
        let storedKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let storedSource = try CueAPIKeyStore.source(for: .openAI)
        expect(storedKey == "openai-key", "stored API key ignores provider environment variables")
        expect(storedSource == .configuration, "stored credential is the only source")
        try CueAPIKeyStore.removeAPIKey(for: .openAI)
        let removedKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let removedSource = try CueAPIKeyStore.source(for: .openAI)
        let hasStoredKey = try CueAPIKeyStore.hasStoredAPIKey(for: .openAI)
        expect(removedKey == nil, "environment cannot revive a removed key")
        expect(removedSource == nil, "environment does not configure a provider")
        expect(!hasStoredKey, "local key is removed independently")
        try FileManager.default.removeItem(at: url)
        let absentProviderKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let absentProfileKey = try CueAPIKeyStore.loadAPIKey(forProfileID: "openai")
        expect(absentProviderKey == nil, "environment alone is not a credential")
        expect(absentProfileKey == nil, "profile credential lookup ignores provider environment variables")
    } catch {
        expect(false, "API key persistence tests should not throw: \(error)")
    }

    do {
        let suiteName = "cue-provider-credential-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-settings-credential-tests-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        CueAPIKeyStore.configurationURLOverride = url
        defer { CueAPIKeyStore.configurationURLOverride = nil }
        try fixtureData(named: "config-provider-keys.json").write(to: url)

        let settings = CueSettings(defaults: defaults, aiProviderService: StubAIProviderService())
        expect(
            settings.credentialSource(for: .openAI) == .configuration,
            "credential source resolves a stored key per provider"
        )
        expect(settings.hasStoredCredential(for: .openAI), "stored credential is visible per provider")
        expect(!settings.hasStoredCredential(for: .anthropic), "unconfigured providers have no stored credential")

        settings.promptExpansionProvider = .openAI
        settings.removeCredential(for: .anthropic)
        expect(
            settings.credentialSource(for: .anthropic) == nil,
            "removing a non-active provider key works from the management list"
        )
        expect(
            settings.credentialSource(for: .openAI) == .configuration,
            "removing another provider keeps the active provider credential"
        )
        expect(
            settings.providerCredentialConfigured,
            "active provider published credential state stays in sync"
        )
        settings.removeCredential(for: .openAI)
        expect(settings.credentialSource(for: .openAI) == nil, "removing the active provider key clears it")
        expect(!settings.providerCredentialConfigured, "active provider state refreshes after removal")
        let remaining = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let keys = remaining?["providerAPIKeys"] as? [String: Any]
        expect(keys?["deepseek"] as? String == "deepseek-key", "removals preserve unrelated provider keys")
        expect(keys?["openai"] == nil, "active provider key is removed from the document")
    } catch {
        expect(false, "provider credential management tests should not throw: \(error)")
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

    do {
        let settingsSuite = "cue-settings-fixture-\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: settingsSuite)!
        defer { settingsDefaults.removePersistentDomain(forName: settingsSuite) }
        try installSettingsFixture(named: "settings-v1.json", into: settingsDefaults)
        let fixtureSettings = CueSettings(
            defaults: settingsDefaults,
            aiProviderService: StubAIProviderService()
        )
        expect(fixtureSettings.locksPromptWindow, "settings v1 fixture reads the window lock")
        fixtureSettings.locksPromptWindow = false
        expect(
            (settingsDefaults.dictionary(forKey: "futureSetting")?["mustRemain"] as? Bool) == true,
            "writing the window lock preserves unknown settings keys"
        )

        let futureSuite = "cue-settings-future-\(UUID().uuidString)"
        let futureDefaults = UserDefaults(suiteName: futureSuite)!
        defer { futureDefaults.removePersistentDomain(forName: futureSuite) }
        try installSettingsFixture(named: "settings-future.json", into: futureDefaults)
        let futureSettings = CueSettings(
            defaults: futureDefaults,
            aiProviderService: StubAIProviderService()
        )
        expect(futureSettings.locksPromptWindow, "future settings fixture reads known values")
        futureSettings.locksPromptWindow = false
        expect(
            futureDefaults.integer(forKey: "cueSettingsSchemaVersion") == 2,
            "writing a known setting preserves a future settings schema version"
        )
        expect(
            (futureDefaults.dictionary(forKey: "futureSetting")?["mustRemain"] as? Bool) == true,
            "writing a known setting preserves future settings keys"
        )
    } catch {
        expect(false, "window lock persistence fixtures should load: \(error)")
    }

    let profileSuite = "cue-provider-profiles-\(UUID().uuidString)"
    let profileDefaults = UserDefaults(suiteName: profileSuite)!
    defer { profileDefaults.removePersistentDomain(forName: profileSuite) }
    profileDefaults.set(CueLanguage.english.rawValue, forKey: "language")
    profileDefaults.set(true, forKey: "inlineCompletionEnabled")
    profileDefaults.set("legacy-model", forKey: "inlineCompletionModel")
    profileDefaults.set(
        try! fixtureData(named: "provider-profiles-v1.json"),
        forKey: "cueProviderProfiles.v1"
    )
    let profiles = CueSettings(defaults: profileDefaults, aiProviderService: StubAIProviderService())
    expect(profiles.providerProfiles.count == 2, "provider profile fixture loads all profiles")
    expect(profiles.activeProviderProfileID == "custom-local", "profile fixture restores active profile")
    expect(profiles.activeProviderProfile.modelID == "qwen3", "profile model is restored")
    expect(!profiles.activeEndpointResolution.isKnown, "custom endpoint uses manual discovery")
    expect(
        profiles.activeEndpointResolution.modelsURL?.absoluteString == "http://localhost:11434/v1/models",
        "custom profile restores its manual models endpoint"
    )

    let deepSeek = profiles.providerProfiles.first { $0.id == "deepseek" }!
    profiles.selectProviderProfile(deepSeek.id)
    expect(profiles.activeEndpointResolution.isKnown, "known Base URL selects Cue endpoint metadata")
    expect(
        profiles.activeEndpointResolution.modelsURL?.absoluteString == "https://api.deepseek.com/models",
        "known provider models endpoint is generated by the catalog"
    )
    expect(profiles.canCheckBalance, "known provider exposes balance detection")

    let addedID = profiles.addCustomProviderProfile()
    expect(profiles.providerProfiles.contains { $0.id == addedID }, "custom profile can be added")
    expect(profiles.activeProviderProfileID == addedID, "new custom profile becomes active")
    var added = profiles.activeProviderProfile
    added.api = .anthropicMessages
    added.name = "Anthropic Gateway"
    added.baseURL = "https://gateway.example.test"
    added.modelID = "claude-test"
    profiles.updateProviderProfile(added)
    expect(profiles.activeProviderProfile.api == .anthropicMessages, "custom profile stores API protocol")
    expect(profiles.activeProviderProfile.modelID == "claude-test", "custom profile stores model")
    profiles.removeProviderProfile(addedID)
    expect(!profiles.providerProfiles.contains { $0.id == addedID }, "custom profile can be deleted")
    expect(
        profiles.promptExpansionInstruction
            == CueLocalization.string(.settingsAIRewriteDefaultPrompt, localization: "en"),
        "English settings use the English rewrite prompt"
    )
    profiles.locksPromptWindow = true
    profiles.restoreAllSettings()
    expect(!profiles.locksPromptWindow, "restoring settings unlocks bottom-edge resizing")
    expect(
        profileDefaults.bool(forKey: "inlineCompletionEnabled")
            && profileDefaults.string(forKey: "inlineCompletionModel") == "legacy-model",
        "removing FIM keeps legacy user-owned settings keys untouched"
    )

    let chineseSuite = "cue-settings-zh-\(UUID().uuidString)"
    let chineseDefaults = UserDefaults(suiteName: chineseSuite)!
    defer { chineseDefaults.removePersistentDomain(forName: chineseSuite) }
    chineseDefaults.set(CueLanguage.simplifiedChinese.rawValue, forKey: "language")
    let chinese = CueSettings(defaults: chineseDefaults, aiProviderService: StubAIProviderService())
    expect(
        chinese.promptExpansionInstruction
            == CueLocalization.string(.settingsAIRewriteDefaultPrompt, localization: "zh-Hans"),
        "Chinese settings use the Chinese rewrite prompt"
    )
    chineseDefaults.set("user-owned instruction", forKey: "promptExpansionInstruction")
    expect(
        CueSettings(defaults: chineseDefaults, aiProviderService: StubAIProviderService()).promptExpansionInstruction
            == "user-owned instruction",
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
