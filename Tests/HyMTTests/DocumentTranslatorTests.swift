import XCTest
import PDFKit
@testable import HyMT

final class DocumentTranslatorTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentTranslatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    func testTextFileRoundTrip() throws {
        let url = workDirectory.appendingPathComponent("note.txt")
        try "Hello\nWorld".write(to: url, atomically: true, encoding: .utf8)

        let document = try DocumentTranslator.read(url: url)
        XCTAssertEqual(document.kind, .text)
        XCTAssertEqual(document.text, "Hello\nWorld")

        let output = workDirectory.appendingPathComponent("note-uk.txt")
        try DocumentTranslator.write(document: document, translated: "Привіт\nСвіт", to: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "Привіт\nСвіт")
    }

    func testMarkdownFileKeepsMarkup() throws {
        let url = workDirectory.appendingPathComponent("page.md")
        try "# Title\n\n- One\n- Two".write(to: url, atomically: true, encoding: .utf8)
        let document = try DocumentTranslator.read(url: url)
        XCTAssertEqual(document.kind, .markdown)
        XCTAssertEqual(document.text, "# Title\n\n- One\n- Two")
    }

    func testReflowJoinsWrappedLines() {
        let text = "A native macOS\ntranslator keeps paragraphs\n\ntogether.\n\nSecond paragraph."
        XCTAssertEqual(
            DocumentTranslator.reflow(text),
            "A native macOS translator keeps paragraphs\n\ntogether.\n\nSecond paragraph."
        )
    }

    func testPDFWriteAndRead() throws {
        let url = workDirectory.appendingPathComponent("translated.pdf")
        try DocumentTranslator.writePDF("Перекладений текст для перевірки.", to: url)

        let document = try DocumentTranslator.read(url: url)
        XCTAssertEqual(document.kind, .pdf)
        XCTAssertTrue(document.text.contains("Перекладений текст"))
    }

    func testDocxParagraphsAndReplacement() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello </w:t></w:r><w:r><w:t>world</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let data = try XCTUnwrap(xml.data(using: .utf8))

        let paragraphs = try DocumentTranslator.paragraphs(fromDocumentXML: data)
        XCTAssertEqual(paragraphs, ["Hello world", "Second"])

        let updated = try DocumentTranslator.replacingParagraphs(
            in: data,
            with: ["Привіт світ", "Другий"]
        )
        XCTAssertEqual(
            try DocumentTranslator.paragraphs(fromDocumentXML: updated),
            ["Привіт світ", "Другий"]
        )
    }

    func testDocxPackageRoundTrip() throws {
        let package = workDirectory.appendingPathComponent("package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Hello</w:t></w:r></w:p>
            <w:p><w:r><w:t>World</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        try documentXML.write(
            to: word.appendingPathComponent("document.xml"),
            atomically: true,
            encoding: .utf8
        )
        let types = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        try types.write(
            to: package.appendingPathComponent("[Content_Types].xml"),
            atomically: true,
            encoding: .utf8
        )

        let docxURL = workDirectory.appendingPathComponent("sample.docx")
        try zip(package, to: docxURL)

        let document = try DocumentTranslator.read(url: docxURL)
        XCTAssertEqual(document.kind, .docx)
        XCTAssertEqual(document.text, "Hello\nWorld")

        let output = workDirectory.appendingPathComponent("sample-uk.docx")
        try DocumentTranslator.write(
            document: document,
            translated: "Привіт\nСвіт",
            to: output
        )

        let translated = try DocumentTranslator.read(url: output)
        XCTAssertEqual(translated.text, "Привіт\nСвіт")
    }

    func testAlignmentFallsBackToNonEmptyLines() {
        let aligned = DocumentTranslator.align(
            "Uno\n\nDos",
            with: ["One", "", "Two"]
        )
        XCTAssertEqual(aligned, ["Uno", "", "Dos"])
    }

    private func zip(_ directory: URL, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = [
            "-q", "-r", "-X", url.path,
            "[Content_Types].xml", "word"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
