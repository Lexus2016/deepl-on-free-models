import AppKit
import CoreText
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// File types the app can open, translate and write back.
enum DocumentKind: String, Sendable {
    case text
    case markdown
    case pdf
    case docx

    static func from(url: URL) -> DocumentKind? {
        switch url.pathExtension.lowercased() {
        case "txt", "text": return .text
        case "md", "markdown", "mdown": return .markdown
        case "pdf": return .pdf
        case "docx": return .docx
        default: return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .docx: return "docx"
        }
    }

    var contentType: UTType? {
        switch self {
        case .text: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .pdf: return .pdf
        case .docx: return UTType(filenameExtension: "docx")
        }
    }
}

/// A DOCX is a zip package; the extracted directory is kept so the translated
/// `document.xml` can be written back without touching images, styles or
/// headers.
struct DocxPackage {
    let directory: URL
}

struct OpenedDocument {
    let url: URL
    let kind: DocumentKind
    let text: String
    /// DOCX only: the original paragraph texts, one per `<w:p>`, used to align
    /// the translated lines back into the XML.
    let paragraphs: [String]
    let docx: DocxPackage?
}

enum DocumentError: Error {
    case unsupported
    case unreadable
    case noText
    case docxFailed

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .unsupported:
            return L10n.t("This file type is not supported.", language)
        case .unreadable:
            return L10n.t("The file could not be read.", language)
        case .noText:
            return L10n.t("The document contains no text. Scanned PDFs need OCR first.", language)
        case .docxFailed:
            return L10n.t("The Word document could not be processed.", language)
        }
    }
}

enum DocumentTranslator {

