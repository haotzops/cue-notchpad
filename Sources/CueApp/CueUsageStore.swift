import Combine
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
    private struct Archive: Codable {
        let schemaVersion: Int
        var records: [CueUsageRecord]
        var cueOpenCount: Int
        var cueOpenDates: [Date]
    }

    static let shared = CueUsageStore()
    static let schemaVersion = 1
    @Published private(set) var records: [CueUsageRecord]
    @Published private(set) var cueOpenCount: Int
    @Published private(set) var cueOpenDates: [Date]

    /// A new, versioned archive. Legacy 0.1/0.2 keys are deliberately left
    /// untouched; this release neither migrates nor deletes them.
    private let archiveKey = "cueUsageArchive.v1"
    private let defaults: UserDefaults
    private var isReadOnly = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.loadArchive(from: defaults)
        records = loaded.archive.records
        cueOpenCount = loaded.archive.cueOpenCount
        cueOpenDates = loaded.archive.cueOpenDates
        isReadOnly = loaded.isReadOnly
    }

    func recordFIMRequest(model: String) {
        guard !isReadOnly else { return }
        records.append(.init(id: UUID(), date: .now, kind: .fimRequest, model: model, inputTokens: 0, outputTokens: 0))
        persist()
    }

    func recordFIM(model: String, inputTokens: Int, outputTokens: Int) {
        guard !isReadOnly else { return }
        records.append(.init(id: UUID(), date: .now, kind: .fim, model: model, inputTokens: inputTokens, outputTokens: outputTokens))
        persist()
    }

    /// Destructively clears usage only after the user explicitly confirms it in
    /// Settings. Future or corrupt archives remain read-only and untouched.
    func clearUsageStatistics() {
        guard !isReadOnly else { return }
        records.removeAll()
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

    private static func loadArchive(from defaults: UserDefaults) -> (archive: Archive, isReadOnly: Bool) {
        let empty = Archive(schemaVersion: schemaVersion, records: [], cueOpenCount: 0, cueOpenDates: [])
        guard let data = defaults.data(forKey: "cueUsageArchive.v1") else {
            return (empty, false)
        }
        let version = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int
        guard version == schemaVersion,
              let archive = try? JSONDecoder().decode(Archive.self, from: data)
        else {
            // A corrupt or future archive must never be replaced by an empty one.
            return (empty, true)
        }
        return (archive, false)
    }

    private func persist() {
        let archive = Archive(
            schemaVersion: Self.schemaVersion,
            records: records,
            cueOpenCount: cueOpenCount,
            cueOpenDates: cueOpenDates
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: archiveKey)
    }
}
