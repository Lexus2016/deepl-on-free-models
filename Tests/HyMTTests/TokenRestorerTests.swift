import XCTest
@testable import HyMT

final class TokenRestorerTests: XCTestCase {
    func testRestoresURL() {
        let source = "Groq (ключ: console.groq.com/keys):"
        let translated = "Groq (key: console.grole.com/keys)"
        let restored = TokenRestorer.restore(source: source, translated: translated)
        XCTAssertEqual(restored, "Groq (key: console.groq.com/keys)")
    }

    func testRestoresModelIDs() {
        let source = "tencent/hy-mt2-7b, qwen/qwen3.7-flash — model"
        let translated = "Tencent/HY-MT2-7B, QWEN/QWEN3.7-FLASH — model"
        let restored = TokenRestorer.restore(source: source, translated: translated)
        XCTAssertEqual(restored, "tencent/hy-mt2-7b, qwen/qwen3.7-flash — model")
    }

    func testMismatchReturnsNil() {
        let source = "See console.groq.com/keys"
        let translated = "No link here"
        XCTAssertNil(TokenRestorer.restore(source: source, translated: translated))
    }

    func testPunctuationIsKept() {
        let source = "Cloud providers:"
        let translated = "Cloud providers"
        XCTAssertEqual(
            TokenRestorer.preserveTrailingPunctuation(source: source, translated: translated),
            "Cloud providers:"
        )
    }

    func testWrongPunctuationIsReplaced() {
        let source = "Cloud providers:"
        let translated = "Cloud providers."
        XCTAssertEqual(
            TokenRestorer.preserveTrailingPunctuation(source: source, translated: translated),
            "Cloud providers:"
        )
    }

    func testMultiLabelDomainIsRestored() {
        let source = "Сайт example.com.ua працює"
        let translated = "The site example.com works"
        let restored = TokenRestorer.restore(source: source, translated: translated)
        XCTAssertEqual(restored, "The site example.com.ua works")
    }

    func testEmailIsRestored() {
        let source = "Напишіть на admin@example.com"
        let translated = "Write to admin@example.org"
        let restored = TokenRestorer.restore(source: source, translated: translated)
        XCTAssertEqual(restored, "Write to admin@example.com")
    }

    func testSentencePeriodIsNotPartOfURL() {
        let source = "Відкрийте https://example.com."
        let translated = "Open https://example.com"
        let restored = TokenRestorer.restore(source: source, translated: translated)
        XCTAssertEqual(restored, "Open https://example.com")
        XCTAssertEqual(
            TokenRestorer.preserveTrailingPunctuation(source: source, translated: restored ?? ""),
            "Open https://example.com."
        )
    }

    func testMarkdownLinkTargetIsRestored() {
        let source = "[key](https://example.com/keys)"
        let translated = "[key](https://example.com/keys)"
        XCTAssertEqual(TokenRestorer.restore(source: source, translated: translated), translated)
    }

    func testInlineCodeIsProtected() {
        let source = "Use `console.groq.com/keys` here"
        let translated = "Use `console.groq.com/keys` here"
        XCTAssertEqual(TokenRestorer.restore(source: source, translated: translated), translated)
    }

    func testHyphenatedModelIDIsProtected() {
        let source = "gpt-oss-120b — ~3000 tokens per second"
        let translated = "GPT-OSS-120B — ~3000 tokens per second"
        XCTAssertEqual(
            TokenRestorer.restore(source: source, translated: translated),
            "gpt-oss-120b — ~3000 tokens per second"
        )
    }
}
