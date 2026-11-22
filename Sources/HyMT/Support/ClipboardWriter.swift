import AppKit
import Foundation

/// Copies Markdown to the pasteboard in three flavours at once:
/// plain Markdown, rendered HTML and RTF. Rich editors paste formatting,
/// plain editors paste the Markdown source.
enum ClipboardWriter {

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

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                closeParagraph()
                closeList()
                body += "<p>&nbsp;</p>"
                continue
            }

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
                    body += "<\(item.kind.tag)>"
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

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 14px; line-height: 1.45; }
        p { margin: 0 0 8px 0; }
        h1,h2,h3,h4,h5,h6 { margin: 12px 0 6px 0; }
        code { font-family: Menlo, monospace; font-size: 13px; }
        a { color: #2f6bff; }
        </style></head><body>\(body)</body></html>
        """
    }

    private enum ListKind {
        case unordered, ordered
        var tag: String { self == .unordered ? "ul" : "ol" }
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

    private static func listItem(_ line: String) -> (kind: ListKind, text: String)? {
        if let match = line.range(of: #"^[-*+]\s+(.+)$"#, options: .regularExpression) {
            let value = String(line[match])
            let text = value.replacingOccurrences(
                of: #"^[-*+]\s+"#,
                with: "",
                options: .regularExpression
            )
            return (.unordered, text)
        }
        if let match = line.range(of: #"^\d+[.)]\s+(.+)$"#, options: .regularExpression) {
            let value = String(line[match])
            let text = value.replacingOccurrences(
                of: #"^\d+[.)]\s+"#,
                with: "",
                options: .regularExpression
            )
            return (.ordered, text)
        }
        return nil
    }

    private static func inline(_ text: String) -> String {
        var value = escapeHTML(text)

        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)\s]+)\)"#,
            with: #"<a href="$2">$1</a>"#,
            options: .regularExpression
        )
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

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - RTF

    private static func renderRTF(html: String) -> Data? {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
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
