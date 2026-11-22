import Foundation

/// Restores model ids, URLs, email addresses and inline code byte-for-byte
/// after the model has translated a line. The model tends to change
/// dots/slashes or capitalisation in these tokens; the surrounding text is
/// still translated normally.
enum TokenRestorer {

    // The trailing lookahead must allow a sentence period: `Hy-MT2.` at the
    // end of a sentence is the same protected token as `Hy-MT2 ` in the
    // middle. The dot is not part of the token and stays in the translation.
    private static let pattern = #"(?:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|(?:https?://[^\s)\]>"']+)|(?:(?:[A-Za-z0-9][A-Za-z0-9-]*\.)+(?:com|ai|org|io|dev|net|app|co|ua|me|info|biz|xyz|tech|cloud|pro)\b(?:/[^\s)\]]*)?)|(?:`[^`\n]+`)|(?<![A-Za-z0-9._-])[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._:-]*(?![A-Za-z0-9_-])|(?<![A-Za-z0-9._-])(?=[A-Za-z0-9.-]*\d)[A-Za-z][A-Za-z0-9]*(?:[.-][A-Za-z0-9]+)+(?![A-Za-z0-9_-])"#

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
        if sourceTokens.count == translatedTokens.count {
            var result = translated
            for (sourceMatch, translatedMatch) in zip(sourceTokens, translatedTokens).reversed() {
                // Preserve the source spelling, including Unicode hyphens.
                let sourceToken = String(source[sourceMatch.range])
                result.replaceSubrange(translatedMatch.range, with: sourceToken)
            }
            return result
        }

        // Counts differ when the model repeats an id or writes it twice with
        // different casing. Accept the line only when every token survived;
        // a dropped or mangled URL still falls back to the source line.
        let normalized = normalizeHyphens(translated).lowercased()
        let keptEveryToken = sourceTokens.allSatisfy { match in
            normalized.contains(normalizeHyphens(match.token).lowercased())
        }
        return keptEveryToken ? translated : nil
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

    /// Models often replace ASCII hyphens with U+2010…U+2212 in model ids
    /// (Hy‑MT2). Normalizing keeps matching stable; the source spelling is
    /// restored afterwards.
    private static func normalizeHyphens(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
    }

    private static func matches(in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let normalized = normalizeHyphens(text)
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: nsRange).compactMap { match in
            guard let normalizedRange = Range(match.range, in: normalized),
                  var range = Range(match.range, in: text) else { return nil }
            var token = String(normalized[normalizedRange])
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
