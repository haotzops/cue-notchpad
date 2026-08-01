#if canImport(XCTest)
@testable import CueApp
import CueCore
import Foundation
import XCTest

final class CueCoreXCTests: XCTestCase {
    func testIPCVersionIsExplicitlyChecked() {
        XCTAssertTrue(CueIPC.supports(version: CueIPC.protocolVersion))
        XCTAssertFalse(CueIPC.supports(version: CueIPC.protocolVersion + 1))
    }

    func testFIMRequestUsesDocumentedBounds() {
        let request = DeepSeekFIMRequest(
            model: "user-selected-model",
            prompt: "prefix",
            suffix: "suffix",
            maxTokens: DeepSeekFIM.maximumTokens + 1
        )
        XCTAssertEqual(request.maxTokens, DeepSeekFIM.maximumTokens)
        XCTAssertEqual(request.model, "user-selected-model")
    }

    func testAPIKeyConfigurationPreservesUnknownFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        CueAPIKeyStore.configurationURLOverride = url
        defer { CueAPIKeyStore.configurationURLOverride = nil }

        try fixtureData(named: "config-v1.json").write(to: url)
        try CueAPIKeyStore.saveDeepSeekAPIKey("replacement-key")
        var document = try jsonObject(at: url)
        XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        XCTAssertEqual(document["deepSeekAPIKey"] as? String, "replacement-key")
        XCTAssertEqual(document["futureField"] as? String, "must-survive-a-supported-write")

        document["schemaVersion"] = 2
        document["futureField"] = "must-survive-a-future-write"
        let futureData = try JSONSerialization.data(withJSONObject: document)
        try futureData.write(to: url)
        XCTAssertThrowsError(try CueAPIKeyStore.saveDeepSeekAPIKey("new-key"))
        XCTAssertEqual(try Data(contentsOf: url), futureData)
    }

    @MainActor
    func testUsageArchiveReadsFixtureAndDoesNotOverwriteFutureSchema() throws {
        let suiteName = "cue-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try fixtureData(named: "usage-v1.json"), forKey: "cueUsageArchive.v1")
        let usage = CueUsageStore(defaults: defaults)
        XCTAssertEqual(usage.records.count, 1)
        XCTAssertEqual(usage.records.first?.totalTokens, 46)
        usage.recordFIMRequest(model: "new-model")
        XCTAssertEqual(usage.records.count, 2)

        let future = Data("{\"schemaVersion\":2,\"records\":[],\"cueOpenCount\":0,\"cueOpenDates\":[],\"futureField\":true}".utf8)
        defaults.set(future, forKey: "cueUsageArchive.v1")
        let futureUsage = CueUsageStore(defaults: defaults)
        futureUsage.recordFIMRequest(model: "must-not-write")
        XCTAssertEqual(defaults.data(forKey: "cueUsageArchive.v1"), future)
    }

    private func fixtureData(named name: String) throws -> Data {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: testsDirectory.appendingPathComponent("Fixtures/Persistence/\(name)"))
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
#endif
