import AppKit
import CueCore
import Foundation

@MainActor
final class InlineCompletionController {
    private let provider: any InlineCompletionProvider
    private weak var textView: CueTextView?
    private weak var settings: CueSettings?
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var revision = 0
    private var requestID = 0

    init(provider: any InlineCompletionProvider = DeepSeekFIMCompletionProvider()) {
        self.provider = provider
    }

    deinit {
        debounceTask?.cancel()
        requestTask?.cancel()
    }

    func attach(to textView: CueTextView, settings: CueSettings) {
        self.textView = textView
        self.settings = settings
        textView.onAcceptInlineCompletion = { [weak self] in self?.accept() ?? false }
        textView.onDismissInlineCompletion = { [weak self] in self?.dismiss() ?? false }
    }

    func updateSettings(_ settings: CueSettings) {
        self.settings = settings
        if !settings.inlineCompletionEnabled { invalidate() }
    }

    func textDidChange() {
        revision += 1
        invalidate(clearRevision: false)
        scheduleIfEligible()
    }

    func selectionDidChange() {
        invalidate()
    }

    func editorWillDisappear() {
        invalidate()
    }

    private func scheduleIfEligible() {
        guard let textView, let settings,
              settings.inlineCompletionEnabled,
              !textView.hasMarkedText(),
              textView.selectedRange().length == 0,
              !textView.string.isEmpty,
              (try? CueKeychain.loadDeepSeekAPIKey()) != nil
        else { return }

        let expectedRevision = revision
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.startRequest(expectedRevision: expectedRevision)
        }
    }

    private func startRequest(expectedRevision: Int) {
        guard expectedRevision == revision,
              let textView, let settings,
              settings.inlineCompletionEnabled,
              !textView.hasMarkedText(),
              let context = InlineCompletionContextBuilder.make(
                document: textView.string,
                selection: textView.selectedRange()
              ),
              !context.prefix.isEmpty,
              let apiKey = try? CueKeychain.loadDeepSeekAPIKey()
        else { return }

        requestID += 1
        let expectedRequestID = requestID
        let expectedSelection = textView.selectedRange()
        let request = InlineCompletionRequest(
            context: context,
            model: "deepseek-v4-pro",
            maxTokens: 64
        )
        requestTask = Task { [weak self, provider] in
            do {
                var candidate = ""
                for try await delta in await provider.streamCompletion(request, apiKey: apiKey) {
                    guard !Task.isCancelled else { return }
                    candidate += delta
                    self?.receive(
                        candidate: candidate,
                        requestID: expectedRequestID,
                        revision: expectedRevision,
                        selection: expectedSelection
                    )
                }
            } catch is CancellationError {
                // A newer edit or session change superseded this request.
            } catch {
                self?.receive(error: error, requestID: expectedRequestID)
            }
        }
    }

    private func receive(candidate: String, requestID: Int, revision: Int, selection: NSRange) {
        guard requestID == self.requestID,
              revision == self.revision,
              let textView,
              textView.selectedRange() == selection,
              !textView.hasMarkedText(),
              let settings, settings.inlineCompletionEnabled
        else { return }

        let filtered = Self.filteredCandidate(candidate)
        guard !filtered.isEmpty else { return }
        textView.inlineCompletion = CueInlineCompletion(start: selection.location, text: filtered)
    }

    private func receive(error: Error, requestID: Int) {
        guard requestID == self.requestID else { return }
        textView?.inlineCompletion = nil
        if let apiError = error as? DeepSeekFIMError {
            switch apiError {
            case .httpStatus(401):
                settings?.inlineCompletionStatus = settings?.localized(
                    .settingsAPIKeyRejected,
                    fallback: "DeepSeek API key was rejected."
                )
            case .httpStatus(402):
                settings?.inlineCompletionStatus = settings?.localized(
                    .settingsInlineCompletionUnavailable,
                    fallback: "DeepSeek account balance is insufficient."
                )
            case .httpStatus(429):
                settings?.inlineCompletionStatus = settings?.localized(
                    .settingsInlineCompletionRateLimited,
                    fallback: "DeepSeek is rate limiting completion requests."
                )
            default:
                settings?.inlineCompletionStatus = settings?.localized(
                    .settingsInlineCompletionUnavailable,
                    fallback: "Inline completion is temporarily unavailable."
                )
            }
        }
    }

    private func accept() -> Bool {
        guard let textView, let completion = textView.inlineCompletion,
              textView.selectedRange().location == completion.start,
              !textView.hasMarkedText()
        else { return false }

        invalidate()
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: completion.text) else { return true }
        textView.textStorage?.replaceCharacters(in: range, with: completion.text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + completion.text.utf16.count, length: 0))
        return true
    }

    private func dismiss() -> Bool {
        guard textView?.inlineCompletion != nil else { return false }
        invalidate()
        return true
    }

    private func invalidate(clearRevision: Bool = true) {
        if clearRevision { revision += 1 }
        debounceTask?.cancel()
        requestTask?.cancel()
        debounceTask = nil
        requestTask = nil
        requestID += 1
        textView?.inlineCompletion = nil
    }

    private static func filteredCandidate(_ candidate: String) -> String {
        let maximumCharacters = 256
        let maximumLines = 3
        guard !candidate.trimmingCharacters(in: .controlCharacters).isEmpty else { return "" }
        let lines = candidate.split(separator: "\n", omittingEmptySubsequences: false)
        let limitedLines = lines.prefix(maximumLines)
        let limited = limitedLines.joined(separator: "\n")
        return String(limited.prefix(maximumCharacters))
    }
}
