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
                            range: 220 ... 800
                        )
                    }
                }

                Toggle(
                    localized(.settingsAlwaysOnTop, "Keep prompt above other windows"),
                    isOn: $settings.alwaysOnTop
                )
            } header: {
                Text(localized(.settingsGeneral, "General"))
            }

            Text(localized(
                .settingsSizeHint,
                "Changes apply to the current prompt window."
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 290)
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

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: CueSettings
    private let onClose: () -> Void
    private var languageObservation: AnyCancellable?

    init(settings: CueSettings, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 290),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: CueSettingsView(settings: settings)
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.animationBehavior = .documentWindow
        window.center()

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
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
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
