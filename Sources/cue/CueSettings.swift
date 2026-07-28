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

final class CueSettings: ObservableObject {
    static let defaults = UserDefaults.standard

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
            let clamped = min(max(windowHeight, 220), 800)
            guard clamped == windowHeight else {
                windowHeight = clamped
                return
            }
            Self.defaults.set(windowHeight, forKey: Keys.windowHeight)
        }
    }

    @Published var alwaysOnTop: Bool {
        didSet { Self.defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    var localizationIdentifier: String? { language.localizationIdentifier }
    var normalizedWidth: Double { min(max(windowWidth, 420), 1_200) }
    var normalizedHeight: Double { min(max(windowHeight, 220), 800) }

    init() {
        Self.defaults.register(defaults: [
            Keys.language: CueLanguage.system.rawValue,
            Keys.windowWidth: 680.0,
            Keys.windowHeight: 292.0,
            Keys.alwaysOnTop: true,
        ])

        language = CueLanguage(
            rawValue: Self.defaults.string(forKey: Keys.language) ?? "system"
        ) ?? .system
        windowWidth = min(max(Self.defaults.double(forKey: Keys.windowWidth), 420), 1_200)
        windowHeight = min(max(Self.defaults.double(forKey: Keys.windowHeight), 220), 800)
        alwaysOnTop = Self.defaults.bool(forKey: Keys.alwaysOnTop)
    }

    private enum Keys {
        static let language = "language"
        static let windowWidth = "windowWidth"
        static let windowHeight = "windowHeight"
        static let alwaysOnTop = "alwaysOnTop"
    }
}
