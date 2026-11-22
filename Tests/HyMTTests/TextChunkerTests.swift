import XCTest
@testable import HyMT

final class TextChunkerTests: XCTestCase {
    func testBlankLineIsPreserved() {
        let chunks = TextChunker.chunks(from: "One\n\nTwo")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, "One")
        XCTAssertEqual(chunks[0].separatorBefore, "")
        XCTAssertEqual(chunks[1].text, "Two")
        XCTAssertEqual(chunks[1].separatorBefore, "\n\n")
    }

    func testSingleLineBreak() {
        let chunks = TextChunker.chunks(from: "One\nTwo")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[1].separatorBefore, "\n")
    }

    func testMultipleBlankLines() {
        let chunks = TextChunker.chunks(from: "One\n\n\nTwo")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[1].separatorBefore, "\n\n\n")
    }

    func testTrailingBlankLinesIgnored() {
        let chunks = TextChunker.chunks(from: "One\n\n")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "One")
    }

    func testLongLineSplitsIntoPieces() {
        let line = String(repeating: "word ", count: 800)
        let chunks = TextChunker.chunks(from: line)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.dropFirst().first?.separatorBefore, " ")
    }

    func testWindowsLineEndingsAreNormalized() {
        let chunks = TextChunker.chunks(from: "One\r\n\r\nTwo\r\nThree")
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].text, "One")
        XCTAssertEqual(chunks[1].separatorBefore, "\n\n")
        XCTAssertEqual(chunks[2].separatorBefore, "\n")
        XCTAssertFalse(chunks.contains { $0.text.contains("\r") })
    }

    func testSentenceSplitter() {
        let sentences = TextChunker.sentences(
            from: "First sentence. Second sentence! Third one?"
        )
        XCTAssertEqual(sentences, ["First sentence.", "Second sentence!", "Third one?"])
    }
}
