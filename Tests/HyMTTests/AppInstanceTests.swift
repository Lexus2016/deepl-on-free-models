import Darwin
import XCTest
@testable import HyMT

final class AppInstanceTests: XCTestCase {
    func testOnlyOneLockAndCanReacquireAfterRelease() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }

        let first = try XCTUnwrap(AppInstance.acquire(at: file))
        XCTAssertNil(try AppInstance.acquire(at: file))
        XCTAssertEqual(close(first), 0)

        let second = try XCTUnwrap(AppInstance.acquire(at: file))
        XCTAssertEqual(close(second), 0)
    }
}
