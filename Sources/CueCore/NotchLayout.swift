import CoreGraphics

/// A single AppKit layout snapshot for the prompt editor. Both values must be
/// measured during the same layout pass: the scroll view's visible viewport
/// and the total height required to display all laid-out text (including text
/// insets and a trailing empty line).
public struct EditorLayoutMetrics: Equatable, Sendable {
    public let viewportHeight: CGFloat
    public let requiredContentHeight: CGFloat

    public init(viewportHeight: CGFloat, requiredContentHeight: CGFloat) {
        self.viewportHeight = viewportHeight
        self.requiredContentHeight = requiredContentHeight
    }
}

/// Calculates content-driven panel height without knowing any PromptView
/// chrome constants. The caller derives chrome from the live content view and
/// editor viewport, so changes to header, footer, or padding stay correct.
public enum EditorHeightPolicy {
    public static func panelHeight(
        basePanelHeight: CGFloat,
        currentPanelHeight: CGFloat,
        editorViewportHeight: CGFloat,
        requiredEditorContentHeight: CGFloat
    ) -> CGFloat {
        guard editorViewportHeight > 0 else { return basePanelHeight }
        let chromeHeight = max(0, currentPanelHeight - editorViewportHeight)
        return max(basePanelHeight, ceil(chromeHeight + requiredEditorContentHeight))
    }
}

/// Values used to make the panel merge with either a real MacBook notch or a
/// menu bar on a display without one. Keeping this calculation independent of
/// AppKit makes it deterministic and testable.
public struct NotchScreenGeometry: Equatable, Sendable {
    public var screenWidth: CGFloat
    public var safeAreaTop: CGFloat
    public var menuBarHeight: CGFloat
    public var leftAuxiliaryWidth: CGFloat?
    public var rightAuxiliaryWidth: CGFloat?

    public init(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        menuBarHeight: CGFloat,
        leftAuxiliaryWidth: CGFloat? = nil,
        rightAuxiliaryWidth: CGFloat? = nil
    ) {
        self.screenWidth = screenWidth
        self.safeAreaTop = safeAreaTop
        self.menuBarHeight = menuBarHeight
        self.leftAuxiliaryWidth = leftAuxiliaryWidth
        self.rightAuxiliaryWidth = rightAuxiliaryWidth
    }
}

public struct NotchLayout: Equatable, Sendable {
    public var closedSize: CGSize
    public var openSize: CGSize
    public var contentTopInset: CGFloat

    public init(
        screen: NotchScreenGeometry,
        preferredOpenWidth: CGFloat = 550,
        preferredOpenHeight: CGFloat = 150
    ) {
        let measuredNotchWidth: CGFloat? = {
            guard let left = screen.leftAuxiliaryWidth,
                  let right = screen.rightAuxiliaryWidth
            else { return nil }

            return screen.screenWidth - left - right + 4
        }()

        let topInset = max(28, screen.safeAreaTop, screen.menuBarHeight)
        let maximumOpenWidth = max(360, screen.screenWidth - 32)

        self.closedSize = CGSize(
            width: min(max(measuredNotchWidth ?? 185, 140), 260),
            height: topInset
        )
        self.openSize = CGSize(
            width: min(max(420, preferredOpenWidth), min(1_200, maximumOpenWidth)),
            height: min(max(130, preferredOpenHeight), 800)
        )
        self.contentTopInset = topInset
    }
}
