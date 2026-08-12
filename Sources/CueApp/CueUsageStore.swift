import Combine
import CueCore
import Foundation

struct CueUsageRecord: Codable, Identifiable {
    enum Kind: String, Codable { case fim, fimRequest }
    let id: UUID
    let date: Date
    let kind: Kind
    let model: String
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}

struct CueUsageActivity {
    struct Bucket: Identifiable {
        let start: Date
        let end: Date
        let opens: Int

        var id: Date { start }

        func shortLabel(locale: Locale) -> String {
            if end.timeIntervalSince(start) < 6 * 60 * 60 {
                return start.formatted(
                    Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
                )
            }
            return start.formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
            )
        }

        func accessibilityLabel(locale: Locale) -> String {
            if end.timeIntervalSince(start) < 6 * 60 * 60 {
                return start.formatted(
                    Date.FormatStyle(date: .long, time: .shortened).locale(locale)
                )
            }
            let style = Date.FormatStyle(date: .long, time: .omitted).locale(locale)
            guard !Calendar.current.isDate(start, inSameDayAs: end) else {
                return start.formatted(style)
            }
            return "\(start.formatted(style)) – \(end.formatted(style))"
        }
    }

    let start: Date
    let end: Date
    let totalOpens: Int
    let activeDays: Int
    let dayCount: Int
    let firstOpen: Date?
    let latestOpen: Date?
    let buckets: [Bucket]

    var averageOpens: Double {
        guard dayCount > 0 else { return 0 }
        return Double(totalOpens) / Double(dayCount)
    }

    func rangeLabel(locale: Locale) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        guard !Calendar.current.isDate(start, inSameDayAs: end) else {
            return start.formatted(style)
        }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

@MainActor
final class CueUsageStore: ObservableObject {
    static let shared = CueUsageStore()
    static let schemaVersion = 1
    static let archiveKey = "cueUsageArchive.v1"

    @Published private(set) var records: [CueUsageRecord]
    @Published private(set) var cueOpenCount: Int
    @Published private(set) var cueOpenDates: [Date]

