import AppKit
import Combine
import CueCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 500, height: 360)

    private let settings: CueSettings
    private let targetScreen: NSScreen
    private let onClose: () -> Void
    private var languageObservation: AnyCancellable?

    init(settings: CueSettings, screen: NSScreen, onClose: @escaping () -> Void) {
        self.settings = settings
        self.targetScreen = screen
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: CueSettingsView(settings: settings))
        hostingView.frame = NSRect(origin: .zero, size: Self.contentSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setContentSize(Self.contentSize)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.animationBehavior = .none
        window.contentMinSize = Self.contentSize

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
        // Center after applying the preferred initial size; the SwiftUI form
        // remains scrollable when a settings page needs more vertical space.
        window.setContentSize(Self.contentSize)
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
            localization: settings.localizationIdentifier
        )
    }
}
