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
    private let presentation: PromptPresentation
    private let settings: CueSettings
    private let targetScreen: NSScreen
    private let screenGeometry: NotchScreenGeometry
    private var completion: (CueOutcome) -> Void
    private weak var editor: NSTextView?
    private var settingsWindowController: SettingsWindowController?
    private var settingsObservation: AnyCancellable?
    private var contentHeightObservation: AnyCancellable?
    private var layoutUpdateWorkItem: DispatchWorkItem?
    private var didFinish = false

    init(
        model: PromptModel,
        sessionID: UUID,
        settings: CueSettings,
        screen: NSScreen,
        sourceName: String?,
        completion: @escaping (CueOutcome) -> Void
    ) {
        let screenGeometry = Self.geometry(for: screen)
        let initialLayout = NotchLayout(
            screen: screenGeometry,
            preferredOpenWidth: settings.normalizedWidth,
            preferredOpenHeight: settings.normalizedHeight
        )

        self.presentation = PromptPresentation(model: model, sourceName: sourceName, sessionID: sessionID)
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
                presentation: presentation,
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
            self?.scheduleLayoutUpdate()
        }
        observeContentHeight(for: model)
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
        presentation.isExpanded = true
        applySettings()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let editor = self.editor else { return }
            self.window?.makeFirstResponder(editor)
        }
    }

    var currentText: String { presentation.model.text }

    func configureSession(
        model: PromptModel,
        sessionID: UUID,
        sourceName: String?,
        index: Int,
        count: Int,
        direction: Int,
        previous: @escaping () -> Void,
        next: @escaping () -> Void,
        completion: @escaping (CueOutcome) -> Void
    ) {
        self.completion = completion
        self.didFinish = false
        observeContentHeight(for: model)
        presentation.switchSession(
            model: model,
            sourceName: sourceName,
            sessionID: sessionID,
            index: index,
            count: count,
            direction: direction,
            previous: previous,
            next: next
        )
        show()
    }

    func submit() {
        finish(with: .submitted(presentation.model.text))
    }

    @objc func cancel() {
        finish(with: .cancelled)
    }

    @objc func hideTemporarily() {
        guard !didFinish else { return }
        settingsWindowController?.close()
        presentation.isExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, !self.didFinish else { return }
            self.window?.orderOut(nil)
        }
    }

    @objc func showAfterHiding() {
        guard !didFinish else { return }
        presentation.isExpanded = true
        show()
    }

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                screen: targetScreen,
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

    /// TextKit can report several intermediate geometries while it lays out a
    /// wrapped line. Coalesce them, then let this controller be the sole owner
    /// of the panel frame. SwiftUI receives the resulting layout only to draw.
    private func scheduleLayoutUpdate() {
        layoutUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.applySettings() }
        layoutUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16), execute: workItem)
    }

    private func applySettings() {
        guard let panel = window else { return }
        let maximumHeight = min(CGFloat(800), targetScreen.visibleFrame.height - 8)
        let requestedHeight: CGFloat
        if settings.overflowBehavior == .growWithContent {
            requestedHeight = max(CGFloat(settings.normalizedHeight), presentation.model.editorContentHeight + 91)
        } else {
            requestedHeight = CGFloat(settings.normalizedHeight)
        }
        let openHeight = min(max(CGFloat(CueSettings.minimumWindowHeight), requestedHeight), maximumHeight)
        if abs(presentation.effectiveOpenHeight - openHeight) >= 0.5 {
            presentation.effectiveOpenHeight = openHeight
        }

        let targetLayout = NotchLayout(
            screen: screenGeometry,
            preferredOpenWidth: settings.normalizedWidth,
            preferredOpenHeight: openHeight
        )
        let contentSize = CGSize(
            width: targetLayout.openSize.width + 36,
            height: targetLayout.openSize.height + 24
        )
        let frame = targetScreen.frame
        let targetFrame = NSRect(
            x: frame.midX - contentSize.width / 2,
            y: frame.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        let currentFrame = panel.frame
        let frameChanged = abs(currentFrame.origin.x - targetFrame.origin.x) >= 0.5
            || abs(currentFrame.origin.y - targetFrame.origin.y) >= 0.5
            || abs(currentFrame.width - targetFrame.width) >= 0.5
            || abs(currentFrame.height - targetFrame.height) >= 0.5
        if frameChanged {
            // Repeated AppKit frame animations were the visible jump. The
            // coalesced final geometry is applied once with its top edge fixed.
            panel.setFrame(targetFrame, display: true, animate: false)
        }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
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
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
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
        window?.makeFirstResponder(nil)
        presentation.isExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self else { return }
            self.window?.orderOut(nil)
            self.completion(outcome)
        }
    }

    private func observeContentHeight(for model: PromptModel) {
        contentHeightObservation = model.$editorContentHeight
            .removeDuplicates()
            .sink { [weak self] _ in
                guard self?.settings.overflowBehavior == .growWithContent else { return }
                self?.scheduleLayoutUpdate()
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
