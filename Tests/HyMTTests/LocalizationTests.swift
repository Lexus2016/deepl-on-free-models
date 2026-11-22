import XCTest
@testable import HyMT

final class LocalizationTests: XCTestCase {
    func testCoreStrings() {
        XCTAssertEqual(L10n.t("Copy", .uk), "Копіювати")
        XCTAssertEqual(L10n.t("Copy", .ru), "Копировать")
        XCTAssertEqual(L10n.t("Copy", .en), "Copy")
        XCTAssertEqual(L10n.t("Settings", .uk), "Налаштування")
        XCTAssertEqual(L10n.t("Settings", .ru), "Настройки")
    }

    func testFormatPlaceholder() {
        XCTAssertEqual(
            L10n.format("Translating… %d of %d", .uk, 2, 5),
            "Перекладаю… 2 з 5"
        )
    }

    func testUkrainianPlurals() {
        XCTAssertEqual(L10n.characters(1, .uk), "1 символ")
        XCTAssertEqual(L10n.characters(2, .uk), "2 символи")
        XCTAssertEqual(L10n.characters(5, .uk), "5 символів")
        XCTAssertEqual(L10n.characters(11, .uk), "11 символів")
        XCTAssertEqual(L10n.characters(21, .uk), "21 символ")
    }

    func testRussianPlurals() {
        XCTAssertEqual(L10n.characters(1, .ru), "1 символ")
        XCTAssertEqual(L10n.characters(2, .ru), "2 символа")
        XCTAssertEqual(L10n.characters(5, .ru), "5 символов")
        XCTAssertEqual(L10n.characters(11, .ru), "11 символов")
        XCTAssertEqual(L10n.characters(21, .ru), "21 символ")
    }
}
