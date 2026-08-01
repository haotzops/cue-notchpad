import AppKit
import SwiftUI

/// AppKit owns an active editing transaction. SwiftUI receives only committed
/// document changes and never uses a view refresh to overwrite NSTextView.
struct PromptTextEditor: NSViewRepresentable {
    @ObservedObject var model: PromptModel
    @ObservedObject var settings: CueSettings
    let editorFont: NSFont
    let overflowBehavior: CueOverflowBehavior
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onHide: () -> Void
    let onOpenSettings: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    let onReady: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 13
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        scrollView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor

        let textView = CueTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onHide = onHide
        textView.onOpenSettings = onOpenSettings
        textView.promptExpansionShortcut = settings.promptExpansionShortcut
        textView.inlineCompletionAcceptShortcut = settings.inlineCompletionAcceptShortcut
        textView.onExpandPrompt = { [weak textView, weak model, weak settings] in
            guard let textView, let model, let settings,
                  !textView.string.isEmpty,
                  let key = try? CueAPIKeyStore.loadDeepSeekAPIKey(),
                  let selectedModel = settings.promptExpansionModel
            else { return }
            let original = textView.string
            Task { @MainActor in
                guard let expanded = try? await DeepSeekFIMCompletionProvider().expandPrompt(original, instruction: settings.promptExpansionInstruction, model: selectedModel, apiKey: key), textView.string == original else { return }
                textView.string = expanded
                textView.setSelectedRange(NSRange(location: expanded.utf16.count, length: 0))
                model.acceptCommittedText(expanded)
                textView.didChangeText()
            }
        }
        textView.string = model.text
        textView.font = editorFont
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.55),
            .foregroundColor: NSColor.white,
        ]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 13, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.identifier = NSUserInterfaceItemIdentifier("cue.prompt.editor")
        context.coordinator.inlineCompletionController.onUsage = { [weak model] input, output in
            model?.recordFIMUsage(input: input, output: output)
        }
        context.coordinator.inlineCompletionController.attach(to: textView, settings: settings)
        scrollView.documentView = textView
        applyOverflowBehavior(to: scrollView)
        context.coordinator.recordInstalledText(model.text)

        DispatchQueue.main.async {
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            context.coordinator.reportCommittedContentHeight(of: textView)
            onReady(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.inlineCompletionController.onUsage = { [weak model] input, output in
            model?.recordFIMUsage(input: input, output: output)
        }
        context.coordinator.inlineCompletionController.updateSettings(settings)
        (scrollView.documentView as? CueTextView)?.promptExpansionShortcut = settings.promptExpansionShortcut
        (scrollView.documentView as? CueTextView)?.inlineCompletionAcceptShortcut = settings.inlineCompletionAcceptShortcut
        applyOverflowBehavior(to: scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.applyExternalDocumentIfNeeded(to: textView)
        applyEditorFontIfNeeded(to: textView)
        DispatchQueue.main.async { context.coordinator.reportCommittedContentHeight(of: textView) }
    }

    private func applyOverflowBehavior(to scrollView: NSScrollView) {
        let scrollable = overflowBehavior == .scrollable
        scrollView.hasVerticalScroller = scrollable
        scrollView.autohidesScrollers = scrollable
    }

    private func applyEditorFontIfNeeded(to textView: NSTextView) {
        guard textView.font?.fontName != editorFont.fontName || textView.font?.pointSize != editorFont.pointSize else {
            return
        }

        textView.font = editorFont
        textView.typingAttributes[.font] = editorFont
        // Do not rewrite attributes while an input method owns marked text.
        guard !textView.hasMarkedText(), let textStorage = textView.textStorage else { return }
        textStorage.addAttribute(
            .font,
            value: editorFont,
            range: NSRange(location: 0, length: textView.string.utf16.count)
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextEditor
        private var installedText: String
        let inlineCompletionController = InlineCompletionController()

        init(parent: PromptTextEditor) {
            self.parent = parent
            self.installedText = parent.model.text
        }

        func recordInstalledText(_ text: String) {
            installedText = text
        }

        /// Applies an explicit model replacement only. Local text changes first
        /// update `installedText`, so SwiftUI redraws cannot feed them back into
        /// the editor or interrupt an NSTextInputClient composition.
        func applyExternalDocumentIfNeeded(to textView: NSTextView) {
            let desired = parent.model.text
            guard desired != installedText else { return }
            guard !textView.hasMarkedText() else { return }

            textView.string = desired
            textView.setSelectedRange(NSRange(location: desired.utf16.count, length: 0))
            installedText = desired
            reportCommittedContentHeight(of: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Marked text belongs exclusively to NSTextInputClient until the
            // input method commits or cancels it.
            guard !textView.hasMarkedText() else { return }
            commitDocument(from: textView)
            inlineCompletionController.textDidChange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            inlineCompletionController.selectionDidChange()
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.hasMarkedText() else { return }
            commitDocument(from: textView)
        }

        private func commitDocument(from textView: NSTextView) {
            let committedText = textView.string
            installedText = committedText
            parent.model.acceptCommittedText(committedText)
            reportCommittedContentHeight(of: textView)
        }

        /// Selection changes deliberately do not measure layout: they happen
        /// during IME composition and do not change the required content height.
        func reportCommittedContentHeight(of textView: NSTextView) {
            guard !textView.hasMarkedText(),
                  let container = textView.textContainer,
                  let manager = textView.layoutManager
            else { return }
            manager.ensureLayout(for: container)
            let usedHeight = manager.usedRect(for: container).height
            let oneLine = manager.defaultLineHeight(for: textView.font ?? .systemFont(ofSize: 16))
            parent.onContentHeightChange(ceil(max(usedHeight, oneLine) + textView.textContainerInset.height * 2))
        }
    }
}

struct CueInlineCompletion: Equatable {
    let start: Int
    let text: String
}

final class CueTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var inlineCompletionTriggerShortcut = CueShortcut.inlineCompletionDefault
    var inlineCompletionAcceptShortcut = CueShortcut(keyCode: 48, modifiers: 0)
    var onCancel: (() -> Void)?
    var onHide: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var promptExpansionShortcut = CueShortcut.promptExpansionDefault
    var onExpandPrompt: (() -> Void)?
    var onAcceptInlineCompletion: (() -> Bool)?
    var onRequestInlineCompletion: (() -> Bool)?
    var onDismissInlineCompletion: (() -> Bool)?
    var inlineCompletion: CueInlineCompletion? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let completion = inlineCompletion,
              let container = textContainer,
              let font = self.font,
              completion.start <= string.utf16.count
        else { return }

        let document = NSMutableAttributedString(attributedString: textStorage ?? NSAttributedString(string: string, attributes: [.font: font]))
        let candidate = NSAttributedString(
            string: completion.text,
            attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.36)]
        )
        document.insert(candidate, at: completion.start)
        let storage = NSTextStorage(attributedString: document)
        let manager = NSLayoutManager()
        let scratchContainer = NSTextContainer(size: container.containerSize)
        scratchContainer.lineFragmentPadding = container.lineFragmentPadding
        scratchContainer.widthTracksTextView = container.widthTracksTextView
        manager.addTextContainer(scratchContainer)
        storage.addLayoutManager(manager)
        let redrawRange = NSRange(location: completion.start, length: document.length - completion.start)
        manager.ensureLayout(for: scratchContainer)
        let glyphRange = manager.glyphRange(forCharacterRange: redrawRange, actualCharacterRange: nil)
        let startGlyph = manager.glyphIndexForCharacter(at: completion.start)
        let start = startGlyph < manager.numberOfGlyphs
            ? manager.location(forGlyphAt: startGlyph)
            : manager.extraLineFragmentRect.origin
        let redrawRect = NSRect(
            x: start.x + textContainerInset.width,
            y: start.y + textContainerInset.height,
            width: bounds.maxX - start.x,
            height: bounds.maxY - start.y
        )
        if let context = NSGraphicsContext.current {
            context.saveGraphicsState()
            context.compositingOperation = .clear
            redrawRect.fill()
            context.restoreGraphicsState()
        }
        manager.drawGlyphs(
            forGlyphRange: glyphRange,
            at: NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !hasMarkedText(), let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector? = switch characters {
        case "x": #selector(NSText.cut(_:))
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: nil
        }
        guard let action else { return super.performKeyEquivalent(with: event) }
        return tryToPerform(action, with: nil)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if event.keyCode == inlineCompletionAcceptShortcut.keyCode, flags == inlineCompletionAcceptShortcut.modifierFlags, !hasMarkedText(), onAcceptInlineCompletion?() == true { return }
        let triggerShortcutMatches = event.keyCode == inlineCompletionTriggerShortcut.keyCode && flags == inlineCompletionTriggerShortcut.modifierFlags
        if triggerShortcutMatches, !hasMarkedText(), onRequestInlineCompletion?() == true { return }
        let expansionShortcutMatches = event.keyCode == promptExpansionShortcut.keyCode && flags == promptExpansionShortcut.modifierFlags
        if expansionShortcutMatches, !hasMarkedText() { onExpandPrompt?(); return }
        if event.keyCode == 53, !hasMarkedText(), onDismissInlineCompletion?() == true { return }
        if event.keyCode == 43, flags == .command, !hasMarkedText() { onOpenSettings?(); return }
        if event.keyCode == 4, flags == .command, !hasMarkedText() { onHide?(); return }
        if isReturn, flags.contains(.command), !hasMarkedText() { onSubmit?(); return }
        if event.keyCode == 53, !hasMarkedText() { onCancel?(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard !hasMarkedText() else { super.cancelOperation(sender); return }
        onCancel?()
    }
}
