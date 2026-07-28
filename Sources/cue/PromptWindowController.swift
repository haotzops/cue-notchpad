import AppKit
import Combine
import CueCore
import SwiftUI

final class CuePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum CueOutcome: Equatable {
    case submitted(String)
    case cancelled
}

final class PromptWindowController: NSWindowController {
    private let model: PromptModel
    private let settings: CueSettings
    private let targetScreen: NSScreen
    private let screenGeometry: NotchScreenGeometry
    private let completion: (CueOutcome) -> Void
    private weak var editor: NSTextView?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var settingsObservation: AnyCancellable?
    private var didFinish = false

    private var layout: NotchLayout {
        NotchLayout(
            screen: screenGeometry,
            preferredOpenWidth: settings.normalizedWidth,
            preferredOpenHeight: settings.normalizedHeight
        )
    }

    init(
        initialText: String,
        settings: CueSettings,
        screen: NSScreen,
        completion: @escaping (CueOutcome) -> Void
    ) {
        let screenGeometry = Self.geometry(for: screen)
        let initialLayout = NotchLayout(
            screen: screenGeometry,
            preferredOpenWidth: settings.normalizedWidth,
            preferredOpenHeight: settings.normalizedHeight
        )

        self.model = PromptModel(text: initialText)
        self.settings = settings
        self.targetScreen = screen
        self.screenGeometry = screenGeometry
        self.completion = completion

        let contentSize = CGSize(
            width: initialLayout.openSize.width + 36,
            height: initialLayout.openSize.height + 24
        )
        let panel = CuePanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)
        configure(panel)

        panel.contentView = NSHostingView(
            rootView: PromptView(
                model: model,
                settings: settings,
                screenGeometry: screenGeometry,
                onSubmit: { [weak self] in self?.submit() },
                onCancel: { [weak self] in self?.cancel() },
                onHide: { [weak self] in self?.hideTemporarily() },
                onOpenSettings: { [weak self] in self?.openSettings() },
                onEditorReady: { [weak self, weak panel] textView in
                    self?.editor = textView
                    panel?.makeFirstResponder(textView)
                }
            )
        )

        settingsObservation = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let panel = window else { return }

        let frame = targetScreen.frame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height
        ))
        panel.alphaValue = 1
        applySettings()
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func submit() {
        finish(with: .submitted(model.text))
    }

    @objc func cancel() {
        finish(with: .cancelled)
    }

    @objc func hideTemporarily() {
        guard !didFinish, statusItem == nil else { return }
        settingsWindowController?.close()
        model.isExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, !self.didFinish else { return }
            self.window?.orderOut(nil)
            self.installStatusItem()
        }
    }

    @objc func showFromStatusItem() {
        guard !didFinish else { return }
        removeStatusItem()
        model.isExpanded = false
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.model.isExpanded = true
            if let editor = self.editor {
                self.window?.makeFirstResponder(editor)
            }
        }
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onClose: { [weak self] in
                    guard let self, !self.didFinish else { return }
                    self.window?.makeKeyAndOrderFront(nil)
                    if let editor = self.editor {
                        self.window?.makeFirstResponder(editor)
                    }
                }
            )
        }
        settingsWindowController?.show()
    }

    private func applySettings() {
        guard let panel = window else { return }
        let contentSize = CGSize(
            width: layout.openSize.width + 36,
            height: layout.openSize.height + 24
        )
        let frame = targetScreen.frame
        panel.setFrame(
            NSRect(
                x: frame.midX - contentSize.width / 2,
                y: frame.maxY - contentSize.height,
                width: contentSize.width,
                height: contentSize.height
            ),
            display: true,
            animate: panel.isVisible
        )
        panel.level = settings.alwaysOnTop
            ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            : .normal
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CUE"

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: CueLocalization.string(
                .sessionShow,
                fallback: "Show Cue",
                localization: settings.localizationIdentifier
            ),
            action: #selector(showFromStatusItem),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let cancelItem = NSMenuItem(
            title: CueLocalization.string(
                .sessionCancel,
                fallback: "Cancel Wait",
                localization: settings.localizationIdentifier
            ),
            action: #selector(cancel),
            keyEquivalent: ""
        )
        cancelItem.target = self
        menu.addItem(cancelItem)
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = settings.alwaysOnTop
            ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            : .normal
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.identifier = NSUserInterfaceItemIdentifier("cue.notch.panel")
    }

    private func finish(with outcome: CueOutcome) {
        guard !didFinish else { return }
        didFinish = true

        settingsWindowController?.close()
        removeStatusItem()
        window?.makeFirstResponder(nil)
        model.isExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.completion(outcome)
        }
    }

    private static func geometry(for screen: NSScreen) -> NotchScreenGeometry {
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)

        return NotchScreenGeometry(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            menuBarHeight: menuBarHeight,
            leftAuxiliaryWidth: screen.auxiliaryTopLeftArea?.width,
            rightAuxiliaryWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}
