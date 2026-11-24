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

    func testPickerSortsByLocalizedNameWithAutoFirstOnlyForSource() {
        for interface in [AppLanguage.en, .uk, .pl] {
            let source = Language.pickerOptions(in: interface, includeAuto: true, query: "")
            let target = Language.pickerOptions(in: interface, includeAuto: false, query: "")
            let locale = Locale(identifier: interface.localeIdentifier)
            XCTAssertEqual(source.first, .auto)
            XCTAssertEqual(Array(source.dropFirst()), target)
            XCTAssertEqual(Set(target), Set(Language.all))
            for (first, second) in zip(target, target.dropFirst()) {
                XCTAssertNotEqual(
                    first.displayName(in: interface).compare(
                        second.displayName(in: interface),
                        options: [.caseInsensitive],
                        locale: locale
                    ),
                    .orderedDescending
                )
            }
        }
    }

    func testPickerMatchesNameOrCodeFromTheStart() {
        func codes(_ query: String, interface: AppLanguage = .en, source: Bool = false) -> [String] {
            Language.pickerOptions(in: interface, includeAuto: source, query: query).map(\.code)
        }
        XCTAssertEqual(codes("  УКРАЇН ", interface: .uk), ["uk"])
        XCTAssertEqual(codes(" Ukrainian ", interface: .uk), ["uk"])
        XCTAssertEqual(codes("Franc", interface: .fr), ["fr"])
        XCTAssertEqual(codes("zh-ha"), ["zh-Hant"])
        XCTAssertEqual(codes("auto", source: true), ["auto"])
        XCTAssertTrue(codes("auto").isEmpty)
        XCTAssertTrue(codes("krain").isEmpty)
    }
}

extension LanguageTests {
    func testRecognizesLatinLanguagesInsteadOfCallingThemEnglish() {
        XCTAssertEqual(Language.detect("Bonjour, je voudrais savoir à quelle heure commence la réunion.")?.code, "fr")
        XCTAssertEqual(Language.detect("Este documento explica cómo funciona el servicio de traducción.")?.code, "es")
    }
}
