import AppKit
import Combine
import CueCore
import SwiftUI

private final class TokenCountCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum PromptChromeLayout {
    static let footerHeight: CGFloat = 34
    static let footerBottomPadding: CGFloat = 9
}

final class PromptModel: ObservableObject {
    private static let tokenQueue = DispatchQueue(
        label: "io.github.haotzops.cue-notchpad.token-counter",
        qos: .utility
    )

    @Published private(set) var text: String {
        didSet { scheduleTokenCount() }
    }
    @Published var tokenCount: Int? = 0
    @Published private(set) var fimInputTokens = 0
    @Published private(set) var fimOutputTokens = 0
    /// Published atomically from one AppKit layout pass. Keeping the viewport
    /// and required text height together prevents panel resizing from combining
    /// values from different TextKit/SwiftUI layout passes.
    @Published private(set) var editorLayoutMetrics: EditorLayoutMetrics?

    private var tokenRequest: TokenCountCancellation?

    init(text: String) {
        self.text = text
        scheduleTokenCount()
    }

    deinit {
        tokenRequest?.cancel()
    }

    /// The editor calls this only after NSTextInputClient has committed a text
    /// transaction. Keeping it explicit prevents SwiftUI refreshes from
    /// becoming a second, competing document editor.
    func acceptCommittedText(_ value: String) {
        guard text != value else { return }
        text = value
    }

    func recordFIMUsage(input: Int, output: Int) {
        fimInputTokens += input
        fimOutputTokens += output
    }

    func updateEditorLayoutMetrics(_ metrics: EditorLayoutMetrics) {
        let rounded = EditorLayoutMetrics(
            viewportHeight: ceil(metrics.viewportHeight),
            requiredContentHeight: ceil(metrics.requiredContentHeight)
        )
        guard editorLayoutMetrics != rounded else { return }
        editorLayoutMetrics = rounded
    }

    private func scheduleTokenCount() {
        tokenRequest?.cancel()
        let snapshot = text
        guard !snapshot.isEmpty else {
            tokenRequest = nil
            tokenCount = 0
            return
        }
        guard CueTokenCounter.shared.isAvailable else {
            tokenCount = nil
            return
        }

        let request = TokenCountCancellation()
        tokenRequest = request
        Self.tokenQueue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard !request.isCancelled,
                  let count = CueTokenCounter.shared.count(
                    snapshot,
                    cancellingWhen: { request.isCancelled }
                  )
            else { return }
            DispatchQueue.main.async {
                guard let self,
                      self.tokenRequest === request,
                      self.text == snapshot
                else { return }
                self.tokenRequest = nil
                self.tokenCount = count
            }
        }
    }
}

final class PromptPresentation: ObservableObject {
    @Published var model: PromptModel
    @Published var sourceName: String?
    @Published var sessionIndex = 0
    @Published var sessionCount = 1
    @Published var sessionID: UUID
    @Published var transitionDirection = 1
    @Published var isExpanded = false
    @Published var effectiveOpenHeight: CGFloat = 150
    var previousSession: () -> Void = {}
    var nextSession: () -> Void = {}

    private var modelObservation: AnyCancellable?

    init(model: PromptModel, sourceName: String?, sessionID: UUID) {
        self.model = model
        self.sourceName = sourceName
        self.sessionID = sessionID
        observeModel()
    }

    func switchSession(
        model: PromptModel,
        sourceName: String?,
        sessionID: UUID,
        index: Int,
        count: Int,
        direction: Int,
        previous: @escaping () -> Void,
        next: @escaping () -> Void
    ) {
        transitionDirection = direction == 0 ? transitionDirection : direction
        previousSession = previous
        nextSession = next
        sessionIndex = index
        sessionCount = count
        self.sourceName = sourceName
        guard self.sessionID != sessionID else {
            self.model = model
            observeModel()
            return
        }
        withAnimation(.easeInOut(duration: 0.24)) {
            self.model = model
            self.sessionID = sessionID
        }
        observeModel()
    }

