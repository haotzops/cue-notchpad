import AppKit
import CueCore
import SwiftUI

struct CueGeneralSettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var isConfirmingRestoreAll = false

    var body: some View {
        Form {
            Section {
                Picker(settings.localized(.settingsLanguage), selection: $settings.language) {
                    Text(settings.localized(.settingsLanguageSystem)).tag(CueLanguage.system)
                    Text(settings.localized(.languageEnglish)).tag(CueLanguage.english)
                    Text(settings.localized(.languageSimplifiedChinese)).tag(CueLanguage.simplifiedChinese)
                }

                Toggle(
                    settings.localized(.settingsChineseEnglishSpacing),
                    isOn: $settings.insertsSpacesBetweenChineseAndEnglish
                )
            } header: {
                Text(settings.localized(.settingsGeneral))
            }

            Section {
                LabeledContent(
                    "\(settings.localized(.settingsWidth)) × \(settings.localized(.settingsHeight))"
                ) {
                    HStack(spacing: 7) {
                        dimensionField(value: $settings.windowWidth, label: .settingsWidth)
                        Text("×").foregroundStyle(.secondary)
                        dimensionField(value: $settings.windowHeight, label: .settingsHeight)
                        Button {
                            settings.windowWidth = CueSettings.defaultWindowWidth
                            settings.windowHeight = CueSettings.defaultWindowHeight
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(settings.localized(.settingsRestoreDefaultWindowSize))
                        .accessibilityLabel(settings.localized(.settingsRestoreDefaultWindowSize))
                        .disabled(
                            settings.normalizedWidth == CueSettings.defaultWindowWidth
                                && settings.normalizedHeight == CueSettings.defaultWindowHeight
                        )
                    }
                }

                Toggle(isOn: $settings.locksPromptWindow) {
                    Text(settings.localized(.settingsLockWindow))
                }

                Picker(settings.localized(.settingsOverflowBehavior), selection: $settings.overflowBehavior) {
                    Text(settings.localized(.settingsOverflowScrollable))
                        .tag(CueOverflowBehavior.scrollable)
                    Text(settings.localized(.settingsOverflowGrow))
                        .tag(CueOverflowBehavior.growWithContent)
                }
            } header: {
                Text(settings.localized(.settingsWindowSize))
            }

            Section {
                LabeledContent(settings.localized(.settingsEditorFont)) {
                    HStack(spacing: 8) {
                        Text(editorFontDisplayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.editorFont.fontName)
                        CueEditorFontPicker(
                            title: settings.localized(.settingsChooseFont),
                            font: Binding(
                                get: { settings.editorFont },
                                set: { settings.setEditorFont($0) }
                            )
                        )
                        Button { settings.restoreDefaultEditorFont() } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(settings.localized(.settingsRestoreDefaultFont))
                        .accessibilityLabel(settings.localized(.settingsRestoreDefaultFont))
                    }
                }

                LabeledContent(settings.localized(.settingsEditorFontSize)) {
                    HStack(spacing: 6) {
                        CuePointField(
                            value: $settings.editorFontSize,
                            unit: settings.localized(.unitPoints),
                            accessibilityLabel: settings.localized(.settingsEditorFontSize),
                            spacing: 6
                        )
                        Stepper(
                            "",
                            value: $settings.editorFontSize,
                            in: CueSettings.minimumEditorFontSize ... CueSettings.maximumEditorFontSize,
                            step: 1
                        )
                        .labelsHidden()
                        .accessibilityLabel(settings.localized(.settingsEditorFontSize))
                    }
                }
            } header: {
                Text(settings.localized(.settingsEditor))
            }

            Section {
                Button(settings.localized(.settingsRestoreAll), role: .destructive) {
                    isConfirmingRestoreAll = true
                }
                .confirmationDialog(
                    settings.localized(.settingsRestoreAllConfirmation),
                    isPresented: $isConfirmingRestoreAll,
                    titleVisibility: .visible
                ) {
                    Button(settings.localized(.settingsRestoreAll), role: .destructive) {
                        settings.restoreAllSettings()
                    }
                    Button(settings.localized(.settingsCancel), role: .cancel) {}
                }
            } header: {
                Text(settings.localized(.settingsResetAndData))
            }
        }
        .cueSettingsFormAppearance()
    }

    private var editorFontDisplayName: String {
        let systemFontName = NSFont.systemFont(
            ofSize: CGFloat(CueSettings.defaultEditorFontSize)
        ).fontName
        guard settings.editorFont.fontName == systemFontName else {
            return settings.editorFont.displayName ?? settings.editorFont.fontName
        }
        return settings.localized(.settingsSystemFontRegular)
    }

    private func dimensionField(value: Binding<Double>, label: CueLocalizedKey) -> some View {
        CuePointField(
            value: value,
            unit: settings.localized(.unitPoints),
            accessibilityLabel: settings.localized(label),
            spacing: 4
        )
    }
}

private struct CueEditorFontPicker: View {
    let title: String
    @Binding var font: NSFont
    @State private var delegate: FontPanelDelegate?

    var body: some View {
        Button(title) {
            delegate = FontPanelDelegate { manager in
                font = manager.convert(font)
            }
            NSFontManager.shared.target = delegate
            NSFontPanel.shared.setPanelFont(font, isMultiple: false)
            NSFontPanel.shared.orderFront(nil)
        }
        .onDisappear {
            NSFontManager.shared.target = nil
            NSFontManager.shared.fontPanel(false)?.close()
        }
    }

    private final class FontPanelDelegate: NSObject {
        let action: (NSFontManager) -> Void

        init(action: @escaping (NSFontManager) -> Void) {
            self.action = action
        }

        @objc func changeFont(_ sender: NSFontManager) {
            action(sender)
        }

        @objc func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
            [.collection, .face, .size]
        }
    }
}
