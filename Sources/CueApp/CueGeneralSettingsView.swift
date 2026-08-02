import AppKit
import CueCore
import SwiftUI

struct CueGeneralSettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var isConfirmingRestoreAll = false
    @State private var isConfirmingUsageClear = false

    var body: some View {
        Section {
            Picker(settings.localized(.settingsLanguage), selection: $settings.language) {
                Text(settings.localized(.settingsLanguageSystem)).tag(CueLanguage.system)
                Text(settings.localized(.languageEnglish)).tag(CueLanguage.english)
                Text(settings.localized(.languageSimplifiedChinese)).tag(CueLanguage.simplifiedChinese)
            }

            HStack(spacing: 8) {
                Text(settings.localized(.settingsWindowSize))
                Spacer(minLength: 0)
                dimensionField(
                    settings.localized(.settingsWidth),
                    value: $settings.windowWidth,
                    range: 420 ... 1_200
                )
                Text("×")
                    .foregroundStyle(.secondary)
                dimensionField(
                    settings.localized(.settingsHeight),
                    value: $settings.windowHeight,
                    range: CueSettings.minimumWindowHeight ... 800
                )
                Button {
                    settings.windowWidth = CueSettings.defaultWindowWidth
                    settings.windowHeight = CueSettings.defaultWindowHeight
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help(settings.localized(.settingsRestoreDefaultWindowSize))
                .disabled(settings.normalizedWidth == CueSettings.defaultWindowWidth && settings.normalizedHeight == CueSettings.defaultWindowHeight)
            }

            editorAppearanceSettings
        }

        Text(settings.localized(.settingsSizeHint))
            .font(.footnote)
            .foregroundStyle(.secondary)

        Section {
            settingsActions
        }
    }

    private var editorFontDisplayName: String {
        let systemFontName = NSFont.systemFont(ofSize: CGFloat(CueSettings.defaultEditorFontSize)).fontName
        guard settings.editorFont.fontName == systemFontName else {
            return settings.editorFont.displayName ?? settings.editorFont.fontName
        }
        return settings.localized(.settingsSystemFontRegular)
    }

    private var editorAppearanceSettings: some View {
        Group {
            LabeledContent(settings.localized(.settingsEditorFont)) {
                HStack(spacing: 8) {
                    Text("\(editorFontDisplayName) · \(settings.editorFont.pointSize.formatted()) \(settings.localized(.unitPoints))")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.editorFont.fontName)
                    Spacer(minLength: 8)
                    CueEditorFontPicker(
                        title: settings.localized(.settingsChooseFont),
                        font: Binding(get: { settings.editorFont }, set: { settings.setEditorFont($0) })
                    )
                    Button { settings.restoreDefaultEditorFont() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help(settings.localized(.settingsRestoreDefaultFont))
                }
            }
            LabeledContent(settings.localized(.settingsEditorFontSize)) {
                HStack(spacing: 5) {
                    TextField(
                        "",
                        value: $settings.editorFontSize,
                        format: .number.precision(.fractionLength(0))
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 46)
                    Text(settings.localized(.unitPoints))
                        .foregroundStyle(.secondary)
                    Stepper(
                        "",
                        value: $settings.editorFontSize,
                        in: CueSettings.minimumEditorFontSize ... CueSettings.maximumEditorFontSize,
                        step: 1
                    )
                    .labelsHidden()
                }
            }
            .help(settings.localized(.settingsEditorFontSizeHint))
            Toggle(
                settings.localized(.settingsChineseEnglishSpacing),
                isOn: $settings.insertsSpacesBetweenChineseAndEnglish
            )
            .help(settings.localized(.settingsChineseEnglishSpacingHint))

            Picker(settings.localized(.settingsOverflowBehavior), selection: $settings.overflowBehavior) {
                Text(settings.localized(.settingsOverflowScrollable))
                    .tag(CueOverflowBehavior.scrollable)
                Text(settings.localized(.settingsOverflowGrow))
                    .tag(CueOverflowBehavior.growWithContent)
            }
            .pickerStyle(.segmented)
        }
    }

    private var settingsActions: some View {
        HStack {
            Button(settings.localized(.settingsRestoreAll)) {
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

            Spacer()

            Button(settings.localized(.settingsClearUsage)) {
                isConfirmingUsageClear = true
            }
            .confirmationDialog(
                settings.localized(.settingsClearUsageConfirmation),
                isPresented: $isConfirmingUsageClear,
                titleVisibility: .visible
            ) {
                Button(settings.localized(.settingsClearUsage), role: .destructive) {
                    CueUsageStore.shared.clearUsageStatistics()
                }
                Button(settings.localized(.settingsCancel), role: .cancel) {}
            }
        }
    }

    private func dimensionField(
        _: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 5) {
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text(settings.localized(.unitPoints))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Stepper("", value: value, in: range, step: 10)
                .labelsHidden()
        }
    }
}

/// Bridges AppKit's shared font panel into the SwiftUI settings form.
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
