import AppKit
import Combine
import CueCore
import SwiftUI

private enum CueSettingsPage: String, CaseIterable, Identifiable {
    case general, ai, usage, shortcuts
    var id: String { rawValue }
}

struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings
    @State private var deepSeekAPIKey = ""
    @State private var page: CueSettingsPage = .general

    private var localization: String? { settings.localizationIdentifier }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text(localized(.settingsPageGeneral, "General")).tag(CueSettingsPage.general)
                Text(localized(.settingsPageAI, "AI")).tag(CueSettingsPage.ai)
                Text(localized(.settingsPageUsage, "Usage")).tag(CueSettingsPage.usage)
                Text(localized(.settingsShortcuts, "Shortcuts")).tag(CueSettingsPage.shortcuts)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding()

            Form {
            if page == .general {
            Section {
                Picker(localized(.settingsLanguage, "Language"), selection: $settings.language) {
                    Text(localized(.settingsLanguageSystem, "System Default"))
                        .tag(CueLanguage.system)
                    Text(localized(.languageEnglish, "English")).tag(CueLanguage.english)
                    Text(localized(.languageSimplifiedChinese, "Simplified Chinese")).tag(CueLanguage.simplifiedChinese)
                }

                HStack(spacing: 8) {
                    Text(localized(.settingsWindowSize, "Window Size"))
                    Spacer(minLength: 0)
                    dimensionField(
                        localized(.settingsWidth, "Width"),
                        value: $settings.windowWidth,
                        range: 420 ... 1_200
                    )
                    Text("×")
                        .foregroundStyle(.secondary)
                    dimensionField(
                        localized(.settingsHeight, "Height"),
                        value: $settings.windowHeight,
                        range: CueSettings.minimumWindowHeight ... 800
                    )
                    Button {
                        settings.windowWidth = CueSettings.defaultWindowWidth
                        settings.windowHeight = CueSettings.defaultWindowHeight
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Restore default window size")
                    .disabled(settings.normalizedWidth == CueSettings.defaultWindowWidth && settings.normalizedHeight == CueSettings.defaultWindowHeight)
                }

                editorAppearanceSettings
            }
            }

            if page == .ai {
            Section(localized(.settingsModelAPIConfiguration, "Model API Configuration")) {
                SecureField(localized(.settingsDeepSeekAPIKey, "DeepSeek API Key"), text: $deepSeekAPIKey)
                HStack {
                    Button(localized(.settingsSaveAPIKey, "Save API Key")) { settings.saveDeepSeekAPIKey(deepSeekAPIKey); deepSeekAPIKey = "" }
                        .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(localized(.settingsRefreshModels, "Refresh Models")) { settings.refreshDeepSeekModelsIfPossible() }
                        .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)
                    Button(localized(.settingsRemoveAPIKey, "Remove API Key")) { settings.removeDeepSeekAPIKey() }
                        .disabled(!settings.inlineCompletionKeyConfigured)
                }
                Text(settings.inlineCompletionKeyConfigured ? localized(.settingsAPIKeyConfigured, "Saved in local configuration") : localized(.settingsAPIKeyNotConfigured, "Not configured"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(localized(.settingsFIM, "FIM")) {
                Toggle(localized(.settingsInlineCompletion, "Enable DeepSeek inline completion"), isOn: $settings.inlineCompletionEnabled)
                VStack(alignment: .leading, spacing: 6) {
                        Text(localized(
                            .settingsInlineCompletionHint,
                            "When enabled, nearby prompt text is sent to DeepSeek FIM to generate a suggestion. Press Tab to accept it."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        HStack {
                            Picker(
                                localized(.settingsInlineCompletionModel, "Model"),
                                selection: $settings.inlineCompletionModel
                            ) {
                                Text(localized(.settingsChooseModel, "Choose a model"))
                                    .tag(String?.none)
                                ForEach(settings.inlineCompletionModels, id: \.self) { model in
                                    Text(model).tag(Optional(model))
                                }
                            }
                            .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)


                            if settings.isLoadingInlineCompletionModels {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Picker(localized(.settingsTriggerMode, "Trigger mode"), selection: $settings.inlineCompletionTriggerMode) {
                            Text(localized(.settingsTriggerAutomatic, "Automatic")).tag(InlineCompletionTriggerMode.automatic)
                            Text(localized(.settingsTriggerManual, "Shortcut only")).tag(InlineCompletionTriggerMode.manual)
                        }

                        if settings.inlineCompletionTriggerMode != .manual {
                            HStack {
                                Text(localized(.settingsTriggerDelay, "Automatic trigger delay"))
                                TextField("ms", value: $settings.inlineCompletionDelayMilliseconds, format: .number.precision(.fractionLength(0)))
                                    .frame(width: 72)
                                Text(localized(.unitMilliseconds, "ms"))
                            }
                        }

                        HStack(spacing: 8) {
                            Text(localized(.settingsMaximumLines, "Maximum completion lines"))
                            Spacer()
                            Text("\(settings.inlineCompletionMaximumLines)")
                                .monospacedDigit()
                                .frame(minWidth: 18, alignment: .trailing)
                            Stepper("", value: $settings.inlineCompletionMaximumLines, in: 1 ... 100)
                                .labelsHidden()
                        }

                }
            }
            Section(localized(.settingsAIPolish, "AI Polish")) {
                Picker(localized(.settingsInlineCompletionModel, "Model"), selection: $settings.promptExpansionModel) {
                    Text(localized(.settingsChooseModel, "Choose a model")).tag(String?.none)
                    ForEach(settings.inlineCompletionModels, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .disabled(!settings.inlineCompletionKeyConfigured)
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized(.settingsPolishPrompt, "Polishing prompt"))
                    TextEditor(text: $settings.promptExpansionInstruction).font(.body).frame(minHeight: 72)
                    Text(localized(.settingsPolishPromptHint, "Changes save automatically and apply to the next polish request."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            }

            if page == .usage {
            Section {
                CueUsageStatisticsView(settings: settings)
            }
            }

            if page == .shortcuts {
            Section {
                shortcutRow(localized(.shortcutToggle, "Show or hide Cue"), shortcut: $settings.toggleShortcut)
                shortcutRow(localized(.shortcutPrevious, "Previous session"), shortcut: $settings.previousShortcut)
                shortcutRow(localized(.shortcutNext, "Next session"), shortcut: $settings.nextShortcut)
                shortcutRow(localized(.settingsManualCompletion, "Trigger completion"), shortcut: $settings.inlineCompletionShortcut, allowsUnmodifiedKeys: true)
                shortcutRow(localized(.settingsAIPolish, "AI Polish"), shortcut: $settings.promptExpansionShortcut)
                LabeledContent(localized(.settingsAcceptCompletion, "Accept completion")) {
                    CueShortcutRecorder(
                        shortcut: $settings.inlineCompletionAcceptShortcut,
                        recordingPrompt: localized(.shortcutRecord, "Type shortcut…"),
                        allowsUnmodifiedKeys: true
                    )
                    .frame(width: 110, height: 24)
                }
            }
            }

            if page == .general {
            Text(localized(
                .settingsSizeHint,
                "Changes apply to the current prompt window."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 680, maxHeight: .infinity)
    }

    private var editorFontDisplayName: String {
        let systemFontName = NSFont.systemFont(ofSize: CGFloat(CueSettings.defaultEditorFontSize)).fontName
        guard settings.editorFont.fontName == systemFontName else {
            return settings.editorFont.displayName ?? settings.editorFont.fontName
        }
        return localized(.settingsSystemFontRegular, "System Font Regular")
    }

    private var editorAppearanceSettings: some View {
        Group {
            LabeledContent(localized(.settingsEditorFont, "Editor Font")) {
                HStack(spacing: 8) {
                    Text("\(editorFontDisplayName) · \(settings.editorFont.pointSize.formatted()) \(localized(.unitPoints, "pt"))")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.editorFont.fontName)
                    Spacer(minLength: 8)
                    CueEditorFontPicker(
                        title: localized(.settingsChooseFont, "Choose…"),
                        font: Binding(get: { settings.editorFont }, set: { settings.setEditorFont($0) })
                    )
                    Button { settings.restoreDefaultEditorFont() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help(localized(.settingsRestoreDefaultFont, "Restore default editor font"))
                }
            }
            Toggle(
                localized(.settingsChineseEnglishSpacing, "Add spaces between Chinese and English"),
                isOn: $settings.insertsSpacesBetweenChineseAndEnglish
            )
            .help(localized(.settingsChineseEnglishSpacingHint, "Apply spacing when the prompt is submitted."))

            Picker(localized(.settingsOverflowBehavior, "Editor Height"), selection: $settings.overflowBehavior) {
                Text(localized(.settingsOverflowScrollable, "Scrollable Window"))
                    .tag(CueOverflowBehavior.scrollable)
                Text(localized(.settingsOverflowGrow, "Grow with Content"))
                    .tag(CueOverflowBehavior.growWithContent)
            }
            .pickerStyle(.segmented)
        }
    }

    private func shortcutRow(_ label: String, shortcut: Binding<CueShortcut>, allowsUnmodifiedKeys: Bool = false) -> some View {
        LabeledContent(label) {
            CueShortcutRecorder(
                shortcut: shortcut,
                recordingPrompt: localized(.shortcutRecord, "Type shortcut…"),
                allowsUnmodifiedKeys: allowsUnmodifiedKeys
            )
            .frame(width: 110, height: 24)
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
            Text(localized(.unitPoints, "pt"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Stepper("", value: value, in: range, step: 10)
                .labelsHidden()
        }
    }

    private func localized(_ key: CueLocalizedKey, _ fallback: String) -> String {
        CueLocalization.string(key, fallback: fallback, localization: localization)
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

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: CueSettings
    private let targetScreen: NSScreen
    private let onClose: () -> Void
    private var languageObservation: AnyCancellable?

    init(settings: CueSettings, screen: NSScreen, onClose: @escaping () -> Void) {
        self.settings = settings
        self.targetScreen = screen
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: CueSettingsView(settings: settings))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 560)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 500, height: 560))
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.animationBehavior = .none
        window.contentMinSize = NSSize(width: 500, height: 560)

        super.init(window: window)
        window.delegate = self
        refreshTitle()
        languageObservation = settings.$language.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshTitle() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refreshTitle()
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        // Center only after the final fixed content size is known; the first
        // SwiftUI layout must not be allowed to move the window afterwards.
        window.setContentSize(NSSize(width: 500, height: 560))
        let visible = targetScreen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI Form otherwise makes its first numeric TextField first responder,
        // selecting the saved width whenever settings opens.
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func refreshTitle() {
        window?.title = CueLocalization.string(
            .settingsTitle,
            fallback: "Settings",
            localization: settings.localizationIdentifier
        )
    }
}
