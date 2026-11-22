import XCTest
@testable import HyMT

final class ProbeTests: XCTestCase {
    func testEmptyModelListIsNotReady() {
        XCTAssertFalse(Probe.model("hy-mt2:7b", isListedIn: []))
    }

    func testExactModelMatches() {
        XCTAssertTrue(Probe.model("hy-mt2:7b", isListedIn: ["hy-mt2:7b"]))
    }

    func testTagSuffixMatches() {
        XCTAssertTrue(Probe.model("gpt-oss", isListedIn: ["gpt-oss:120b-cloud"]))
        XCTAssertTrue(Probe.model("hy-mt2-7b", isListedIn: ["tencent/hy-mt2-7b"]))
    }

    func testUnrelatedModelDoesNotMatch() {
        XCTAssertFalse(Probe.model("hy-mt2:7b", isListedIn: ["llama-3.3-70b"]))
    }
}
