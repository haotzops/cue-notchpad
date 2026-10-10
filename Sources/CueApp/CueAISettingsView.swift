import AppKit
import CueCore
import SwiftUI

struct CueAISettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var isConfirmingPiUninstall = false
    @State private var copiedPiEditorInstruction = false
    @State private var showPiDetails = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.promptExpansionInstruction)
                    .font(.body)
                    .frame(minHeight: 150)
                    .accessibilityLabel(settings.localized(.settingsRewritePrompt))
            } header: {
                Text(settings.localized(.settingsRewritePrompt))
            }

            Section(settings.localized(.settingsPiIntegration)) {
                HStack {
                    statusLabel
                    Spacer()
                    piIntegrationAction
                }

                if let message = settings.piIntegrationErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .foreign = settings.piIntegrationState {
                    Label(
                        settings.localized(.settingsPiIntegrationForeignHint),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }

                piEditorConfiguration

                DisclosureGroup(
                    settings.localized(.settingsAdvanced),
                    isExpanded: $showPiDetails
                ) {
                    LabeledContent(settings.localized(.settingsPiIntegrationPath)) {
                        Text(settings.piIntegrationDirectoryPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .cueSettingsFormAppearance()
        .onAppear { settings.refreshPiIntegrationState() }
    }

    private var statusLabel: some View {
        CueSettingsStatusLabel(
            text: piIntegrationStatusText,
            color: piIntegrationStatusColor,
            systemImage: piIntegrationStatusImage
        )
    }

    private var piEditorConfiguration: some View {
        LabeledContent("externalEditor") {
            HStack(spacing: 8) {
                Text(piExternalEditorInstruction)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(piExternalEditorInstruction, forType: .string)
                    copiedPiEditorInstruction = true
                } label: {
                    Image(systemName: copiedPiEditorInstruction ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(settings.localized(.settingsPiIntegrationCopy))
                .help(
                    copiedPiEditorInstruction
                        ? settings.localized(.settingsPiIntegrationCopied)
                        : settings.localized(.settingsPiIntegrationCopy)
                )
            }
        }
    }

    @ViewBuilder
    private var piIntegrationAction: some View {
        switch settings.piIntegrationState {
        case .notInstalled:
            Button(settings.localized(.settingsPiIntegrationInstall)) {
                settings.installPiIntegration()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .installed:
            Button(settings.localized(.settingsPiIntegrationUninstall), role: .destructive) {
                isConfirmingPiUninstall = true
            }
            .controlSize(.small)
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
            .controlSize(.small)
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
