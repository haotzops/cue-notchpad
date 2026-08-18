import AppKit

final class CueBottomResizeHandle: NSView {
    var onResizeBegan: () -> Void = {}
    var onResize: (CGFloat) -> Void = { _ in }
    private var initialMouseY: CGFloat?

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseY = NSEvent.mouseLocation.y
        onResizeBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialMouseY else { return }
        onResize(initialMouseY - NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseY = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let indicator = NSRect(x: bounds.midX - 18, y: 4, width: 36, height: 2)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: indicator, xRadius: 1, yRadius: 1).fill()
    }
}
