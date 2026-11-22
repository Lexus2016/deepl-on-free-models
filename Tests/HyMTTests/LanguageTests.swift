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

extension LanguageTests {
    func testRecognizesLatinLanguagesInsteadOfCallingThemEnglish() {
        XCTAssertEqual(Language.detect("Bonjour, je voudrais savoir à quelle heure commence la réunion.")?.code, "fr")
        XCTAssertEqual(Language.detect("Este documento explica cómo funciona el servicio de traducción.")?.code, "es")
    }
}
