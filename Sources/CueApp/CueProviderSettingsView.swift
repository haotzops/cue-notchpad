import CueCore
import SwiftUI

struct CueProviderSettingsView: View {
    @ObservedObject var settings: CueSettings
    @Binding var providerAPIKey: String
    @State private var isConfirmingProfileRemoval = false
    @State private var isConfirmingCredentialRemoval = false
    @State private var showAdvanced = false

    private let customAPIs: [CueAIAPI] = [
        .openAICompletions,
        .openAIResponses,
        .anthropicMessages,
    ]

    var body: some View {
        Form {
            Section {
                Picker(
                    settings.localized(.settingsProviderCredentials),
                    selection: $settings.activeProviderProfileID
                ) {
                    ForEach(settings.providerProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                HStack {
                    Button(settings.localized(.settingsProviderAdd)) {
                        _ = settings.addCustomProviderProfile()
                    }

                    if settings.activeProviderProfile.isCustom {
                        Button(settings.localized(.settingsProviderDelete), role: .destructive) {
                            isConfirmingProfileRemoval = true
                        }
                    }
                    Spacer()
                }
                .confirmationDialog(
                    settings.localized(.settingsProviderDeleteConfirmation),
                    isPresented: $isConfirmingProfileRemoval,
                    titleVisibility: .visible
                ) {
                    Button(settings.localized(.settingsProviderDelete), role: .destructive) {
                        settings.removeProviderProfile(settings.activeProviderProfileID)
                    }
                    Button(settings.localized(.settingsCancel), role: .cancel) {}
                }

            }

            if settings.activeProviderProfile.isCustom {
                Section(settings.localized(.settingsProviderCredentials)) {
                    Picker(settings.localized(.settingsProviderAPI), selection: profileBinding(\.api)) {
                        ForEach(customAPIs) { api in
                            Text(api.displayName).tag(api)
                        }
                    }
                    TextField(
                        settings.localized(.settingsProviderName),
                        text: profileBinding(\.name)
                    )
                    TextField(
                        settings.localized(.settingsProviderBaseURL),
                        text: profileBinding(\.baseURL)
                    )
                    TextField(
                        settings.localized(.settingsProviderModelsURL),
                        text: optionalProfileBinding(\.manualModelsURL)
                    )
                    TextField(
                        settings.localized(.settingsProviderBalanceURL),
                        text: optionalProfileBinding(\.manualBalanceURL)
                    )
                    TextField(
                        settings.localized(.settingsProviderBalancePath),
                        text: profileBinding(\.balanceJSONPointer)
                    )
                }
            }

            Section(settings.localized(.settingsModel)) {
                HStack(spacing: 8) {
                    TextField(
                        settings.localized(.settingsModelID),
                        text: Binding(
                            get: { settings.activeProviderProfile.modelID ?? "" },
                            set: { value in
                                let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                updateProfile { $0.modelID = model.isEmpty ? nil : model }
                            }
                        )
                    )

                    if !settings.availableModels.isEmpty {
                        Menu {
                            ForEach(settings.availableModels, id: \.self) { model in
                                Button(model) {
                                    updateProfile { $0.modelID = model }
                                }
                            }
                        } label: {
                            Text(settings.localized(.settingsChooseModel))
                        }
                        .fixedSize()
                    }
                }

                HStack {
                    Button(settings.localized(.settingsRefreshModels)) {
                        settings.refreshModelsIfPossible()
                    }
                    if settings.isLoadingModels {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                .disabled(
                    !settings.activeEndpointResolution.supportsModelDiscovery
                        || (!settings.providerCredentialConfigured && settings.activeProviderProfile.requiresAPIKey)
                        || settings.isLoadingModels
                )
            }

            Section(settings.localized(.settingsProviderCredential)) {
                SecureField(credentialFieldLabel, text: $providerAPIKey)

                HStack {
                    Button(settings.localized(.settingsSaveAPIKey)) {
                        settings.saveProviderAPIKey(providerAPIKey)
                        providerAPIKey = ""
                    }
                    .disabled(providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if settings.providerHasStoredCredential {
                        Button(settings.localized(.settingsRemoveAPIKey), role: .destructive) {
                            isConfirmingCredentialRemoval = true
                        }
                        .confirmationDialog(
                            settings.localized(.settingsRemoveAPIKeyConfirmation),
                            isPresented: $isConfirmingCredentialRemoval,
                            titleVisibility: .visible
                        ) {
                            Button(settings.localized(.settingsRemoveAPIKey), role: .destructive) {
                                settings.removeProviderAPIKey()
                            }
                            Button(settings.localized(.settingsCancel), role: .cancel) {}
                        }
                    }
                }

                CueSettingsStatusLabel(
                    text: credentialStatusText(settings.activeProviderProfile),
                    color: credentialStatusColor(settings.activeProviderProfile),
                    systemImage: credentialStatusImage(settings.activeProviderProfile)
                )
            }

            Section(settings.localized(.settingsProviderDiagnostics)) {
                HStack {
                    Button(settings.localized(.settingsHealthCheck)) {
                        settings.checkProviderHealth()
                    }
                    .disabled(
                        settings.activeProviderProfile.modelID == nil
                            || !settings.providerConfigurationValid
                            || settings.isTestingConnection
                            || (!settings.providerCredentialConfigured && settings.activeProviderProfile.requiresAPIKey)
                    )

                    if settings.canCheckBalance {
                        Button(settings.localized(.settingsCheckBalance)) {
                            settings.checkProviderBalance()
                        }
                        .disabled(
                            settings.isCheckingBalance
                                || (!settings.providerCredentialConfigured && settings.activeProviderProfile.requiresAPIKey)
                        )
                    }

                    Spacer()
                }

                if settings.isTestingConnection || settings.isCheckingBalance {
                    ProgressView().controlSize(.small)
                }

                if let balance = settings.providerBalance {
                    LabeledContent(settings.localized(.settingsProviderBalance)) {
                        Text(balanceText(balance)).monospacedDigit()
                    }
                }

                if let status = settings.aiServiceStatus {
                    CueSettingsStatusLabel(
                        text: status.message,
                        color: status.style == .error ? .red : .secondary,
                        systemImage: status.style == .error ? "exclamationmark.circle" : "info.circle"
                    )
                }
            }

            if !settings.activeProviderProfile.isCustom {
                Section {
                    DisclosureGroup(
                        settings.localized(.settingsAdvanced),
                        isExpanded: $showAdvanced
                    ) {
                        advancedConfiguration
                    }
                }
            }
        }
        .cueSettingsFormAppearance()
        .onChange(of: settings.activeProviderProfileID) { _ in
            providerAPIKey = ""
            showAdvanced = false
        }
    }

    private var advancedConfiguration: some View {
        Group {
            if !settings.activeProviderProfile.isCustom {
                TextField(
                    settings.localized(.settingsProviderBaseURL),
                    text: profileBinding(\.baseURL)
                )
            }

            let resolution = settings.activeEndpointResolution
            if resolution.isKnown {
                CueSettingsStatusLabel(
                    text: settings.localized(.settingsProviderEndpointsDetected),
                    color: .secondary,
                    systemImage: "checkmark.circle"
                )
            } else {
                TextField(
                    settings.localized(.settingsProviderModelsURL),
                    text: optionalProfileBinding(\.manualModelsURL)
                )
                TextField(
                    settings.localized(.settingsProviderBalanceURL),
                    text: optionalProfileBinding(\.manualBalanceURL)
                )
                TextField(
                    settings.localized(.settingsProviderBalancePath),
                    text: profileBinding(\.balanceJSONPointer)
                )
            }
        }
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<CueProviderProfile, Value>) -> Binding<Value> {
        Binding(
            get: { settings.activeProviderProfile[keyPath: keyPath] },
            set: { value in updateProfile { $0[keyPath: keyPath] = value } }
        )
    }

    private func optionalProfileBinding(_ keyPath: WritableKeyPath<CueProviderProfile, String?>) -> Binding<String> {
        Binding(
            get: { settings.activeProviderProfile[keyPath: keyPath] ?? "" },
            set: { value in updateProfile { $0[keyPath: keyPath] = value.isEmpty ? nil : value } }
        )
    }

    private func updateProfile(_ update: (inout CueProviderProfile) -> Void) {
        var profile = settings.activeProviderProfile
        update(&profile)
        settings.updateProviderProfile(profile)
    }

    private var credentialFieldLabel: String {
        String(
            format: settings.localized(.settingsProviderAPIKeyFormat),
            settings.activeProviderProfile.name
        )
    }

    private func credentialStatusText(_ profile: CueProviderProfile) -> String {
        if settings.credentialSource(for: profile) != nil {
            return settings.localized(.settingsProviderCredentialStatusStored)
        }
        return profile.requiresAPIKey
            ? settings.localized(.settingsProviderCredentialStatusNotConfigured)
            : settings.localized(.settingsProviderCredentialStatusOptional)
    }

    private func credentialStatusColor(_ profile: CueProviderProfile) -> Color {
        if settings.credentialSource(for: profile) != nil { return .green }
        return profile.requiresAPIKey ? .orange : .secondary
    }

    private func credentialStatusImage(_ profile: CueProviderProfile) -> String {
        settings.credentialSource(for: profile) == nil ? "circle" : "checkmark.circle"
    }

    private func balanceText(_ balance: CueProviderBalance) -> String {
        if let currency = balance.currency {
            return String(format: "%.4g %@", balance.amount, currency)
        }
        return String(format: "%.4g", balance.amount)
    }
}
