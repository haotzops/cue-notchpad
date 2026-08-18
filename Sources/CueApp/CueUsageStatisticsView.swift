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
        VStack(spacing: 18) {
            periodCard
            summaryCards(selectedActivity)
            activityCard(selectedActivity)
            dataCard
        }
    }

    private var periodCard: some View {
        CueSettingsCard {
            VStack(alignment: .leading, spacing: 12) {
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
                    HStack(spacing: 18) {
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
                        Spacer()
                    }
                    .datePickerStyle(.compact)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryCards(_ activity: CueUsageActivity) -> some View {
        HStack(spacing: 12) {
            UsageMetricCard(
                title: localized(.usageCueOpens),
                value: "\(activity.totalOpens)",
                systemImage: "rectangle.and.pencil.and.ellipsis",
                color: .blue
            )
            if activity.dayCount == 1 {
                UsageMetricCard(
                    title: localized(.usageFirstOpen),
                    value: time(activity.firstOpen),
                    systemImage: "sunrise.fill",
                    color: .orange
                )
                UsageMetricCard(
                    title: localized(.usageLatestOpen),
                    value: time(activity.latestOpen),
                    systemImage: "clock.fill",
                    color: .purple
                )
            } else {
                UsageMetricCard(
                    title: localized(.usageActiveDays),
                    value: "\(activity.activeDays)",
                    systemImage: "calendar",
                    color: .orange
                )
                UsageMetricCard(
                    title: localized(.usageDailyAverage),
                    value: activity.averageOpens.formatted(.number.precision(.fractionLength(1))),
                    systemImage: "chart.bar.fill",
                    color: .purple
                )
            }
        }
    }

    private func activityCard(_ activity: CueUsageActivity) -> some View {
        CueSettingsCard {
            VStack(alignment: .leading, spacing: 14) {
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
                            .font(.system(size: 26))
                            .foregroundStyle(.tertiary)
                        Text(localized(.usageNoActivity))
                            .font(.callout.weight(.medium))
                        Text(localized(.usageNoActivityHint))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 138)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    UsageActivityChart(
                        activity: activity,
                        locale: locale,
                        valueLabel: localized(.usageCueOpens)
                    )
                    .frame(height: 150)
                }
            }
        }
    }

    private var dataCard: some View {
        CueSettingsCard {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized(.usagePrivacyHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(localized(.settingsClearUsageDetail))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 18)

                Button(localized(.settingsClearUsage), role: .destructive) {
                    isConfirmingUsageClear = true
                }
                .disabled(usage.cueOpenCount == 0 && usage.records.isEmpty)
            }
        }
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
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct UsageActivityChart: View {
    let activity: CueUsageActivity
    let locale: Locale
    let valueLabel: String
    @State private var hoveredBucketID: Date?

    private var maximum: Int {
        max(activity.buckets.map(\.opens).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                let spacing: CGFloat = activity.buckets.count > 20 ? 3 : 6
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(activity.buckets) { bucket in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(barColor(for: bucket))
                                    .frame(
                                        minHeight: 3,
                                        maxHeight: barHeight(
                                            for: bucket.opens,
                                            availableHeight: proxy.size.height
                                        )
                                    )
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .help(tooltipText(for: bucket))
                            .accessibilityLabel(bucket.accessibilityLabel(locale: locale))
                            .accessibilityValue("\(bucket.opens)")
                        }
                    }

                    if let hoveredBucket,
                       let index = activity.buckets.firstIndex(where: { $0.id == hoveredBucket.id })
                    {
                        chartTooltip(for: hoveredBucket)
                            .fixedSize()
                            .position(
                                x: tooltipX(
                                    index: index,
                                    width: proxy.size.width,
                                    spacing: spacing
                                ),
                                y: 21
                            )
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredBucketID = bucketID(
                            at: location.x,
                            width: proxy.size.width,
                            spacing: spacing
                        )
                    case .ended:
                        hoveredBucketID = nil
                    }
                }
            }
            .frame(height: 118)

            HStack {
                Text(activity.buckets.first?.shortLabel(locale: locale) ?? "")
                Spacer()
                Text(activity.buckets.last?.shortLabel(locale: locale) ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var hoveredBucket: CueUsageActivity.Bucket? {
        activity.buckets.first { $0.id == hoveredBucketID }
    }

    private func chartTooltip(for bucket: CueUsageActivity.Bucket) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bucket.accessibilityLabel(locale: locale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(valueLabel)
                    .foregroundStyle(.secondary)
                Text("\(bucket.opens)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .font(.caption2)
        .frame(maxWidth: 190, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
    }

    private func tooltipText(for bucket: CueUsageActivity.Bucket) -> String {
        "\(bucket.accessibilityLabel(locale: locale))\n\(valueLabel): \(bucket.opens)"
    }

    private func barColor(for bucket: CueUsageActivity.Bucket) -> Color {
        if hoveredBucketID == bucket.id {
            return Color.accentColor.opacity(0.72)
        }
        return bucket.opens == 0 ? Color.secondary.opacity(0.13) : Color.accentColor
    }

    private func tooltipX(index: Int, width: CGFloat, spacing: CGFloat) -> CGFloat {
        let count = max(activity.buckets.count, 1)
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = max((width - totalSpacing) / CGFloat(count), 1)
        let center = CGFloat(index) * (barWidth + spacing) + barWidth / 2
        return min(max(center, 105), max(width - 105, 105))
    }

    private func bucketID(at x: CGFloat, width: CGFloat, spacing: CGFloat) -> Date? {
        guard !activity.buckets.isEmpty else { return nil }
        let count = activity.buckets.count
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = max((width - totalSpacing) / CGFloat(count), 1)
        let stride = barWidth + spacing
        let index = min(max(Int(x / stride), 0), count - 1)
        return activity.buckets[index].id
    }

    private func barHeight(for opens: Int, availableHeight: CGFloat) -> CGFloat {
        guard opens > 0 else { return 3 }
        return max(8, availableHeight * CGFloat(opens) / CGFloat(maximum))
    }
}
