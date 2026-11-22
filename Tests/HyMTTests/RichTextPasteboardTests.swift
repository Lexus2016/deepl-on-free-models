import AppKit
import XCTest
@testable import HyMT

final class AttributedMarkdownTests: XCTestCase {
    private func markdown(fromHTML html: String) throws -> String? {
        let data = try XCTUnwrap(html.data(using: .utf8))
        let attributed = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        return AttributedMarkdown.convert(attributed)
    }

    func testHeadingsParagraphsAndListsSurvive() throws {
        let markdown = try markdown(fromHTML: """
        <h1>Title</h1>
        <h2>Section</h2>
        <p>Body with <strong>bold</strong> and <em>italic</em>.</p>
        <ul><li>One</li><li>Two</li></ul>
        <ol><li>First</li><li>Second</li></ol>
        """)
        XCTAssertEqual(markdown, """
        # Title

        ## Section

        Body with **bold** and *italic*.

        - One
        - Two

        1. First
        2. Second
        """)
    }

    func testLinksAndInlineCodeAreConverted() throws {
        let markdown = try markdown(fromHTML: """
        <p>Read <a href="https://example.com/docs">the docs</a> or call <code>run()</code>.</p>
        """)
        XCTAssertEqual(markdown, "Read [the docs](https://example.com/docs) or call `run()`.")
    }

    func testCodeBlockIsFenced() throws {
        let markdown = try markdown(fromHTML: """
        <p>Example:</p>
        <pre><code>let x = 1
        let y = 2</code></pre>
        """)
        XCTAssertEqual(markdown, "Example:\n\n```\nlet x = 1\nlet y = 2\n```")
    }

    func testPlainTextAsterisksAreEscaped() throws {
        let markdown = try markdown(fromHTML: "<p>2 * 3 = 6 and snake_case</p>")
        XCTAssertEqual(markdown, "2 \\* 3 = 6 and snake\\_case")
    }

    func testPlainClipboardFallsBackToString() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("Plain text", forType: .string)
        XCTAssertEqual(RichTextPasteboard.markdown(from: pasteboard), "Plain text")
    }

    func testHTMLClipboardBecomesMarkdown() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("<h2>Title</h2><p>Body</p>", forType: .html)
        pasteboard.setString("Title\nBody", forType: .string)
        XCTAssertEqual(RichTextPasteboard.markdown(from: pasteboard), "## Title\n\nBody")
    }

    @MainActor
    func testEditorPasteInsertsMarkdown() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("<h1>Title</h1><p>Body</p>", forType: .html)
        pasteboard.setString("Title\nBody", forType: .string)

        let textView = SourceTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        textView.isRichText = false
        textView.string = ""
        textView.paste(nil)

        XCTAssertEqual(textView.string, "# Title\n\nBody")
    }
}
