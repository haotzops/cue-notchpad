import Foundation

public enum CueLocalizedKey: String, CaseIterable, Sendable {
    case promptLabel = "prompt.label"
    case promptPlaceholder = "prompt.placeholder"
    case actionCancel = "action.cancel"
    case actionDone = "action.done"
    case characterCount = "character_count.format"
    case tokenCount = "token_count.format"
    case tokenUnavailable = "token_count.unavailable"
    case noDisplay = "error.no_display"
    case settingsTitle = "settings.title"
    case settingsMenuTitle = "settings.menu_title"
    case settingsGeneral = "settings.general"
    case settingsLanguage = "settings.language"
    case settingsLanguageSystem = "settings.language.system"
    case settingsWindowSize = "settings.window_size"
    case settingsWidth = "settings.width"
    case settingsHeight = "settings.height"
    case settingsSizeHint = "settings.size_hint"
    case settingsEditor = "settings.editor"
    case settingsEditorFont = "settings.editor_font"
    case settingsEditorFontSize = "settings.editor_font_size"
    case settingsEditorFontSizeHint = "settings.editor_font_size.hint"
    case settingsSystemFontRegular = "settings.system_font_regular"
    case unitPoints = "unit.points"
    case languageEnglish = "language.english"
    case languageSimplifiedChinese = "language.simplified_chinese"
    case settingsChooseFont = "settings.choose_font"
    case settingsRestoreDefaultFont = "settings.restore_default_font"
    case settingsRestoreDefaultWindowSize = "settings.restore_default_window_size"
    case settingsResetAndData = "settings.reset_and_data"
    case settingsRestoreAll = "settings.restore_all"
    case settingsRestoreAllDetail = "settings.restore_all.detail"
    case settingsRestoreAllConfirmation = "settings.restore_all.confirmation"
    case settingsRestore = "settings.restore"
    case settingsClearUsage = "settings.clear_usage"
    case settingsClearUsageDetail = "settings.clear_usage.detail"
    case settingsClearUsageConfirmation = "settings.clear_usage.confirmation"
    case settingsClear = "settings.clear"
    case settingsCancel = "settings.cancel"
    case settingsChineseEnglishSpacing = "settings.chinese_english_spacing"
    case settingsChineseEnglishSpacingHint = "settings.chinese_english_spacing.hint"
    case settingsModel = "settings.model"
    case settingsRefreshModels = "settings.refresh_models"
    case settingsLoadingModels = "settings.loading_models"
    case settingsChooseModel = "settings.choose_model"
    case settingsDeepSeekAPIKey = "settings.deepseek_api_key"
    case settingsSaveAPIKey = "settings.save_api_key"
    case settingsRemoveAPIKey = "settings.remove_api_key"
    case settingsAPIKeyConfigured = "settings.api_key_configured"
    case settingsAPIKeyNotConfigured = "settings.api_key_not_configured"
    case settingsAPIKeyMissing = "settings.api_key_missing"
    case settingsAPIKeySaved = "settings.api_key_saved"
    case settingsAPIKeyRemoved = "settings.api_key_removed"
    case settingsAIRewriteUnavailable = "settings.ai_rewrite_unavailable"
    case settingsHealthCheck = "settings.health_check"
    case settingsCheckingServiceHealth = "settings.checking_service_health"
    case settingsServiceHealthy = "settings.service_healthy"
    case settingsOverflowBehavior = "settings.overflow_behavior"
    case settingsOverflowScrollable = "settings.overflow.scrollable"
    case settingsOverflowGrow = "settings.overflow.grow"
    case settingsShortcuts = "settings.shortcuts"
    case settingsPageGeneral = "settings.page.general"
    case settingsPageAI = "settings.page.ai"
    case settingsPageUsage = "settings.page.usage"
    case settingsRewritePrompt = "settings.rewrite_prompt"
    case settingsRewritePromptHint = "settings.rewrite_prompt.hint"
    case settingsRewriteMessageVariableHint = "settings.rewrite_prompt.message_variable_hint"
    case settingsModelAPIConfiguration = "settings.model_api_configuration"
    case settingsPiIntegration = "settings.pi_integration"
    case settingsPiIntegrationInstall = "settings.pi_integration.install"
    case settingsPiIntegrationRepair = "settings.pi_integration.repair"
    case settingsPiIntegrationUninstall = "settings.pi_integration.uninstall"
    case settingsPiIntegrationInstalledFormat = "settings.pi_integration.installed_format"
    case settingsPiIntegrationNotInstalled = "settings.pi_integration.not_installed"
    case settingsPiIntegrationNeedsRepair = "settings.pi_integration.needs_repair"
    case settingsPiIntegrationForeign = "settings.pi_integration.foreign"
    case settingsPiIntegrationForeignHint = "settings.pi_integration.foreign_hint"
    case settingsPiIntegrationPath = "settings.pi_integration.path"
    case settingsPiIntegrationRewriteHint = "settings.pi_integration.rewrite_hint"
    case settingsPiIntegrationExternalEditorHint = "settings.pi_integration.external_editor_hint"
    case settingsPiIntegrationCopy = "settings.pi_integration.copy"
    case settingsPiIntegrationCopied = "settings.pi_integration.copied"
    case settingsPiIntegrationUninstallConfirmation = "settings.pi_integration.uninstall_confirmation"
    case settingsAIRewrite = "settings.ai_rewrite"
    case settingsAIRewriteDefaultPrompt = "settings.ai_rewrite.default_prompt"
    case usageToday = "usage.today"
    case usageWeek = "usage.week"
    case usageMonth = "usage.month"
    case usageCustom = "usage.custom"
    case usageStart = "usage.start"
    case usageEnd = "usage.end"
    case usageCueOpens = "usage.cue_opens"
    case usageFirstOpen = "usage.first_open"
    case usageLatestOpen = "usage.latest_open"
    case usageActiveDays = "usage.active_days"
    case usageDailyAverage = "usage.daily_average"
    case usageActivity = "usage.activity"
    case usageNoActivity = "usage.no_activity"
    case usageNoActivityHint = "usage.no_activity.hint"
    case usagePrivacyHint = "usage.privacy_hint"
    case shortcutToggle = "shortcut.toggle"
    case shortcutPrevious = "shortcut.previous"
    case shortcutNext = "shortcut.next"
    case shortcutRecord = "shortcut.record"
    case sessionShow = "session.show"
    case sessionCancel = "session.cancel"
    case menuEdit = "menu.edit"
    case menuQuitCue = "menu.quit_cue"
    case menuUndo = "menu.undo"
    case menuRedo = "menu.redo"
    case menuCut = "menu.cut"
    case menuCopy = "menu.copy"
    case menuPaste = "menu.paste"
    case menuSelectAll = "menu.select_all"
}

