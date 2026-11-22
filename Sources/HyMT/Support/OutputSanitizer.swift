import Foundation

/// Removes special tokens some GGUF builds leak at the end of a generation.
/// The server-side stop list normally prevents them; this is the second line
/// of defence and also cleans older history entries.
enum OutputSanitizer {
    static func clean(_ text: String) -> String {
        var value = text
        let known = [
            "<｜hy_place▁holder▁no▁2｜>",
            "<｜hy_place▁holder▁no▁8｜>",
            "<｜hy_end▁of▁sentence｜>",
            "｜hy_end▁of▁sentence｜",
            "｜hy_end",
            "hy-Assistant",
            "hy-User",
            "hy_Assistant",
            "hy_User"
        ]
        for token in known {
            value = value.replacingOccurrences(of: token, with: "")
        }
        value = value.replacingOccurrences(
            of: #"[<｜|]hy_[A-Za-z0-9_▁]*[>|]?"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[<｜|]\s*hy[-_/]?[A-Za-z]*[^>]*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"<｜[^>]*$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"</｜[^>]*$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"｜hy[^\s]*$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[<｜|]\s*$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\u{FFFD}", with: "")
        value = value.replacingOccurrences(of: "\u{0000}", with: "")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
