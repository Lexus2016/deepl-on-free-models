import AppKit
import XCTest
@testable import HyMT

final class SelectionTranslationServiceTests: XCTestCase {
    @MainActor
    func testServiceUsesOnlyTheSelectionPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboardChangeCount = NSPasteboard.general.changeCount
        pasteboard.setString("  Guten Morgen.  ", forType: .string)
        var received: [String] = []
        let service = SelectionTranslationService { received.append($0) }
        var error: NSString?

        service.translateSelection(pasteboard, userData: nil, error: &error)
        XCTAssertEqual(received, ["Guten Morgen."])
        XCTAssertNil(error)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)

        pasteboard.clearContents()
        service.translateSelection(pasteboard, userData: nil, error: &error)
        XCTAssertEqual(received.count, 1)
        XCTAssertNotNil(error)
    }
}
