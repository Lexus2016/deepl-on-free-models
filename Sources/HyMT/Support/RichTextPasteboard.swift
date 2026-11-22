import AppKit
import Foundation

/// Converts rich text on the pasteboard into Markdown. Copying a page in a
/// browser puts HTML on the pasteboard and a word processor puts RTF there;
/// without this the app would receive plain text only and the headings, lists,
/// links and emphasis would be lost before translation.
enum RichTextPasteboard {

    /// Markdown for the current clipboard content, or the plain string when
    /// the clipboard has no usable rich flavour.
    static func markdown(from pasteboard: NSPasteboard = .general) -> String? {
        let plain = pasteboard.string(forType: .string)
        let converted: String?
        if let html = pasteboard.string(forType: .html), html.utf8.count <= 8_000_000 {
            converted = markdown(fromHTML: html)
        } else if let data = pasteboard.data(forType: .rtf), data.count <= 8_000_000 {
            converted = markdown(fromRTF: data)
        } else {
            converted = nil
        }

        guard let converted, !converted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return plain
        }
        return converted
    }

    private static func markdown(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else { return nil }
        return AttributedMarkdown.convert(attributed)
    }

    private static func markdown(fromRTF data: Data) -> String? {
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }
        return AttributedMarkdown.convert(attributed)
    }
}

/// Best-effort NSAttributedString → Markdown. AppKit has no exporter, so the
/// structure is recovered from what the HTML/RTF importer leaves behind:
/// heading sizes, list paragraph styles, monospaced runs and link attributes.
enum AttributedMarkdown {

