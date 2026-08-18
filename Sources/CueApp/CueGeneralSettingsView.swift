import AppKit
import CueCore
import SwiftUI

struct CueGeneralSettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var isConfirmingRestoreAll = false

    var body: some View {
        VStack(spacing: 18) {
            applicationCard
            windowCard
            editorCard
            resetCard
        }
    }

    private var applicationCard: some View {
        CueSettingsCard(settings.localized(.settingsGeneral)) {
            CueSettingsRow(
                settings.localized(.settingsLanguage),
                systemImage: "globe"
            ) {
                Picker("", selection: $settings.language) {
                    Text(settings.localized(.settingsLanguageSystem)).tag(CueLanguage.system)
                    Text(settings.localized(.languageEnglish)).tag(CueLanguage.english)
                    Text(settings.localized(.languageSimplifiedChinese)).tag(CueLanguage.simplifiedChinese)
                }
                .labelsHidden()
            }

            CueSettingsRow(
                settings.localized(.settingsChineseEnglishSpacing),
                detail: settings.localized(.settingsChineseEnglishSpacingHint),
                systemImage: "textformat"
            ) {
                Toggle("", isOn: $settings.insertsSpacesBetweenChineseAndEnglish)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private var windowCard: some View {
        CueSettingsCard(settings.localized(.settingsWindowSize)) {
            CueSettingsRow(
                "\(settings.localized(.settingsWidth)) × \(settings.localized(.settingsHeight))",
                detail: settings.localized(.settingsSizeHint),
                systemImage: "macwindow"
            ) {
                HStack(spacing: 8) {
                    dimensionField(value: $settings.windowWidth)
                    Text("×")
                        .foregroundStyle(.tertiary)
                    dimensionField(value: $settings.windowHeight)
                    Button {
                        settings.windowWidth = CueSettings.defaultWindowWidth
                        settings.windowHeight = CueSettings.defaultWindowHeight
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help(settings.localized(.settingsRestoreDefaultWindowSize))
                    .disabled(
                        settings.normalizedWidth == CueSettings.defaultWindowWidth
                            && settings.normalizedHeight == CueSettings.defaultWindowHeight
                    )
                }
            }

            CueSettingsRow(
                settings.localized(.settingsLockWindow),
                detail: settings.localized(.settingsLockWindowHint),
                systemImage: settings.locksPromptWindow ? "lock.fill" : "lock.open"
            ) {
                Toggle("", isOn: $settings.locksPromptWindow)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            CueSettingsRow(
                settings.localized(.settingsOverflowBehavior),
                systemImage: "arrow.up.and.down.text.horizontal"
            ) {
                Picker("", selection: $settings.overflowBehavior) {
                    Text(settings.localized(.settingsOverflowScrollable))
                        .tag(CueOverflowBehavior.scrollable)
                    Text(settings.localized(.settingsOverflowGrow))
                        .tag(CueOverflowBehavior.growWithContent)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var editorCard: some View {
        CueSettingsCard(settings.localized(.settingsEditor)) {
            CueSettingsRow(
                settings.localized(.settingsEditorFont),
                systemImage: "textformat.size"
            ) {
                HStack(spacing: 8) {
                    Text(editorFontDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180, alignment: .trailing)
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
                    .help(settings.localized(.settingsRestoreDefaultFont))
                }
            }

            CueSettingsRow(
                settings.localized(.settingsEditorFontSize),
                detail: settings.localized(.settingsEditorFontSizeHint),
                systemImage: "character.cursor.ibeam"
            ) {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        value: $settings.editorFontSize,
                        format: .number.precision(.fractionLength(0))
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
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
        }
    }

    private var resetCard: some View {
        CueSettingsCard(settings.localized(.settingsResetAndData)) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.localized(.settingsRestoreAll))
                    Text(settings.localized(.settingsRestoreAllDetail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 20)

                Button(settings.localized(.settingsRestore)) {
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
            }
        }
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

    private func dimensionField(value: Binding<Double>) -> some View {
        HStack(spacing: 5) {
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text(settings.localized(.unitPoints))
                .foregroundStyle(.secondary)
        }
    }
}

/// Bridges AppKit's shared font panel into the SwiftUI settings surface.
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
