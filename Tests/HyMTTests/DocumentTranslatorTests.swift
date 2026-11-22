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

    func testPDFOverlayKeepsGraphicsAndAddsTranslation() throws {
        let source = workDirectory.appendingPathComponent("source.pdf")
        try makePDF(text: "Hello world", to: source)

        let document = try DocumentTranslator.read(url: source)
        XCTAssertEqual(document.kind, .pdf)
        XCTAssertTrue(document.text.contains("Hello world"))

        let output = workDirectory.appendingPathComponent("translated.pdf")
        try DocumentTranslator.write(
            document: document,
            translated: "Привіт світе",
            to: output
        )

        let translated = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(translated.pageCount, 1)
        XCTAssertTrue((translated.string ?? "").contains("Привіт світе"))

        // The red rectangle from the original page must survive the overlay.
        let page = try XCTUnwrap(translated.page(at: 0))
        let image = page.thumbnail(of: NSSize(width: 400, height: 300), for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
        let red = try XCTUnwrap(bitmap.colorAt(x: 30, y: 270))
        XCTAssertGreaterThan(red.redComponent, 0.7)
        XCTAssertGreaterThan(red.redComponent - red.greenComponent, 0.4)
    }

    private func makePDF(text: String, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(
            CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        )
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 10, y: 10, width: 50, height: 50))

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 50, y: 150, width: 300, height: 100),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
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

    func testDocxUpdateKeepsOtherPackageEntries() throws {
        let package = workDirectory.appendingPathComponent("package", isDirectory: true)
        let word = package.appendingPathComponent("word", isDirectory: true)
        let media = word.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

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
        let imageBytes = Data((0..<512).map { UInt8($0 % 251) })
        try imageBytes.write(to: media.appendingPathComponent("image1.bin"))

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
        XCTAssertEqual(
            try unzipEntry("word/media/image1.bin", from: output),
            imageBytes
        )
    }

    private func unzipEntry(_ entry: String, from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return data
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
