import AppKit
import Foundation

/// Copies Markdown to the pasteboard in three flavours at once:
/// plain Markdown, rendered HTML and RTF. Rich editors paste formatting,
/// plain editors paste the Markdown source.
enum ClipboardWriter {

    /// Plain text only: used by the "Text only" and "Markdown" result modes,
    /// where a rich destination must not re-interpret the markup.
    static func copyPlain(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let html = renderHTML(text)
        pasteboard.setString(html, forType: .html)

        if let rtf = renderRTF(html: html) {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    // MARK: - HTML

    static func renderHTML(_ text: String) -> String {
        var body = ""
        var paragraphOpen = false
        var listKind: ListKind?
        var blockquoteOpen = false

        func closeParagraph() {
            if paragraphOpen {
                body += "</p>"
                paragraphOpen = false
            }
        }

        func closeList() {
            if let kind = listKind {
                body += "</\(kind.tag)>"
                listKind = nil
            }
        }

        func closeBlockquote() {
            if blockquoteOpen {
                body += "</blockquote>"
                blockquoteOpen = false
            }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                closeParagraph()
                closeList()
                closeBlockquote()
                body += "<p>&nbsp;</p>"
                continue
            }

            if let quote = blockquoteText(trimmed) {
                closeParagraph()
                closeList()
                if !blockquoteOpen {
                    body += "<blockquote>"
                    blockquoteOpen = true
                }
                body += "<p>\(inline(quote))</p>"
                continue
            }
            closeBlockquote()

            if let heading = headingParts(trimmed) {
                closeParagraph()
                closeList()
                body += "<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>"
                continue
            }

            if let item = listItem(trimmed) {
                closeParagraph()
                if listKind != item.kind {
                    closeList()
                    let start = item.kind == .ordered && item.start != 1
                        ? " start=\"\(item.start)\""
                        : ""
                    body += "<\(item.kind.tag)\(start)>"
                    listKind = item.kind
                }
                body += "<li>\(inline(item.text))</li>"
                continue
            }

            closeList()
            if paragraphOpen {
                body += "<br>"
            } else {
                body += "<p>"
                paragraphOpen = true
            }
            body += inline(trimmed)
        }

        closeParagraph()
        closeList()
        closeBlockquote()

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 14px; line-height: 1.45; }
        p { margin: 0 0 8px 0; }
        h1,h2,h3,h4,h5,h6 { margin: 12px 0 6px 0; }
        code { font-family: Menlo, monospace; font-size: 13px; }
        a { color: #2f6bff; }
        blockquote { margin: 8px 0; padding-left: 10px; border-left: 3px solid #555; }
        </style></head><body>\(body)</body></html>
        """
    }

    private enum ListKind: Equatable {
        case unordered
        case ordered

        var tag: String { self == .unordered ? "ul" : "ol" }
    }

    private static func blockquoteText(_ line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        let value = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        guard let match = line.range(of: #"^(#{1,6})\s+(.+)$"#, options: .regularExpression) else {
            return nil
        }
        let value = String(line[match])
        let hashes = value.prefix { $0 == "#" }
        let level = hashes.count
        let text = value.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func listItem(_ line: String) -> (kind: ListKind, start: Int, text: String)? {
        if let match = line.range(of: #"^[-*+]\s+(.+)$"#, options: .regularExpression) {
            let value = String(line[match])
            let text = value.replacingOccurrences(
                of: #"^[-*+]\s+"#,
                with: "",
                options: .regularExpression
            )
            return (.unordered, 1, text)
        }
        if let match = line.range(of: #"^(\d+)[.)]\s+(.+)$"#, options: .regularExpression) {
            let value = String(line[match])
            let digits = value.prefix { $0.isNumber }
            let text = value.replacingOccurrences(
                of: #"^\d+[.)]\s+"#,
                with: "",
                options: .regularExpression
            )
            return (.ordered, Int(digits) ?? 1, text)
        }
        return nil
    }

    private static func inline(_ text: String) -> String {
        var value = escapeHTML(text)
        value = replaceLinks(in: value)

        value = value.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: #"<strong>$1</strong>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"__([^_]+)__"#,
            with: #"<strong>$1</strong>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: #"<code>$1</code>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#,
            with: #"<em>$1</em>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?<![\w_])_([^_\n]+)_(?![\w_])"#,
            with: #"<em>$1</em>"#,
            options: .regularExpression
        )
        return value
    }

    private static func replaceLinks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let full = Range(match.range, in: text),
                  let labelRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { continue }
            result += String(text[cursor..<full.lowerBound])
            let label = String(text[labelRange])
            let url = String(text[urlRange])
            if isSafeLink(url) {
                let escapedURL = url.replacingOccurrences(of: "\"", with: "&quot;")
                result += "<a href=\"\(escapedURL)\">\(label)</a>"
            } else {
                result += label
            }
            cursor = full.upperBound
        }
        result += String(text[cursor...])
        return result
    }

    private static func isSafeLink(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") {
            return true
        }
        // Relative links and anchors are safe; any other scheme is not.
        return !lower.contains(":")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - RTF

    private static func renderRTF(html: String) -> Data? {
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(
                  html: data,
                  options: [.characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else {
            return nil
        }
        let range = NSRange(location: 0, length: attributed.length)
        return try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
