import AppKit
import Combine
import CueCore
import Foundation

enum CueLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
}

enum InlineCompletionTriggerMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }
}

enum CueOverflowBehavior: String, CaseIterable, Identifiable {
    case scrollable
    case growWithContent

    var id: String { rawValue }
}

struct InlineCompletionStatus: Equatable {
    enum Style: Equatable {
        case information
        case error
    }

    let message: String
    let style: Style
}

final class CueSettings: ObservableObject {
    static let defaultWindowWidth = Double(NotchLayoutConstraints.defaultOpenWidth)
    static let defaultWindowHeight = Double(NotchLayoutConstraints.defaultOpenHeight)
    static let minimumWindowHeight = Double(NotchLayoutConstraints.minimumOpenHeight)
    static let maximumWindowHeight = Double(NotchLayoutConstraints.maximumOpenHeight)
    static let minimumWindowWidth = Double(NotchLayoutConstraints.minimumOpenWidth)
    static let maximumWindowWidth = Double(NotchLayoutConstraints.maximumOpenWidth)
    static let defaultEditorFontSize = 16.0
    static let persistenceSchemaVersion = 1
    static let minimumEditorFontSize = 8.0
    static let maximumEditorFontSize = 72.0
    static let defaultInlineCompletionDelayMilliseconds = 200.0
    static let maximumInlineCompletionDelayMilliseconds = 5_000.0
    static let defaultInlineCompletionMaximumLines = 1
    static let maximumInlineCompletionLines = 100

    private let defaults: UserDefaults
    private let deepSeekService: any DeepSeekService
    private let piIntegrationService: CuePiIntegrationService

    @Published var language: CueLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var windowWidth: Double {
        didSet {
            let clamped = min(max(windowWidth, Self.minimumWindowWidth), Self.maximumWindowWidth)
            guard clamped == windowWidth else {
                windowWidth = clamped
                return
            }
            defaults.set(windowWidth, forKey: Keys.windowWidth)
        }
    }

    @Published var windowHeight: Double {
        didSet {
            let clamped = min(max(windowHeight, Self.minimumWindowHeight), Self.maximumWindowHeight)
            guard clamped == windowHeight else {
                windowHeight = clamped
                return
            }
            defaults.set(windowHeight, forKey: Keys.windowHeight)
        }
    }

    @Published var overflowBehavior: CueOverflowBehavior {
        didSet { defaults.set(overflowBehavior.rawValue, forKey: Keys.overflowBehavior) }
    }

    /// Stored as a PostScript name because it remains stable across localized font display names.
    @Published var editorFontName: String {
        didSet { defaults.set(editorFontName, forKey: Keys.editorFontName) }
    }

