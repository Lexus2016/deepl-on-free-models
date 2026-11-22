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

/// One paragraph-like run of text on a PDF page. The original page is kept as
/// the background; this rectangle is the only part that gets replaced.
struct PDFTextBlock: Sendable {
    let pageIndex: Int
    let bounds: CGRect
    let text: String
    let fontSize: CGFloat
    let isBold: Bool
    let fontName: String?
    let color: NSColor
    let alignment: NSTextAlignment
    let lineSpacing: CGFloat
}

struct PDFLayout: Sendable {
    let url: URL
    let pageCount: Int
    let blocks: [PDFTextBlock]
}

struct OpenedDocument: Sendable {
    let url: URL
    let kind: DocumentKind
    let sourceText: String?
    /// One entry per DOCX paragraph or PDF text block, used to align the
    /// translated lines back to the original document.
    let paragraphs: [String]
    let pdf: PDFLayout?

    var text: String { sourceText ?? paragraphs.joined(separator: "\n") }
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
            return L10n.t("No selectable text found. For a scanned PDF, run text recognition first.", language)
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
        try Task.checkCancellation()
        guard let kind = DocumentKind.from(url: url) else {
            throw DocumentError.unsupported
        }
        switch kind {
        case .text, .markdown:
            let text = try readText(url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentError.noText
            }
            return OpenedDocument(
                url: url, kind: kind, sourceText: text, paragraphs: [], pdf: nil
            )

        case .pdf:
            let layout = try readPDFLayout(url: url)
            return OpenedDocument(
                url: url,
                kind: kind,
                sourceText: nil,
                paragraphs: layout.blocks.map(\.text),
                pdf: layout
            )

        case .docx:
            let data = try unzipEntry("word/document.xml", from: url)
            let paragraphs = try paragraphs(fromDocumentXML: data)
            guard paragraphs.contains(where: { $0.contains(where: { !$0.isWhitespace }) }) else {
                throw DocumentError.noText
            }
            return OpenedDocument(
                url: url, kind: kind, sourceText: nil, paragraphs: paragraphs, pdf: nil
            )
        }
    }

    static func readText(_ url: URL) throws -> String {
        if let value = try? String(contentsOf: url, encoding: .utf8) { return value }
        if let value = try? String(contentsOf: url, encoding: .utf16) { return value }
        if let value = try? String(contentsOf: url, encoding: .isoLatin1) { return value }
        throw DocumentError.unreadable
    }

    static func textUnits(in text: String, markdown: Bool) -> [(text: String, translate: Bool)] {
        var units: [(String, Bool)] = []
        var cursor = text.startIndex
        var paragraphStart: String.Index?
        var paragraphEnd = text.startIndex
        var codeFence: (marker: Character, count: Int)?

        func flushParagraph() {
            guard let start = paragraphStart else { return }
            if cursor < start { units.append((String(text[cursor..<start]), false)) }
            units.append((String(text[start..<paragraphEnd]), true))
            cursor = paragraphEnd
            paragraphStart = nil
        }

        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let indentation = line.prefix(while: { $0 == " " }).count
            let content = line.dropFirst(indentation)
            if markdown, indentation <= 3, let mark = content.first, mark == "`" || mark == "~" {
                let count = content.prefix(while: { $0 == mark }).count
                let suffix = content.dropFirst(count)
                if let fence = codeFence {
                    if mark == fence.marker, count >= fence.count, suffix.allSatisfy(\.isWhitespace) {
                        codeFence = nil
                    }
                    continue
                } else if count >= 3, mark != "`" || !suffix.contains("`") {
                    flushParagraph()
                    codeFence = (mark, count)
                    continue
                }
            }
            guard codeFence == nil else { continue }
            if content.allSatisfy(\.isWhitespace) {
                flushParagraph()
            } else {
                if paragraphStart == nil { paragraphStart = line.startIndex }
                paragraphEnd = line.endIndex
            }
        }

        flushParagraph()
        if cursor < text.endIndex { units.append((String(text[cursor...]), false)) }
        return units
    }

    // MARK: - PDF reading

    static func readPDFLayout(url: URL) throws -> PDFLayout {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.unreadable
        }

        var blocks: [PDFTextBlock] = []
        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBox = page.bounds(for: .mediaBox)
            guard let selection = page.selection(for: pageBox) else { continue }

            let lines = selection.selectionsByLine().compactMap { line -> PDFLine? in
                let text = (line.string ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let bounds = line.bounds(for: page)
                guard bounds.width > 1, bounds.height > 1 else { return nil }

                var fontSize = bounds.height * 0.8
                var bold = false
                var fontName: String?
                var color = NSColor.black
                if let attributed = line.attributedString, attributed.length > 0 {
                    if let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                        fontSize = font.pointSize
                        bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                        fontName = font.fontName
                    }
                    if let value = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
                        color = value
                    }
                }
                return PDFLine(
                    text: text,
                    bounds: bounds,
                    fontSize: fontSize,
                    isBold: bold,
                    fontName: fontName,
                    color: color
                )
            }
            blocks.append(contentsOf: group(lines, pageIndex: pageIndex, pageBox: pageBox))
        }

        guard !blocks.isEmpty else { throw DocumentError.noText }
        return PDFLayout(url: url, pageCount: document.pageCount, blocks: blocks)
    }

    private struct PDFLine {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let fontName: String?
        let color: NSColor
    }

    /// Lines become paragraphs when the vertical gap is small, the font matches
    /// and the lines overlap horizontally. A side-by-side column does not
    /// overlap, so it starts its own block.
    private static func group(
        _ lines: [PDFLine],
        pageIndex: Int,
        pageBox: CGRect
    ) -> [PDFTextBlock] {
        let sorted = lines.sorted { first, second in
            if abs(first.bounds.maxY - second.bounds.maxY) > 1.5 {
                return first.bounds.maxY > second.bounds.maxY
            }
            return first.bounds.minX < second.bounds.minX
        }

        var groups: [[PDFLine]] = []
        for line in sorted {
            var target: Int?
            for (index, group) in groups.enumerated() {
                guard let previous = group.last,
                      previous.bounds.maxY > line.bounds.maxY,
                      sameBlock(previous, line) else { continue }
                target = index
            }
            if let target {
                groups[target].append(line)
            } else {
                groups.append([line])
            }
        }

        let ordered = groups.sorted { first, second in
            guard let a = first.first, let b = second.first else { return false }
            if abs(a.bounds.maxY - b.bounds.maxY) > 1.5 {
                return a.bounds.maxY > b.bounds.maxY
            }
            return a.bounds.minX < b.bounds.minX
        }

        return ordered.map { group in
            let bounds = group.dropFirst().reduce(group[0].bounds) { $0.union($1.bounds) }
            let first = group[0]

            var alignment = NSTextAlignment.left
            if bounds.width < pageBox.width * 0.75 {
                if abs(bounds.midX - pageBox.midX) < pageBox.width * 0.06 {
                    alignment = .center
                } else if bounds.maxX > pageBox.maxX - pageBox.width * 0.08 {
                    alignment = .right
                }
            }

            var spacing: CGFloat = 0
            if group.count > 1 {
                var gaps: [CGFloat] = []
                for index in 1..<group.count {
                    let gap = group[index - 1].bounds.minY - group[index].bounds.maxY
                    if gap > 0 { gaps.append(gap) }
                }
                if !gaps.isEmpty {
                    spacing = min(10, gaps.reduce(0, +) / CGFloat(gaps.count))
                }
            }

            return PDFTextBlock(
                pageIndex: pageIndex,
                bounds: bounds,
                text: group.map(\.text).joined(separator: " "),
                fontSize: group.map(\.fontSize).max() ?? 12,
                isBold: first.isBold,
                fontName: first.fontName,
                color: first.color,
                alignment: alignment,
                lineSpacing: spacing
            )
        }
    }

    private static func sameBlock(_ previous: PDFLine, _ line: PDFLine) -> Bool {
        guard abs(previous.fontSize - line.fontSize) < 1.5 else { return false }

        let height = max(previous.bounds.height, line.bounds.height)
        let gap = previous.bounds.minY - line.bounds.maxY
        guard gap <= max(2.5, height * 0.45), gap >= -height * 1.2 else { return false }

        let overlap = min(previous.bounds.maxX, line.bounds.maxX)
            - max(previous.bounds.minX, line.bounds.minX)
        let width = min(previous.bounds.width, line.bounds.width)
        guard width > 0 else { return true }
        return overlap >= width * 0.35
    }

    // MARK: - Write

    static func write(document: OpenedDocument, translated: String, to url: URL) throws {
        switch document.kind {
        case .text, .markdown:
            try translated.write(to: url, atomically: true, encoding: .utf8)

        case .pdf:
            guard let layout = document.pdf else { throw DocumentError.unreadable }
            try writePDF(layout: layout, translated: translated, to: url)

        case .docx:
            try writeDocx(
                original: document.url,
                paragraphs: document.paragraphs,
                translated: translated,
                to: url
            )
        }
    }

    static func write(document: OpenedDocument, translatedUnits: [String], to url: URL) throws {
        try Task.checkCancellation()
        switch document.kind {
        case .text, .markdown:
            try translatedUnits.joined().write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            guard let layout = document.pdf else { throw DocumentError.unreadable }
            try writePDF(layout: layout, lines: translatedUnits, to: url)
        case .docx:
            try writeDocx(original: document.url, lines: translatedUnits, to: url)
        }
    }

    /// Keeps the original page as the visual layer and paints the translation
    /// into the same rectangles. Images, charts, borders, fonts and page size
    /// stay untouched; only the text areas are covered and redrawn.
    static func writePDF(layout: PDFLayout, translated: String, to url: URL) throws {
        try writePDF(layout: layout, lines: align(translated, with: layout.blocks.map(\.text)), to: url)
    }

    private static func writePDF(layout: PDFLayout, lines: [String], to url: URL) throws {
        guard let document = PDFDocument(url: layout.url) else {
            throw DocumentError.unreadable
        }
        guard let firstPage = document.page(at: 0) else { throw DocumentError.unreadable }

        var mediaBox = firstPage.bounds(for: .mediaBox)
        try? FileManager.default.removeItem(at: url)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(
                  consumer: consumer,
                  mediaBox: &mediaBox,
                  [
                      kCGPDFContextTitle as String: layout.url.deletingPathExtension().lastPathComponent,
                      kCGPDFContextCreator as String: "DeepL-oFM"
                  ] as CFDictionary
              ) else {
            throw DocumentError.unreadable
        }

        let changedBlocks = layout.blocks.indices.filter {
            lines.indices.contains($0) && !lines[$0].isEmpty && lines[$0] != layout.blocks[$0].text
        }
        let blocksByPage = Dictionary(
            grouping: changedBlocks,
            by: { layout.blocks[$0].pageIndex }
        )

        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex) else { continue }
            let box = page.bounds(for: .mediaBox)
            let boxData = withUnsafeBytes(of: box) { Data($0) }
            context.beginPDFPage(
                [kCGPDFContextMediaBox as String: boxData] as CFDictionary
            )
            page.draw(with: .mediaBox, to: context)

            let changed = blocksByPage[pageIndex] ?? []
            let bitmap = changed.isEmpty ? nil : pageBitmap(page)
            for index in changed {
                let block = layout.blocks[index]
                guard index < lines.count else { continue }
                let translation = lines[index]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty, translation != block.text else { continue }

                let background = bitmap
                    .flatMap { sampledColor(around: block.bounds, in: $0, pageBox: box) }
                    ?? .white
                context.setFillColor(background.cgColor)
                context.fill(block.bounds.insetBy(dx: -2, dy: -1))
                draw(
                    translation,
                    in: block.bounds,
                    block: block,
                    background: background,
                    context: context
                )
            }
            context.endPDFPage()
        }
        context.closePDF()

        copyAnnotations(from: document, to: url)
    }

    /// Links and notes live outside the page content, so they are copied onto
    /// the new pages after the overlay is written.
    private static func copyAnnotations(from source: PDFDocument, to url: URL) {
        guard let target = PDFDocument(url: url) else { return }
        var copied = false
        for index in 0..<min(source.pageCount, target.pageCount) {
            guard let sourcePage = source.page(at: index),
                  let targetPage = target.page(at: index) else { continue }
            for annotation in sourcePage.annotations {
                guard let copy = annotation.copy() as? PDFAnnotation else { continue }
                targetPage.addAnnotation(copy)
                copied = true
            }
        }
        if copied {
            target.write(to: url)
        }
    }

    private static func pageBitmap(_ page: PDFPage) -> CGContext? {
        let box = page.bounds(for: .mediaBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return nil }
        let scale = min(2, 4096 / max(box.width, box.height),
                        (4_194_304 / box.width / box.height).squareRoot())
        let width = max(1, Int(box.width * scale))
        let height = max(1, Int(box.height * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: context)
        return context
    }

    private static func sampledColor(
        around bounds: CGRect,
        in context: CGContext,
        pageBox: CGRect
    ) -> NSColor? {
        let points = [
            CGPoint(x: bounds.minX - 4, y: bounds.midY),
            CGPoint(x: bounds.maxX + 4, y: bounds.midY),
            CGPoint(x: bounds.midX, y: bounds.maxY + 4),
            CGPoint(x: bounds.midX, y: bounds.minY - 4)
        ].filter { pageBox.contains($0) }

        guard !points.isEmpty, let data = context.data else { return nil }
        let scaleX = CGFloat(context.width) / pageBox.width
        let scaleY = CGFloat(context.height) / pageBox.height
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var samples: [(Int, Int, Int)] = []

        for point in points {
            let x = Int((point.x - pageBox.minX) * scaleX)
            let y = Int((point.y - pageBox.minY) * scaleY)
            guard x >= 0, x < context.width, y >= 0, y < context.height else { continue }
            let offset = y * context.bytesPerRow + x * 4
            samples.append((
                Int(bytes[offset]),
                Int(bytes[offset + 1]),
                Int(bytes[offset + 2])
            ))
        }
        guard !samples.isEmpty else { return nil }

        let red = samples.map(\.0).reduce(0, +) / samples.count
        let green = samples.map(\.1).reduce(0, +) / samples.count
        let blue = samples.map(\.2).reduce(0, +) / samples.count
        return NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        block: PDFTextBlock,
        background: NSColor,
        context: CGContext
    ) {
        let original = block.color.usingColorSpace(.sRGB) ?? .black
        let color: NSColor
        if abs(luminance(original) - luminance(background)) > 0.25 {
            color = original
        } else {
            color = luminance(background) < 0.55 ? .white : .black
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = block.alignment
        paragraph.lineSpacing = block.lineSpacing

        var size = max(4.5, block.fontSize)
        while size >= 4.5 {
            let font = resolvedFont(
                name: block.fontName,
                bold: block.isBold,
                size: size,
                text: text
            )
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: 0),
                nil,
                CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                nil
            )
            if suggested.height <= rect.height + 1.5 || size <= 4.6 {
                let path = CGPath(rect: rect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: 0, length: 0),
                    path,
                    nil
                )
                CTFrameDraw(frame, context)
                return
            }
            size -= 0.5
        }
    }

    /// Keeps the original typeface when it has glyphs for the translation;
    /// otherwise falls back to the system font, which covers every script the
    /// app supports.
    private static func resolvedFont(
        name: String?,
        bold: Bool,
        size: CGFloat,
        text: String
    ) -> NSFont {
        if let name, let original = NSFont(name: name, size: size),
           supports(original, text: text) {
            return original
        }
        return bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
    }

    private static func supports(_ font: NSFont, text: String) -> Bool {
        let characters = Array(text.utf16)
        guard !characters.isEmpty else { return true }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let ctFont = font as CTFont
        return characters.withUnsafeBufferPointer { buffer in
            glyphs.withUnsafeMutableBufferPointer { output in
                guard let chars = buffer.baseAddress, let glyphs = output.baseAddress else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(ctFont, chars, glyphs, characters.count)
            }
        }
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 1 }
        return 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
    }

    // MARK: - DOCX

    /// Only `word/document.xml` is replaced inside the existing archive. Every
    /// other entry — styles, media, fonts, headers — stays byte-for-byte as it
    /// was, so the document keeps its layout and visual identity.
    static func writeDocx(
        original: URL,
        paragraphs: [String],
        translated: String,
        to url: URL
    ) throws {
        try writeDocx(original: original, lines: align(translated, with: paragraphs), to: url)
    }

    private static func writeDocx(original: URL, lines: [String], to url: URL) throws {
        let xml = try unzipEntry("word/document.xml", from: original)
        try Task.checkCancellation()
        let updated = try replacingParagraphs(in: xml, with: lines)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepL-oFM-docx-\(UUID().uuidString)", isDirectory: true)
        let word = directory.appendingPathComponent("word", isDirectory: true)
        try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try updated.write(
            to: word.appendingPathComponent("document.xml"),
            options: .atomic
        )

        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: original, to: url)
        try run("/usr/bin/zip", ["-q", "-X", url.path, "word/document.xml"], in: directory)
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
        let xml = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard let root = xml.rootElement() else { throw DocumentError.docxFailed }
        return elements(named: "p", in: root).map { paragraphText($0) }
    }

    static func replacingParagraphs(in data: Data, with lines: [String]) throws -> Data {
        let xml = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
        guard let root = xml.rootElement() else { throw DocumentError.docxFailed }
        let paragraphs = elements(named: "p", in: root)

        for (index, paragraph) in paragraphs.enumerated() {
            try Task.checkCancellation()
            guard index < lines.count else { break }
            let texts = elements(named: "t", in: paragraph)
            guard !texts.isEmpty, lines[index] != paragraphText(paragraph) else { continue }
            let weights = texts.map { $0.stringValue?.count ?? 0 }
            let weight = weights.reduce(0, +)
            let line = lines[index]
            let length = line.count
            var position = line.startIndex
            var offset = 0
            var consumedWeight = 0

            for (run, count) in zip(texts, weights) {
                consumedWeight += count
                let endOffset = weight > 0 ? length * consumedWeight / weight : length
                let end = line.index(position, offsetBy: endOffset - offset)
                let fragment = String(line[position..<end])
                run.stringValue = fragment
                if fragment.first?.isWhitespace == true || fragment.last?.isWhitespace == true {
                    if let attribute = run.attribute(forName: "xml:space") {
                        attribute.stringValue = "preserve"
                    } else if let attribute = XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as? XMLNode {
                        run.addAttribute(attribute)
                    }
                }
                position = end
                offset = endOffset
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

    private static func unzipEntry(_ entry: String, from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let handle = output.fileHandleForReading
        defer { try? handle.close() }
        var data = Data()
        do {
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                guard data.count + chunk.count <= 32 * 1024 * 1024 else { throw DocumentError.docxFailed }
                data.append(chunk)
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw DocumentError.docxFailed
        }
        return data
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocumentError.docxFailed
        }
    }
}
