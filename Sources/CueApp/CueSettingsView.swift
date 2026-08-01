import CueCore
import SwiftUI

private enum CueSettingsPage: String, CaseIterable, Identifiable {
    case general, ai, usage, shortcuts

    var id: String { rawValue }
}

struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var page: CueSettingsPage = .general
    @State private var deepSeekAPIKey = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text(settings.localized(.settingsPageGeneral)).tag(CueSettingsPage.general)
                Text(settings.localized(.settingsPageAI)).tag(CueSettingsPage.ai)
                Text(settings.localized(.settingsPageUsage)).tag(CueSettingsPage.usage)
                Text(settings.localized(.settingsShortcuts)).tag(CueSettingsPage.shortcuts)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding()

            Form {
                switch page {
                case .general:
                    CueGeneralSettingsView(settings: settings)
                case .ai:
                    CueAISettingsView(settings: settings, deepSeekAPIKey: $deepSeekAPIKey)
                case .usage:
                    Section {
                        CueUsageStatisticsView(settings: settings)
                    }
                case .shortcuts:
                    CueShortcutSettingsView(settings: settings)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
    }
}
