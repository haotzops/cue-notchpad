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
        inlineCompletion
        promptRewrite
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
                .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)

                Button(settings.localized(.settingsHealthCheck)) {
                    settings.checkDeepSeekServiceHealth()
                }
                .disabled(!settings.inlineCompletionKeyConfigured || settings.isTestingInlineCompletionConnection)

                Button(settings.localized(.settingsRemoveAPIKey)) {
                    settings.removeDeepSeekAPIKey()
                }
                .disabled(!settings.inlineCompletionKeyConfigured)
            }
            Text(settings.inlineCompletionKeyConfigured
                ? settings.localized(.settingsAPIKeyConfigured)
                : settings.localized(.settingsAPIKeyNotConfigured)
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let status = settings.inlineCompletionStatus {
                HStack(spacing: 6) {
                    if settings.isTestingInlineCompletionConnection {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(status.message)
                }
                .font(.footnote)
                .foregroundStyle(status.style == .error ? Color.red : Color.secondary)
            }
        }
    }

    private var inlineCompletion: some View {
        Section(settings.localized(.settingsFIM)) {
            piIntegrationControls

            Toggle(settings.localized(.settingsInlineCompletion), isOn: $settings.inlineCompletionEnabled)
                .disabled(!settings.piIntegrationInstalled)

            if !settings.piIntegrationInstalled {
                Text(settings.localized(.settingsPiIntegrationRequired))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.localized(.settingsInlineCompletionHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Picker(
                        settings.localized(.settingsInlineCompletionModel),
                        selection: $settings.inlineCompletionModel
                    ) {
                        Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                        ForEach(settings.inlineCompletionModels, id: \.self) { model in
                            Text(model).tag(Optional(model))
                        }
                    }
                    .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)

                    if settings.isLoadingInlineCompletionModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button(settings.localized(.settingsTestFIM)) {
                        settings.testDeepSeekFIM()
                    }
                    .disabled(
                        !settings.inlineCompletionKeyConfigured
                            || settings.inlineCompletionModel == nil
                            || settings.isTestingInlineCompletionConnection
                    )
                }

                Picker(settings.localized(.settingsTriggerMode), selection: $settings.inlineCompletionTriggerMode) {
                    Text(settings.localized(.settingsTriggerAutomatic)).tag(InlineCompletionTriggerMode.automatic)
                    Text(settings.localized(.settingsTriggerManual)).tag(InlineCompletionTriggerMode.manual)
                }

                if settings.inlineCompletionTriggerMode != .manual {
                    HStack {
                        Text(settings.localized(.settingsTriggerDelay))
                        TextField(
                            settings.localized(.unitMilliseconds),
                            value: $settings.inlineCompletionDelayMilliseconds,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 72)
                        Text(settings.localized(.unitMilliseconds))
                    }
                }

                HStack(spacing: 8) {
                    Text(settings.localized(.settingsMaximumLines))
                    Spacer()
                    Text("\(settings.inlineCompletionMaximumLines)")
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                    Stepper("", value: $settings.inlineCompletionMaximumLines, in: 1 ... 100)
                        .labelsHidden()
                }
            }
        }
    }

    private var piIntegrationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var promptRewrite: some View {
        Section(settings.localized(.settingsAIRewrite)) {
            Picker(settings.localized(.settingsInlineCompletionModel), selection: $settings.promptExpansionModel) {
                Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                ForEach(settings.inlineCompletionModels, id: \.self) {
                    Text($0).tag(Optional($0))
                }
            }
            .disabled(!settings.inlineCompletionKeyConfigured)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.localized(.settingsRewritePrompt))
                TextEditor(text: $settings.promptExpansionInstruction)
                    .font(.body)
                    .frame(minHeight: 72)
                Text(settings.localized(.settingsRewritePromptHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
