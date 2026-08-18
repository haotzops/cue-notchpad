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

    var detailKey: CueLocalizedKey {
        switch self {
        case .general: .settingsPageGeneralDetail
        case .ai: .settingsPageAIDetail
        case .providers: .settingsPageProvidersDetail
        case .usage: .settingsPageUsageDetail
        case .shortcuts: .settingsPageShortcutsDetail
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
    @State private var page: CueSettingsPage = .general
    @State private var providerAPIKey = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CueBrandMark()
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 9))

                Text(settings.localized(.settingsTitle))
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 22)

            VStack(spacing: 5) {
                ForEach(CueSettingsPage.allCases) { candidate in
                    sidebarButton(candidate)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Label(settings.localized(.settingsAutosaveHint), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
        }
        .frame(width: 208)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sidebarButton(_ candidate: CueSettingsPage) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                page = candidate
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: candidate.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(settings.localized(candidate.titleKey))
                    .font(.body.weight(page == candidate ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(page == candidate ? Color.accentColor : Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                page == candidate ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(spacing: 0) {
            CueSettingsPageHeader(
                title: settings.localized(page.titleKey),
                detail: settings.localized(page.detailKey),
                systemImage: page.systemImage
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Divider()

            if page == .providers {
                pageContent
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    pageContent
                        .frame(maxWidth: 760, alignment: .topLeading)
                        .padding(28)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
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
