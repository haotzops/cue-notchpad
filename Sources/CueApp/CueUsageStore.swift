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
    static let shared = CueUsageStore()
    @Published private(set) var records: [CueUsageRecord]
    @Published private(set) var cueOpenCount: Int
    @Published private(set) var cueOpenDates: [Date]

    private let recordsKey = "cueUsageRecords"
    private let opensKey = "cueOpenCount"
    private let openDatesKey = "cueOpenDates"

    private init() {
        records = (try? JSONDecoder().decode([CueUsageRecord].self, from: UserDefaults.standard.data(forKey: recordsKey) ?? Data())) ?? []
        cueOpenCount = UserDefaults.standard.integer(forKey: opensKey)
        cueOpenDates = (try? JSONDecoder().decode([Date].self, from: UserDefaults.standard.data(forKey: openDatesKey) ?? Data())) ?? []
    }

    func recordFIMRequest(model: String) {
        records.append(.init(id: UUID(), date: .now, kind: .fimRequest, model: model, inputTokens: 0, outputTokens: 0))
        persist()
    }

    func recordFIM(model: String, inputTokens: Int, outputTokens: Int) {
        records.append(.init(id: UUID(), date: .now, kind: .fim, model: model, inputTokens: inputTokens, outputTokens: outputTokens))
        persist()
    }

    func recordCueOpen() {
        cueOpenCount += 1
        cueOpenDates.append(.now)
        UserDefaults.standard.set(cueOpenCount, forKey: opensKey)
        if let data = try? JSONEncoder().encode(cueOpenDates) {
            UserDefaults.standard.set(data, forKey: openDatesKey)
        }
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

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: recordsKey) }
    }
}
