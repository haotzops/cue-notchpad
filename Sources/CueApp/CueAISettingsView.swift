import CueCore
import SwiftUI

struct CueAISettingsView: View {
    @ObservedObject var settings: CueSettings
    @Binding var deepSeekAPIKey: String

    var body: some View {
        modelAPIConfiguration
        inlineCompletion
        promptPolish
    }

    private var modelAPIConfiguration: some View {
        Section(settings.localized(.settingsModelAPIConfiguration)) {
            SecureField(settings.localized(.settingsDeepSeekAPIKey), text: $deepSeekAPIKey)
            HStack {
                Button(settings.localized(.settingsSaveAPIKey)) {
                    settings.saveDeepSeekAPIKey(deepSeekAPIKey)
                    deepSeekAPIKey = ""
                }
                .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(settings.localized(.settingsRefreshModels)) {
                    settings.refreshDeepSeekModelsIfPossible()
                }
                .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)

                Button(settings.localized(.settingsRemoveAPIKey)) {
                    settings.removeDeepSeekAPIKey()
                }
                .disabled(!settings.inlineCompletionKeyConfigured)
            }
            Text(settings.inlineCompletionKeyConfigured
                ? settings.localized(.settingsAPIKeyConfigured)
                : settings.localized(.settingsAPIKeyNotConfigured)
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let status = settings.inlineCompletionStatus {
                HStack(spacing: 6) {
                    if settings.isTestingInlineCompletionConnection {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(status.message)
                }
                .font(.footnote)
                .foregroundStyle(status.style == .error ? Color.red : Color.secondary)
            }
        }
    }

    private var inlineCompletion: some View {
        Section(settings.localized(.settingsFIM)) {
            Toggle(settings.localized(.settingsInlineCompletion), isOn: $settings.inlineCompletionEnabled)
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.localized(.settingsInlineCompletionHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Picker(
                        settings.localized(.settingsInlineCompletionModel),
                        selection: $settings.inlineCompletionModel
                    ) {
                        Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                        ForEach(settings.inlineCompletionModels, id: \.self) { model in
                            Text(model).tag(Optional(model))
                        }
                    }
                    .disabled(!settings.inlineCompletionKeyConfigured || settings.isLoadingInlineCompletionModels)

                    if settings.isLoadingInlineCompletionModels {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button(settings.localized(.settingsTestModel)) {
                        settings.testDeepSeekAPIKey()
                    }
                    .disabled(
                        !settings.inlineCompletionKeyConfigured
                            || settings.inlineCompletionModel == nil
                            || settings.isTestingInlineCompletionConnection
                    )
                }

                Picker(settings.localized(.settingsTriggerMode), selection: $settings.inlineCompletionTriggerMode) {
                    Text(settings.localized(.settingsTriggerAutomatic)).tag(InlineCompletionTriggerMode.automatic)
                    Text(settings.localized(.settingsTriggerManual)).tag(InlineCompletionTriggerMode.manual)
                }

                if settings.inlineCompletionTriggerMode != .manual {
                    HStack {
                        Text(settings.localized(.settingsTriggerDelay))
                        TextField(
                            settings.localized(.unitMilliseconds),
                            value: $settings.inlineCompletionDelayMilliseconds,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 72)
                        Text(settings.localized(.unitMilliseconds))
                    }
                }

                HStack(spacing: 8) {
                    Text(settings.localized(.settingsMaximumLines))
                    Spacer()
                    Text("\(settings.inlineCompletionMaximumLines)")
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                    Stepper("", value: $settings.inlineCompletionMaximumLines, in: 1 ... 100)
                        .labelsHidden()
                }
            }
        }
    }

    private var promptPolish: some View {
        Section(settings.localized(.settingsAIPolish)) {
            Picker(settings.localized(.settingsInlineCompletionModel), selection: $settings.promptExpansionModel) {
                Text(settings.localized(.settingsChooseModel)).tag(String?.none)
                ForEach(settings.inlineCompletionModels, id: \.self) {
                    Text($0).tag(Optional($0))
                }
            }
            .disabled(!settings.inlineCompletionKeyConfigured)

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.localized(.settingsPolishPrompt))
                TextEditor(text: $settings.promptExpansionInstruction)
                    .font(.body)
                    .frame(minHeight: 72)
                Text(settings.localized(.settingsPolishPromptHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
