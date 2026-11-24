import AppKit
import Carbon.HIToolbox
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

    @MainActor
    func testConflictingReplacementLeavesBothShortcutsRegistered() {
        let manager = HotKeyManager()
        defer { manager.unregisterAll() }
        let modifiers = NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue
        let clipboard = KeyCombo(keyCode: UInt32(kVK_F17), modifiers: modifiers)
        let selection = KeyCombo(keyCode: UInt32(kVK_F18), modifiers: modifiers)
        let available = KeyCombo(keyCode: UInt32(kVK_F19), modifiers: modifiers)

        XCTAssertTrue(manager.register(clipboard, id: 1) {})
        XCTAssertTrue(manager.register(selection, id: 2) {})
        XCTAssertFalse(manager.register(selection, id: 1) {})
        XCTAssertFalse(manager.register(clipboard, id: 3) {})
        XCTAssertFalse(manager.register(selection, id: 3) {})
        XCTAssertTrue(manager.register(available, id: 1) {})
        XCTAssertTrue(manager.register(clipboard, id: 3) {})
    }
}
