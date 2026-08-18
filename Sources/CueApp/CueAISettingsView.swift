import AppKit
import CueCore
import SwiftUI

struct CueAISettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var isConfirmingPiUninstall = false
    @State private var copiedPiEditorInstruction = false

    var body: some View {
        VStack(spacing: 18) {
            rewritePrompt
            piIntegrationControls
        }
    }

    private var rewritePrompt: some View {
        CueSettingsCard(
            settings.localized(.settingsRewritePrompt),
            detail: settings.localized(.settingsRewritePromptHint)
        ) {
            VStack(alignment: .leading, spacing: 9) {
                TextEditor(text: $settings.promptExpansionInstruction)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 126)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                Label(
                    settings.localized(.settingsRewriteMessageVariableHint),
                    systemImage: "curlybraces"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var piIntegrationControls: some View {
        CueSettingsCard(
            settings.localized(.settingsPiIntegration),
            detail: settings.localized(.settingsPiIntegrationRewriteHint)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CueSettingsStatusBadge(
                        text: piIntegrationStatusText,
                        color: piIntegrationStatusColor,
                        systemImage: piIntegrationStatusImage
                    )
                    Spacer()
                    piIntegrationAction
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.localized(.settingsPiIntegrationPath))
                        .font(.caption.weight(.medium))
                    Text(settings.piIntegrationDirectoryPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if case .foreign = settings.piIntegrationState {
                    Label(
                        settings.localized(.settingsPiIntegrationForeignHint),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let message = settings.piIntegrationErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text(settings.localized(.settingsPiIntegrationExternalEditorHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(piExternalEditorInstruction)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
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
                    }
                }
            }
        }
        .onAppear { settings.refreshPiIntegrationState() }
    }

    @ViewBuilder
    private var piIntegrationAction: some View {
        switch settings.piIntegrationState {
        case .notInstalled:
            Button(settings.localized(.settingsPiIntegrationInstall)) {
                settings.installPiIntegration()
            }
            .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
        case .foreign:
            EmptyView()
        }
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

    private var piIntegrationStatusImage: String {
        switch settings.piIntegrationState {
        case .installed: "checkmark.circle.fill"
        case .needsRepair, .foreign: "exclamationmark.triangle.fill"
        case .notInstalled: "circle.dashed"
        }
    }
}