    private func observeModel() {
        modelObservation = model.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

struct PromptView: View {
    @ObservedObject var presentation: PromptPresentation
    @ObservedObject var settings: CueSettings
    let screenGeometry: NotchScreenGeometry
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onHide: () -> Void
    let onOpenSettings: () -> Void
    let onEditorReady: (NSTextView) -> Void

    /// The notch shoulder occupies 19 pt horizontally while expanded. Adding
    /// 26 pt of visual breathing room matches the footer's bottom clearance.
    private let chromeHorizontalInset: CGFloat = 45

    private var layout: NotchLayout {
        NotchLayout(
            screen: screenGeometry,
            preferredOpenWidth: settings.normalizedWidth,
            preferredOpenHeight: presentation.effectiveOpenHeight
        )
    }

    private var localization: String? { settings.localizationIdentifier }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(
                shoulderRadius: presentation.isExpanded ? 19 : 6,
                bottomRadius: presentation.isExpanded ? 24 : 14
            )
            .fill(Color.black)
            .overlay {
                NotchShape(
                    shoulderRadius: presentation.isExpanded ? 19 : 6,
                    bottomRadius: presentation.isExpanded ? 24 : 14
                )
                .stroke(Color.white.opacity(presentation.isExpanded ? 0.08 : 0), lineWidth: 1)
            }

            if presentation.isExpanded {
                editorContent
                    // Keep the expanded layout stable while the notch frame grows.
                    // Otherwise trailing Spacer content is repeatedly laid out at
                    // intermediate widths and appears to slide in from the side.
                    .frame(
                        width: layout.openSize.width,
                        height: layout.openSize.height,
                        alignment: .top
                    )
                    .transition(
                        .scale(scale: 0.8, anchor: .top)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(
            width: presentation.isExpanded ? layout.openSize.width : layout.closedSize.width,
            height: presentation.isExpanded ? layout.openSize.height : layout.closedSize.height,
            alignment: .top
        )
        .clipped()
        .frame(
            width: layout.openSize.width,
            height: layout.openSize.height,
            alignment: .top
        )
        .preferredColorScheme(.dark)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CueBrandMark()

                if let sourceName = presentation.sourceName {
                    Text("· \(sourceName)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(sourceColor.opacity(0.75))
                }

                Spacer()

                Text(localized(.promptLabel))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(height: layout.contentTopInset)
            .padding(.horizontal, chromeHorizontalInset)

            ZStack {
                sessionEditor
                    .id(presentation.sessionID)
                    .transition(sessionTransition)
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 27)

            HStack(spacing: 7) {
                Text(characterCount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))

                Text("·")
                    .foregroundStyle(.white.opacity(0.18))

                Text(tokenCount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))

                if settings.inlineCompletionEnabled {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.18))

                    Text(String(
                        format: CueLocalization.string(.fimUsage,  localization: settings.localizationIdentifier),
                        Int64(presentation.model.fimInputTokens),
                        Int64(presentation.model.fimOutputTokens)
                    ))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.28))
                }

                Spacer()

                if presentation.sessionCount > 1 {
                    Button(action: presentation.previousSession) { Text("‹") }.buttonStyle(.plain)
                    Text("\(presentation.sessionIndex + 1) / \(presentation.sessionCount)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                    Button(action: presentation.nextSession) { Text("›") }.buttonStyle(.plain)
                }

                Spacer()

                if presentation.sessionCount > 1 {
                    shortcutKeycaps(settings.nextShortcut)
                    Text(localized(.shortcutNext))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.18))
                        .padding(.horizontal, 2)
                }

                keycap("⌘")
                keycap("↩")
                    .padding(.leading, -4)
                Text(localized(.actionDone))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .font(.system(size: 10, weight: .medium))
            .frame(height: PromptChromeLayout.footerHeight)
            .padding(.horizontal, chromeHorizontalInset)
            .padding(.bottom, PromptChromeLayout.footerBottomPadding)
        }
    }

    private var sourceColor: Color {
        switch (presentation.sourceName ?? "").lowercased() {
        case let name where name.contains("pi"): return Color(red: 0.96, green: 0.69, blue: 0.25)
        case let name where name.contains("codex"): return Color(red: 0.38, green: 0.71, blue: 1.0)
        case let name where name.contains("opencode"): return Color(red: 0.56, green: 0.86, blue: 0.48)
        default: return .white
        }
    }

    private var characterCount: String {
        CueLocalization.characterCount(presentation.model.text.count, localization: localization)
    }

    private var tokenCount: String {
        guard let count = presentation.model.tokenCount else {
            return localized(.tokenUnavailable)
        }
        return CueLocalization.tokenCount(count, localization: localization)
    }

    private func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: localization)
    }

    private var sessionEditor: some View {
        SessionEditor(
            model: presentation.model,
            settings: settings,
            placeholder: localized(.promptPlaceholder),
            onSubmit: onSubmit,
            onCancel: onCancel,
            onHide: onHide,
            onOpenSettings: onOpenSettings,
            onLayoutMetricsChange: presentation.model.updateEditorLayoutMetrics,
            onEditorReady: onEditorReady
        )
    }

    private var sessionTransition: AnyTransition {
        let forward = presentation.transitionDirection >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func shortcutKeycaps(_ shortcut: CueShortcut) -> some View {
        HStack(spacing: 2) {
            ForEach(shortcut.keycapLabels, id: \.self) { keycap($0) }
        }
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct SessionEditor: View {
    @ObservedObject var model: PromptModel
    @ObservedObject var settings: CueSettings
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onHide: () -> Void
    let onOpenSettings: () -> Void
    let onLayoutMetricsChange: (EditorLayoutMetrics) -> Void
    let onEditorReady: (NSTextView) -> Void

    var body: some View {
        PromptTextEditor(
            model: model,
            settings: settings,
            editorFont: settings.editorFont,
            placeholder: placeholder,
            overflowBehavior: settings.overflowBehavior,
            onSubmit: onSubmit,
            onCancel: onCancel,
            onHide: onHide,
            onOpenSettings: onOpenSettings,
            onAdjustEditorFontSize: settings.adjustEditorFontSize,
            onLayoutMetricsChange: onLayoutMetricsChange,
            onReady: onEditorReady
        )
    }
}
