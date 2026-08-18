import CueCore
import SwiftUI

struct CueShortcutSettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        CueSettingsCard(
            settings.localized(.settingsShortcuts),
            detail: settings.localized(.settingsPageShortcutsDetail)
        ) {
            VStack(spacing: 0) {
                shortcutRow(
                    settings.localized(.shortcutToggle),
                    systemImage: "rectangle.on.rectangle",
                    shortcut: $settings.toggleShortcut
                )
                shortcutRow(
                    settings.localized(.shortcutPrevious),
                    systemImage: "arrow.left",
                    shortcut: $settings.previousShortcut
                )
                shortcutRow(
                    settings.localized(.shortcutNext),
                    systemImage: "arrow.right",
                    shortcut: $settings.nextShortcut
                )
                shortcutRow(
                    settings.localized(.settingsAIRewrite),
                    systemImage: "sparkles",
                    shortcut: $settings.promptExpansionShortcut
                )
            }
        }
    }

    private func shortcutRow(
        _ label: String,
        systemImage: String,
        shortcut: Binding<CueShortcut>,
        allowsUnmodifiedKeys: Bool = false
    ) -> some View {
        CueSettingsRow(label, systemImage: systemImage) {
            CueShortcutRecorder(
                shortcut: shortcut,
                recordingPrompt: settings.localized(.shortcutRecord),
                allowsUnmodifiedKeys: allowsUnmodifiedKeys
            )
            .frame(width: 122, height: 28)
        }
    }
}
