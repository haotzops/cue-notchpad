import AppKit
import CueCore
import Foundation

public final class CueApplicationCoordinator: NSObject, CueHostServerDelegate, NSApplicationDelegate {
    private struct Session {
        let id: UUID
        let callerName: String?
        let fd: Int32
        let model: PromptModel
    }
    private let server = CueHostServer()
    private let settings = CueSettings()
    private var shortcutController: CueGlobalShortcutController?
    private var mainMenu: CueMainMenu?
    private var controller: PromptWindowController?
    private var sessions: [Session] = []
    private var active = 0
    private var cueIsVisible = false

    public func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = self
        application.finishLaunching()
        mainMenu = CueMainMenu(settings: settings)
        server.delegate = self
        let shortcuts = CueGlobalShortcutController(settings: settings)
        shortcuts.onToggle = { [weak self] in self?.toggleCue() }
        shortcuts.onPrevious = { [weak self] in self?.move(-1) }
        shortcuts.onNext = { [weak self] in self?.move(1) }
        shortcutController = shortcuts
        do { try server.start() } catch { FileHandle.standardError.write(Data("cue-host: \(error)\n".utf8)); exit(EXIT_FAILURE) }
        application.run()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sessions.isEmpty ? .terminateNow : .terminateCancel
    }

    func hostServer(_ server: CueHostServer, received request: CueSessionRequest, fileDescriptor: Int32) {
        // The full IPC request may contain up to 8 MiB of initial text. Once
        // PromptModel owns the live document, retain only presentation metadata
        // instead of keeping the decoded request for the entire wait session.
        sessions.append(Session(
            id: request.id,
            callerName: request.callerName,
            fd: fileDescriptor,
            model: PromptModel(text: request.initialText)
        ))
        if sessions.count == 1 { active = 0 }
        else { active = sessions.count - 1 }
        cueIsVisible = true
        presentActive(direction: sessions.count > 1 ? 1 : 0)
    }

    private func presentActive(direction: Int = 0) {
        guard sessions.indices.contains(active) else { return }
        let session = sessions[active]
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let completion: (CueOutcome) -> Void = { [weak self] outcome in self?.completeActive(outcome) }
        if let controller {
            controller.configureSession(model: session.model, sessionID: session.id, sourceName: session.callerName, index: active, count: sessions.count, direction: direction, previous: { [weak self] in self?.move(-1) }, next: { [weak self] in self?.move(1) }, completion: completion)
        } else {
            controller = PromptWindowController(model: session.model, sessionID: session.id, settings: settings, screen: screen, sourceName: session.callerName, completion: completion)
            controller?.configureSession(model: session.model, sessionID: session.id, sourceName: session.callerName, index: active, count: sessions.count, direction: direction, previous: { [weak self] in self?.move(-1) }, next: { [weak self] in self?.move(1) }, completion: completion)
        }
    }

    private func toggleCue() {
        guard !sessions.isEmpty else { return }
        if controller?.window?.isVisible == true {
            cueIsVisible = false
            controller?.hideTemporarily()
        } else {
            cueIsVisible = true
            // Reconfigure after an Escape cancellation so the restored panel
            // never displays the session that was just discarded.
            presentActive(direction: 0)
        }
    }

    private func move(_ delta: Int) {
        guard sessions.count > 1 else { return }
        active = (active + delta + sessions.count) % sessions.count
        presentActive(direction: delta)
    }

    private func completeActive(_ outcome: CueOutcome) {
        guard sessions.indices.contains(active) else { return }
        let session = sessions.remove(at: active)
        switch outcome { case .submitted(let text): CueHostServer.reply(.submitted(text), to: session.fd); case .cancelled: CueHostServer.reply(.cancelled, to: session.fd) }
        if sessions.isEmpty {
            cueIsVisible = false
            controller?.close()
            controller = nil
            server.stop()
            // `stop(_:)` can leave NSApplication blocked in its next-event
            // cycle when called from this delayed completion callback. A normal
            // termination is now permitted because no waiting clients remain.
            NSApp.terminate(nil)
            return
        }
        active = min(active, sessions.count - 1)
        // Escape cancels only the current transaction and hides Cue. Remaining
        // callers keep waiting until the user explicitly restores Cue.
        if case .cancelled = outcome {
            cueIsVisible = false
            return
        }
        cueIsVisible = true
        presentActive(direction: 0)
    }
}
