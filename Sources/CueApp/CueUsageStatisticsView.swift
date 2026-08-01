import CueCore
import SwiftUI

private enum CueUsagePeriod: String, CaseIterable, Identifiable {
    case day, week, month, custom
    var id: String { rawValue }
}

struct CueUsageStatisticsView: View {
    @ObservedObject var settings: CueSettings
    @ObservedObject var usage = CueUsageStore.shared
    @State private var period: CueUsagePeriod = .day
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var customEnd = Date.now

    private var range: (Date, Date) {
        let calendar = Calendar.current
        switch period {
        case .day: return (calendar.startOfDay(for: .now), .now)
        case .week: return (calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now))!, .now)
        case .month: return (calendar.date(byAdding: .month, value: -1, to: calendar.startOfDay(for: .now))!, .now)
        case .custom: return (min(customStart, customEnd), max(customStart, customEnd))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                DatePicker(localized(.usageStart), selection: $customStart, displayedComponents: .date)
                DatePicker(localized(.usageEnd), selection: $customEnd, displayedComponents: .date)
            }
            let totals = usage.totals(from: range.0, through: range.1)
            LabeledContent(localized(.usageFIMInput), value: "\(totals.input)")
            LabeledContent(localized(.usageFIMOutput), value: "\(totals.output)")
            LabeledContent(localized(.usageFIMTokens), value: "\(totals.total)")
            LabeledContent(localized(.usageFIMRequests), value: "\(totals.requests)")
            LabeledContent(localized(.usageCueOpens), value: "\(totals.opens)")
        }
    }

    private func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: settings.localizationIdentifier)
    }
}
