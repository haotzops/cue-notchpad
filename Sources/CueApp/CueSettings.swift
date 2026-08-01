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

final class CueSettings: ObservableObject {
    static let defaults = UserDefaults.standard
    static let defaultWindowWidth = 550.0
    static let defaultWindowHeight = 150.0
    static let minimumWindowHeight = 130.0
    static let defaultEditorFontSize = 16.0
    static let minimumEditorFontSize = 8.0
    static let maximumEditorFontSize = 72.0

    @Published var language: CueLanguage {
        didSet { Self.defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var windowWidth: Double {
        didSet {
            let clamped = min(max(windowWidth, 420), 1_200)
            guard clamped == windowWidth else {
                windowWidth = clamped
                return
            }
            Self.defaults.set(windowWidth, forKey: Keys.windowWidth)
        }
    }

    @Published var windowHeight: Double {
        didSet {
            let clamped = min(max(windowHeight, Self.minimumWindowHeight), 800)
            guard clamped == windowHeight else {
                windowHeight = clamped
                return
            }
            Self.defaults.set(windowHeight, forKey: Keys.windowHeight)
        }
    }

    @Published var overflowBehavior: CueOverflowBehavior {
        didSet { Self.defaults.set(overflowBehavior.rawValue, forKey: Keys.overflowBehavior) }
    }

    /// Stored as a PostScript name because it remains stable across localized font display names.
    @Published var editorFontName: String {
        didSet { Self.defaults.set(editorFontName, forKey: Keys.editorFontName) }
    }

    @Published var editorFontSize: Double {
        didSet {
            let clamped = min(max(editorFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
            guard clamped == editorFontSize else {
                editorFontSize = clamped
                return
            }
            Self.defaults.set(editorFontSize, forKey: Keys.editorFontSize)
        }
    }

    @Published var insertsSpacesBetweenChineseAndEnglish: Bool {
        didSet { Self.defaults.set(insertsSpacesBetweenChineseAndEnglish, forKey: Keys.insertsSpacesBetweenChineseAndEnglish) }
    }

    @Published var inlineCompletionEnabled: Bool {
        didSet {
            Self.defaults.set(inlineCompletionEnabled, forKey: Keys.inlineCompletionEnabled)
            if inlineCompletionEnabled { refreshDeepSeekModelsIfPossible() }
        }
    }

    @Published var inlineCompletionTriggerMode: InlineCompletionTriggerMode {
        didSet { Self.defaults.set(inlineCompletionTriggerMode.rawValue, forKey: Keys.inlineCompletionTriggerMode) }
    }
    @Published var inlineCompletionDelayMilliseconds: Double {
        didSet { Self.defaults.set(min(max(inlineCompletionDelayMilliseconds, 0), 5_000), forKey: Keys.inlineCompletionDelayMilliseconds) }
    }
    @Published var inlineCompletionMaximumLines: Int {
        didSet { Self.defaults.set(min(max(inlineCompletionMaximumLines, 1), 100), forKey: Keys.inlineCompletionMaximumLines) }
    }

    @Published var promptExpansionModel: String? {
        didSet { Self.defaults.set(promptExpansionModel, forKey: Keys.promptExpansionModel) }
    }
    @Published var promptExpansionInstruction: String {
        didSet { Self.defaults.set(promptExpansionInstruction, forKey: Keys.promptExpansionInstruction) }
    }

    @Published var inlineCompletionModel: String? {
        didSet {
            if let inlineCompletionModel {
                Self.defaults.set(inlineCompletionModel, forKey: Keys.inlineCompletionModel)
            } else {
                Self.defaults.removeObject(forKey: Keys.inlineCompletionModel)
            }
        }
    }
    @Published private(set) var inlineCompletionModels = [String]()
    @Published private(set) var isLoadingInlineCompletionModels = false
    @Published var inlineCompletionKeyConfigured = false
    @Published var inlineCompletionStatus: String?

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
    var normalizedWidth: Double { min(max(windowWidth, 420), 1_200) }
    var normalizedHeight: Double { min(max(windowHeight, Self.minimumWindowHeight), 800) }

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

    private static var defaultEditorFont: NSFont {
        .systemFont(ofSize: CGFloat(defaultEditorFontSize), weight: .regular)
    }

    init() {
        Self.defaults.register(defaults: [
            Keys.language: CueLanguage.system.rawValue,
            Keys.windowWidth: Self.defaultWindowWidth,
            Keys.windowHeight: Self.defaultWindowHeight,
            Keys.overflowBehavior: CueOverflowBehavior.scrollable.rawValue,
            Keys.editorFontName: Self.defaultEditorFont.fontName,
            Keys.editorFontSize: Self.defaultEditorFontSize,
            Keys.insertsSpacesBetweenChineseAndEnglish: false,
            Keys.inlineCompletionEnabled: false,
            Keys.inlineCompletionTriggerMode: InlineCompletionTriggerMode.manual.rawValue,
            Keys.inlineCompletionDelayMilliseconds: 200.0,
            Keys.inlineCompletionMaximumLines: 1,
            Keys.promptExpansionInstruction: "在不改变原意的前提下，润色并扩写以下 prompt；只输出最终 prompt，不要解释。",
        ])

        language = CueLanguage(
            rawValue: Self.defaults.string(forKey: Keys.language) ?? "system"
        ) ?? .system
        let storedWidth = Self.defaults.double(forKey: Keys.windowWidth)
        windowWidth = min(max(storedWidth, 420), 1_200)
        let storedHeight = Self.defaults.double(forKey: Keys.windowHeight)
        windowHeight = min(max(storedHeight, Self.minimumWindowHeight), 800)
        overflowBehavior = CueOverflowBehavior(
            rawValue: Self.defaults.string(forKey: Keys.overflowBehavior) ?? "scrollable"
        ) ?? .scrollable
        editorFontName = Self.defaults.string(forKey: Keys.editorFontName) ?? Self.defaultEditorFont.fontName
        let storedFontSize = Self.defaults.double(forKey: Keys.editorFontSize)
        editorFontSize = min(max(storedFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
        insertsSpacesBetweenChineseAndEnglish = Self.defaults.bool(forKey: Keys.insertsSpacesBetweenChineseAndEnglish)
        inlineCompletionEnabled = Self.defaults.bool(forKey: Keys.inlineCompletionEnabled)
        inlineCompletionTriggerMode = InlineCompletionTriggerMode(rawValue: Self.defaults.string(forKey: Keys.inlineCompletionTriggerMode) ?? "automatic") ?? .automatic
        inlineCompletionDelayMilliseconds = min(max(Self.defaults.double(forKey: Keys.inlineCompletionDelayMilliseconds), 0), 5_000)
        inlineCompletionMaximumLines = min(max(Self.defaults.integer(forKey: Keys.inlineCompletionMaximumLines), 1), 100)
        promptExpansionModel = Self.defaults.string(forKey: Keys.promptExpansionModel)
        let legacyDefaultPolishPrompt = "在不改变原意的前提下，润色并扩写以下 prompt；只输出最终 prompt，不要解释。"
        let localizedDefaultPolishPrompt = CueLocalization.string(
            .settingsAIPolishDefaultPrompt,
            fallback: "Polish and expand the following prompt without changing its meaning. Output only the final prompt, with no explanation.",
            localization: Self.defaults.string(forKey: Keys.language)
        )
        let storedPolishPrompt = Self.defaults.string(forKey: Keys.promptExpansionInstruction)
        promptExpansionInstruction = (storedPolishPrompt == nil || storedPolishPrompt == legacyDefaultPolishPrompt)
            ? localizedDefaultPolishPrompt
            : storedPolishPrompt!
        inlineCompletionModel = Self.defaults.string(forKey: Keys.inlineCompletionModel)
        inlineCompletionKeyConfigured = (try? CueAPIKeyStore.loadDeepSeekAPIKey()) != nil
        toggleShortcut = Self.loadShortcut(key: Keys.toggleShortcut, fallback: .toggleDefault)
        previousShortcut = Self.loadShortcut(key: Keys.previousShortcut, fallback: .previousDefault)
        nextShortcut = Self.loadShortcut(key: Keys.nextShortcut, fallback: .nextDefault)
        inlineCompletionShortcut = Self.loadShortcut(
            key: Keys.inlineCompletionShortcut,
            fallback: .inlineCompletionDefault
        )
        inlineCompletionAcceptShortcut = Self.loadShortcut(key: Keys.inlineCompletionAcceptShortcut, fallback: CueShortcut(keyCode: 48, modifiers: 0))
        promptExpansionShortcut = Self.loadShortcut(key: Keys.promptExpansionShortcut, fallback: .promptExpansionDefault)
        if inlineCompletionEnabled { refreshDeepSeekModelsIfPossible() }
    }

    func saveDeepSeekAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inlineCompletionStatus = localized(.settingsAPIKeyMissing, fallback: "Enter an API key before saving.")
            return
        }
        do {
            try CueAPIKeyStore.saveDeepSeekAPIKey(trimmed)
            inlineCompletionKeyConfigured = true
            inlineCompletionStatus = localized(.settingsAPIKeySaved, fallback: "API key saved in local configuration.")
            refreshDeepSeekModelsIfPossible()
        } catch {
            inlineCompletionStatus = error.localizedDescription
        }
    }

    func testDeepSeekAPIKey() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey() else {
            inlineCompletionStatus = localized(.settingsAPIKeyMissing, fallback: "Enter an API key before saving.")
            return
        }
        guard let model = inlineCompletionModel else {
            inlineCompletionStatus = localized(.settingsModelMissing, fallback: "Choose a model first.")
            return
        }
        inlineCompletionStatus = localized(.settingsTestingAPIKey, fallback: "Testing API key…")
        Task { @MainActor [weak self] in
            do {
                try await DeepSeekFIMCompletionProvider().validate(apiKey: apiKey, model: model)
                self?.inlineCompletionStatus = self?.localized(
                    .settingsAPIKeyValid,
                    fallback: "DeepSeek API key is valid."
                )
            } catch {
                self?.inlineCompletionStatus = self?.localized(
                    .settingsInlineCompletionUnavailable,
                    fallback: "Inline completion is temporarily unavailable."
                )
            }
        }
    }

    func refreshDeepSeekModelsIfPossible() {
        guard let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(), !isLoadingInlineCompletionModels else { return }
        isLoadingInlineCompletionModels = true
        inlineCompletionStatus = localized(.settingsLoadingModels, fallback: "Loading available models…")
        Task { @MainActor [weak self] in
            defer { self?.isLoadingInlineCompletionModels = false }
            do {
                let models = try await DeepSeekFIMCompletionProvider().availableModels(apiKey: apiKey)
                guard !models.isEmpty else {
                    self?.inlineCompletionStatus = self?.localized(
                        .settingsInlineCompletionUnavailable,
                        fallback: "Inline completion is temporarily unavailable."
                    )
                    return
                }
                self?.inlineCompletionModels = models
                if let self, let selectedModel = self.inlineCompletionModel, !models.contains(selectedModel) {
                    self.inlineCompletionModel = nil
                }
                self?.inlineCompletionStatus = nil
            } catch {
                self?.inlineCompletionStatus = self?.localized(
                    .settingsInlineCompletionUnavailable,
                    fallback: "Inline completion is temporarily unavailable."
                )
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
            inlineCompletionStatus = localized(.settingsAPIKeyRemoved, fallback: "API key removed.")
        } catch {
            inlineCompletionStatus = error.localizedDescription
        }
    }

    func localized(_ key: CueLocalizedKey, fallback: String) -> String {
        CueLocalization.string(key, fallback: fallback, localization: language.localizationIdentifier)
    }

    private func save(_ shortcut: CueShortcut, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        Self.defaults.set(data, forKey: key)
    }

    private static func loadShortcut(key: String, fallback: CueShortcut) -> CueShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(CueShortcut.self, from: data)
        else { return fallback }
        return shortcut
    }

    private enum Keys {
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
