import AppKit
import CueCore
import Darwin
import Foundation

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private func wakeApplicationRunLoop() {
    guard let event = NSEvent.otherEvent(
        with: .applicationDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 0,
        data1: 0,
        data2: 0
    ) else { return }

    NSApp.postEvent(event, atStart: false)
}

let arguments: CueArguments

do {
    arguments = try CueArguments(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as LocalizedError {
    writeStandardError((error.errorDescription ?? "usage: cue --wait") + "\n")
    exit(EX_USAGE)
} catch {
    writeStandardError("usage: cue --wait\n")
    exit(EX_USAGE)
}

guard arguments.waitsForEditing else {
    writeStandardError("usage: cue --wait\n")
    exit(EX_USAGE)
}

let initialText: String
if isatty(STDIN_FILENO) == 0 {
    initialText = String(
        decoding: FileHandle.standardInput.readDataToEndOfFile(),
        as: UTF8.self
    )
} else {
    initialText = ""
}

let sessionLock: CueSessionLock
do {
    sessionLock = try CueSessionLock()
} catch {
    writeStandardError("cue: unable to acquire the editing session: \(error)\n")
    exit(EXIT_FAILURE)
}

let previousApplication = NSWorkspace.shared.frontmostApplication
let mouseLocation = NSEvent.mouseLocation
let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    ?? NSScreen.main
    ?? NSScreen.screens.first

guard let targetScreen else {
    writeStandardError(
        CueLocalization.string(
            .noDisplay,
            fallback: "cue: no display is available"
        ) + "\n"
    )
    exit(EXIT_FAILURE)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.finishLaunching()

let settings = CueSettings()
var outcome: CueOutcome?
let windowController = PromptWindowController(
    initialText: initialText,
    settings: settings,
    screen: targetScreen
) { result in
    outcome = result
    NSApp.stop(nil)
    wakeApplicationRunLoop()
}

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
let settingsMenuItem = NSMenuItem(
    title: CueLocalization.string(
        .settingsMenuTitle,
        fallback: "Settings…",
        localization: settings.localizationIdentifier
    ),
    action: #selector(PromptWindowController.openSettings),
    keyEquivalent: ","
)
settingsMenuItem.keyEquivalentModifierMask = [.command]
settingsMenuItem.target = windowController
appMenu.addItem(settingsMenuItem)

let hideMenuItem = NSMenuItem(
    title: "Hide Cue",
    action: #selector(PromptWindowController.hideTemporarily),
    keyEquivalent: "h"
)
hideMenuItem.keyEquivalentModifierMask = [.command]
hideMenuItem.target = windowController
appMenu.addItem(hideMenuItem)

appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)
application.mainMenu = mainMenu

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
interruptSource.setEventHandler { windowController.cancel() }
terminateSource.setEventHandler { windowController.cancel() }
interruptSource.resume()
terminateSource.resume()

windowController.show()
withExtendedLifetime(sessionLock) {
    application.run()
}

windowController.close()
if let previousApplication,
   previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier
{
    previousApplication.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
}

switch outcome {
case .submitted(let text):
    FileHandle.standardOutput.write(Data(text.utf8))
    exit(EXIT_SUCCESS)
case .cancelled:
    exit(130)
case nil:
    exit(EXIT_FAILURE)
}
