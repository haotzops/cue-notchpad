import AppKit
@testable import CueApp
import CoreGraphics
import CueCore
import Darwin
import Foundation

private struct StubAIProviderService: AIProviderService {
    func availableModels(provider: CueAIProvider, apiKey: String?) async throws -> [String] { [] }
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
expect(CueAIProvider.builtIn(.google)?.api == .googleGenerativeAI, "Google uses Generative AI")
expect(CueAIProvider.builtIn(.miniMaxTokenPlanCN)?.api == .anthropicMessages, "MiniMax Token Plan uses Messages")
expect(CueAIProvider.builtIn(.xiaomiTokenPlanCN)?.api == .openAICompletions, "MiMo Token Plan uses completions")
expect(CueAIProvider.builtIn(.moonshotAICN)?.api == .openAICompletions, "Moonshot AI CN uses completions")
expect(CueAIProvider.builtIn(.zAI)?.api == .openAICompletions, "Z.AI uses completions")
expect(CueAIProvider.builtIn(.miniMax)?.api == .anthropicMessages, "MiniMax intl uses Messages")
expect(CueAIProvider.builtIn(.xiaomi)?.api == .openAICompletions, "Xiaomi MiMo uses completions")
expect(CueAIProvider.builtIn(.antLing)?.api == .openAICompletions, "Ant Ling uses completions")
expect(CueAIProvider.builtIn(.aliyunBailian)?.api == .openAICompletions, "Aliyun Bailian uses completions")
expect(CueAIProvider.builtIn(.volcengineArk)?.api == .openAICompletions, "Volcengine Ark uses completions")
expect(CueAIProvider.builtIn(.tencentHunyuan)?.api == .openAICompletions, "Tencent Hunyuan uses completions")
expect(CueAIProvider.builtIn(.baiduQianfan)?.api == .openAICompletions, "Baidu Qianfan uses completions")
expect(CueAIProvider.builtIn(.siliconFlow)?.api == .openAICompletions, "SiliconFlow uses completions")
expect(
    CueAIProvider.builtIn(.aliyunBailian)?.baseURL.absoluteString
        == "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "Aliyun Bailian uses the OpenAI-compatible DashScope endpoint"
)
expect(
    CueAIProvider.builtIn(.siliconFlow)?.baseURL.absoluteString == "https://api.siliconflow.cn/v1",
    "SiliconFlow uses its v1 endpoint"
)
expect(
    CueAIProvider.builtIn(.tencentHunyuan)?.baseURL.absoluteString
        == "https://api.hunyuan.cloud.tencent.com/v1",
    "Tencent Hunyuan uses its OpenAI-compatible endpoint"
)
let domesticAPIs = [
    "moonshotai-cn", "zai", "minimax", "xiaomi", "ant-ling",
    "dashscope", "ark", "hunyuan", "qianfan", "siliconflow",
]
expect(
    domesticAPIs.allSatisfy { CueAIProviderID(rawValue: $0) != nil },
    "domestic pay-as-you-go API providers are built in"
)
expect(CueAIProvider.builtIn(.azureOpenAI) == nil, "Azure requires an explicit resource endpoint")
expect(CueAIProvider.builtIn(.googleVertex) == nil, "Vertex requires an explicit project endpoint")
expect(CueAIProvider.builtIn(.amazonBedrock)?.api == .bedrockConverse, "Bedrock uses Converse")
expect(
    CueAIProvider.builtIn(.openCode, api: .anthropicMessages)?.baseURL.absoluteString
        == "https://opencode.ai/zen",
    "multi-API providers select the protocol-specific endpoint"
)
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
expect(
    CueAIProviderCatalog.providers.allSatisfy {
        ($0.authentication == .none) == $0.environmentKeys.isEmpty
    },
    "credential-less providers declare no environment keys"
)
expect(CueAIProvider.builtIn(.ollama)?.api == .openAICompletions, "Ollama uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.lmStudio)?.api == .openAICompletions, "LM Studio uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.vllm)?.api == .openAICompletions, "vLLM uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.llamaCpp)?.api == .openAICompletions, "llama.cpp uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.localAI)?.api == .openAICompletions, "LocalAI uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.mlx)?.api == .openAICompletions, "MLX uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.jan)?.api == .openAICompletions, "Jan uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.gpt4All)?.api == .openAICompletions, "GPT4All uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.koboldCpp)?.api == .openAICompletions, "KoboldCpp uses OpenAI-compatible completions")
expect(CueAIProvider.builtIn(.msty)?.api == .openAICompletions, "Msty uses OpenAI-compatible completions")
expect(
    CueAIProvider.builtIn(.ollama)?.baseURL.absoluteString == "http://localhost:11434/v1",
    "Ollama defaults to localhost:11434"
)
expect(
    CueAIProvider.builtIn(.lmStudio)?.baseURL.absoluteString == "http://localhost:1234/v1",
    "LM Studio defaults to localhost:1234"
)
expect(
    CueAIProvider.builtIn(.jan)?.baseURL.absoluteString == "http://localhost:1337/v1",
    "Jan defaults to localhost:1337"
)
expect(
    CueAIProviderID.ollama.requiresAPIKey == false && CueAIProviderID.msty.requiresAPIKey == false,
    "local providers do not require credentials"
)
expect(CueAIProviderID.deepSeek.requiresAPIKey, "cloud providers require credentials")
expect(CueAIProviderID.custom.requiresAPIKey == false, "custom providers may run keyless")
let restrictedProviderIDs = [
    "zai-coding-cn", "qwen-token-plan-cn", "tencent-tokenhub", "astron-coding",
    "baidu-coding-plan", "volcengine-coding-plan", "kimi-coding", "github-copilot", "openai-codex",
]
expect(
    restrictedProviderIDs.allSatisfy { CueAIProviderID(rawValue: $0) == nil },
    "restricted plans and subscription OAuth providers are not built into Cue"
)

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

        let openRouter = CueAIProvider.builtIn(.openRouter)!
        let completionService = makeMockProviderService { request in
            expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions", "OpenAI-compatible endpoint")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            let messages = body?["messages"] as? [[String: Any]]
            expect(messages?.map { $0["role"] as? String } == ["system", "user"], "Chat Completions sends system and user roles")
            return successfulResponse(
                for: request,
                json: #"{"choices":[{"message":{"content":"chat rewrite"}}]}"#
            )
        }
        let completionResult = try await completionService.rewritePrompt(
            "draft", instruction: "system", provider: openRouter, model: "router/model", apiKey: "router-key"
        )
        expect(completionResult == "chat rewrite", "OpenAI-compatible text is decoded")

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

        let google = CueAIProvider.builtIn(.google)!
        let googleService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent",
                "Google uses generateContent endpoint"
            )
            expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-key", "Google uses x-goog-api-key")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            expect(body?["systemInstruction"] != nil, "Google sends systemInstruction")
            return successfulResponse(
                for: request,
                json: #"{"candidates":[{"content":{"parts":[{"text":"google rewrite"}]}}]}"#
            )
        }
        let googleResult = try await googleService.rewritePrompt(
            "draft", instruction: "system", provider: google, model: "gemini-test", apiKey: "gemini-key"
        )
        expect(googleResult == "google rewrite", "Google candidate text is decoded")

        let modelService = makeMockProviderService { request in
            if request.url?.host == "generativelanguage.googleapis.com" {
                return successfulResponse(
                    for: request,
                    json: #"{"models":[{"name":"models/gemini-a","supportedGenerationMethods":["generateContent"]},{"name":"models/embed","supportedGenerationMethods":["embedContent"]}]}"#
                )
            }
            return successfulResponse(for: request, json: #"{"data":[{"id":"model-b"},{"id":"model-a"}]}"#)
        }
        let googleModels = try await modelService.availableModels(provider: google, apiKey: "gemini-key")
        let openRouterModels = try await modelService.availableModels(provider: openRouter, apiKey: "router-key")
        expect(googleModels == ["gemini-a"], "Google model discovery filters generateContent models")
        expect(openRouterModels == ["model-a", "model-b"], "OpenAI model discovery sorts model identifiers")

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

        let miniMax = CueAIProvider.builtIn(.miniMax)!
        let miniMaxService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "https://api.minimax.io/anthropic/v1/messages",
                "MiniMax intl uses the Messages endpoint on its Anthropic-compatible base"
            )
            expect(
                request.value(forHTTPHeaderField: "x-api-key") == "minimax-key",
                "MiniMax intl uses Anthropic vendor authentication"
            )
            expect(
                request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
                "MiniMax intl keeps the Anthropic protocol version header"
            )
            return successfulResponse(
                for: request,
                json: #"{"content":[{"type":"text","text":"minimax rewrite"}]}"#
            )
        }
        let miniMaxResult = try await miniMaxService.rewritePrompt(
            "draft", instruction: "system", provider: miniMax,
            model: "MiniMax-M3", apiKey: "minimax-key"
        )
        expect(miniMaxResult == "minimax rewrite", "MiniMax intl Anthropic text is decoded")

        let siliconFlow = CueAIProvider.builtIn(.siliconFlow)!
        let siliconFlowService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "https://api.siliconflow.cn/v1/chat/completions",
                "SiliconFlow uses the OpenAI-compatible Chat Completions endpoint"
            )
            expect(
                request.value(forHTTPHeaderField: "Authorization") == "Bearer siliconflow-key",
                "SiliconFlow uses bearer auth"
            )
            return successfulResponse(
                for: request,
                json: #"{"choices":[{"message":{"content":"siliconflow rewrite"}}]}"#
            )
        }
        let siliconFlowResult = try await siliconFlowService.rewritePrompt(
            "draft", instruction: "system", provider: siliconFlow,
            model: "deepseek-ai/DeepSeek-V3", apiKey: "siliconflow-key"
        )
        expect(siliconFlowResult == "siliconflow rewrite", "SiliconFlow text is decoded")

        let ollama = CueAIProvider.builtIn(.ollama)!
        let ollamaService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "http://localhost:11434/v1/chat/completions",
                "Ollama uses the OpenAI-compatible Chat Completions endpoint"
            )
            expect(
                request.value(forHTTPHeaderField: "Authorization") == nil,
                "local providers send no auth header without a key"
            )
            return successfulResponse(
                for: request,
                json: #"{"choices":[{"message":{"content":"local rewrite"}}]}"#
            )
        }
        let ollamaResult = try await ollamaService.rewritePrompt(
            "draft", instruction: "system", provider: ollama,
            model: "qwen3", apiKey: nil
        )
        expect(ollamaResult == "local rewrite", "local rewrite works without credentials")

        let ollamaDiscovery = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "http://localhost:11434/v1/models",
                "local model discovery uses the OpenAI-compatible models endpoint"
            )
            return successfulResponse(
                for: request,
                json: #"{"data":[{"id":"qwen3"},{"id":"llama3.3"}]}"#
            )
        }
        let ollamaModels = try await ollamaDiscovery.availableModels(provider: ollama, apiKey: nil)
        expect(ollamaModels == ["llama3.3", "qwen3"], "local model discovery works without credentials")

        let openCodeAnthropic = CueAIProvider.builtIn(.openCode, api: .anthropicMessages)!
        let openCodeService = makeMockProviderService { request in
            expect(
                request.value(forHTTPHeaderField: "Authorization") == "Bearer opencode-key",
                "OpenCode Anthropic-compatible API uses bearer auth"
            )
            expect(
                request.value(forHTTPHeaderField: "x-api-key") == nil,
                "OpenCode does not use Anthropic vendor authentication"
            )
            expect(
                request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
                "Anthropic-compatible bearer endpoints retain the protocol version header"
            )
            return successfulResponse(
                for: request,
                json: #"{"content":[{"type":"text","text":"opencode rewrite"}]}"#
            )
        }
        let openCodeResult = try await openCodeService.rewritePrompt(
            "draft", instruction: "system", provider: openCodeAnthropic,
            model: "claude-test", apiKey: "opencode-key"
        )
        expect(openCodeResult == "opencode rewrite", "OpenCode Anthropic response is decoded")

        let azure = CueAIProvider.builtIn(
            .azureOpenAI,
            baseURLOverride: URL(string: "https://example.openai.azure.com/openai/v1")!
        )!
        let azureService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString == "https://example.openai.azure.com/openai/v1/responses",
                "Azure uses the v1 Responses endpoint"
            )
            expect(request.value(forHTTPHeaderField: "api-key") == "azure-key", "Azure uses api-key auth")
            return successfulResponse(
                for: request,
                json: #"{"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"azure rewrite"}]}]}"#
            )
        }
        let azureResult = try await azureService.rewritePrompt(
            "draft", instruction: "system", provider: azure, model: "deployment-name", apiKey: "azure-key"
        )
        expect(azureResult == "azure rewrite", "Azure Responses text is decoded")

        let vertex = CueAIProvider.builtIn(
            .googleVertex,
            baseURLOverride: URL(string: "https://us-central1-aiplatform.googleapis.com/v1/projects/demo/locations/us-central1/publishers/google")!
        )!
        let vertexService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString
                    == "https://us-central1-aiplatform.googleapis.com/v1/projects/demo/locations/us-central1/publishers/google/models/gemini-test:generateContent",
                "Vertex uses the complete publisher model endpoint"
            )
            expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "vertex-key", "Vertex uses Google API key auth")
            return successfulResponse(
                for: request,
                json: #"{"candidates":[{"content":{"parts":[{"text":"vertex rewrite"}]}}]}"#
            )
        }
        let vertexResult = try await vertexService.rewritePrompt(
            "draft", instruction: "system", provider: vertex, model: "gemini-test", apiKey: "vertex-key"
        )
        expect(vertexResult == "vertex rewrite", "Vertex candidate text is decoded")

        let bedrock = CueAIProvider.builtIn(.amazonBedrock)!
        let bedrockService = makeMockProviderService { request in
            expect(
                request.url?.absoluteString
                    == "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.nova-2-lite-v1:0/converse",
                "Bedrock uses the Converse endpoint"
            )
            expect(
                request.value(forHTTPHeaderField: "Authorization") == "Bearer bedrock-token",
                "Bedrock API key uses bearer auth"
            )
            return successfulResponse(
                for: request,
                json: #"{"output":{"message":{"content":[{"text":"bedrock rewrite"}]}}}"#
            )
        }
        let bedrockResult = try await bedrockService.rewritePrompt(
            "draft", instruction: "system", provider: bedrock,
            model: "amazon.nova-2-lite-v1:0", apiKey: "bedrock-token"
        )
        expect(bedrockResult == "bedrock rewrite", "Bedrock Converse text is decoded")

        let cloudflare = CueAIProvider.builtIn(
            .cloudflareAIGateway,
            api: .openAIResponses,
            baseURLOverride: URL(string: "https://gateway.ai.cloudflare.com/v1/account/gateway/openai")!
        )!
        let cloudflareService = makeMockProviderService { request in
            expect(
                request.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer cloudflare-key",
                "Cloudflare uses gateway authentication"
            )
            expect(
                request.value(forHTTPHeaderField: "Authorization") == nil,
                "Cloudflare does not forward its gateway key as upstream auth"
            )
            return successfulResponse(
                for: request,
                json: #"{"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"gateway rewrite"}]}]}"#
            )
        }
        let cloudflareResult = try await cloudflareService.rewritePrompt(
            "draft", instruction: "system", provider: cloudflare, model: "gpt-test", apiKey: "cloudflare-key"
        )
        expect(cloudflareResult == "gateway rewrite", "Cloudflare gateway response is decoded")
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
        CueAPIKeyStore.environmentOverride = [:]
        defer {
            CueAPIKeyStore.configurationURLOverride = nil
            CueAPIKeyStore.environmentOverride = nil
        }

        let versionOneData = try fixtureData(named: "config-v1.json")
        try versionOneData.write(to: url)
        let versionOneDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        expect(
            versionOneDeepSeekKey == "fixture-key",
            "schema v1 DeepSeek key remains readable before migration"
        )
        try CueAPIKeyStore.saveAPIKey("openai-key", for: .openAI)
        let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let migratedKeys = migrated?["providerAPIKeys"] as? [String: Any]
        expect(migrated?["schemaVersion"] as? Int == 2, "API key config migrates to schema v2")
        expect(migrated?["deepSeekAPIKey"] as? String == "fixture-key", "migration preserves the legacy key")
        expect(migratedKeys?["deepseek"] as? String == "fixture-key", "migration copies the DeepSeek key")
        expect(migratedKeys?["openai"] as? String == "openai-key", "provider keys are stored independently")
        expect(
            migrated?["futureField"] as? String == "must-survive-a-supported-write",
            "API key migration preserves unknown fields"
        )
        let backupURL = directory.appendingPathComponent("config.v1.backup.json")
        let backupData = try Data(contentsOf: backupURL)
        expect(backupData == versionOneData, "migration keeps an exact version-one backup")

        try fixtureData(named: "config-v2.json").write(to: url)
        let versionTwoOpenAIKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let versionTwoDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        let versionTwoMiniMaxKey = try CueAPIKeyStore.loadAPIKey(for: .miniMaxTokenPlanCN)
        let versionTwoGroqKey = try CueAPIKeyStore.loadAPIKey(for: .groq)
        let versionTwoSiliconFlowKey = try CueAPIKeyStore.loadAPIKey(for: .siliconFlow)
        expect(versionTwoOpenAIKey == "openai-v2-key", "schema v2 fixture is readable")
        expect(versionTwoDeepSeekKey == "deepseek-v2-key", "v2 provider key wins")
        expect(versionTwoMiniMaxKey == "minimax-plan-v2-key", "coding plan keys are readable")
        expect(versionTwoGroqKey == "groq-v2-key", "platform provider keys are readable")
        expect(versionTwoSiliconFlowKey == "siliconflow-v2-key", "domestic API keys are readable")
        try CueAPIKeyStore.saveAPIKey("anthropic-key", for: .anthropic)
        try CueAPIKeyStore.removeAPIKey(for: .deepSeek)
        let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let updatedKeys = updated?["providerAPIKeys"] as? [String: Any]
        expect(updatedKeys?["deepseek"] == nil, "removing a provider key only removes its v2 entry")
        expect(updatedKeys?["openai"] as? String == "openai-v2-key", "removing one key preserves other providers")
        expect(updatedKeys?["minimax-cn"] as? String == "minimax-plan-v2-key", "removing preserves coding plan keys")
        expect(updatedKeys?["groq"] as? String == "groq-v2-key", "removing preserves platform keys")
        expect(updatedKeys?["siliconflow"] as? String == "siliconflow-v2-key", "removing preserves domestic API keys")
        expect(updatedKeys?["anthropic"] as? String == "anthropic-key", "new providers persist in schema v2")
        expect(updated?["deepSeekAPIKey"] as? String == "legacy-copy-must-survive", "v2 writes preserve legacy source data")
        let removedDeepSeekKey = try CueAPIKeyStore.loadAPIKey(for: .deepSeek)
        expect(removedDeepSeekKey == nil, "a removed v2 DeepSeek key is not revived")
        expect(
            updated?["futureField"] as? String == "must-survive-a-supported-write",
            "schema v2 writes preserve unknown fields"
        )

        let futureData = try fixtureData(named: "config-future.json")
        try futureData.write(to: url)
        let futureAnthropicKey = try CueAPIKeyStore.loadAPIKey(for: .anthropic)
        expect(
            futureAnthropicKey == "future-anthropic-key",
            "future schema known provider keys remain readable"
        )
        expectThrows(
            try CueAPIKeyStore.saveAPIKey("must-not-write", for: .google),
            "API key writes reject future schemas"
        )
        expectThrows(
            try CueAPIKeyStore.removeAPIKey(for: .anthropic),
            "API key removal rejects future schemas"
        )
        let unchangedFutureData = try Data(contentsOf: url)
        expect(unchangedFutureData == futureData, "future API key config remains unchanged")

        for fixture in ["config-corrupt.json", "config-v2-corrupt-provider-keys.json"] {
            let corruptData = try fixtureData(named: fixture)
            try corruptData.write(to: url)
            expectThrows(
                try CueAPIKeyStore.saveAPIKey("must-not-write", for: .openRouter),
                "\(fixture) rejects writes"
            )
            expectThrows(
                try CueAPIKeyStore.removeAPIKey(for: .deepSeek),
                "\(fixture) rejects removal"
            )
            let unchangedCorruptData = try Data(contentsOf: url)
            expect(unchangedCorruptData == corruptData, "\(fixture) remains unchanged")
        }

        try fixtureData(named: "config-v2.json").write(to: url)
        CueAPIKeyStore.environmentOverride = ["OPENAI_API_KEY": "environment-openai-key"]
        let environmentOpenAIKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        expect(environmentOpenAIKey == "environment-openai-key", "environment key takes priority")
        let environmentSource = try CueAPIKeyStore.source(for: .openAI)
        let hadStoredOpenAIKey = try CueAPIKeyStore.hasStoredAPIKey(for: .openAI)
        expect(
            environmentSource == .environment("OPENAI_API_KEY"),
            "credential source reports the environment variable"
        )
        expect(hadStoredOpenAIKey, "stored key remains visible below environment auth")
        try CueAPIKeyStore.removeAPIKey(for: .openAI)
        let remainingEnvironmentKey = try CueAPIKeyStore.loadAPIKey(for: .openAI)
        let hasStoredOpenAIKey = try CueAPIKeyStore.hasStoredAPIKey(for: .openAI)
        expect(remainingEnvironmentKey == "environment-openai-key", "removing local key preserves environment auth")
        expect(!hasStoredOpenAIKey, "local key is removed independently")
        CueAPIKeyStore.environmentOverride = [:]
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
        CueAPIKeyStore.environmentOverride = [:]
        defer {
            CueAPIKeyStore.configurationURLOverride = nil
            CueAPIKeyStore.environmentOverride = nil
        }
        try fixtureData(named: "config-v2.json").write(to: url)

        let settings = CueSettings(defaults: defaults, aiProviderService: StubAIProviderService())
        expect(
            settings.credentialSource(for: .openAI) == .configuration,
            "credential source resolves a stored key per provider"
        )
        expect(settings.hasStoredCredential(for: .openAI), "stored credential is visible per provider")
        expect(!settings.hasStoredCredential(for: .anthropic), "unconfigured providers have no stored credential")
        expect(settings.credentialSource(for: .ollama) == nil, "local providers have no credential source")

        settings.promptExpansionProvider = .openAI
        settings.removeCredential(for: .siliconFlow)
        expect(
            settings.credentialSource(for: .siliconFlow) == nil,
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
        expect(keys?["deepseek"] as? String == "deepseek-v2-key", "removals preserve unrelated provider keys")
        expect(keys?["minimax-cn"] as? String == "minimax-plan-v2-key", "removals preserve coding plan keys")
        expect(keys?["openai"] == nil, "active provider key is removed from the document")
        expect(keys?["siliconflow"] == nil, "management list removal is written through")
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

    let englishSuite = "cue-settings-en-\(UUID().uuidString)"
    let englishDefaults = UserDefaults(suiteName: englishSuite)!
    defer { englishDefaults.removePersistentDomain(forName: englishSuite) }
    englishDefaults.set(CueLanguage.english.rawValue, forKey: "language")
    englishDefaults.set(true, forKey: "inlineCompletionEnabled")
    englishDefaults.set("legacy-model", forKey: "inlineCompletionModel")
    englishDefaults.set("legacy-deepseek-model", forKey: "promptExpansionModel")
    let english = CueSettings(defaults: englishDefaults, aiProviderService: StubAIProviderService())
    expect(!english.locksPromptWindow, "window resizing is unlocked by default")
    expect(english.promptExpansionProvider == .deepSeek, "legacy settings default to DeepSeek provider")
    expect(english.promptExpansionModel == "legacy-deepseek-model", "legacy DeepSeek model remains selected")
    english.promptExpansionProvider = .openAI
    english.promptExpansionModel = "gpt-model"
    english.promptExpansionProvider = .custom
    english.promptExpansionAPI = .anthropicMessages
    english.providerBaseURL = "http://localhost:9000"
    english.promptExpansionModel = "custom-anthropic-model"
    english.promptExpansionAPI = .openAICompletions
    english.promptExpansionModel = "custom-openai-model"
    english.promptExpansionAPI = .anthropicMessages
    expect(
        english.promptExpansionModel == "custom-anthropic-model",
        "models persist independently for each provider API"
    )
    english.promptExpansionProvider = .openAI
    expect(english.promptExpansionModel == "gpt-model", "provider switching restores the provider model")
    english.promptExpansionProvider = .custom
    expect(english.promptExpansionModel == "custom-anthropic-model", "custom provider model remains independent")
    expect(english.promptExpansionAPI == .anthropicMessages, "custom provider API persists in settings")
    expect(english.providerBaseURL == "http://localhost:9000", "custom provider Base URL persists")
    english.promptExpansionProvider = .cloudflareAIGateway
    english.promptExpansionAPI = .openAICompletions
    english.providerBaseURL = "https://gateway.ai.cloudflare.com/v1/account/gateway/compat"
    english.promptExpansionModel = "workers-model"
    english.promptExpansionAPI = .openAIResponses
    english.providerBaseURL = "https://gateway.ai.cloudflare.com/v1/account/gateway/openai"
    english.promptExpansionModel = "responses-model"
    english.promptExpansionAPI = .openAICompletions
    expect(english.promptExpansionModel == "workers-model", "gateway models are isolated by API")
    expect(
        english.providerBaseURL == "https://gateway.ai.cloudflare.com/v1/account/gateway/compat",
        "gateway Base URLs are isolated by API"
    )
    english.promptExpansionAPI = .openAIResponses
    let reloadedGateway = CueSettings(defaults: englishDefaults, aiProviderService: StubAIProviderService())
    expect(reloadedGateway.promptExpansionProvider == .cloudflareAIGateway, "gateway provider persists")
    expect(reloadedGateway.promptExpansionAPI == .openAIResponses, "gateway API persists")
    expect(reloadedGateway.promptExpansionModel == "responses-model", "gateway API model persists")
    expect(
        reloadedGateway.providerBaseURL == "https://gateway.ai.cloudflare.com/v1/account/gateway/openai",
        "gateway API Base URL persists"
    )
    reloadedGateway.promptExpansionProvider = .custom
    let reloadedProviders = CueSettings(defaults: englishDefaults, aiProviderService: StubAIProviderService())
    expect(reloadedProviders.promptExpansionProvider == .custom, "selected provider persists")
    expect(reloadedProviders.promptExpansionModel == "custom-anthropic-model", "selected provider model persists")
    reloadedProviders.promptExpansionModel = nil
    let reloadedWithoutModel = CueSettings(defaults: englishDefaults, aiProviderService: StubAIProviderService())
    expect(reloadedWithoutModel.promptExpansionModel == nil, "clearing a provider model persists")
    expect(
        english.promptExpansionInstruction
            == CueLocalization.string(.settingsAIRewriteDefaultPrompt, localization: "en"),
        "English settings use the English rewrite prompt"
    )
    english.locksPromptWindow = true
    english.restoreAllSettings()
    expect(!english.locksPromptWindow, "restoring settings unlocks bottom-edge resizing")
    expect(
        englishDefaults.bool(forKey: "inlineCompletionEnabled")
            && englishDefaults.string(forKey: "inlineCompletionModel") == "legacy-model",
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
