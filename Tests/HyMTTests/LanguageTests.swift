import XCTest
@testable import HyMT

final class LanguageTests: XCTestCase {
    func testUkrainian() {
        XCTAssertEqual(Language.detect("Це український текст про переклад", preferred: .uk)?.code, "uk")
    }

    func testRussian() {
        XCTAssertEqual(Language.detect("Это русский текст про перевод", preferred: .ru)?.code, "ru")
    }

    func testEnglish() {
        XCTAssertEqual(Language.detect("Hello, this is a test")?.code, "en")
    }

    func testAmbiguousCyrillicUsesPreferredLanguage() {
        XCTAssertEqual(Language.detect("ключ", preferred: .uk)?.code, "uk")
        XCTAssertEqual(Language.detect("ключ", preferred: .ru)?.code, "ru")
    }
}
