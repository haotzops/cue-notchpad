import Combine
import Foundation

private struct CueLegacyUsageRecord: Codable {
    enum Kind: String, Codable { case fim, fimRequest }
    let date: Date
    let kind: Kind
    let model: String
    let inputTokens: Int
    let outputTokens: Int
}

private struct CueDailyUsage: Codable, Identifiable, Sendable {
    let day: Date
    let model: String
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    var cueOpens: Int

    var id: String { "\(day.timeIntervalSince1970)-\(model)" }
    var totalTokens: Int { inputTokens + outputTokens }
}

@MainActor
final class CueUsageStore: ObservableObject {
    static let shared = CueUsageStore()
    @Published private var dailyUsage: [CueDailyUsage]

    private let usageKey = "cueDailyUsage"
    private let legacyRecordsKey = "cueUsageRecords"
    private let legacyOpenDatesKey = "cueOpenDates"
    private static let retentionDays = 180
    private var persistTask: Task<Void, Never>?

    private init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: usageKey),
           let saved = try? JSONDecoder().decode([CueDailyUsage].self, from: data)
        {
            dailyUsage = Self.pruned(saved)
        } else {
            dailyUsage = Self.migrateLegacy(defaults: defaults)
        }
        schedulePersist()
    }

    deinit { persistTask?.cancel() }

    func recordFIMRequest(model: String) {
        update(day: .now, model: model) { $0.requests += 1 }
    }

    func recordFIM(model: String, inputTokens: Int, outputTokens: Int) {
        update(day: .now, model: model) {
            $0.inputTokens += max(inputTokens, 0)
            $0.outputTokens += max(outputTokens, 0)
        }
    }

    func recordCueOpen() {
        update(day: .now, model: "") { $0.cueOpens += 1 }
    }

    func totals(from start: Date, through end: Date = .now) -> (input: Int, output: Int, total: Int, requests: Int, opens: Int) {
        let matching = dailyUsage.filter { $0.day >= Self.day(for: start) && $0.day <= Self.day(for: end) }
        return matching.reduce(into: (input: 0, output: 0, total: 0, requests: 0, opens: 0)) { result, usage in
            result.input += usage.inputTokens
            result.output += usage.outputTokens
            result.total += usage.totalTokens
            result.requests += usage.requests
            result.opens += usage.cueOpens
        }
    }

    private func update(day: Date, model: String, _ body: (inout CueDailyUsage) -> Void) {
        let day = Self.day(for: day)
        if let index = dailyUsage.firstIndex(where: { $0.day == day && $0.model == model }) {
            body(&dailyUsage[index])
        } else {
            var usage = CueDailyUsage(day: day, model: model, requests: 0, inputTokens: 0, outputTokens: 0, cueOpens: 0)
            body(&usage)
            dailyUsage.append(usage)
        }
        dailyUsage = Self.pruned(dailyUsage)
        schedulePersist()
    }

    private func schedulePersist() {
        persistTask?.cancel()
        let usage = dailyUsage
        persistTask = Task.detached(priority: .utility) { [usageKey] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  let data = try? JSONEncoder().encode(usage)
            else { return }
            UserDefaults.standard.set(data, forKey: usageKey)
        }
    }

    private static func migrateLegacy(defaults: UserDefaults) -> [CueDailyUsage] {
        let records = defaults.data(forKey: "cueUsageRecords")
            .flatMap { try? JSONDecoder().decode([CueLegacyUsageRecord].self, from: $0) } ?? []
        let opens = defaults.data(forKey: "cueOpenDates")
            .flatMap { try? JSONDecoder().decode([Date].self, from: $0) } ?? []
        var result = [CueDailyUsage]()
        func update(_ date: Date, model: String, _ body: (inout CueDailyUsage) -> Void) {
            let day = Self.day(for: date)
            if let index = result.firstIndex(where: { $0.day == day && $0.model == model }) {
                body(&result[index])
            } else {
                var usage = CueDailyUsage(day: day, model: model, requests: 0, inputTokens: 0, outputTokens: 0, cueOpens: 0)
                body(&usage)
                result.append(usage)
            }
        }
        for record in records {
            update(record.date, model: record.model) {
                if record.kind == .fimRequest { $0.requests += 1 }
                $0.inputTokens += max(record.inputTokens, 0)
                $0.outputTokens += max(record.outputTokens, 0)
            }
        }
        for date in opens { update(date, model: "") { $0.cueOpens += 1 } }
        defaults.removeObject(forKey: "cueUsageRecords")
        defaults.removeObject(forKey: "cueOpenDates")
        defaults.removeObject(forKey: "cueOpenCount")
        return pruned(result)
    }

    private static func day(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func pruned(_ usage: [CueDailyUsage]) -> [CueDailyUsage] {
        let earliest = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: day(for: .now)) ?? .distantPast
        return usage.filter { $0.day >= earliest }
    }
}
