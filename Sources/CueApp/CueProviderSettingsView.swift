import CueCore
import SwiftUI

struct CueProviderSettingsView: View {
    @ObservedObject var settings: CueSettings
    @Binding var providerAPIKey: String
    @State private var providerSearch = ""
    @State private var expandedCategories: Set<CueAIProviderCategory>

    init(settings: CueSettings, providerAPIKey: Binding<String>) {
        self.settings = settings
        _providerAPIKey = providerAPIKey
        _expandedCategories = State(
            initialValue: [settings.promptExpansionProvider.descriptor.category]
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            providerBrowser
                .frame(width: 238)
                .frame(maxHeight: .infinity)

            ScrollView {
                providerConfiguration
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: settings.promptExpansionProvider) { provider in
            providerAPIKey = ""
            expandedCategories.insert(provider.descriptor.category)
        }
    }

    private var providerBrowser: some View {
        CueSettingsCard(
            settings.localized(.settingsProviderCredentials),
            detail: settings.localized(.settingsProviderCredentialsHint),
            fillsAvailableHeight: true
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(settings.localized(.settingsSearchProviders), text: $providerSearch)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(CueAIProviderCategory.allCases, id: \.self) { category in
                            let providers = filteredProviders(in: category)
                            if !providers.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    categoryHeader(category, providerCount: providers.count)

                                    if categoryIsExpanded(category) {
                                        ForEach(providers) { descriptor in
                                            providerRow(descriptor)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func categoryHeader(
        _ category: CueAIProviderCategory,
        providerCount: Int
    ) -> some View {
        Button {
            guard normalizedProviderSearch.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                if expandedCategories.contains(category) {
                    expandedCategories.remove(category)
                } else {
                    expandedCategories.insert(category)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: categoryIsExpanded(category) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 10)
                Text(providerCategoryName(category))
                    .font(.caption.weight(.semibold))
                Text("\(providerCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryIsExpanded(_ category: CueAIProviderCategory) -> Bool {
        !normalizedProviderSearch.isEmpty || expandedCategories.contains(category)
    }

    private func providerRow(_ descriptor: CueAIProviderDescriptor) -> some View {
        let selected = settings.promptExpansionProvider == descriptor.id
        return HStack(spacing: 3) {
            Button {
                settings.promptExpansionProvider = descriptor.id
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(credentialStatusColor(for: descriptor.id))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.name)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                        Text(credentialStatusText(for: descriptor.id))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 42)
                .contentShape(Rectangle())
                .background(
                    selected ? Color.accentColor.opacity(0.11) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .buttonStyle(.plain)

            if settings.hasStoredCredential(for: descriptor.id) {
                Button {
                    settings.removeCredential(for: descriptor.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(settings.localized(.settingsRemoveAPIKey))
            }
        }
    }

    private var providerConfiguration: some View {
        CueSettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.selectedProviderName)
                            .font(.headline)
                        Text(settings.promptExpansionAPI.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    CueSettingsStatusBadge(
                        text: credentialStatusText(for: settings.promptExpansionProvider),
                        color: credentialStatusColor(for: settings.promptExpansionProvider)
                    )
                }

                if settings.selectedProviderSupportedAPIs.count > 1 {
                    configurationLabel(settings.localized(.settingsProviderAPI))
                    Picker("", selection: $settings.promptExpansionAPI) {
                        ForEach(settings.selectedProviderSupportedAPIs) { api in
                            Text(api.displayName).tag(api)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                if settings.providerAllowsBaseURLOverride {
                    configurationLabel(settings.localized(.settingsProviderBaseURL))
                    TextField(settings.localized(.settingsProviderBaseURL), text: $settings.providerBaseURL)
                    Text(settings.localized(baseURLHintKey))
                        .font(.caption)
                        .foregroundStyle(settings.providerConfigurationValid ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if supportsCredentialInput {
                    configurationLabel(
                        String(
                            format: settings.localized(.settingsProviderAPIKeyFormat),
                            settings.selectedProviderName
                        )
                    )
                    HStack(spacing: 8) {
                        SecureField(
                            String(
                                format: settings.localized(.settingsProviderAPIKeyFormat),
                                settings.selectedProviderName
                            ),
                            text: $providerAPIKey
                        )
                        Button(settings.localized(.settingsSaveAPIKey)) {
                            settings.saveProviderAPIKey(providerAPIKey)
                            providerAPIKey = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Text(credentialDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                configurationLabel(settings.localized(.settingsModel))
                if !settings.availableModels.isEmpty {
                    Picker("", selection: $settings.promptExpansionModel) {
                        Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                        ForEach(settings.availableModels, id: \.self) {
                            Text($0).tag(Optional($0))
                        }
                    }
                    .labelsHidden()
                    .disabled(
                        !settings.providerCredentialConfigured
                            && settings.promptExpansionProvider.requiresAPIKey
                    )
                }

                TextField(
                    settings.localized(.settingsModelID),
                    text: Binding(
                        get: { settings.promptExpansionModel ?? "" },
                        set: {
                            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            settings.promptExpansionModel = trimmed.isEmpty ? nil : trimmed
                        }
                    )
                )

                HStack(spacing: 8) {
                    if settings.selectedProvider?.supportsModelDiscovery == true {
                        Button(settings.localized(.settingsRefreshModels)) {
                            settings.refreshModelsIfPossible()
                        }
                        .disabled(
                            (!settings.providerCredentialConfigured
                                && settings.promptExpansionProvider.requiresAPIKey)
                                || settings.isLoadingModels
                        )
                    }

                    Button(settings.localized(.settingsHealthCheck)) {
                        settings.checkProviderHealth()
                    }
                    .disabled(
                        settings.promptExpansionModel == nil
                            || !settings.providerConfigurationValid
                            || settings.isTestingConnection
                            || (!settings.providerCredentialConfigured
                                && settings.promptExpansionProvider.requiresAPIKey)
                    )

                    Spacer()

                    if settings.hasStoredCredential(for: settings.promptExpansionProvider) {
                        Button(settings.localized(.settingsRemoveAPIKey), role: .destructive) {
                            settings.removeCredential(for: settings.promptExpansionProvider)
                        }
                    }
                }

                if let status = settings.aiServiceStatus {
                    HStack(spacing: 7) {
                        if settings.isTestingConnection || settings.isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(
                                systemName: status.style == .error
                                    ? "exclamationmark.triangle.fill"
                                    : "checkmark.circle.fill"
                            )
                        }
                        Text(status.message)
                    }
                    .font(.caption)
                    .foregroundStyle(status.style == .error ? Color.red : Color.secondary)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (status.style == .error ? Color.red : Color.accentColor).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
            }
        }
    }

    private var normalizedProviderSearch: String {
        providerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredProviders(in category: CueAIProviderCategory) -> [CueAIProviderDescriptor] {
        let providers = CueAIProviderCatalog.providers(in: category)
        guard !normalizedProviderSearch.isEmpty else { return providers }
        return providers.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedProviderSearch)
        }
    }

    private func configurationLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func credentialStatusText(for provider: CueAIProviderID) -> String {
        if let source = settings.credentialSource(for: provider) {
            switch source {
            case .environment(let key):
                return settings.hasStoredCredential(for: provider)
                    ? String(
                        format: settings.localized(.settingsProviderCredentialStatusEnvironmentWithStoredFormat),
                        key
                    )
                    : String(
                        format: settings.localized(.settingsProviderCredentialStatusEnvironmentFormat),
                        key
                    )
            case .configuration:
                return settings.localized(.settingsProviderCredentialStatusStored)
            }
        }
        if provider.descriptor.authentication == .none {
            return settings.localized(.settingsProviderCredentialStatusKeyless)
        }
        if provider == .custom {
            return settings.localized(.settingsProviderCredentialStatusOptional)
        }
        return settings.localized(.settingsProviderCredentialStatusNotConfigured)
    }

    private func credentialStatusColor(for provider: CueAIProviderID) -> Color {
        if settings.credentialSource(for: provider) != nil {
            return .green
        }
        if provider.descriptor.authentication == .none || provider == .custom {
            return .secondary
        }
        return .orange
    }

    private func providerCategoryName(_ category: CueAIProviderCategory) -> String {
        let key: CueLocalizedKey = switch category {
        case .directAPI: .settingsProviderCategoryDirect
        case .codingPlan: .settingsProviderCategoryCodingPlan
        case .platform: .settingsProviderCategoryPlatform
        case .local: .settingsProviderCategoryLocal
        case .custom: .settingsProviderCategoryCustom
        }
        return settings.localized(key)
    }

    private var supportsCredentialInput: Bool {
        settings.promptExpansionProvider.descriptor.authentication != .none
    }

    private var baseURLHintKey: CueLocalizedKey {
        if settings.promptExpansionProvider == .custom {
            return .settingsCustomProviderHint
        }
        return settings.promptExpansionProvider.requiresAPIKey
            ? .settingsProviderBaseURLHint
            : .settingsProviderBaseURLLocalHint
    }

    private var credentialDescription: String {
        if let environmentKey = settings.providerCredentialEnvironmentKey {
            let key = settings.providerHasStoredCredential
                ? CueLocalizedKey.settingsAPIKeyFromEnvironmentWithStoredFormat
                : .settingsAPIKeyFromEnvironmentFormat
            return String(format: settings.localized(key), environmentKey)
        }
        if settings.providerCredentialConfigured {
            return settings.localized(.settingsAPIKeyConfigured)
        }
        if settings.promptExpansionProvider == .custom {
            return settings.localized(.settingsProviderCredentialStatusOptional)
        }
        if !settings.promptExpansionProvider.requiresAPIKey {
            return settings.localized(.settingsLocalProviderHint)
        }
        return settings.localized(.settingsAPIKeyNotConfigured)
    }
}
