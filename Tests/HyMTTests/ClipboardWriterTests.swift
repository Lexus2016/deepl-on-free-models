import XCTest
@testable import HyMT

final class ClipboardWriterTests: XCTestCase {
    func testMarkdownRendersHTML() {
        let markdown = """
        # Heading

        **Bold** and [link](https://example.com)

        - one
        - two
        """
        let html = ClipboardWriter.renderHTML(markdown)
        XCTAssertTrue(html.contains("<h1>Heading</h1>"))
        XCTAssertTrue(html.contains("<strong>Bold</strong>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">link</a>"))
        XCTAssertTrue(html.contains("<ul><li>one</li><li>two</li></ul>"))
    }

    func testParagraphBreaksArePreserved() {
        let html = ClipboardWriter.renderHTML("First line\nSecond line\n\nNext paragraph")
        XCTAssertTrue(html.contains("First line<br>Second line"))
        XCTAssertTrue(html.contains("<p>&nbsp;</p>"))
        XCTAssertTrue(html.contains("Next paragraph"))
    }

    func testOrderedListKeepsItsStart() {
        let html = ClipboardWriter.renderHTML("3. three\n4. four")
        XCTAssertTrue(html.contains("<ol start=\"3\"><li>three</li><li>four</li></ol>"))
    }

    func testUnsafeLinkSchemeIsDropped() {
        let html = ClipboardWriter.renderHTML("[click](javascript:alert(1))")
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("click"))
    }

    func testBlockquoteIsRendered() {
        let html = ClipboardWriter.renderHTML("> quoted **text**")
        XCTAssertTrue(html.contains("<blockquote><p>quoted <strong>text</strong></p></blockquote>"))
    }
}
