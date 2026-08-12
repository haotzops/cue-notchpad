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

enum CueOverflowBehavior: String, CaseIterable, Identifiable {
    case scrollable
    case growWithContent

    var id: String { rawValue }
}

struct AIServiceStatus: Equatable {
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

    @Published var promptExpansionModel: String? {
        didSet { defaults.set(promptExpansionModel, forKey: Keys.promptExpansionModel) }
    }
    @Published var promptExpansionInstruction: String {
        didSet { defaults.set(promptExpansionInstruction, forKey: Keys.promptExpansionInstruction) }
    }

    @Published private(set) var deepSeekModels = [String]()
    @Published private(set) var isLoadingDeepSeekModels = false
    @Published private(set) var isTestingDeepSeekConnection = false
    @Published var deepSeekKeyConfigured = false
    @Published private(set) var deepSeekStatus: AIServiceStatus?

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
        promptExpansionModel = nil
        promptExpansionInstruction = localizedDefaultPromptInstruction()
        toggleShortcut = .toggleDefault
        previousShortcut = .previousDefault
        nextShortcut = .nextDefault
        promptExpansionShortcut = .promptExpansionDefault
        deepSeekStatus = nil
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
        deepSeekService: any DeepSeekService = DeepSeekChatService(),
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
        promptExpansionModel = defaults.string(forKey: Keys.promptExpansionModel)
        // A stored instruction is user data, including a prior default that a
        // user may have edited; never replace it during an application update.
        promptExpansionInstruction = defaults.string(forKey: Keys.promptExpansionInstruction)
            ?? Self.defaultPromptInstruction(for: selectedLanguage)
        deepSeekKeyConfigured = (try? CueAPIKeyStore.loadDeepSeekAPIKey()) != nil
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
        promptExpansionShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.promptExpansionShortcut,
            fallback: .promptExpansionDefault
        )
        piIntegrationState = piIntegrationService.state()
        if deepSeekKeyConfigured { refreshDeepSeekModelsIfPossible() }
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
            setDeepSeekStatus(.settingsAPIKeyMissing, style: .error)
            return
        }
        do {
            try CueAPIKeyStore.saveDeepSeekAPIKey(trimmed)
            deepSeekKeyConfigured = true
            setDeepSeekStatus(.settingsAPIKeySaved)
            refreshDeepSeekModelsIfPossible()
        } catch {
            setDeepSeekStatus(error.localizedDescription, style: .error)
        }
    }

    func checkDeepSeekServiceHealth() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(),
              !isTestingDeepSeekConnection
        else {
            if !deepSeekKeyConfigured {
                setDeepSeekStatus(.settingsAPIKeyMissing, style: .error)
            }
            return
        }

        isTestingDeepSeekConnection = true
        setDeepSeekStatus(.settingsCheckingServiceHealth)
        Task { @MainActor [weak self] in
            defer { self?.isTestingDeepSeekConnection = false }
            do {
                guard let service = self?.deepSeekService else { return }
                _ = try await service.availableModels(apiKey: apiKey)
                self?.setDeepSeekStatus(.settingsServiceHealthy)
            } catch {
                self?.setDeepSeekStatus(.settingsAIRewriteUnavailable, style: .error)
            }
        }
    }

    func refreshDeepSeekModelsIfPossible() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(), !isLoadingDeepSeekModels else { return }
        isLoadingDeepSeekModels = true
        setDeepSeekStatus(.settingsLoadingModels)
        Task { @MainActor [weak self] in
            defer { self?.isLoadingDeepSeekModels = false }
            do {
                guard let service = self?.deepSeekService else { return }
                let models = try await service.availableModels(apiKey: apiKey)
                guard !models.isEmpty else {
                    self?.setDeepSeekStatus(.settingsAIRewriteUnavailable, style: .error)
                    return
                }
                self?.deepSeekModels = models
                if let self, let selectedModel = self.promptExpansionModel, !models.contains(selectedModel) {
                    self.promptExpansionModel = nil
                }
                self?.deepSeekStatus = nil
            } catch {
                self?.setDeepSeekStatus(.settingsAIRewriteUnavailable, style: .error)
            }
        }
    }

    func removeDeepSeekAPIKey() {
        do {
            try CueAPIKeyStore.removeDeepSeekAPIKey()
            deepSeekKeyConfigured = false
            deepSeekModels = []
            setDeepSeekStatus(.settingsAPIKeyRemoved)
        } catch {
            setDeepSeekStatus(error.localizedDescription, style: .error)
        }
    }

    func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: language.localizationIdentifier)
    }

    func expandPrompt(_ text: String, message: String?) async throws -> String? {
        guard let apiKey = try CueAPIKeyStore.loadDeepSeekAPIKey(),
              let model = promptExpansionModel
        else { return nil }
        do {
            let instruction = PromptRewriteTemplate.render(
                promptExpansionInstruction,
                message: message
            )
            let result = try await deepSeekService.rewritePrompt(
                text,
                instruction: instruction,
                model: model,
                apiKey: apiKey
            )
            deepSeekStatus = nil
            return result
        } catch {
            setDeepSeekStatus(.settingsAIRewriteUnavailable, style: .error)
            throw error
        }
    }

    private func setDeepSeekStatus(
        _ key: CueLocalizedKey,
        style: AIServiceStatus.Style = .information
    ) {
        setDeepSeekStatus(localized(key), style: style)
    }

    private func setDeepSeekStatus(
        _ message: String,
        style: AIServiceStatus.Style = .information
    ) {
        deepSeekStatus = AIServiceStatus(message: message, style: style)
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
        static let promptExpansionModel = "promptExpansionModel"
        static let promptExpansionInstruction = "promptExpansionInstruction"
        static let toggleShortcut = "toggleShortcut"
        static let previousShortcut = "previousShortcut"
        static let nextShortcut = "nextShortcut"
        static let promptExpansionShortcut = "promptExpansionShortcut"
    }
}
