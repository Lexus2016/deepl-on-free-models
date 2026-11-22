import AppKit
import XCTest
@testable import HyMT

final class MarkdownRendererTests: XCTestCase {
    func testParagraphsAreSeparated() {
        let rendered = MarkdownRenderer.render("First paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(rendered.string, "First paragraph.\nSecond paragraph.")
    }

    func testHeadingIsLargerAndBold() throws {
        let rendered = MarkdownRenderer.render("## Heading\n\nBody")
        let ns = rendered.string as NSString
        let headingRange = ns.range(of: "Heading")
        let bodyRange = ns.range(of: "Body")
        let headingFont = try XCTUnwrap(
            rendered.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        )
        let bodyFont = try XCTUnwrap(
            rendered.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize)
        XCTAssertTrue(headingFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testListsUseMarkers() {
        let rendered = MarkdownRenderer.render("- One\n- Two\n\n1. First\n2. Second")
        XCTAssertTrue(rendered.string.contains("•\tOne"))
        XCTAssertTrue(rendered.string.contains("•\tTwo"))
        XCTAssertTrue(rendered.string.contains("1.\tFirst"))
        XCTAssertTrue(rendered.string.contains("2.\tSecond"))
    }

    func testBoldItalicAndInlineCode() throws {
        let rendered = MarkdownRenderer.render("A **bold** and *italic* with `code`.")
        let ns = rendered.string as NSString

        let boldRange = ns.range(of: "bold")
        let boldFont = try XCTUnwrap(
            rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

        let italicRange = ns.range(of: "italic")
        let italicFont = try XCTUnwrap(
            rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(italicFont.fontDescriptor.symbolicTraits.contains(.italic))

        let codeRange = ns.range(of: "code")
        let codeFont = try XCTUnwrap(
            rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testLinkKeepsURL() throws {
        let rendered = MarkdownRenderer.render("Read [the guide](https://example.com/docs) now.")
        let ns = rendered.string as NSString
        let linkRange = ns.range(of: "the guide")
        let url = try XCTUnwrap(
            rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL
        )
        XCTAssertEqual(url.absoluteString, "https://example.com/docs")
    }

    func testCodeBlockIsMonospaced() throws {
        let rendered = MarkdownRenderer.render("```\nlet x = 1\nlet y = 2\n```")
        let ns = rendered.string as NSString
        let range = ns.range(of: "let x")
        let font = try XCTUnwrap(
            rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertFalse(rendered.string.hasSuffix("\n"))
    }

    func testPlainTextSurvives() {
        let rendered = MarkdownRenderer.render("Just plain text without markers.")
        XCTAssertEqual(rendered.string, "Just plain text without markers.")
    }

    func testPlainTextStripsMarkup() {
        let plain = MarkdownRenderer.plainText(
            "## Title\n\nA **bold** and *italic* with `code` and [link](https://example.com)."
        )
        XCTAssertEqual(plain, "Title\n\nA bold and italic with code and link.")
    }

    func testPlainTextKeepsListStructure() {
        let plain = MarkdownRenderer.plainText("- One\n- Two\n\n1. First\n\n```\nlet x = 1\n```")
        XCTAssertEqual(plain, "• One\n• Two\n1. First\n\nlet x = 1")
    }

    func testPlainTextDropsLinkTarget() {
        let plain = MarkdownRenderer.plainText("Read [the guide](https://example.com/docs) now.")
        XCTAssertEqual(plain, "Read the guide now.")
    }
}
