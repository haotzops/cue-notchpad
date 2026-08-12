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

    func recordCompletionRequest(model: String) {
        append(.init(
            id: UUID(),
            date: .now,
            kind: .fimRequest,
            model: model,
            inputTokens: 0,
            outputTokens: 0
        ))
    }

    func recordCompletionUsage(model: String, usage: LLMAPIUsage) {
        append(.init(
            id: UUID(),
            date: .now,
            kind: .fim,
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        ))
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

    func totals(from start: Date, through end: Date = .now) -> (input: Int, output: Int, total: Int, requests: Int, opens: Int) {
        let filtered = records.filter { $0.date >= start && $0.date <= end }
        return (
            filtered.reduce(0) { $0 + $1.inputTokens },
            filtered.reduce(0) { $0 + $1.outputTokens },
            filtered.reduce(0) { $0 + $1.totalTokens },
            filtered.filter { $0.kind == .fimRequest }.count,
            cueOpenDates.filter { $0 >= start && $0 <= end }.count
        )
    }

    private func append(_ record: CueUsageRecord) {
        guard !isReadOnly, let recordDocument = Self.jsonObject(for: record) else { return }
        records.append(record)
        recordDocuments.append(recordDocument)
        persist()
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