    private let defaults: UserDefaults
    private var document: [String: Any]
    private var recordDocuments: [[String: Any]]
    private var isReadOnly: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.loadArchive(from: defaults)
        document = loaded.document
        recordDocuments = loaded.recordDocuments
        records = loaded.records
        cueOpenCount = loaded.cueOpenCount
        cueOpenDates = loaded.cueOpenDates
        isReadOnly = loaded.isReadOnly
    }

    func clearUsageStatistics() {
        guard !isReadOnly else { return }
        records.removeAll()
        recordDocuments.removeAll()
        cueOpenCount = 0
        cueOpenDates.removeAll()
        persist()
    }

    func recordCueOpen() {
        guard !isReadOnly else { return }
        cueOpenCount += 1
        cueOpenDates.append(.now)
        persist()
    }

    func activity(
        from start: Date,
        through end: Date = .now,
        calendar: Calendar = .current,
        maximumBuckets: Int = 30
    ) -> CueUsageActivity {
        let firstDay = calendar.startOfDay(for: min(start, end))
        let lastDate = max(start, end)
        let lastDay = calendar.startOfDay(for: lastDate)
        let dayCount = max(
            calendar.dateComponents([.day], from: firstDay, to: lastDay).day.map { $0 + 1 } ?? 1,
            1
        )
        let filteredDates = cueOpenDates.filter { $0 >= firstDay && $0 <= lastDate }.sorted()
        let activeDays = Set(filteredDates.map { calendar.startOfDay(for: $0) }).count
        let buckets = dayCount == 1
            ? Self.hourlyBuckets(from: firstDay, through: lastDate, dates: filteredDates, calendar: calendar)
            : Self.dailyBuckets(
                from: firstDay,
                through: lastDate,
                dayCount: dayCount,
                dates: filteredDates,
                calendar: calendar,
                maximumBuckets: maximumBuckets
            )

        return CueUsageActivity(
            start: firstDay,
            end: lastDate,
            totalOpens: filteredDates.count,
            activeDays: activeDays,
            dayCount: dayCount,
            firstOpen: filteredDates.first,
            latestOpen: filteredDates.last,
            buckets: buckets
        )
    }

    private static func hourlyBuckets(
        from start: Date,
        through end: Date,
        dates: [Date],
        calendar: Calendar
    ) -> [CueUsageActivity.Bucket] {
        let finalHour = calendar.dateInterval(of: .hour, for: end)?.start ?? end
        let hourCount = max(
            calendar.dateComponents([.hour], from: start, to: finalHour).hour.map { $0 + 1 } ?? 1,
            1
        )
        return (0 ..< hourCount).compactMap { offset in
            guard let bucketStart = calendar.date(byAdding: .hour, value: offset, to: start),
                  let nextHour = calendar.date(byAdding: .hour, value: 1, to: bucketStart)
            else { return nil }
            let bucketEnd = min(end, nextHour.addingTimeInterval(-1))
            return .init(
                start: bucketStart,
                end: bucketEnd,
                opens: dates.filter { $0 >= bucketStart && $0 <= bucketEnd }.count
            )
        }
    }

    private static func dailyBuckets(
        from start: Date,
        through end: Date,
        dayCount: Int,
        dates: [Date],
        calendar: Calendar,
        maximumBuckets: Int
    ) -> [CueUsageActivity.Bucket] {
        let bucketCount = max(min(maximumBuckets, dayCount), 1)
        let daysPerBucket = Int(ceil(Double(dayCount) / Double(bucketCount)))
        var buckets = [CueUsageActivity.Bucket]()
        var dayOffset = 0

        while dayOffset < dayCount {
            guard let bucketStart = calendar.date(byAdding: .day, value: dayOffset, to: start) else { break }
            let finalOffset = min(dayOffset + daysPerBucket - 1, dayCount - 1)
            guard let bucketEndDay = calendar.date(byAdding: .day, value: finalOffset, to: start),
                  let dayAfterBucket = calendar.date(byAdding: .day, value: 1, to: bucketEndDay)
            else { break }
            let bucketEnd = min(end, dayAfterBucket.addingTimeInterval(-1))
            buckets.append(.init(
                start: bucketStart,
                end: bucketEnd,
                opens: dates.filter { $0 >= bucketStart && $0 <= bucketEnd }.count
            ))
            dayOffset += daysPerBucket
        }
        return buckets
    }

    private static func loadArchive(from defaults: UserDefaults) -> (
        document: [String: Any],
        recordDocuments: [[String: Any]],
        records: [CueUsageRecord],
        cueOpenCount: Int,
        cueOpenDates: [Date],
        isReadOnly: Bool
    ) {
        let empty: [String: Any] = [
            "schemaVersion": schemaVersion,
            "records": [],
            "cueOpenCount": 0,
            "cueOpenDates": [],
        ]
        guard let data = defaults.data(forKey: archiveKey) else {
            return (empty, [], [], 0, [], false)
        }
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["schemaVersion"] as? Int == schemaVersion,
              let recordDocuments = document["records"] as? [[String: Any]],
              let records = decodeRecords(recordDocuments),
              let cueOpenCount = document["cueOpenCount"] as? Int,
              let cueOpenDates = decodeDates(document["cueOpenDates"])
        else {
            return (empty, [], [], 0, [], true)
        }
        return (document, recordDocuments, records, cueOpenCount, cueOpenDates, false)
    }

    private func persist() {
        document["schemaVersion"] = Self.schemaVersion
        document["records"] = recordDocuments
        document["cueOpenCount"] = cueOpenCount
        document["cueOpenDates"] = cueOpenDates.map(\.timeIntervalSinceReferenceDate)
        guard JSONSerialization.isValidJSONObject(document),
              let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        else { return }
        defaults.set(data, forKey: Self.archiveKey)
    }

    private static func decodeRecords(_ documents: [[String: Any]]) -> [CueUsageRecord]? {
        documents.reduce(into: Optional<[CueUsageRecord]>([])) { result, document in
            guard var records = result,
                  JSONSerialization.isValidJSONObject(document),
                  let data = try? JSONSerialization.data(withJSONObject: document),
                  let record = try? JSONDecoder().decode(CueUsageRecord.self, from: data)
            else {
                result = nil
                return
            }
            records.append(record)
            result = records
        }
    }

    private static func decodeDates(_ value: Any?) -> [Date]? {
        guard let values = value as? [NSNumber] else { return nil }
        return values.map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) }
    }

    private static func jsonObject(for record: CueUsageRecord) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
