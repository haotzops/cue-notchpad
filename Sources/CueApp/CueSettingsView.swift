import CueCore
import SwiftUI

private enum CueSettingsPage: String, CaseIterable, Identifiable {
    case general, ai, providers, usage, shortcuts

    var id: String { rawValue }

    var titleKey: CueLocalizedKey {
        switch self {
        case .general: .settingsPageGeneral
        case .ai: .settingsPageAI
        case .providers: .settingsProviderCredentials
        case .usage: .settingsPageUsage
        case .shortcuts: .settingsShortcuts
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .ai: "sparkles"
        case .providers: "key.horizontal"
        case .usage: "chart.bar.xaxis"
        case .shortcuts: "command"
        }
    }
}

struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        if #available(macOS 26.0, *) {
            CueModernSettingsView(settings: settings)
        } else {
            CueLegacySettingsView(settings: settings)
        }
    }
}

struct CueLegacySettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        CueSettingsNavigation(settings: settings)
            .navigationSplitViewStyle(.balanced)
    }
}

@available(macOS 26.0, *)
struct CueModernSettingsView: View {
    @ObservedObject var settings: CueSettings

    var body: some View {
        // Let the system own sidebar material, toolbar treatment and column behavior.
        CueSettingsNavigation(settings: settings)
            .navigationSplitViewStyle(.automatic)
    }
}

private struct CueSettingsNavigation: View {
    @ObservedObject var settings: CueSettings
    @State private var page: CueSettingsPage? = .general
    @State private var providerAPIKey = ""

    var body: some View {
        NavigationSplitView {
            List(CueSettingsPage.allCases, selection: $page) { candidate in
                Label(settings.localized(candidate.titleKey), systemImage: candidate.systemImage)
                    .tag(candidate)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            pageContent
                .navigationTitle(settings.localized((page ?? .general).titleKey))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page ?? .general {
        case .general:
            CueGeneralSettingsView(settings: settings)
        case .ai:
            CueAISettingsView(settings: settings)
        case .providers:
            CueProviderSettingsView(settings: settings, providerAPIKey: $providerAPIKey)
        case .usage:
            CueUsageStatisticsView(settings: settings)
        case .shortcuts:
            CueShortcutSettingsView(settings: settings)
        }
    }
}
