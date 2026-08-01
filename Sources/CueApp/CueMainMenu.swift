import AppKit
import Combine
import CueCore

/// Installs standard responder-chain editing commands. Even though Cue is an
/// accessory app with no document window, AppKit resolves these key equivalents
/// to the focused NSTextView before it reaches custom shortcut handling.
final class CueMainMenu {
    private let settings: CueSettings
    private var observation: AnyCancellable?

    init(settings: CueSettings) {
        self.settings = settings
        install()
        observation = settings.$language.sink { [weak self] _ in self?.install() }
    }

    private func install() {
        let main = NSMenu()
        let appItem = NSMenuItem(title: "Cue", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Cue")
        appMenu.addItem(withTitle: localized(.menuQuitCue), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem(title: localized(.menuEdit), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: editItem.title)
        // AppKit exposes these responder-chain actions as `undo:` / `redo:`;
        // unlike NSText's cut/copy/paste actions, they are not Swift members
        // of NSText, so retain their canonical Objective-C selectors.
        edit.addItem(item(localized(.menuUndo), Selector(("undo:")), "z"))
        edit.addItem(item(localized(.menuRedo), Selector(("redo:")), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item(localized(.menuCut), #selector(NSText.cut(_:)), "x"))
        edit.addItem(item(localized(.menuCopy), #selector(NSText.copy(_:)), "c"))
        edit.addItem(item(localized(.menuPaste), #selector(NSText.paste(_:)), "v"))
        edit.addItem(item(localized(.menuSelectAll), #selector(NSText.selectAll(_:)), "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }

    private func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: settings.localizationIdentifier)
    }
}