    // MARK: - Blocks

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String, ordered: Bool)
        case code(String)
    }

    static func convert(_ attributed: NSAttributedString) -> String? {
        guard attributed.length > 0,
              attributed.string.contains(where: { !$0.isWhitespace }) else {
            return nil
        }

        let bodySize = bodyFontSize(in: attributed)
        let string = attributed.string as NSString
        var blocks: [Block] = []
        var index = 0

        while index < string.length {
            let range = string.paragraphRange(for: NSRange(location: index, length: 0))
            let paragraph = attributed.attributedSubstring(from: range)
            index = max(range.upperBound, index + 1)
            if let block = block(from: paragraph, bodySize: bodySize) {
                blocks.append(block)
            }
        }

        guard !blocks.isEmpty else { return nil }
        return render(blocks)
    }

    /// Body size is the most common size among non-bold runs: headings are
    /// bold, so counting them would make a heading-only fragment look like
    /// body text and lose its level.
    private static func bodyFontSize(in attributed: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard let font = value as? NSFont, !isBold(font) else { return }
            let text = (attributed.string as NSString).substring(with: range)
            weights[font.pointSize, default: 0] += text.count
        }
        return weights.max { $0.value < $1.value }?.key ?? 12
    }

    private static func block(from paragraph: NSAttributedString, bodySize: CGFloat) -> Block? {
        guard paragraph.length > 0 else { return nil }
        let attributes = paragraph.attributes(at: 0, effectiveRange: nil)
        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        let font = attributes[.font] as? NSFont

        if let list = style?.textLists.first {
            guard let item = listItem(from: paragraph, list: list, style: style) else { return nil }
            return .listItem(item.text, ordered: item.ordered)
        }

        if isMonospaced(font) {
            let code = paragraph.string
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .newlines)
            guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return .code(code)
        }

        // HTML headings survive the import only as a larger bold font.
        if let font, isBold(font), font.pointSize >= bodySize * 1.12 {
            let level: Int
            if font.pointSize >= bodySize * 1.62 {
                level = 1
            } else if font.pointSize >= bodySize * 1.35 {
                level = 2
            } else {
                level = 3
            }
            let text = inlineMarkdown(paragraph, suppressBold: true)
            guard !text.isEmpty else { return nil }
            return .heading(level: level, text: text)
        }

        let text = inlineMarkdown(paragraph)
        guard !text.isEmpty else { return nil }
        return .paragraph(escapeLineStart(text))
    }

    private static func listItem(
        from paragraph: NSAttributedString,
        list: NSTextList,
        style: NSParagraphStyle?
    ) -> (text: String, ordered: Bool)? {
        let raw = paragraph.string.replacingOccurrences(of: "\u{00A0}", with: " ")
        let ns = raw as NSString
        guard let marker = try? NSRegularExpression(
            pattern: #"^\s*(?:[•▪◦‣∙·]|[0-9]+[.)]?)\s+"#
        ).firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        let markerText = ns.substring(with: marker.range)
        let number = Int(markerText.filter(\.isNumber)) ?? 1
        let contentRange = NSRange(
            location: marker.range.upperBound,
            length: ns.length - marker.range.upperBound
        )
        let content = inlineMarkdown(paragraph, range: contentRange)
        guard !content.isEmpty else { return nil }

        let ordered = orderedFormats.contains(list.markerFormat)
        let level = max(0, (style?.textLists.count ?? 1) - 1)
        let indent = String(repeating: "  ", count: level)
        let prefix = ordered ? "\(number). " : "- "
        return (indent + prefix + content, ordered)
    }

    private static let orderedFormats: Set<NSTextList.MarkerFormat> = [
        .decimal, .octal,
        .uppercaseAlpha, .lowercaseAlpha,
        .uppercaseRoman, .lowercaseRoman,
        .uppercaseLatin, .lowercaseLatin
    ]

    private static func render(_ blocks: [Block]) -> String {
        var output: [String] = []
        var index = 0

        while index < blocks.count {
            switch blocks[index] {
            case .code:
                var lines: [String] = []
                while index < blocks.count, case .code(let line) = blocks[index] {
                    lines.append(line)
                    index += 1
                }
                output.append("```\n" + lines.joined(separator: "\n") + "\n```")

            case .listItem(_, let ordered):
                var lines: [String] = []
                while index < blocks.count,
                      case .listItem(let line, let kind) = blocks[index],
                      kind == ordered {
                    lines.append(line)
                    index += 1
                }
                output.append(lines.joined(separator: "\n"))

            case .heading(let level, let text):
                output.append(String(repeating: "#", count: level) + " " + text)
                index += 1

            case .paragraph(let text):
                output.append(text)
                index += 1
            }
        }

        return output.joined(separator: "\n\n")
    }

    // MARK: - Inline

    private static func inlineMarkdown(
        _ paragraph: NSAttributedString,
        range: NSRange? = nil,
        suppressBold: Bool = false
    ) -> String {
        let target = range ?? NSRange(location: 0, length: paragraph.length)
        guard target.length > 0 else { return "" }
        var pieces: [String] = []
        paragraph.enumerateAttributes(in: target, options: []) { attributes, runRange, _ in
            let raw = (paragraph.string as NSString).substring(with: runRange)
            pieces.append(decorate(raw, attributes: attributes, suppressBold: suppressBold))
        }
        return pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decorate(
        _ raw: String,
        attributes: [NSAttributedString.Key: Any],
        suppressBold: Bool
    ) -> String {
        guard !raw.isEmpty else { return "" }
        let font = attributes[.font] as? NSFont
        let bold = !suppressBold && isBold(font)
        let italic = isItalic(font)
        let mono = isMonospaced(font)
        let link = linkURL(attributes[.link])

        let leading = String(raw.prefix { $0.isWhitespace })
        let trailing = String(raw.reversed().prefix { $0.isWhitespace }.reversed())
        let start = raw.index(raw.startIndex, offsetBy: leading.count)
        let end = raw.index(raw.endIndex, offsetBy: -trailing.count)
        guard start < end else { return raw }
        let core = String(raw[start..<end])

        var body = mono ? codeSpan(core) : escape(core)
        if italic { body = "*\(body)*" }
        if bold { body = "**\(body)**" }
        if let link { body = linkMarkdown(label: body, url: link) }
        return leading + body + trailing
    }

    private static func codeSpan(_ text: String) -> String {
        text.contains("`") ? "`` \(text) ``" : "`\(text)`"
    }

    private static func escape(_ text: String) -> String {
        var value = ""
        value.reserveCapacity(text.count + 8)
        for character in text {
            if "\\`*_[]".contains(character) {
                value.append("\\")
            }
            value.append(character)
        }
        return value
    }

    /// Plain text that happens to start with "#", ">" or "- " would turn into
    /// a heading, quote or list, so the first marker is escaped.
    private static func escapeLineStart(_ line: String) -> String {
        let pattern = #"^(?:#{1,6}\s|>|[-+]\s|[0-9]+[.)]\s)"#
        return line.range(of: pattern, options: .regularExpression) != nil ? "\\" + line : line
    }

    private static func linkMarkdown(label: String, url: String) -> String {
        let target = url.contains(where: { $0 == " " || $0 == "(" || $0 == ")" })
            ? "<\(url)>"
            : url
        return "[\(label)](\(target))"
    }

    // MARK: - Fonts and links

    private static func isBold(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    private static func isItalic(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
    }

    private static func isMonospaced(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return true }
        let name = font.fontName.lowercased()
        return name.contains("mono") || name.contains("courier") || name.contains("menlo")
    }

    private static func linkURL(_ value: Any?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let url = value as? NSURL { return url.absoluteString }
        if let string = value as? String, !string.isEmpty { return string }
        return nil
    }
}
