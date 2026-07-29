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

    init() {
        Self.defaults.register(defaults: [
            Keys.language: CueLanguage.system.rawValue,
            Keys.windowWidth: Self.defaultWindowWidth,
            Keys.windowHeight: Self.defaultWindowHeight,
            Keys.overflowBehavior: CueOverflowBehavior.scrollable.rawValue,
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
        static let toggleShortcut = "toggleShortcut"
        static let previousShortcut = "previousShortcut"
        static let nextShortcut = "nextShortcut"
    }
}