    static var supportedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let docx = UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }

    // MARK: - Read

    static func read(url: URL) throws -> OpenedDocument {
        guard let kind = DocumentKind.from(url: url) else {
            throw DocumentError.unsupported
        }
        switch kind {
        case .text, .markdown:
            let text = try readText(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentError.noText
            }
            return OpenedDocument(url: url, kind: kind, text: text, paragraphs: [], docx: nil)

        case .pdf:
            let text = try readPDF(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentError.noText
            }
            return OpenedDocument(url: url, kind: kind, text: text, paragraphs: [], docx: nil)

        case .docx:
            let package = try unzip(url)
            do {
                let xmlURL = package.directory.appendingPathComponent("word/document.xml")
                guard let data = try? Data(contentsOf: xmlURL) else {
                    throw DocumentError.docxFailed
                }
                let paragraphs = try paragraphs(fromDocumentXML: data)
                let text = paragraphs.joined(separator: "\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DocumentError.noText
                }
                return OpenedDocument(
                    url: url,
                    kind: kind,
                    text: text,
                    paragraphs: paragraphs,
                    docx: package
                )
            } catch {
                discard(package)
                throw error
            }
        }
    }

    static func discard(_ package: DocxPackage) {
        try? FileManager.default.removeItem(at: package.directory)
    }

    static func readText(_ url: URL) throws -> String {
        if let value = try? String(contentsOf: url, encoding: .utf8) { return value }
        if let value = try? String(contentsOf: url, encoding: .utf16) { return value }
        if let value = try? String(contentsOf: url, encoding: .isoLatin1) { return value }
        throw DocumentError.unreadable
    }

    static func readPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.unreadable
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            pages.append(document.page(at: index)?.string ?? "")
        }
        return reflow(pages.joined(separator: "\n\n"))
    }

    /// PDF text arrives with a line break at every visual line. Joining lines
    /// back into paragraphs gives the translator whole sentences instead of
    /// fragments; blank lines and page breaks remain paragraph boundaries.
    static func reflow(_ text: String) -> String {
        var paragraphs: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { paragraphs.append(trimmed) }
            current = ""
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-") {
                // A word split across lines: glue it back together.
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    // MARK: - Write

    static func write(document: OpenedDocument, translated: String, to url: URL) throws {
        switch document.kind {
        case .text, .markdown:
            try translated.write(to: url, atomically: true, encoding: .utf8)

        case .pdf:
            try writePDF(translated, to: url)

        case .docx:
            guard let package = document.docx else {
                throw DocumentError.docxFailed
            }
            try writeDocx(
                package: package,
                translated: translated,
                sourceParagraphs: document.paragraphs,
                to: url
            )
        }
    }

    /// A clean reflowed PDF: A4, vector text, one paragraph after another. The
    /// original layout is not reproduced — a rebuilt page keeps the text
    /// selectable and readable.
    static func writePDF(_ text: String, to url: URL) throws {
        guard !text.isEmpty else { throw DocumentError.noText }

        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentError.unreadable
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 7
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = mediaBox.insetBy(dx: 56, dy: 56)
        var location = 0

        while location < attributed.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { break }
            location += visible.length
        }
        context.closePDF()
    }

    // MARK: - DOCX package

    static func writeDocx(
        package: DocxPackage,
        translated: String,
        sourceParagraphs: [String],
        to url: URL
    ) throws {
        let xmlURL = package.directory.appendingPathComponent("word/document.xml")
        let data = try Data(contentsOf: xmlURL)
        let lines = align(translated, with: sourceParagraphs)
        let updated = try replacingParagraphs(in: data, with: lines)
        try updated.write(to: xmlURL, options: .atomic)

        try? FileManager.default.removeItem(at: url)
        let contents = try FileManager.default
            .contentsOfDirectory(atPath: package.directory.path)
            .filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        try run(
            "/usr/bin/zip",
            ["-q", "-r", "-X", url.path] + contents,
            in: package.directory
        )
    }

    /// The translator keeps the line structure, so paragraph i maps to line i.
    /// If the model changed blank lines, non-empty lines are matched to the
    /// non-empty paragraphs instead; the rest keeps its original text.
    static func align(_ translated: String, with source: [String]) -> [String] {
        let lines = translated.components(separatedBy: "\n")
        if lines.count == source.count { return lines }

        var result = source
        let sourceIndexes = source.indices.filter {
            !source[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        let translatedLines = lines.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        for (position, index) in sourceIndexes.enumerated() where position < translatedLines.count {
            result[index] = translatedLines[position]
        }
        return result
    }

    // MARK: - DOCX XML

    private static let wordNamespace =
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    static func paragraphs(fromDocumentXML data: Data) throws -> [String] {
        let xml = try XMLDocument(data: data, options: [.nodePreserveAll])
        guard let root = xml.rootElement() else { throw DocumentError.docxFailed }
        return elements(named: "p", in: root).map { paragraphText($0) }
    }

    static func replacingParagraphs(in data: Data, with lines: [String]) throws -> Data {
        let xml = try XMLDocument(data: data, options: [.nodePreserveAll])
        guard let root = xml.rootElement() else { throw DocumentError.docxFailed }
        let paragraphs = elements(named: "p", in: root)

        for (index, paragraph) in paragraphs.enumerated() {
            guard index < lines.count else { break }
            let texts = elements(named: "t", in: paragraph)
            guard let first = texts.first else { continue }
            first.stringValue = lines[index]
            for extra in texts.dropFirst() {
                extra.stringValue = ""
            }
        }
        return xml.xmlData(options: [])
    }

    private static func elements(named name: String, in element: XMLElement) -> [XMLElement] {
        var result: [XMLElement] = []
        for child in element.children ?? [] {
            guard let child = child as? XMLElement else { continue }
            if child.localName == name, child.uri == wordNamespace {
                result.append(child)
            }
            result.append(contentsOf: elements(named: name, in: child))
        }
        return result
    }

    /// All visible text of one paragraph, including runs inside hyperlinks and
    /// smart tags. Tabs and manual breaks become spaces.
    private static func paragraphText(_ paragraph: XMLElement) -> String {
        var result = ""
        for child in paragraph.children ?? [] {
            guard let child = child as? XMLElement else { continue }
            if child.localName == "t", child.uri == wordNamespace {
                result += child.stringValue ?? ""
            } else if child.localName == "tab"
                        || child.localName == "br"
                        || child.localName == "cr" {
                result += " "
            } else {
                result += paragraphText(child)
            }
        }
        return result
    }

    // MARK: - Zip

    private static func unzip(_ url: URL) throws -> DocxPackage {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepL-oFM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        do {
            try run("/usr/bin/unzip", ["-q", "-o", url.path, "-d", directory.path])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw DocumentError.docxFailed
        }
        return DocxPackage(directory: directory)
    }

    private static func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocumentError.docxFailed
        }
    }
}
