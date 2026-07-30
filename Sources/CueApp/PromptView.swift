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

final class PromptModel: ObservableObject {
    private static let tokenQueue = DispatchQueue(
        label: "io.github.haotzops.cue-notchpad.token-counter",
        qos: .utility
    )

    @Published private(set) var text: String {
        didSet { scheduleTokenCount() }
    }
    @Published var tokenCount = 0
    @Published private(set) var editorContentHeight: CGFloat = 42

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

    func updateEditorContentHeight(_ value: CGFloat) {
        let rounded = ceil(value)
        guard abs(editorContentHeight - rounded) >= 1 else { return }
        editorContentHeight = rounded
    }

    private func scheduleTokenCount() {
        tokenRequest?.cancel()
        let snapshot = text
        guard !snapshot.isEmpty else {
            tokenRequest = nil
            tokenCount = 0
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
                Circle()
                    .fill(Color(red: 0.96, green: 0.69, blue: 0.25))
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.orange.opacity(0.65), radius: 4)

                Text(presentation.sourceName ?? "CUE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(sourceColor.opacity(0.85))

                Spacer()

                Text(localized(.promptLabel, "PROMPT"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.30))
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
            .padding(.top, 6)

            HStack(spacing: 7) {
                Text(characterCount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))

                Text("·")
                    .foregroundStyle(.white.opacity(0.18))

                Text(tokenCount)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))

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
                    Text(localized(.shortcutNext, "Next session"))
                        .foregroundStyle(.white.opacity(0.42))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.18))
                        .padding(.horizontal, 2)
                }

                keycap("⌘")
                keycap("↩")
                    .padding(.leading, -4)
                Text(localized(.actionDone, "done"))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .font(.system(size: 10, weight: .medium))
            .frame(height: 34)
            .padding(.horizontal, chromeHorizontalInset)
            .padding(.bottom, 9)
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
        CueLocalization.tokenCount(presentation.model.tokenCount, localization: localization)
    }

    private func localized(_ key: CueLocalizedKey, _ fallback: String) -> String {
        CueLocalization.string(key, fallback: fallback, localization: localization)
    }

    private var sessionEditor: some View {
        SessionEditor(
            model: presentation.model,
            settings: settings,
            placeholder: localized(.promptPlaceholder, "Write a prompt…"),
            onSubmit: onSubmit,
            onCancel: onCancel,
            onHide: onHide,
            onOpenSettings: onOpenSettings,
            onContentHeightChange: { presentation.model.updateEditorContentHeight($0) },
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
            .frame(minWidth: 20, minHeight: 18)
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
    let onContentHeightChange: (CGFloat) -> Void
    let onEditorReady: (NSTextView) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            PromptTextEditor(
                model: model,
                editorFont: settings.editorFont,
                overflowBehavior: settings.overflowBehavior,
                onSubmit: onSubmit,
                onCancel: onCancel,
                onHide: onHide,
                onOpenSettings: onOpenSettings,
                onContentHeightChange: onContentHeightChange,
                onReady: onEditorReady
            )

            if model.text.isEmpty {
                Text(placeholder)
                    .font(Font(settings.editorFont))
                    .foregroundStyle(.white.opacity(0.26))
                    .padding(.leading, 21)
                    .padding(.top, 13)
                    .allowsHitTesting(false)
            }
        }
    }
}
