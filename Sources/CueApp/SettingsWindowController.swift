import AppKit
import Combine
import CueCore
import SwiftUI

struct CueSettingsView: View {
    @ObservedObject var settings: CueSettings

    private var localization: String? { settings.localizationIdentifier }

    var body: some View {
        Form {
            Section {
                Picker(localized(.settingsLanguage, "Language"), selection: $settings.language) {
                    Text(localized(.settingsLanguageSystem, "System Default"))
                        .tag(CueLanguage.system)
                    Text("English").tag(CueLanguage.english)
                    Text("简体中文").tag(CueLanguage.simplifiedChinese)
                }

                LabeledContent(localized(.settingsWindowSize, "Window Size")) {
                    HStack(spacing: 8) {
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
                    }
                    Button {
                        settings.windowWidth = CueSettings.defaultWindowWidth
                        settings.windowHeight = CueSettings.defaultWindowHeight
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Restore default window size")
                    .disabled(settings.normalizedWidth == CueSettings.defaultWindowWidth && settings.normalizedHeight == CueSettings.defaultWindowHeight)
                }

            } header: {
                Text(localized(.settingsGeneral, "General"))
            }

            Section {
                LabeledContent(localized(.settingsEditorFont, "Editor Font")) {
                    HStack(spacing: 8) {
                        Text("\(settings.editorFont.displayName ?? settings.editorFont.fontName) · \(settings.editorFont.pointSize.formatted()) pt")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.editorFont.fontName)
                        Spacer(minLength: 8)
                        CueEditorFontPicker(
                            title: localized(.settingsChooseFont, "Choose…"),
                            font: Binding(
                                get: { settings.editorFont },
                                set: { settings.setEditorFont($0) }
                            )
                        )
                        Button {
                            settings.restoreDefaultEditorFont()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help(localized(.settingsRestoreDefaultFont, "Restore default editor font"))
                        .disabled(
                            settings.editorFontName == NSFont.systemFont(
                                ofSize: CGFloat(CueSettings.defaultEditorFontSize)
                            ).fontName && settings.editorFontSize == CueSettings.defaultEditorFontSize
                        )
                    }
                }

                Picker(localized(.settingsOverflowBehavior, "Editor Height"), selection: $settings.overflowBehavior) {
                    Text(localized(.settingsOverflowScrollable, "Scrollable Window"))
                        .tag(CueOverflowBehavior.scrollable)
                    Text(localized(.settingsOverflowGrow, "Grow with Content"))
                        .tag(CueOverflowBehavior.growWithContent)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(localized(.settingsEditor, "Editor"))
            }

            Section {
                shortcutRow(localized(.shortcutToggle, "Show or hide Cue"), shortcut: $settings.toggleShortcut)
                shortcutRow(localized(.shortcutPrevious, "Previous session"), shortcut: $settings.previousShortcut)
                shortcutRow(localized(.shortcutNext, "Next session"), shortcut: $settings.nextShortcut)
            } header: {
                Text(localized(.settingsShortcuts, "Shortcuts"))
            }

            Text(localized(
                .settingsSizeHint,
                "Changes apply to the current prompt window."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
    }

    private func shortcutRow(_ label: String, shortcut: Binding<CueShortcut>) -> some View {
        LabeledContent(label) {
            CueShortcutRecorder(
                shortcut: shortcut,
                recordingPrompt: localized(.shortcutRecord, "Type shortcut…")
            )
            .frame(width: 110, height: 24)
        }
    }

    private func dimensionField(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text("pt")
                .foregroundStyle(.secondary)
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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: CueSettingsView(settings: settings))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 440)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 500, height: 440))
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.animationBehavior = .none
        window.contentMinSize = NSSize(width: 500, height: 440)

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
        window.setContentSize(NSSize(width: 500, height: 440))
        let visible = targetScreen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
