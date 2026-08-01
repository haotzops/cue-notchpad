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
    private var lastRequestStartedAt: Date?
    private var lastRequestCancelledAt: Date?
    private let requestCooldown: TimeInterval = 1.5
    private let cancellationQuietPeriod: TimeInterval = 1.0
    var onUsage: ((Int, Int) -> Void)?

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
        textView.inlineCompletionTriggerShortcut = settings.inlineCompletionShortcut
        textView.onAcceptInlineCompletion = { [weak self] in self?.accept() ?? false }
        textView.onDismissInlineCompletion = { [weak self] in self?.dismiss() ?? false }
        textView.onRequestInlineCompletion = { [weak self] in self?.requestManually() ?? false }
    }

    func updateSettings(_ settings: CueSettings) {
        self.settings = settings
        textView?.inlineCompletionTriggerShortcut = settings.inlineCompletionShortcut
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

    private func requestManually() -> Bool {
        guard let settings, settings.inlineCompletionEnabled else { return false }
        scheduleIfEligible(force: true)
        return true
    }

    private func scheduleIfEligible(force: Bool = false) {
        guard let textView, let settings,
              settings.inlineCompletionEnabled,
              (force || settings.inlineCompletionTriggerMode != .manual),
              !textView.hasMarkedText(),
              textView.selectedRange().length == 0,
              !textView.string.isEmpty,
              (try? CueAPIKeyStore.loadDeepSeekAPIKey()) != nil
        else { return }

        let expectedRevision = revision
        debounceTask = Task { [weak self] in
            if !force {
                try? await Task.sleep(for: .milliseconds(Int(settings.inlineCompletionDelayMilliseconds)))
            }
            guard !Task.isCancelled, let self else { return }
            let now = Date.now
            let cooldown = max(
                self.lastRequestStartedAt?.addingTimeInterval(self.requestCooldown) ?? now,
                self.lastRequestCancelledAt?.addingTimeInterval(self.cancellationQuietPeriod) ?? now
            )
            if !force, cooldown > now {
                try? await Task.sleep(for: .seconds(cooldown.timeIntervalSince(now)))
            }
            guard !Task.isCancelled else { return }
            self.startRequest(expectedRevision: expectedRevision)
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
              let apiKey = try? CueAPIKeyStore.loadDeepSeekAPIKey(),
              let model = settings.inlineCompletionModel
        else { return }

        requestID += 1
        lastRequestStartedAt = .now
        CueUsageStore.shared.recordFIMRequest(model: model)
        let expectedRequestID = requestID
        let expectedSelection = textView.selectedRange()
        let request = InlineCompletionRequest(
            context: context,
            model: model,
            maxTokens: DeepSeekFIM.defaultMaximumTokens,
            stop: settings.inlineCompletionMaximumLines == 1 ? ["\n"] : nil
        )
        requestTask = Task { [weak self, provider] in
            do {
                var candidate = ""
                for try await event in await provider.streamCompletion(request, apiKey: apiKey) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .text(let delta):
                        candidate += delta
                        self?.receive(
                            candidate: candidate,
                            requestID: expectedRequestID,
                            revision: expectedRevision,
                            selection: expectedSelection
                        )
                    case .usage(let usage):
                        CueUsageStore.shared.recordFIM(
                            model: request.model,
                            inputTokens: usage.promptTokens,
                            outputTokens: usage.completionTokens
                        )
                        self?.onUsage?(usage.promptTokens, usage.completionTokens)
                    case .finished:
                        break
                    }
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

        let filtered = Self.filteredCandidate(candidate, maximumLines: settings.inlineCompletionMaximumLines)
        guard !filtered.isEmpty else { return }
        textView.inlineCompletion = CueInlineCompletion(start: selection.location, text: filtered)
    }

    private func receive(error: Error, requestID: Int) {
        guard requestID == self.requestID else { return }
        textView?.inlineCompletion = nil
        if let apiError = error as? DeepSeekFIMError {
            switch apiError {
            case .httpStatus(401):
                settings?.reportInlineCompletionFailure(.settingsAPIKeyRejected)
            case .httpStatus(402):
                settings?.reportInlineCompletionFailure(.settingsInlineCompletionUnavailable)
            case .httpStatus(429):
                settings?.reportInlineCompletionFailure(.settingsInlineCompletionRateLimited)
            default:
                settings?.reportInlineCompletionFailure(.settingsInlineCompletionUnavailable)
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
        if requestTask != nil { lastRequestCancelledAt = .now }
        requestTask?.cancel()
        debounceTask = nil
        requestTask = nil
        requestID += 1
        textView?.inlineCompletion = nil
    }

    private static func filteredCandidate(_ candidate: String, maximumLines: Int) -> String {
        let maximumCharacters = 256
        guard !candidate.trimmingCharacters(in: .controlCharacters).isEmpty else { return "" }
        let lines = candidate.split(separator: "\n", omittingEmptySubsequences: false)
        let limitedLines = lines.prefix(maximumLines)
        let limited = limitedLines.joined(separator: "\n")
        return String(limited.prefix(maximumCharacters))
    }
}
