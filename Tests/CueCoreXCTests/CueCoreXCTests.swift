#if canImport(XCTest)
import CueCore
import XCTest

final class CueCoreXCTests: XCTestCase {
    func testIPCVersionIsExplicitlyChecked() {
        XCTAssertTrue(CueIPC.supports(version: CueIPC.protocolVersion))
        XCTAssertFalse(CueIPC.supports(version: CueIPC.protocolVersion + 1))
    }

    func testFIMRequestUsesDocumentedBounds() {
        let request = DeepSeekFIMRequest(
            model: DeepSeekFIM.model,
            prompt: "prefix",
            suffix: "suffix",
            maxTokens: DeepSeekFIM.maximumTokens + 1
        )
        XCTAssertEqual(request.maxTokens, DeepSeekFIM.maximumTokens)
        XCTAssertTrue(DeepSeekFIM.supports(model: request.model))
    }
}
#endif
