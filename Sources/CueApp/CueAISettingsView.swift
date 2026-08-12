import AppKit
import CueCore
import SwiftUI

struct CueAISettingsView: View {
    @ObservedObject var settings: CueSettings
    @Binding var deepSeekAPIKey: String
    @State private var isConfirmingPiUninstall = false
    @State private var copiedPiEditorInstruction = false

    var body: some View {
        modelAPIConfiguration
        promptRewrite
        piIntegrationControls
    }

    private var modelAPIConfiguration: some View {
        Section(settings.localized(.settingsModelAPIConfiguration)) {
            SecureField(settings.localized(.settingsDeepSeekAPIKey), text: $deepSeekAPIKey)
            HStack {
                Button(settings.localized(.settingsSaveAPIKey)) {
                    settings.saveDeepSeekAPIKey(deepSeekAPIKey)
                    deepSeekAPIKey = ""
                }
                .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(settings.localized(.settingsRefreshModels)) {
                    settings.refreshDeepSeekModelsIfPossible()
                }
                .disabled(!settings.deepSeekKeyConfigured || settings.isLoadingDeepSeekModels)

                Button(settings.localized(.settingsHealthCheck)) {
                    settings.checkDeepSeekServiceHealth()
                }
                .disabled(!settings.deepSeekKeyConfigured || settings.isTestingDeepSeekConnection)

                Button(settings.localized(.settingsRemoveAPIKey)) {
                    settings.removeDeepSeekAPIKey()
                }
                .disabled(!settings.deepSeekKeyConfigured)
            }

            Text(settings.deepSeekKeyConfigured
                ? settings.localized(.settingsAPIKeyConfigured)
                : settings.localized(.settingsAPIKeyNotConfigured)
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let status = settings.deepSeekStatus {
                HStack(spacing: 6) {
                    if settings.isTestingDeepSeekConnection {
                        ProgressView().controlSize(.small)
                    }
                    Text(status.message)
                }
                .font(.footnote)
                .foregroundStyle(status.style == .error ? Color.red : Color.secondary)
            }
        }
    }

    private var promptRewrite: some View {
        Section(settings.localized(.settingsAIRewrite)) {
            Picker(settings.localized(.settingsModel), selection: $settings.promptExpansionModel) {
                Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                ForEach(settings.deepSeekModels, id: \.self) {
                    Text($0).tag(Optional($0))
                }
            }
            .disabled(!settings.deepSeekKeyConfigured)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.localized(.settingsRewritePrompt))
                TextEditor(text: $settings.promptExpansionInstruction)
                    .font(.body)
                    .frame(minHeight: 96)
                Text(settings.localized(.settingsRewritePromptHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(settings.localized(.settingsRewriteMessageVariableHint))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var piIntegrationControls: some View {
        Section(settings.localized(.settingsPiIntegration)) {
            LabeledContent(settings.localized(.settingsPiIntegration)) {
                Text(piIntegrationStatusText)
                    .font(.footnote)
                    .foregroundStyle(piIntegrationStatusColor)
            }

            Text("\(settings.localized(.settingsPiIntegrationPath)) \(settings.piIntegrationDirectoryPath)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                switch settings.piIntegrationState {
                case .notInstalled:
                    Button(settings.localized(.settingsPiIntegrationInstall)) {
                        settings.installPiIntegration()
                    }
                case .installed:
                    Button(settings.localized(.settingsPiIntegrationUninstall), role: .destructive) {
                        isConfirmingPiUninstall = true
                    }
                    .confirmationDialog(
                        settings.localized(.settingsPiIntegrationUninstallConfirmation),
                        isPresented: $isConfirmingPiUninstall,
                        titleVisibility: .visible
                    ) {
                        Button(settings.localized(.settingsPiIntegrationUninstall), role: .destructive) {
                            settings.uninstallPiIntegration()
                        }
                        Button(settings.localized(.settingsCancel), role: .cancel) {}
                    }
                case .needsRepair:
                    Button(settings.localized(.settingsPiIntegrationRepair)) {
                        settings.repairPiIntegration()
                    }
                case .foreign:
                    EmptyView()
                }
            }

            if case .foreign = settings.piIntegrationState {
                Text(settings.localized(.settingsPiIntegrationForeignHint))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let message = settings.piIntegrationErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text(settings.localized(.settingsPiIntegrationRewriteHint))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(settings.localized(.settingsPiIntegrationExternalEditorHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(piExternalEditorInstruction)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(piExternalEditorInstruction, forType: .string)
                        copiedPiEditorInstruction = true
                    } label: {
                        Label(
                            copiedPiEditorInstruction
                                ? settings.localized(.settingsPiIntegrationCopied)
                                : settings.localized(.settingsPiIntegrationCopy),
                            systemImage: copiedPiEditorInstruction ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onAppear { settings.refreshPiIntegrationState() }
    }

    private var piExternalEditorInstruction: String {
        #""externalEditor": "cue --wait""#
    }

    private var piIntegrationStatusText: String {
        switch settings.piIntegrationState {
        case .notInstalled:
            settings.localized(.settingsPiIntegrationNotInstalled)
        case .installed(let version):
            String(format: settings.localized(.settingsPiIntegrationInstalledFormat), Int64(version))
        case .needsRepair:
            settings.localized(.settingsPiIntegrationNeedsRepair)
        case .foreign:
            settings.localized(.settingsPiIntegrationForeign)
        }
    }

    private var piIntegrationStatusColor: Color {
        switch settings.piIntegrationState {
        case .installed: .green
        case .needsRepair, .foreign: .red
        case .notInstalled: .secondary
        }
    }
}
