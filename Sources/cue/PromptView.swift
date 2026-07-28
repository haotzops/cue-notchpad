import AppKit
import CueCore
import SwiftUI

final class PromptModel: ObservableObject {
    @Published var text: String {
        didSet { scheduleTokenCount() }
    }
    @Published var tokenCount = 0
    @Published var isExpanded = false

    private var tokenWorkItem: DispatchWorkItem?

    init(text: String) {
        self.text = text
        scheduleTokenCount()
    }

    deinit {
        tokenWorkItem?.cancel()
    }

    private func scheduleTokenCount() {
        tokenWorkItem?.cancel()
        let snapshot = text
        guard !snapshot.isEmpty else {
            tokenCount = 0
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            let count = CueTokenCounter.shared.count(snapshot)
            DispatchQueue.main.async {
                guard let self, self.text == snapshot else { return }
                self.tokenCount = count
            }
        }
        tokenWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.12,
            execute: workItem
        )
    }
}

struct PromptView: View {
    @ObservedObject var model: PromptModel
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
            preferredOpenHeight: settings.normalizedHeight
        )
    }

    private var localization: String? { settings.localizationIdentifier }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(
                shoulderRadius: model.isExpanded ? 19 : 6,
                bottomRadius: model.isExpanded ? 24 : 14
            )
            .fill(Color.black)
            .overlay {
                NotchShape(
                    shoulderRadius: model.isExpanded ? 19 : 6,
                    bottomRadius: model.isExpanded ? 24 : 14
                )
                .stroke(Color.white.opacity(model.isExpanded ? 0.08 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(model.isExpanded ? 0.75 : 0), radius: 14, y: 7)

            editorContent
                .opacity(model.isExpanded ? 1 : 0)
                .scaleEffect(model.isExpanded ? 1 : 0.97, anchor: .top)
                .allowsHitTesting(model.isExpanded)
        }
        .frame(
            width: model.isExpanded ? layout.openSize.width : layout.closedSize.width,
            height: model.isExpanded ? layout.openSize.height : layout.closedSize.height,
            alignment: .top
        )
        .animation(.spring(response: 0.40, dampingFraction: 0.84), value: model.isExpanded)
        .frame(
            width: layout.openSize.width + 36,
            height: layout.openSize.height + 24,
            alignment: .top
        )
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                model.isExpanded = true
            }
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.96, green: 0.69, blue: 0.25))
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.orange.opacity(0.65), radius: 4)

                Text("CUE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.70))

                Spacer()

                Text(localized(.promptLabel, "PROMPT"))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.30))
            }
            .frame(height: layout.contentTopInset)
            .padding(.horizontal, chromeHorizontalInset)

            ZStack(alignment: .topLeading) {
                PromptTextEditor(
                    text: $model.text,
                    onSubmit: onSubmit,
                    onCancel: onCancel,
                    onHide: onHide,
                    onOpenSettings: onOpenSettings,
                    onReady: onEditorReady
                )

                if model.text.isEmpty {
                    Text(localized(.promptPlaceholder, "Write a prompt…"))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.26))
                        // NSTextView starts at 13 pt inset + 5 pt line-fragment
                        // padding. Keep the placeholder just clear of its caret.
                        .padding(.leading, 21)
                        .padding(.top, 13)
                        .allowsHitTesting(false)
                }
            }
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

                keycap("esc")
                Text(localized(.actionCancel, "cancel"))
                    .foregroundStyle(.white.opacity(0.34))

                Text("·")
                    .foregroundStyle(.white.opacity(0.18))
                    .padding(.horizontal, 2)

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

    private var characterCount: String {
        CueLocalization.characterCount(model.text.count, localization: localization)
    }

    private var tokenCount: String {
        CueLocalization.tokenCount(model.tokenCount, localization: localization)
    }

    private func localized(_ key: CueLocalizedKey, _ fallback: String) -> String {
        CueLocalization.string(key, fallback: fallback, localization: localization)
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
