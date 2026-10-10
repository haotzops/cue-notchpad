import CueCore
import SwiftUI

struct CueShortcutSettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        Form {
            Section(settings.localized(.settingsShortcuts)) {
                shortcutRow(
                    settings.localized(.shortcutToggle),
                    shortcut: $settings.toggleShortcut
                )
                shortcutRow(
                    settings.localized(.shortcutPrevious),
                    shortcut: $settings.previousShortcut
                )
                shortcutRow(
                    settings.localized(.shortcutNext),
                    shortcut: $settings.nextShortcut
                )
                shortcutRow(
                    settings.localized(.settingsAIRewrite),
                    shortcut: $settings.promptExpansionShortcut
                )
            }
        }
        .cueSettingsFormAppearance()
    }

    private func shortcutRow(
        _ label: String,
        shortcut: Binding<CueShortcut>
    ) -> some View {
        LabeledContent(label) {
            CueShortcutRecorder(
                shortcut: shortcut,
                recordingPrompt: settings.localized(.shortcutRecord),
                allowsUnmodifiedKeys: false
            )
            .frame(width: 122, height: 28)
            .accessibilityLabel(label)
        }
    }
}
