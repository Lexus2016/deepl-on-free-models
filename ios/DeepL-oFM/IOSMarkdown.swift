import Foundation

enum IOSMarkdown {
    /// Plain text with the Markdown markers removed.
    static func plain(_ text: String) -> String {
        var value = text
        let patterns: [(String, String)] = [
            ("(?m)^\\s{0,3}#{1,6}\\s+", ""),
            ("(?m)^\\s{0,3}>\\s?", ""),
            ("(?m)^\\s*[-*+]\\s+", ""),
            ("(?m)^\\s*\\d+[.)]\\s+", ""),
            ("\\*\\*([^*]+)\\*\\*", "$1"),
            ("__([^_]+)__", "$1"),
            ("(?<![\\w*])\\*([^*\\n]+)\\*(?![\\w*])", "$1"),
            ("(?<![\\w_])_([^_\\n]+)_(?![\\w_])", "$1"),
            ("`([^`]+)`", "$1"),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", ""),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1")
        ]
        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return value
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inline formatting with the original line breaks kept.
    static func rendered(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}
