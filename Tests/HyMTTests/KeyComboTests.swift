import AppKit
import XCTest
@testable import HyMT

final class KeyComboTests: XCTestCase {
    func testPunctuationKeyIsReadable() {
        let combo = KeyCombo(
            keyCode: 39,
            modifiers: UInt(NSEvent.ModifierFlags.option.rawValue)
        )
        XCTAssertEqual(combo.displayString(.uk), "⌥'")
    }

    func testRecordedLabelWins() {
        let combo = KeyCombo(
            keyCode: 39,
            modifiers: UInt(NSEvent.ModifierFlags.option.rawValue),
            label: "є"
        )
        XCTAssertEqual(combo.displayString(.uk), "⌥Є")
    }

    func testDefaultShortcut() {
        XCTAssertEqual(KeyCombo.standard.displayString(.uk), "⌥⌘T")
    }
}
