import Foundation

public enum CueLocalizedKey: String, Sendable {
    case promptLabel = "prompt.label"
    case promptPlaceholder = "prompt.placeholder"
    case actionCancel = "action.cancel"
    case actionDone = "action.done"
    case characterCount = "character_count.format"
    case tokenCount = "token_count.format"
    case noDisplay = "error.no_display"
    case settingsTitle = "settings.title"
    case settingsMenuTitle = "settings.menu_title"
    case settingsGeneral = "settings.general"
    case settingsLanguage = "settings.language"
    case settingsLanguageSystem = "settings.language.system"
    case settingsWindowSize = "settings.window_size"
    case settingsWidth = "settings.width"
    case settingsHeight = "settings.height"
    case settingsAlwaysOnTop = "settings.always_on_top"
    case settingsSizeHint = "settings.size_hint"
    case sessionShow = "session.show"
    case sessionCancel = "session.cancel"
}

/// Localized copy shared by the AppKit/SwiftUI surface and command-line errors.
///
/// In an assembled app, localization files live in `Contents/Resources` and
/// are loaded from `Bundle.main`. During `swift run`, SwiftPM puts the same
/// files in a sibling resource bundle, which is discovered without relying on
/// an absolute build path.
public enum CueLocalization {
    public static func string(
        _ key: CueLocalizedKey,
        fallback: String,
        localization: String? = nil
    ) -> String {
        let identifier = resolvedLocalization(localization)
        return localizationTables[identifier]?[key.rawValue]
            ?? localizationTables["en"]?[key.rawValue]
            ?? fallback
    }

    public static func characterCount(
        _ count: Int,
        localization: String? = nil
    ) -> String {
        let format = string(
            .characterCount,
            fallback: "characters: %lld",
            localization: localization
        )
        return String(format: format, locale: Locale.current, Int64(count))
    }

    public static func tokenCount(
        _ count: Int,
        localization: String? = nil
    ) -> String {
        let format = string(
            .tokenCount,
            fallback: "token: %lld",
            localization: localization
        )
        return String(format: format, locale: Locale.current, Int64(count))
    }

    private static func resolvedLocalization(_ requested: String?) -> String {
        let available = Array(localizationTables.keys)
        let preferences = requested.map { [$0] } ?? Locale.preferredLanguages

        return Bundle.preferredLocalizations(
            from: available,
            forPreferences: preferences
        ).first ?? "en"
    }

    private static let localizationTables: [String: [String: String]] = {
        var tables: [String: [String: String]] = [:]

        for localization in CueResources.bundle.localizations where localization != "Base" {
            guard let url = CueResources.bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ),
            let data = try? Data(contentsOf: url),
            let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ),
            let table = propertyList as? [String: String]
            else { continue }

            tables[localization] = table
        }

        return tables
    }()

}
