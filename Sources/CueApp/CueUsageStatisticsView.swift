import CueCore
import SwiftUI

private enum CueUsagePeriod: String, CaseIterable, Identifiable {
    case day, week, month, custom

    var id: String { rawValue }
}

private struct CueUsageSelection {
    let start: Date
    let end: Date
}

struct CueUsageStatisticsView: View {
    @ObservedObject var settings: CueSettings
    @ObservedObject var usage = CueUsageStore.shared
    @State private var period: CueUsagePeriod = .week
    @State private var customStart = Calendar.current.date(
        byAdding: .day,
        value: -29,
        to: Calendar.current.startOfDay(for: .now)
    ) ?? .now
    @State private var customEnd = Date.now
    @State private var isConfirmingUsageClear = false

    private var selection: CueUsageSelection {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        switch period {
        case .day:
            return CueUsageSelection(start: today, end: .now)
        case .week:
            return CueUsageSelection(
                start: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                end: .now
            )
        case .month:
            return CueUsageSelection(
                start: calendar.date(byAdding: .day, value: -29, to: today) ?? today,
                end: .now
            )
        case .custom:
            let firstDay = calendar.startOfDay(for: min(customStart, customEnd))
            let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
            let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return CueUsageSelection(start: firstDay, end: min(.now, endOfLastDay))
        }
    }

    private var activity: CueUsageActivity {
        usage.activity(from: selection.start, through: selection.end)
    }

    var body: some View {
        let selectedActivity = activity
        VStack(alignment: .leading, spacing: 16) {
            periodControls
            summaryCards(selectedActivity)
            activitySection(selectedActivity)
            privacyNote
            clearAction
        }
        .padding(.vertical, 4)
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $period) {
                Text(localized(.usageToday)).tag(CueUsagePeriod.day)
                Text(localized(.usageWeek)).tag(CueUsagePeriod.week)
                Text(localized(.usageMonth)).tag(CueUsagePeriod.month)
                Text(localized(.usageCustom)).tag(CueUsagePeriod.custom)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            if period == .custom {
                HStack(spacing: 12) {
                    DatePicker(
                        localized(.usageStart),
                        selection: $customStart,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    DatePicker(
                        localized(.usageEnd),
                        selection: $customEnd,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
                .datePickerStyle(.compact)
            }
        }
    }

    @ViewBuilder
    private func summaryCards(_ activity: CueUsageActivity) -> some View {
        HStack(spacing: 10) {
            UsageMetricCard(
                title: localized(.usageCueOpens),
                value: "\(activity.totalOpens)",
                systemImage: "rectangle.and.pencil.and.ellipsis"
            )
            if activity.dayCount == 1 {
                UsageMetricCard(
                    title: localized(.usageFirstOpen),
                    value: time(activity.firstOpen),
                    systemImage: "sunrise.fill"
                )
                UsageMetricCard(
                    title: localized(.usageLatestOpen),
                    value: time(activity.latestOpen),
                    systemImage: "clock.fill"
                )
            } else {
                UsageMetricCard(
                    title: localized(.usageActiveDays),
                    value: "\(activity.activeDays)",
                    systemImage: "calendar"
                )
                UsageMetricCard(
                    title: localized(.usageDailyAverage),
                    value: activity.averageOpens.formatted(.number.precision(.fractionLength(1))),
                    systemImage: "chart.bar.fill"
                )
            }
        }
    }

    private func activitySection(_ activity: CueUsageActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized(.usageActivity))
                    .font(.headline)
                Spacer()
                Text(activity.rangeLabel(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activity.totalOpens == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(localized(.usageNoActivity))
                        .font(.callout.weight(.medium))
                    Text(localized(.usageNoActivityHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            } else {
                UsageActivityChart(activity: activity, locale: locale)
                    .frame(height: 128)
            }
        }
    }

    private var privacyNote: some View {
        Label(localized(.usagePrivacyHint), systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var clearAction: some View {
        HStack {
            Text(localized(.settingsClearUsageDetail))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(localized(.settingsClearUsage), role: .destructive) {
                isConfirmingUsageClear = true
            }
            .disabled(usage.cueOpenCount == 0 && usage.records.isEmpty)
        }
        .padding(.top, 2)
        .confirmationDialog(
            localized(.settingsClearUsageConfirmation),
            isPresented: $isConfirmingUsageClear,
            titleVisibility: .visible
        ) {
            Button(localized(.settingsClearUsage), role: .destructive) {
                usage.clearUsageStatistics()
            }
            Button(localized(.settingsCancel), role: .cancel) {}
        }
    }

    private var locale: Locale {
        settings.localizationIdentifier.map(Locale.init(identifier:)) ?? .current
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    private func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: settings.localizationIdentifier)
    }
}

private struct UsageMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct UsageActivityChart: View {
    let activity: CueUsageActivity
    let locale: Locale

    private var maximum: Int {
        max(activity.buckets.map(\.opens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: activity.buckets.count > 20 ? 3 : 6) {
                    ForEach(activity.buckets) { bucket in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucket.opens == 0 ? Color.secondary.opacity(0.14) : Color.accentColor)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 3,
                                maxHeight: barHeight(for: bucket.opens, availableHeight: proxy.size.height)
                            )
                            .accessibilityLabel(bucket.accessibilityLabel(locale: locale))
                            .accessibilityValue("\(bucket.opens)")
                    }
                }
            }
            .frame(height: 100)

            HStack {
                Text(activity.buckets.first?.shortLabel(locale: locale) ?? "")
                Spacer()
                Text(activity.buckets.last?.shortLabel(locale: locale) ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func barHeight(for opens: Int, availableHeight: CGFloat) -> CGFloat {
        guard opens > 0 else { return 3 }
        return max(8, availableHeight * CGFloat(opens) / CGFloat(maximum))
    }
}
