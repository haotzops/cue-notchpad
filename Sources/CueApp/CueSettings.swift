import AppKit
import Combine
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

    @Published var toggleShortcut: CueShortcut {
        didSet { save(toggleShortcut, key: Keys.toggleShortcut) }
    }
    @Published var previousShortcut: CueShortcut {
        didSet { save(previousShortcut, key: Keys.previousShortcut) }
    }
    @Published var nextShortcut: CueShortcut {
        didSet { save(nextShortcut, key: Keys.nextShortcut) }
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
        ])

        language = CueLanguage(
            rawValue: Self.defaults.string(forKey: Keys.language) ?? "system"
        ) ?? .system
        let storedWidth = Self.defaults.double(forKey: Keys.windowWidth)
        windowWidth = storedWidth == 650 ? Self.defaultWindowWidth : min(max(storedWidth, 420), 1_200)
        let storedHeight = Self.defaults.double(forKey: Keys.windowHeight)
        // Migrate only previous shipped defaults; other intentional user values remain untouched.
        windowHeight = storedHeight == 180 ? Self.defaultWindowHeight : min(max(storedHeight, Self.minimumWindowHeight), 800)
        overflowBehavior = CueOverflowBehavior(
            rawValue: Self.defaults.string(forKey: Keys.overflowBehavior) ?? "scrollable"
        ) ?? .scrollable
        editorFontName = Self.defaults.string(forKey: Keys.editorFontName) ?? Self.defaultEditorFont.fontName
        let storedFontSize = Self.defaults.double(forKey: Keys.editorFontSize)
        editorFontSize = min(max(storedFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
        insertsSpacesBetweenChineseAndEnglish = Self.defaults.bool(forKey: Keys.insertsSpacesBetweenChineseAndEnglish)
        toggleShortcut = Self.loadShortcut(key: Keys.toggleShortcut, fallback: .toggleDefault)
        previousShortcut = Self.loadShortcut(key: Keys.previousShortcut, fallback: .previousDefault)
        nextShortcut = Self.loadShortcut(key: Keys.nextShortcut, fallback: .nextDefault)
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
        static let toggleShortcut = "toggleShortcut"
        static let previousShortcut = "previousShortcut"
        static let nextShortcut = "nextShortcut"
    }
}
