import Foundation

/// Detects the Markdown constructs the app promises to preserve. The prompt
/// is only extended when the source actually contains Markdown, so ordinary
/// prose is not charged for an instruction it does not need.
enum MarkdownDetector {

    private static let patterns = [
        #"^\s{0,3}#{1,6}\s+\S"#,          // heading
        #"^\s{0,3}[-*+]\s+\S"#,           // unordered list
        #"^\s{0,3}\d+[.)]\s+\S"#,         // ordered list
        #"^\s{0,3}>\s+\S"#,               // block quote
        #"\*\*[^*\n]+\*\*"#,              // bold
        #"__[^_\n]+__"#,                  // bold
        #"(?<![\w*])\*[^*\n]+\*(?![\w*])"#,
        #"(?<![\w_])_[^_\n]+_(?![\w_])"#,
        #"`[^`\n]+`"#,                    // inline code
        #"\[[^\]]+\]\([^)\s]+\)"#         // link
    ]

    static func contains(_ text: String) -> Bool {
        patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
