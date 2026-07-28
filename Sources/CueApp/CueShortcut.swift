import AppKit
import Carbon
import Combine
import SwiftUI

struct CueShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt

    static let toggleDefault = CueShortcut(keyCode: 8, modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue)
    static let previousDefault = CueShortcut(keyCode: 123, modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue)
    static let nextDefault = CueShortcut(keyCode: 124, modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue)

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    var displayString: String {
        var result = ""
        let flags = modifierFlags
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    var keycapLabels: [String] {
        var labels: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { labels.append("⌃") }
        if flags.contains(.option) { labels.append("⌥") }
        if flags.contains(.shift) { labels.append("⇧") }
        if flags.contains(.command) { labels.append("⌘") }
        labels.append(Self.keyName(keyCode))
        return labels
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyName(_ code: UInt16) -> String {
        switch code {
        case 36, 76: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 119: return "↘"
        case 121: return "⇟"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return "#\(code)" }
            let data = unsafeBitCast(pointer, to: CFData.self) as Data
            return data.withUnsafeBytes { bytes -> String in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return "#\(code)" }
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 4)
                var length = 0
                let status = characters.withUnsafeMutableBufferPointer { buffer in
                    UCKeyTranslate(
                        layout, code, UInt16(kUCKeyActionDisplay), 0,
                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState, buffer.count, &length, buffer.baseAddress
                    )
                }
                guard status == noErr, length > 0 else { return "#\(code)" }
                return String(utf16CodeUnits: characters, count: Int(length)).uppercased()
            }
        }
    }
}

private extension Notification.Name {
    static let cueShortcutRecordingBegan = Notification.Name("CueShortcutRecordingBegan")
    static let cueShortcutRecordingEnded = Notification.Name("CueShortcutRecordingEnded")
}

final class CueGlobalShortcutController {
    private var hotKeys: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var observations = Set<AnyCancellable>()
    private var latestShortcuts: [CueShortcut] = []
    private var isRecording = false
    var onToggle: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    init(settings: CueSettings) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard status == noErr else { return status }
            let owner = Unmanaged<CueGlobalShortcutController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch identifier.id {
                case 1: owner.onToggle()
                case 2: owner.onPrevious()
                case 3: owner.onNext()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, pointer, &handler)

        Publishers.CombineLatest3(
            settings.$toggleShortcut,
            settings.$previousShortcut,
            settings.$nextShortcut
        ).sink { [weak self] toggle, previous, next in
            guard let self else { return }
            latestShortcuts = [toggle, previous, next]
            if !isRecording { register(latestShortcuts) }
        }
        .store(in: &observations)

        NotificationCenter.default.publisher(for: .cueShortcutRecordingBegan)
            .sink { [weak self] _ in
                self?.isRecording = true
                self?.unregisterAll()
            }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: .cueShortcutRecordingEnded)
            .sink { [weak self] _ in
                guard let self else { return }
                isRecording = false
                register(latestShortcuts)
            }
            .store(in: &observations)
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    private func register(_ shortcuts: [CueShortcut]) {
        unregisterAll()
        for (offset, shortcut) in shortcuts.enumerated() {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: OSType(0x43554521), id: UInt32(offset + 1)) // CUE!
            RegisterEventHotKey(
                UInt32(shortcut.keyCode), shortcut.carbonModifiers, identifier,
                GetApplicationEventTarget(), 0, &reference
            )
            hotKeys.append(reference)
        }
    }

    private func unregisterAll() {
        hotKeys.forEach { reference in
            if let reference { UnregisterEventHotKey(reference) }
        }
        hotKeys.removeAll()
    }
}

struct CueShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: CueShortcut
    let recordingPrompt: String

    func makeNSView(context: Context) -> CueShortcutRecorderButton {
        let button = CueShortcutRecorderButton()
        button.onChange = { shortcut = $0 }
        button.recordingPrompt = recordingPrompt
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: CueShortcutRecorderButton, context: Context) {
        button.onChange = { shortcut = $0 }
        button.recordingPrompt = recordingPrompt
        if !button.isRecording { button.shortcut = shortcut }
    }
}

final class CueShortcutRecorderButton: NSButton {
    var onChange: (CueShortcut) -> Void = { _ in }
    var shortcut: CueShortcut = .toggleDefault { didSet { refreshTitle() } }
    var recordingPrompt = "Type shortcut…"
    fileprivate var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        NotificationCenter.default.post(name: .cueShortcutRecordingBegan, object: nil)
        title = recordingPrompt
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == 53 {
            endRecording()
            window?.makeFirstResponder(nil)
            return
        }
        let allowed = NSEvent.ModifierFlags.command.union(.option).union(.control).union(.shift)
        let modifiers = event.modifierFlags.intersection(allowed)
        guard !modifiers.isEmpty else { NSSound.beep(); return }
        shortcut = CueShortcut(keyCode: event.keyCode, modifiers: modifiers.rawValue)
        onChange(shortcut)
        endRecording()
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        refreshTitle()
        NotificationCenter.default.post(name: .cueShortcutRecordingEnded, object: nil)
    }

    private func refreshTitle() {
        title = shortcut.displayString
        sizeToFit()
        frame.size.width = max(frame.width + 14, 88)
    }
}
