import Foundation

/// Restores model ids and URLs byte-for-byte after the model has translated a
/// line. The model tends to change dots/slashes or capitalisation in these
/// tokens; the surrounding text is still translated normally.
enum TokenRestorer {

    private static let pattern = #"(?:https?://[^\s)\]]+)|(?:(?:[A-Za-z0-9][A-Za-z0-9.-]*\.(?:com|ai|org|io|dev|net|app|co|ua)\b(?:/[^\s)\]]*)?)|(?<![A-Za-z0-9._-])[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*(?![A-Za-z0-9._-]))"#

    private struct Match {
        let range: Range<String.Index>
        let token: String
    }

    static func restore(source: String, translated: String) -> String {
        let sourceTokens = matches(in: source)
        let translatedTokens = matches(in: translated)
        guard !sourceTokens.isEmpty,
              sourceTokens.count == translatedTokens.count else {
            return translated
        }

        var result = translated
        for (sourceMatch, translatedMatch) in zip(sourceTokens, translatedTokens).reversed() {
            result.replaceSubrange(translatedMatch.range, with: sourceMatch.token)
        }
        return result
    }

    static func preserveTrailingPunctuation(source: String, translated: String) -> String {
        let punctuation: Set<Character> = [":", ";", ",", ".", "!", "?"]
        guard let lastSource = source.trimmingCharacters(in: .whitespacesAndNewlines).last,
              punctuation.contains(lastSource) else {
            return translated
        }
        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastTranslated = trimmed.last, punctuation.contains(lastTranslated) {
            return translated
        }
        return trimmed + String(lastSource)
    }

    private static func matches(in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let token = String(text[range])
            guard token.contains(".") || token.contains(where: { $0.isNumber || $0 == ":" || $0 == "-" }) else {
                return nil
            }
            return Match(range: range, token: token)
        }
    }
}
