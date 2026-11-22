import Foundation

/// Restores model ids, URLs, email addresses and inline code byte-for-byte
/// after the model has translated a line. The model tends to change
/// dots/slashes or capitalisation in these tokens; the surrounding text is
/// still translated normally.
enum TokenRestorer {

    private static let pattern = #"(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|(?:https?://[^\s)\]>"']+)|(?:(?:[A-Za-z0-9][A-Za-z0-9-]*\.)+(?:com|ai|org|io|dev|net|app|co|ua|me|info|biz|xyz|tech|cloud|pro)\b(?:/[^\s)\]]*)?)|(?:`[^`\n]+`)|(?<![A-Za-z0-9._-])[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*(?![A-Za-z0-9._-])|(?<![A-Za-z0-9._-])(?=[A-Za-z0-9.-]*\d)[A-Za-z][A-Za-z0-9]*(?:[.-][A-Za-z0-9]+)+(?![A-Za-z0-9._-])"#

    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "…"]

    private struct Match {
        let range: Range<String.Index>
        let token: String
    }

    /// Returns nil when the model changed the number of protected tokens:
    /// keeping a corrupted URL or model id is worse than asking for a retry.
    static func restore(source: String, translated: String) -> String? {
        let sourceTokens = matches(in: source)
        guard !sourceTokens.isEmpty else { return translated }

        let translatedTokens = matches(in: translated)
        guard sourceTokens.count == translatedTokens.count else {
            return nil
        }

        var result = translated
        for (sourceMatch, translatedMatch) in zip(sourceTokens, translatedTokens).reversed() {
            result.replaceSubrange(translatedMatch.range, with: sourceMatch.token)
        }
        return result
    }

    static func preserveTrailingPunctuation(source: String, translated: String) -> String {
        let punctuation: Set<Character> = [":", ";", ",", ".", "!", "?", "…"]
        guard let lastSource = source.trimmingCharacters(in: .whitespacesAndNewlines).last,
              punctuation.contains(lastSource) else {
            return translated
        }
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastTranslated = trimmed.last, punctuation.contains(lastTranslated) {
            return String(trimmed.dropLast()) + String(lastSource)
        }
        return trimmed + String(lastSource)
    }

    private static func matches(in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard var range = Range(match.range, in: text) else { return nil }
            var token = String(text[range])
            let originalCount = token.count

            // A URL at the end of a sentence must not swallow the full stop.
            while let last = token.last, trailingPunctuation.contains(last) {
                token.removeLast()
            }
            guard !token.isEmpty else { return nil }
            if token.count != originalCount {
                let end = text.index(range.lowerBound, offsetBy: token.count)
                range = range.lowerBound..<end
            }

            guard token.hasPrefix("`")
                || token.contains("@")
                || token.contains(".")
                || token.contains(where: { $0.isNumber || $0 == ":" || $0 == "-" }) else {
                return nil
            }
            return Match(range: range, token: token)
        }
    }
}
