import AppKit
import Combine
import CueCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultContentSize = NSSize(width: 960, height: 700)
    private static let minimumContentSize = NSSize(width: 900, height: 560)

    private let settings: CueSettings
    private let targetScreen: NSScreen
    private let onClose: () -> Void
    private var languageObservation: AnyCancellable?
    private var hasPositionedWindow = false

    init(settings: CueSettings, screen: NSScreen, onClose: @escaping () -> Void) {
        self.settings = settings
        self.targetScreen = screen
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: CueSettingsView(settings: settings))
        hostingView.frame = NSRect(origin: .zero, size: Self.defaultContentSize)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setContentSize(Self.defaultContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.animationBehavior = .documentWindow

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

        if !hasPositionedWindow {
            positionWindow(window)
            hasPositionedWindow = true
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Avoid selecting the first editable field when the settings surface opens.
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func positionWindow(_ window: NSWindow) {
        let visible = targetScreen.visibleFrame
        let fittedWidth = min(Self.defaultContentSize.width, visible.width - 40)
        let fittedHeight = min(Self.defaultContentSize.height, visible.height - 40)
        window.setContentSize(NSSize(width: fittedWidth, height: fittedHeight))
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2
        ))
    }

    private func refreshTitle() {
        window?.title = CueLocalization.string(
            .settingsTitle,
            localization: settings.localizationIdentifier
        )
    }
}
