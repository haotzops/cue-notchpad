import CueCore
import SwiftUI

struct CueShortcutSettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        Section {
            shortcutRow(settings.localized(.shortcutToggle), shortcut: $settings.toggleShortcut)
            shortcutRow(settings.localized(.shortcutPrevious), shortcut: $settings.previousShortcut)
            shortcutRow(settings.localized(.shortcutNext), shortcut: $settings.nextShortcut)
            shortcutRow(
                settings.localized(.settingsManualCompletion),
                shortcut: $settings.inlineCompletionShortcut,
                allowsUnmodifiedKeys: true
            )
            shortcutRow(settings.localized(.settingsAIPolish), shortcut: $settings.promptExpansionShortcut)
            LabeledContent(settings.localized(.settingsAcceptCompletion)) {
                CueShortcutRecorder(
                    shortcut: $settings.inlineCompletionAcceptShortcut,
                    recordingPrompt: settings.localized(.shortcutRecord),
                    allowsUnmodifiedKeys: true
                )
                .frame(width: 110, height: 24)
            }
        }
    }

    private func shortcutRow(
        _ label: String,
        shortcut: Binding<CueShortcut>,
        allowsUnmodifiedKeys: Bool = false
    ) -> some View {
        LabeledContent(label) {
            CueShortcutRecorder(
                shortcut: shortcut,
                recordingPrompt: settings.localized(.shortcutRecord),
                allowsUnmodifiedKeys: allowsUnmodifiedKeys
            )
            .frame(width: 110, height: 24)
        }
    }
}