/// Localized copy shared by the AppKit/SwiftUI surface and command-line errors.
///
/// In an assembled app, localization files live in `Contents/Resources` and
/// are loaded from `Bundle.main`. During `swift run`, SwiftPM puts the same
/// files in a sibling resource bundle, which is discovered without relying on
/// an absolute build path.
public enum CueLocalization {
    /// Looks up a key from the app's `Localizable.strings` table.
    ///
    /// English is the package's development localization, so translated copy
    /// has one source of truth: the `.strings` resources. The optional
    /// identifier is used by the in-app language preference rather than the
    /// process-wide system language.
    public static func string(
        _ key: CueLocalizedKey,
        localization: String? = nil
    ) -> String {
        let bundle = bundle(for: localization)
        return bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: "Localizable")
    }

    public static func characterCount(
        _ count: Int,
        localization: String? = nil
    ) -> String {
        let format = string(.characterCount, localization: localization)
        return String(format: format, locale: Locale.current, Int64(count))
    }

    public static func tokenCount(
        _ count: Int,
        localization: String? = nil
    ) -> String {
        let format = string(.tokenCount, localization: localization)
        return String(format: format, locale: Locale.current, Int64(count))
    }

    private static func bundle(for requestedLocalization: String?) -> Bundle {
        let available = CueResources.bundle.localizations.filter { $0 != "Base" }
        let preferences = requestedLocalization.map { [$0] } ?? Locale.preferredLanguages
        let identifier = Bundle.preferredLocalizations(
            from: available,
            forPreferences: preferences
        ).first ?? "en"

        guard let path = CueResources.bundle.path(forResource: identifier, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else { return CueResources.bundle }
        return localizedBundle
    }

}
