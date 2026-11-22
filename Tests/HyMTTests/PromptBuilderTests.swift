import XCTest
@testable import HyMT

final class PromptBuilderTests: XCTestCase {
    func testAutoStandardInstruction() {
        let prompt = PromptBuilder.instruction(style: .auto, tone: .standard, targetLanguage: "Ukrainian")
        XCTAssertTrue(prompt.contains("into Ukrainian"))
        XCTAssertTrue(prompt.contains("only output the translated result"))
        XCTAssertFalse(prompt.contains("[literal"))
    }

    func testLiteralDescriptor() {
        let prompt = PromptBuilder.instruction(style: .literal, tone: .standard, targetLanguage: "English")
        XCTAssertTrue(prompt.contains("[literal, word for word]"))
    }

    func testNaturalFormalDescriptor() {
        let prompt = PromptBuilder.instruction(style: .natural, tone: .formal, targetLanguage: "English")
        XCTAssertTrue(prompt.contains("natural and idiomatic"))
        XCTAssertTrue(prompt.contains("formal and professional"))
    }

    func testCasualDescriptor() {
        let prompt = PromptBuilder.instruction(style: .auto, tone: .casual, targetLanguage: "English")
        XCTAssertTrue(prompt.contains("casual and conversational"))
    }

    func testMarkdownClauseComesBeforeTheFinalColon() throws {
        let prompt = PromptBuilder.instruction(
            style: .auto,
            tone: .standard,
            targetLanguage: "English",
            preserveMarkdown: true
        )
        let clause = try XCTUnwrap(prompt.range(of: "Preserve Markdown syntax"))
        let colon = try XCTUnwrap(prompt.range(of: ":", options: .backwards))
        XCTAssertLessThan(clause.lowerBound, colon.lowerBound)
    }

    func testNoMarkdownClauseForPlainText() {
        let prompt = PromptBuilder.instruction(
            style: .auto,
            tone: .standard,
            targetLanguage: "English",
            preserveMarkdown: false
        )
        XCTAssertFalse(prompt.contains("Preserve Markdown"))
    }

    func testHeadingPromptKeepsTheClauseBeforeTheColon() {
        let prompt = PromptBuilder.headingPrompt(
            text: "About",
            style: .auto,
            tone: .standard,
            targetLanguage: "Ukrainian",
            preserveMarkdown: true
        )
        XCTAssertTrue(prompt.hasPrefix("Translate this heading into Ukrainian."))
        XCTAssertTrue(prompt.contains("Preserve Markdown syntax"))
        XCTAssertTrue(prompt.hasSuffix("\n\nAbout"))
    }

    func testPreviewIncludesTheSample() {
        let preview = PromptBuilder.preview(
            style: .auto,
            tone: .standard,
            targetLanguage: "English",
            sample: "Зразок"
        )
        XCTAssertTrue(preview.hasSuffix("\n\nЗразок"))
    }

    func testPlainPromptIsStyleFree() {
        let prompt = PromptBuilder.plainPrompt(text: "Hello.", targetLanguage: "Ukrainian")
        XCTAssertTrue(prompt.hasPrefix("Translate the following text into Ukrainian."))
        XCTAssertTrue(prompt.contains("Output only the translated text"))
        XCTAssertFalse(prompt.contains("[literal"))
        XCTAssertTrue(prompt.hasSuffix("\n\nHello."))
    }
}