    @Published var editorFontSize: Double {
        didSet {
            let clamped = min(max(editorFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
            guard clamped == editorFontSize else {
                editorFontSize = clamped
                return
            }
            defaults.set(editorFontSize, forKey: Keys.editorFontSize)
        }
    }

    @Published var insertsSpacesBetweenChineseAndEnglish: Bool {
        didSet { defaults.set(insertsSpacesBetweenChineseAndEnglish, forKey: Keys.insertsSpacesBetweenChineseAndEnglish) }
    }

    @Published var inlineCompletionEnabled: Bool {
        didSet {
            defaults.set(inlineCompletionEnabled, forKey: Keys.inlineCompletionEnabled)
            if inlineCompletionEnabled { refreshDeepSeekModelsIfPossible() }
        }
    }

    @Published var inlineCompletionTriggerMode: InlineCompletionTriggerMode {
        didSet { defaults.set(inlineCompletionTriggerMode.rawValue, forKey: Keys.inlineCompletionTriggerMode) }
    }
    @Published var inlineCompletionDelayMilliseconds: Double {
        didSet {
            defaults.set(
                min(max(inlineCompletionDelayMilliseconds, 0), Self.maximumInlineCompletionDelayMilliseconds),
                forKey: Keys.inlineCompletionDelayMilliseconds
            )
        }
    }
    @Published var inlineCompletionMaximumLines: Int {
        didSet {
            defaults.set(
                min(max(inlineCompletionMaximumLines, 1), Self.maximumInlineCompletionLines),
                forKey: Keys.inlineCompletionMaximumLines
            )
        }
    }

    @Published var promptExpansionModel: String? {
        didSet { defaults.set(promptExpansionModel, forKey: Keys.promptExpansionModel) }
    }
    @Published var promptExpansionInstruction: String {
        didSet { defaults.set(promptExpansionInstruction, forKey: Keys.promptExpansionInstruction) }
    }

    @Published var inlineCompletionModel: String? {
        didSet {
            if let inlineCompletionModel {
                defaults.set(inlineCompletionModel, forKey: Keys.inlineCompletionModel)
            } else {
                defaults.removeObject(forKey: Keys.inlineCompletionModel)
            }
        }
    }
    @Published private(set) var inlineCompletionModels = [String]()
    @Published private(set) var isLoadingInlineCompletionModels = false
    @Published private(set) var isTestingInlineCompletionConnection = false
    @Published var inlineCompletionKeyConfigured = false
    @Published private(set) var inlineCompletionStatus: InlineCompletionStatus?

    @Published private(set) var piIntegrationState: PiIntegrationState = .notInstalled
    @Published private(set) var piIntegrationErrorMessage: String?

    @Published var toggleShortcut: CueShortcut {
        didSet { save(toggleShortcut, key: Keys.toggleShortcut) }
    }
    @Published var previousShortcut: CueShortcut {
        didSet { save(previousShortcut, key: Keys.previousShortcut) }
    }
    @Published var nextShortcut: CueShortcut {
        didSet { save(nextShortcut, key: Keys.nextShortcut) }
    }
    @Published var inlineCompletionShortcut: CueShortcut {
        didSet { save(inlineCompletionShortcut, key: Keys.inlineCompletionShortcut) }
    }
    @Published var inlineCompletionAcceptShortcut: CueShortcut {
        didSet { save(inlineCompletionAcceptShortcut, key: Keys.inlineCompletionAcceptShortcut) }
    }
    @Published var promptExpansionShortcut: CueShortcut {
        didSet { save(promptExpansionShortcut, key: Keys.promptExpansionShortcut) }
    }

    var localizationIdentifier: String? { language.localizationIdentifier }
    var normalizedWidth: Double { min(max(windowWidth, Self.minimumWindowWidth), Self.maximumWindowWidth) }
    var normalizedHeight: Double { min(max(windowHeight, Self.minimumWindowHeight), Self.maximumWindowHeight) }

    /// Falls back safely if a font selected on another machine is not installed here.
    var editorFont: NSFont {
        NSFont(name: editorFontName, size: CGFloat(editorFontSize))
            ?? .systemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    func setEditorFont(_ font: NSFont) {
        editorFontName = font.fontName
        editorFontSize = Double(font.pointSize)
    }

    func restoreDefaultEditorFont() {
        editorFontName = Self.defaultEditorFont.fontName
        editorFontSize = Self.defaultEditorFontSize
    }

    func adjustEditorFontSize(by delta: Double) {
        editorFontSize = min(
            max(editorFontSize + delta, Self.minimumEditorFontSize),
            Self.maximumEditorFontSize
        )
    }

    /// Explicitly restores application preferences. API keys and usage history
    /// are separate user data and are intentionally not included.
    func restoreAllSettings() {
        language = .system
        windowWidth = Self.defaultWindowWidth
        windowHeight = Self.defaultWindowHeight
        overflowBehavior = .scrollable
        restoreDefaultEditorFont()
        insertsSpacesBetweenChineseAndEnglish = false
        inlineCompletionEnabled = false
        inlineCompletionTriggerMode = .manual
        inlineCompletionDelayMilliseconds = Self.defaultInlineCompletionDelayMilliseconds
        inlineCompletionMaximumLines = Self.defaultInlineCompletionMaximumLines
        inlineCompletionModel = nil
        promptExpansionModel = nil
        promptExpansionInstruction = localizedDefaultPromptInstruction()
        toggleShortcut = .toggleDefault
        previousShortcut = .previousDefault
        nextShortcut = .nextDefault
        inlineCompletionShortcut = .inlineCompletionDefault
        inlineCompletionAcceptShortcut = .inlineCompletionAcceptDefault
        promptExpansionShortcut = .promptExpansionDefault
        inlineCompletionStatus = nil
    }

    private func localizedDefaultPromptInstruction() -> String {
        Self.defaultPromptInstruction(for: language)
    }

    private static func defaultPromptInstruction(for language: CueLanguage) -> String {
        CueLocalization.string(
            .settingsAIRewriteDefaultPrompt,
            localization: language.localizationIdentifier
        )
    }

    private static var defaultEditorFont: NSFont {
        .systemFont(ofSize: CGFloat(defaultEditorFontSize), weight: .regular)
    }

    init(
        defaults: UserDefaults = .standard,
        deepSeekService: any DeepSeekService = DeepSeekFIMCompletionProvider(),
        piIntegrationService: CuePiIntegrationService = .shared
    ) {
        self.defaults = defaults
        self.deepSeekService = deepSeekService
        self.piIntegrationService = piIntegrationService
        if defaults.object(forKey: Keys.schemaVersion) == nil {
            defaults.set(Self.persistenceSchemaVersion, forKey: Keys.schemaVersion)
        }
        defaults.register(defaults: [
            Keys.language: CueLanguage.system.rawValue,
            Keys.windowWidth: Self.defaultWindowWidth,
            Keys.windowHeight: Self.defaultWindowHeight,
            Keys.overflowBehavior: CueOverflowBehavior.scrollable.rawValue,
            Keys.editorFontName: Self.defaultEditorFont.fontName,
            Keys.editorFontSize: Self.defaultEditorFontSize,
            Keys.insertsSpacesBetweenChineseAndEnglish: false,
            Keys.inlineCompletionEnabled: false,
            Keys.inlineCompletionTriggerMode: InlineCompletionTriggerMode.manual.rawValue,
            Keys.inlineCompletionDelayMilliseconds: Self.defaultInlineCompletionDelayMilliseconds,
            Keys.inlineCompletionMaximumLines: Self.defaultInlineCompletionMaximumLines,
        ])

        let selectedLanguage = CueLanguage(
            rawValue: defaults.string(forKey: Keys.language) ?? CueLanguage.system.rawValue
        ) ?? .system
        language = selectedLanguage
        let storedWidth = defaults.double(forKey: Keys.windowWidth)
        windowWidth = min(max(storedWidth, Self.minimumWindowWidth), Self.maximumWindowWidth)
        let storedHeight = defaults.double(forKey: Keys.windowHeight)
        windowHeight = min(max(storedHeight, Self.minimumWindowHeight), Self.maximumWindowHeight)
        overflowBehavior = CueOverflowBehavior(
            rawValue: defaults.string(forKey: Keys.overflowBehavior) ?? "scrollable"
        ) ?? .scrollable
        editorFontName = defaults.string(forKey: Keys.editorFontName) ?? Self.defaultEditorFont.fontName
        let storedFontSize = defaults.double(forKey: Keys.editorFontSize)
        editorFontSize = min(max(storedFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
        insertsSpacesBetweenChineseAndEnglish = defaults.bool(forKey: Keys.insertsSpacesBetweenChineseAndEnglish)
        inlineCompletionEnabled = defaults.bool(forKey: Keys.inlineCompletionEnabled)
        inlineCompletionTriggerMode = InlineCompletionTriggerMode(
            rawValue: defaults.string(forKey: Keys.inlineCompletionTriggerMode) ?? InlineCompletionTriggerMode.manual.rawValue
        ) ?? .manual
        inlineCompletionDelayMilliseconds = min(
            max(defaults.double(forKey: Keys.inlineCompletionDelayMilliseconds), 0),
            Self.maximumInlineCompletionDelayMilliseconds
        )
        inlineCompletionMaximumLines = min(
            max(defaults.integer(forKey: Keys.inlineCompletionMaximumLines), 1),
            Self.maximumInlineCompletionLines
        )
        promptExpansionModel = defaults.string(forKey: Keys.promptExpansionModel)
        // A stored instruction is user data, including a prior default that a
        // user may have edited; never replace it during an application update.
        promptExpansionInstruction = defaults.string(forKey: Keys.promptExpansionInstruction)
            ?? Self.defaultPromptInstruction(for: selectedLanguage)
        inlineCompletionModel = defaults.string(forKey: Keys.inlineCompletionModel)
        inlineCompletionKeyConfigured = (try? CueAPIKeyStore.loadDeepSeekAPIKey()) != nil
        toggleShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.toggleShortcut,
            fallback: .toggleDefault
        )
        previousShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.previousShortcut,
            fallback: .previousDefault
        )
        nextShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.nextShortcut,
            fallback: .nextDefault
        )
        inlineCompletionShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.inlineCompletionShortcut,
            fallback: .inlineCompletionDefault
        )
        inlineCompletionAcceptShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.inlineCompletionAcceptShortcut,
            fallback: .inlineCompletionAcceptDefault
        )
        promptExpansionShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.promptExpansionShortcut,
            fallback: .promptExpansionDefault
        )
        piIntegrationState = piIntegrationService.state()
        if inlineCompletionEnabled { refreshDeepSeekModelsIfPossible() }
    }

    var piIntegrationInstalled: Bool {
        if case .installed = piIntegrationState { return true }
        return false
    }

    var piIntegrationDirectoryPath: String {
        piIntegrationService.integrationDirectory.path
    }

    func refreshPiIntegrationState() {
        piIntegrationState = piIntegrationService.state()
    }

    func installPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.install() }
    }

    func repairPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.repair() }
    }

    func uninstallPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.uninstall() }
    }

    private func runPiIntegrationAction(_ action: () throws -> Void) {
        do {
            try action()
            piIntegrationErrorMessage = nil
        } catch {
            piIntegrationErrorMessage = error.localizedDescription
        }
        refreshPiIntegrationState()
    }

    func saveDeepSeekAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setInlineCompletionStatus(.settingsAPIKeyMissing, style: .error)
            return
        }
        do {
            try CueAPIKeyStore.saveDeepSeekAPIKey(trimmed)
            inlineCompletionKeyConfigured = true
            setInlineCompletionStatus(.settingsAPIKeySaved)
            refreshDeepSeekModelsIfPossible()
        } catch {
            setInlineCompletionStatus(error.localizedDescription, style: .error)
        }
    }

    func testDeepSeekFIM() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey() else {
            setInlineCompletionStatus(.settingsAPIKeyMissing, style: .error)
            return
        }
        guard let model = inlineCompletionModel else {
            setInlineCompletionStatus(.settingsModelMissing, style: .error)
            return
        }
        guard !isTestingInlineCompletionConnection else { return }

        isTestingInlineCompletionConnection = true
        setInlineCompletionStatus(.settingsTestingAPIKey)
        Task { @MainActor [weak self] in
            defer { self?.isTestingInlineCompletionConnection = false }
            do {
                guard let service = self?.deepSeekService else { return }
                try await service.validate(apiKey: apiKey, model: model)
                self?.setInlineCompletionStatus(.settingsFIMAvailable)
            } catch {
                self?.setInlineCompletionStatus(.settingsInlineCompletionUnavailable, style: .error)
            }
        }
    }

    func checkDeepSeekServiceHealth() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(),
              !isTestingInlineCompletionConnection
        else {
            if inlineCompletionKeyConfigured == false {
                setInlineCompletionStatus(.settingsAPIKeyMissing, style: .error)
            }
            return
        }

        isTestingInlineCompletionConnection = true
        setInlineCompletionStatus(.settingsCheckingServiceHealth)
        Task { @MainActor [weak self] in
            defer { self?.isTestingInlineCompletionConnection = false }
            do {
                guard let service = self?.deepSeekService else { return }
                _ = try await service.availableModels(apiKey: apiKey)
                self?.setInlineCompletionStatus(.settingsServiceHealthy)
            } catch {
                self?.setInlineCompletionStatus(.settingsInlineCompletionUnavailable, style: .error)
            }
        }
    }

    func refreshDeepSeekModelsIfPossible() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(), !isLoadingInlineCompletionModels else { return }
        isLoadingInlineCompletionModels = true
        setInlineCompletionStatus(.settingsLoadingModels)
        Task { @MainActor [weak self] in
            defer { self?.isLoadingInlineCompletionModels = false }
            do {
                guard let service = self?.deepSeekService else { return }
                let models = try await service.availableModels(apiKey: apiKey)
                guard !models.isEmpty else {
                    self?.setInlineCompletionStatus(.settingsInlineCompletionUnavailable, style: .error)
                    return
                }
                self?.inlineCompletionModels = models
                if let self, let selectedModel = self.inlineCompletionModel, !models.contains(selectedModel) {
                    self.inlineCompletionModel = nil
                }
                self?.inlineCompletionStatus = nil
            } catch {
                self?.setInlineCompletionStatus(.settingsInlineCompletionUnavailable, style: .error)
            }
        }
    }

    func removeDeepSeekAPIKey() {
        do {
            try CueAPIKeyStore.removeDeepSeekAPIKey()
            inlineCompletionKeyConfigured = false
            inlineCompletionEnabled = false
            inlineCompletionModel = nil
            inlineCompletionModels = []
            setInlineCompletionStatus(.settingsAPIKeyRemoved)
        } catch {
            setInlineCompletionStatus(error.localizedDescription, style: .error)
        }
    }

    func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: language.localizationIdentifier)
    }

    func reportInlineCompletionFailure(_ key: CueLocalizedKey) {
        setInlineCompletionStatus(key, style: .error)
    }

    func expandPrompt(_ text: String) async throws -> String? {
        guard let apiKey = try CueAPIKeyStore.loadDeepSeekAPIKey(),
              let model = promptExpansionModel
        else { return nil }
        do {
            let expanded = try await deepSeekService.expandPrompt(
                text,
                instruction: promptExpansionInstruction,
                model: model,
                apiKey: apiKey
            )
            inlineCompletionStatus = nil
            return expanded
        } catch {
            setInlineCompletionStatus(.settingsInlineCompletionUnavailable, style: .error)
            throw error
        }
    }

    private func setInlineCompletionStatus(
        _ key: CueLocalizedKey,
        style: InlineCompletionStatus.Style = .information
    ) {
        setInlineCompletionStatus(localized(key), style: style)
    }

    private func setInlineCompletionStatus(
        _ message: String,
        style: InlineCompletionStatus.Style = .information
    ) {
        inlineCompletionStatus = InlineCompletionStatus(message: message, style: style)
    }

    private func save(_ shortcut: CueShortcut, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadShortcut(
        from defaults: UserDefaults,
        key: String,
        fallback: CueShortcut
    ) -> CueShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(CueShortcut.self, from: data)
        else { return fallback }
        return shortcut
    }

    private enum Keys {
        static let schemaVersion = "cueSettingsSchemaVersion"
        static let language = "language"
        static let windowWidth = "windowWidth"
        static let windowHeight = "windowHeight"
        static let overflowBehavior = "overflowBehavior"
        static let editorFontName = "editorFontName"
        static let editorFontSize = "editorFontSize"
        static let insertsSpacesBetweenChineseAndEnglish = "insertsSpacesBetweenChineseAndEnglish"
        static let inlineCompletionEnabled = "inlineCompletionEnabled"
        static let inlineCompletionTriggerMode = "inlineCompletionTriggerMode"
        static let inlineCompletionDelayMilliseconds = "inlineCompletionDelayMilliseconds"
        static let inlineCompletionMaximumLines = "inlineCompletionMaximumLines"
        static let promptExpansionModel = "promptExpansionModel"
        static let promptExpansionInstruction = "promptExpansionInstruction"
        static let inlineCompletionModel = "inlineCompletionModel"
        static let toggleShortcut = "toggleShortcut"
        static let previousShortcut = "previousShortcut"
        static let nextShortcut = "nextShortcut"
        static let inlineCompletionShortcut = "inlineCompletionShortcut"
        static let inlineCompletionAcceptShortcut = "inlineCompletionAcceptShortcut"
        static let promptExpansionShortcut = "promptExpansionShortcut"
    }
}
