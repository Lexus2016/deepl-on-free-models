import XCTest
@testable import HyMT

final class TranslationServiceTests: XCTestCase {
    func testModelListIsSplit() throws {
        let result = try XCTUnwrap(
            TranslationService.splitMixedLine(
                "tencent/hy-mt2-7b, google/gemma-4-31b-it:free — translation models"
            )
        )
        XCTAssertEqual(result.keep, "tencent/hy-mt2-7b, google/gemma-4-31b-it:free — ")
        XCTAssertEqual(result.translate, "translation models")
    }

    func testSingleModelIDIsSplit() {
        let result = TranslationService.splitMixedLine("llama-3.3-70b-versatile — a model")
        XCTAssertEqual(result?.keep, "llama-3.3-70b-versatile — ")
    }

    func testHyphenatedModelIDIsSplit() {
        let result = TranslationService.splitMixedLine("gpt-oss-120b — a model")
        XCTAssertEqual(result?.keep, "gpt-oss-120b — ")
    }

    func testProseWithSlashIsNotSplit() {
        XCTAssertNil(TranslationService.splitMixedLine("Use HTTP/2 — it is faster"))
    }

    func testTwoNamesWithSlashAreNotSplit() {
        XCTAssertNil(TranslationService.splitMixedLine("Google/YouTube — platforms"))
    }

    func testCJKScriptIncludesJapanese() {
        XCTAssertTrue(TranslationService.usesCJKScript("ja"))
        XCTAssertTrue(TranslationService.usesCJKScript("zh-Hant"))
        XCTAssertFalse(TranslationService.usesCJKScript("en"))
    }

    func testUkrainianAlphabet() {
        XCTAssertTrue(TranslationService.usesAllowedCyrillic("Привіт, це український текст.", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("маў", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("цѯнструмент", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("коштуђуце", target: "uk"))
    }

    func testRussianAlphabet() {
        XCTAssertTrue(TranslationService.usesAllowedCyrillic("Привет, это русский текст.", target: "ru"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("Привіт", target: "ru"))
    }

    func testPreambleIsStripped() {
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Ось переклад тексту: «Привіт». Далі текст.",
                source: "Hello. More text."
            ),
            "Привіт. Далі текст."
        )
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Here is the translation: Hello.",
                source: "Привіт."
            ),
            "Hello."
        )
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Звісно! Цей пакет коштує 57 доларів.",
                source: "The bundle costs $57."
            ),
            "Цей пакет коштує 57 доларів."
        )
    }

    func testTargetScriptPresence() {
        XCTAssertTrue(TranslationService.hasTargetScript("Привіт", target: "uk"))
        XCTAssertFalse(TranslationService.hasTargetScript("Hello", target: "uk"))
        XCTAssertTrue(TranslationService.hasTargetScript("Hello", target: "en"))
        XCTAssertFalse(TranslationService.hasTargetScript("Привіт", target: "en"))
        XCTAssertTrue(TranslationService.hasTargetScript("こんにちは", target: "ja"))
        XCTAssertFalse(TranslationService.hasTargetScript("Hello", target: "ja"))
    }
}
