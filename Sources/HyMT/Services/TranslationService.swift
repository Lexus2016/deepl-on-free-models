import Foundation

enum TranslationEvent: Sendable {
    case chunk(String)
    case stats(tokensPerSecond: Double?)
    case progress(Int, Int)
    case warning
}

enum TranslationError: LocalizedError {
    case invalidURL(String)
    case emptyModel
    case missingAPIKey
    case connection(String)
    case http(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case backend(String)
    case modelNotFound(String)
    case emptyResponse
    case degenerateResponse
    case unexpectedResponse

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .invalidURL(let value):
            return L10n.format("Invalid server URL: %@", language, value)
        case .emptyModel:
            return L10n.t("Choose a model in Settings.", language)
        case .missingAPIKey:
            return L10n.t("Add your API key in Settings.", language)
        case .connection(let host):
            return L10n.format("Could not connect to %@. Check that the server is running.", language, host)
        case .http(let code):
            if code == 429 {
                return TranslationError.rateLimited(retryAfter: nil).message(language)
            }
            switch code {
            case 400, 401, 403, 422:
                return L10n.t("The provider rejected the request. Check the API key and model in Settings.", language)
            case 500...599:
                return L10n.t("The provider is temporarily unavailable. Try again.", language)
            default:
                return L10n.format("Server returned error %@.", language, String(code))
            }
        case .rateLimited:
            return L10n.t("Too many requests. Wait a moment and try again.", language)
        case .backend:
            return L10n.t("The provider rejected the request. Check the API key and model in Settings.", language)
        case .modelNotFound(let model):
            return L10n.format("Model “%@” not found on the server.", language, model)
        case .emptyResponse:
            return L10n.t("The model returned an empty translation. Try again.", language)
        case .degenerateResponse:
            return L10n.t("The model could not translate this text. Try again or choose another model.", language)
        case .unexpectedResponse:
            return L10n.t("The server interrupted the response. Try again.", language)
        }
    }

    var errorDescription: String? { message(.uk) }
}

struct TextChunk {
    let text: String
    let separatorBefore: String
}

enum TextChunker {
    static let limit = 3200

    /// One chunk per source line: line breaks and blank lines are reproduced
    /// exactly in the result. Long lines are additionally split by sentences,
    /// but their pieces are rejoined with spaces so the line stays one line.
    static func chunks(from text: String) -> [TextChunk] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [TextChunk] = []
        var pendingLineBreaks = 0
        var started = false

        for line in lines {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                if started { pendingLineBreaks += 1 }
                continue
            }

            let separator: String
            if result.isEmpty {
                separator = ""
            } else {
                separator = String(repeating: "\n", count: max(1, pendingLineBreaks + 1))
            }
            append(line, separator: separator, to: &result)
            started = true
            pendingLineBreaks = 0
        }

        if result.isEmpty {
            return [TextChunk(text: text, separatorBefore: "")]
        }
        return result
    }

    private static func append(_ text: String, separator: String, to result: inout [TextChunk]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.count <= limit {
            result.append(TextChunk(text: trimmed, separatorBefore: result.isEmpty ? "" : separator))
            return
        }

        let pieces = splitSentences(trimmed, limit: limit)
        for (index, piece) in pieces.enumerated() {
            let pieceText = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pieceText.isEmpty else { continue }
            let pieceSeparator = index == 0 ? separator : " "
            result.append(TextChunk(
                text: pieceText,
                separatorBefore: result.isEmpty ? "" : pieceSeparator
            ))
        }
    }

    static func sentences(from text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            if let substring, !substring.isEmpty {
                sentences.append(substring)
            }
        }
        if sentences.isEmpty { sentences = [text] }
        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitSentences(_ text: String, limit: Int) -> [String] {
        let sentences = sentences(from: text)
        var result: [String] = []
        for sentence in sentences {
            if sentence.count <= limit {
                result.append(sentence)
            } else {
                var remaining = sentence[...]
                while !remaining.isEmpty {
                    let piece = remaining.prefix(limit)
                    result.append(String(piece))
                    remaining = remaining.dropFirst(piece.count)
                }
            }
        }
        return result
    }
}

final class TranslationService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        target: Language,
        config: BackendConfig,
        retryRateLimit: Bool = true,
        sourceLanguage: Language? = nil
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !config.model.isEmpty else { throw TranslationError.emptyModel }
                    let chunks = TextChunker.chunks(from: text)
                    continuation.yield(.progress(0, chunks.count))
                    var completed = 0
                    var translatedCount = 0
                    var warnings = 0
                    for chunk in chunks {
                        try Task.checkCancellation()
                        if !chunk.separatorBefore.isEmpty {
                            if case .terminated = continuation.yield(.chunk(chunk.separatorBefore)) {
                                return
                            }
                        }
                        let segment = parseSegment(chunk.text)
                            ?? Segment(prefix: "", body: chunk.text)
                        var prefix = segment.prefix
                        var body = segment.body
                        let preserveMarkdown = MarkdownDetector.contains(chunk.text)

                        // Model lists and URLs must stay byte-for-byte: keep the
                        // left side of "IDs — description" and translate only
                        // the description.
                        if let mixed = Self.splitMixedLine(body) {
                            prefix += mixed.keep
                            body = mixed.translate
                        }

                        // The literal style prompt makes Hy-MT2 argue with
                        // itself on short fragments (role tokens, self-dialogue).
                        // Short lines always use the neutral heading prompt;
                        // long lines use the selected style first, then the
                        // neutral prompt as a fallback.
                        let neutralHeading = PromptBuilder.headingPrompt(
                            text: body,
                            style: .auto,
                            tone: .standard,
                            targetLanguage: target.englishName,
                            preserveMarkdown: false
                        )
                        let plainFallback = PromptBuilder.plainPrompt(
                            text: body,
                            targetLanguage: target.englishName
                        )

                        let prompts: [String]
                        if body.count <= 80 {
                            prompts = [neutralHeading, plainFallback]
                        } else {
                            let styled = PromptBuilder.prompt(
                                text: body,
                                style: style,
                                tone: tone,
                                targetLanguage: target.englishName,
                                preserveMarkdown: preserveMarkdown
                            )
                            let natural = PromptBuilder.prompt(
                                text: body,
                                style: .natural,
                                tone: tone,
                                targetLanguage: target.englishName,
                                preserveMarkdown: preserveMarkdown
                            )
                            let literal = PromptBuilder.prompt(
                                text: body,
                                style: .literal,
                                tone: .standard,
                                targetLanguage: target.englishName,
                                preserveMarkdown: preserveMarkdown
                            )
                            switch style {
                            case .auto:
                                prompts = [styled, natural, plainFallback]
                            case .natural:
                                prompts = [styled, plainFallback, literal]
                            case .literal:
                                prompts = [styled, natural, plainFallback]
                            }
                        }

                        if !body.unicodeScalars.contains(where: CharacterSet.letters.contains) {
                            if case .terminated = continuation.yield(.chunk(prefix + body)) { return }
                            completed += 1
                            continuation.yield(.progress(completed, chunks.count))
                            continue
                        }

                        var warning = false
                        var translated: String
                        do {
                            let result = try await bufferedTranslation(
                                prompts: prompts,
                                source: body,
                                target: target,
                                config: config,
                                retryRateLimit: retryRateLimit,
                                sourceLanguage: sourceLanguage
                            )
                            translated = result.text
                            warning = result.warning
                            if let restored = TokenRestorer.restore(source: body, translated: translated) {
                                translated = TokenRestorer.preserveTrailingPunctuation(
                                    source: body,
                                    translated: restored
                                )
                            } else {
                                debugLog("Protected tokens changed in model output.")
                                translated = body
                                warning = true
                            }
                        } catch let error as TranslationError {
                            switch error {
                            case .degenerateResponse, .emptyResponse:
                                translated = body
                                warning = true
                            default:
                                throw error
                            }
                        }

                        let output = prefix + translated
                        if case .terminated = continuation.yield(.chunk(output)) {
                            return
                        }
                        if warning {
                            warnings += 1
                            continuation.yield(.warning)
                        } else {
                            translatedCount += 1
                        }
                        completed += 1
                        continuation.yield(.progress(completed, chunks.count))
                    }
                    if warnings > 0, translatedCount == 0 {
                        throw TranslationError.degenerateResponse
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func translateBlock(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        target: Language,
        config: BackendConfig,
        retryRateLimit: Bool = true,
        sourceLanguage: Language? = nil
    ) async throws -> (text: String, warning: Bool) {
        let preserve = MarkdownDetector.contains(text)
        let standardPrompt = PromptBuilder.prompt(
            text: text, style: style, tone: tone, targetLanguage: target.englishName,
            preserveMarkdown: preserve
        )
        let concisePrompt = "Translate into \(target.englishName)."
            + (preserve ? " Preserve Markdown syntax and keep line breaks." : "")
            + "\n\n" + text
        let prompts = [
            style == .auto && tone == .standard ? concisePrompt : standardPrompt,
            style == .auto && tone == .standard ? standardPrompt : concisePrompt,
            PromptBuilder.plainPrompt(text: text, targetLanguage: target.englishName)
        ].map { Self.withSourceLanguage($0, sourceLanguage) }
        let result = try await bufferedTranslation(
            prompts: prompts,
            source: text,
            target: target,
            config: config,
            retryRateLimit: retryRateLimit,
            preserveLineBreaks: true,
            requiresMarkdownStructure: preserve
        )
        if let restored = TokenRestorer.restore(source: text, translated: result.text) {
            return (restored, result.warning)
        }
        throw TranslationError.degenerateResponse
    }

    /// Raw completion for the writing mode: no translation prompts or target
    /// validation, just the provider's answer.
    func rewrite(
        prompt: String,
        config: BackendConfig,
        retryRateLimit: Bool = true
    ) async throws -> String {
        let result = try await collectWithRetry(
            prompt: prompt, config: config, maxLength: 128_000, retryRateLimit: retryRateLimit
        )
        let cleaned = OutputSanitizer.clean(result)
        guard !cleaned.isEmpty else { throw TranslationError.emptyResponse }
        return cleaned
    }

    // MARK: - Short blocks

    private struct Segment {
        let prefix: String
        let body: String
    }

    private func parseSegment(_ text: String) -> Segment? {
        guard !text.contains("\n") else { return nil }
        var prefix = ""
        var body = text

        let patterns = [
            #"^(\s*#{1,6}\s+)(.+)$"#,
            #"^(\s*>\s+)(.+)$"#,
            #"^(\s*(?:[-*•–—]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)(.+)$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges == 3,
                  let prefixRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            prefix = String(text[prefixRange])
            body = String(text[bodyRange])
            break
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Segment(prefix: prefix, body: trimmed)
    }

    /// Splits "model-id, model-id — description" so the ids stay byte-for-byte.
    /// Prose with a slash or an em dash must not be mistaken for an id list.
    static func splitMixedLine(_ text: String) -> (keep: String, translate: String)? {
        guard let separatorRange = text.range(of: " — ") else { return nil }
        let left = String(text[..<separatorRange.lowerBound])
        let right = String(text[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !right.isEmpty else { return nil }

        let latin = left.unicodeScalars.filter {
            (0x0041...0x007A).contains($0.value) || (0x0030...0x0039).contains($0.value)
        }.count
        let cyrillic = left.unicodeScalars.filter {
            (0x0400...0x04FF).contains($0.value)
        }.count
        guard latin >= 8, latin > cyrillic * 2 else { return nil }

        let pieces = left.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !pieces.isEmpty else { return nil }
        let looksLikeIDs = pieces.allSatisfy { piece in
            !piece.isEmpty
                && !piece.contains(where: { $0.isWhitespace })
                && (piece.contains("/") || piece.contains(":") || piece.contains(".") || piece.contains("-"))
                && piece.contains(where: { $0.isNumber })
        }
        guard looksLikeIDs else { return nil }

        return (left + " — ", right)
    }

    /// Japanese uses CJK ideographs; the CJK guard must not reject it.
    static func usesCJKScript(_ code: String) -> Bool {
        ["zh", "zh-Hant", "yue", "ja"].contains(code)
    }

    /// A translation into a non-Latin language must contain at least one
    /// character of that script. Otherwise the model has simply echoed the
    /// source, which used to pass validation and leave English inside a
    /// Ukrainian paragraph.
    static func hasTargetScript(_ text: String, target: String) -> Bool {
        guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return true
        }
        func has(_ ranges: [ClosedRange<UInt32>]) -> Bool {
            text.unicodeScalars.contains { scalar in
                ranges.contains { $0.contains(scalar.value) }
            }
        }
        switch target {
        case "uk", "ru", "be", "bg", "mk", "kk", "mn":
            return has([0x0400...0x04FF])
        case "sr":
            return has([0x0400...0x04FF, 0x0041...0x024F])
        case "zh", "zh-Hant", "yue":
            return has([0x4E00...0x9FFF, 0x3400...0x4DBF])
        case "ja":
            return has([0x3040...0x30FF, 0x4E00...0x9FFF])
        case "ko":
            return has([0xAC00...0xD7AF, 0x1100...0x11FF])
        case "ar", "fa", "ur", "ug":
            return has([0x0600...0x06FF, 0x0750...0x077F])
        case "he":
            return has([0x0590...0x05FF])
        case "th":
            return has([0x0E00...0x0E7F])
        case "hi", "mr":
            return has([0x0900...0x097F])
        case "bn":
            return has([0x0980...0x09FF])
        case "ta":
            return has([0x0B80...0x0BFF])
        case "te":
            return has([0x0C00...0x0C7F])
        case "gu":
            return has([0x0A80...0x0AFF])
        case "km":
            return has([0x1780...0x17FF])
        case "my":
            return has([0x1000...0x109F])
        case "bo":
            return has([0x0F00...0x0FFF])
        default:
            return has([0x0041...0x024F])
        }
    }

    /// Ukrainian and Russian have well-defined alphabets. A character outside
    /// them is a strong sign that the model switched language or degenerated.
    static func usesAllowedCyrillic(_ text: String, target: String) -> Bool {
        let alphabet: Set<Character>
        switch target {
        case "uk":
            alphabet = Set("абвгґдеєжзиіїйклмнопрстуфхцчшщьюяАБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ")
        case "ru":
            alphabet = Set("абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
        default:
            return true
        }
        return text.unicodeScalars.allSatisfy { scalar in
            guard (0x0400...0x04FF).contains(scalar.value) else { return true }
            let character = Character(String(scalar))
            return alphabet.contains(character)
        }
    }

    /// Removes "Here is the translation:" / "Ось переклад тексту:" before the
    /// actual translation. The model adds these wrappers on the natural style.
    static func stripPreamble(_ text: String, source: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLower = source.lowercased()
        var removedPreamble = false
        let patterns = [
            #"^(?:Ось\s+(?:ваш\s+|твій\s+)?(?:переклад|текст\s+у\s+перекладі)(?:[^:\n]{0,50})?|Звісно,?\s+ось(?:[^:\n]{0,50})?|Here(?:'s|\s+is)\s+(?:the\s+|your\s+)?translation(?:[^:\n]{0,50})?|The\s+translation\s+is|Translation|Вот\s+перевод|Перевод\s+текста)\s*:\s*"#,
            #"^(?:Звісно|Звичайно|Ось)[!,.]\s*"#
        ]
        for pattern in patterns {
            guard let range = value.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) else { continue }
            let matched = String(value[range])
            guard !sourceLower.contains(matched.lowercased()) else { continue }
            value.removeSubrange(range)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            removedPreamble = true
        }

        if removedPreamble, let first = value.first, ["«", "“", "\""].contains(first) {
            value.removeFirst()
            if let close = value.firstIndex(where: { ["»", "”", "\""].contains($0) }) {
                value.remove(at: close)
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private func bufferedTranslation(
        prompts: [String],
        source: String,
        target: Language,
        config: BackendConfig,
        retryRateLimit: Bool,
        preserveLineBreaks: Bool = false,
        requiresMarkdownStructure: Bool = false,
        sourceLanguage: Language? = nil
    ) async throws -> (text: String, warning: Bool) {
        let sourceCount = source.count
        let maxLength = max(200, sourceCount * 4 + 100)
        for (promptIndex, prompt) in prompts.enumerated() {
            let attempts = promptIndex == 0 ? 3 : 2
            for attempt in 0..<attempts {
                if attempt > 0 {
                    try await Task.sleep(for: .milliseconds(120))
                }
                var retryConfig = config
                if attempt > 0 {
                    retryConfig.temperature = min(config.temperature, 0.3)
                }
                let raw = try await collectCandidate(
                    prompt: Self.withSourceLanguage(prompt, sourceLanguage), config: retryConfig, maxLength: maxLength,
                    retryRateLimit: retryRateLimit
                )
                let candidate = Self.stripPreamble(raw, source: source)
                if let clean = validated(candidate, source: source, target: target, preserveLineBreaks: preserveLineBreaks),
                   !requiresMarkdownStructure || Self.markdownStructure(clean) == Self.markdownStructure(source) {
                    return (clean, false)
                }
                debugLog("Rejected model output (prompt \(promptIndex), attempt \(attempt)).")
            }
        }

        if !requiresMarkdownStructure, !(preserveLineBreaks && source.contains("\n")),
           let segmented = try await sentenceFallback(
               source: source, target: target, config: config, retryRateLimit: retryRateLimit,
               sourceLanguage: sourceLanguage
           ) {
            return segmented
        }
        throw TranslationError.degenerateResponse
    }

    static func markdownStructure(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let body = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let first = body.first else { return nil }
            let prefix = body.prefix(while: { $0 == first })
            let rest = body.dropFirst(prefix.count)
            if first == "#" || first == ">" {
                return rest.first?.isWhitespace == true ? String(prefix) : nil
            }
            if "-+*".contains(first), prefix.count == 1, rest.first?.isWhitespace == true {
                return "bullet"
            }
            let digits = body.prefix(while: \.isNumber)
            if !digits.isEmpty, let marker = body.dropFirst(digits.count).first, ".)".contains(marker),
               body.dropFirst(digits.count + 1).first?.isWhitespace == true {
                return "number"
            }
            return nil
        }
    }

    /// Last resort for long paragraphs: Hy-MT2 occasionally returns an empty
    /// stream for a whole paragraph while translating each sentence fine.
    /// Markdown/URLs are excluded because a sentence splitter can cut a link.
    private func sentenceFallback(
        source: String,
        target: Language,
        config: BackendConfig,
        retryRateLimit: Bool,
        sourceLanguage: Language?
    ) async throws -> (text: String, warning: Bool)? {
        guard !source.contains("http"), !source.contains("]("), !source.contains("`") else {
            return nil
        }
        let pieces = TextChunker.sentences(from: source)
        guard pieces.count > 1 else { return nil }

        var translated: [String] = []
        var failures = 0
        for piece in pieces {
            if Task.isCancelled { throw CancellationError() }
            let prompts = [
                PromptBuilder.plainPrompt(text: piece, targetLanguage: target.englishName),
                PromptBuilder.prompt(
                    text: piece,
                    style: .natural,
                    tone: .standard,
                    targetLanguage: target.englishName
                ),
                PromptBuilder.prompt(
                    text: piece,
                    style: .literal,
                    tone: .standard,
                    targetLanguage: target.englishName
                )
            ]
            var success: String?
            for prompt in prompts {
                var retryConfig = config
                retryConfig.temperature = min(config.temperature, 0.3)
                let maxLength = max(200, piece.count * 4 + 100)
                let raw = try await collectCandidate(
                    prompt: Self.withSourceLanguage(prompt, sourceLanguage), config: retryConfig, maxLength: maxLength,
                    retryRateLimit: retryRateLimit
                )
                let candidate = Self.stripPreamble(raw, source: piece)
                if let clean = validated(candidate, source: piece, target: target) {
                    success = clean
                    break
                }
            }
            if let success {
                translated.append(success)
            } else {
                translated.append(piece)
                failures += 1
            }
        }

        guard failures < pieces.count else { return nil }
        return (translated.joined(separator: " "), failures > 0)
    }

    private func validated(
        _ raw: String, source: String, target: Language, preserveLineBreaks: Bool = false
    ) -> String? {
        guard !raw.contains("\u{FFFD}") else { return nil }
        let sanitized = OutputSanitizer.clean(raw)
        guard !sanitized.isEmpty else { return nil }

        let cleaned = preserveLineBreaks ? sanitized : sanitized.replacingOccurrences(
            of: #"\s*\n\s*"#, with: " ", options: .regularExpression
        )
        guard !cleaned.isEmpty else { return nil }
        let sourceCount = source.count
        let cleanedCount = cleaned.count
        if sourceCount >= 60, cleanedCount < sourceCount / 4 {
            return nil
        }
        if sourceCount >= 60, cleanedCount < sourceCount / 2,
           !Self.usesCJKScript(target.code),
           TextChunker.sentences(from: source).count > 1,
           TextChunker.sentences(from: cleaned).count == 1 {
            return nil
        }
        guard Self.hasTargetScript(cleaned, target: target.code) else { return nil }

        let lower = cleaned.lowercased()
        if lower.contains("hy-assistant")
            || lower.contains("hy-user")
            || lower.contains("hy_end") {
            return nil
        }
        if cleaned.contains("<｜") || cleaned.contains("<|")
            || cleaned.contains("</|") || cleaned.contains("｜hy") {
            return nil
        }

        // If the model echoes the instruction instead of translating, reject
        // the block. The source is checked too: a document may legitimately
        // talk about prompts and Markdown.
        let sourceLower = source.lowercased()
        let instructionMarkers = [
            "preserve markdown syntax",
            "translate only the human-readable text",
            "translation style must strictly conform",
            "output only the translated heading",
            "output only the translated text",
            "here is the translation",
            "here's the translation",
            "the translation is",
            "ось переклад",
            "звісно, ось",
            "переклад тексту",
            "вот перевод",
            "перевод текста"
        ]
        for marker in instructionMarkers where lower.contains(marker) && !sourceLower.contains(marker) {
            return nil
        }

        // "I recommend..." / "Я можу допомогти..." is the model answering the
        // instruction, not translating it. Only reject it when the source has
        // no first person of its own.
        let paddedSource = " " + sourceLower + " "
        let firstPersonSource = [
            " i ", "i'", " me ", " my ", " we ", "we'", " us ", " our ",
            " я ", " мене ", " мені ", " мій ", " моя ", " ми ", " нас ", " наш ",
            " меня ", " мне ", " мой ", " мы "
        ].contains { paddedSource.contains($0) }
        if !firstPersonSource {
            let metaMarkers = [
                "я рекомендую", "я реком", "я можу допомогти", "я не можу",
                "якщо вам потрібно", "сподіваюся", "надіюся",
                "i recommend", "i can help", "i cannot", "let me know"
            ]
            if metaMarkers.contains(where: { lower.contains($0) }) {
                return nil
            }
        }

        if !Self.usesCJKScript(target.code) {
            let hasCJK = cleaned.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            }
            if hasCJK { return nil }
        }

        let cyrillicTargets = ["uk", "ru", "be", "bg", "mk", "sr", "kk", "mn"]
        if !cyrillicTargets.contains(target.code) {
            let hasCyrillic = cleaned.unicodeScalars.contains {
                (0x0400...0x04FF).contains($0.value)
            }
            if hasCyrillic { return nil }
        } else if !Self.usesAllowedCyrillic(cleaned, target: target.code) {
            // Hy-MT2 sometimes emits Belarusian/Serbian/archaic letters in the
            // middle of Ukrainian or Russian words. That is degeneration, not a
            // translation; retry instead of showing corrupted text.
            return nil
        }

        if sourceCount >= 40, cleanedCount > sourceCount * 4 {
            return nil
        }
        if sourceCount < 40, cleanedCount > max(120, sourceCount * 8) {
            return nil
        }

        if cleanedCount > 120 {
            let characters = Array(cleaned)
            var shingles = Set<String>()
            var duplicates = 0
            var index = 0
            while index + 40 <= characters.count {
                let shingle = String(characters[index..<(index + 40)])
                if shingles.contains(shingle) { duplicates += 1 }
                shingles.insert(shingle)
                index += 20
            }
            if duplicates > 1 { return nil }
        }

        return cleaned
    }

    private func collectCandidate(
        prompt: String, config: BackendConfig, maxLength: Int, retryRateLimit: Bool
    ) async throws -> String {
        do {
            return try await collectWithRetry(
                prompt: prompt, config: config, maxLength: maxLength, retryRateLimit: retryRateLimit
            )
        } catch TranslationError.degenerateResponse {
            return ""
        }
    }

    private func collectWithRetry(
        prompt: String, config: BackendConfig, maxLength: Int, retryRateLimit: Bool
    ) async throws -> String {
        var retries = 0
        while true {
            try Task.checkCancellation()
            var output = TranslationOutput(maxBytes: maxLength * 4)
            do {
                try await run(prompt: prompt, config: config) { piece in
                    output.append(piece)
                }
                try Task.checkCancellation()
                guard !output.exceededLimit else { throw TranslationError.degenerateResponse }
                return output.text
            } catch TranslationError.rateLimited(let retryAfter) where retryRateLimit && retries < 2 {
                let delay = retryAfter ?? Double(3 << retries)
                guard delay <= 30 else { throw TranslationError.rateLimited(retryAfter: retryAfter) }
                retries += 1
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Loads a local model into memory (Ollama, LM Studio, oMLX, llama.cpp).
    /// The response itself is irrelevant; a 200 means the model is warm.
    func warmUp(config: BackendConfig) async -> Bool {
        guard !config.model.isEmpty else { return false }
        let url: URL?
        let body: [String: Any]
        switch config.kind {
        case .ollama:
            url = URL(string: config.baseURL + "/api/chat")
            body = [
                "model": config.model,
                "messages": [["role": "user", "content": "Hello"]],
                "stream": false,
                "keep_alive": "5m",
                "options": [
                    "temperature": 0.0,
                    "num_predict": 1,
                    "num_ctx": config.contextWindow
                ] as [String: Any]
            ]
        case .openAI:
            url = openAIEndpoint(base: config.baseURL, path: "chat/completions")
            body = [
                "model": config.model,
                "messages": [["role": "user", "content": "Hello"]],
                "stream": false,
                "temperature": 0.0,
                "max_tokens": 1
            ]
        }
        guard let url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func run(
        prompt: String, config: BackendConfig, onText: (String) -> Bool
    ) async throws {
        guard !config.model.isEmpty else { throw TranslationError.emptyModel }
        guard !config.requiresAPIKey || !config.apiKey.isEmpty else { throw TranslationError.missingAPIKey }
        switch config.kind {
        case .ollama:
            try await runOllama(prompt: prompt, config: config, onText: onText)
        case .openAI:
            try await runOpenAI(prompt: prompt, config: config, onText: onText)
        }
    }

    static func withSourceLanguage(_ prompt: String, _ source: Language?) -> String {
        guard let source, source != .auto else { return prompt }
        return "The source language is \(source.englishName). " + prompt
    }

    // MARK: - Ollama

    private func runOllama(
        prompt: String,
        config: BackendConfig,
        onText: (String) -> Bool
    ) async throws {
        guard let url = URL(string: config.baseURL + "/api/chat") else {
            throw TranslationError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "stream": true,
            "keep_alive": "5m",
            "options": [
                "temperature": config.temperature,
                "top_p": config.topP,
                "top_k": config.topK,
                "repeat_penalty": config.repetitionPenalty,
                "num_ctx": config.contextWindow,
                "num_predict": 4096,
                "stop": [
                    "hy_end",
                    "<｜hy_place▁holder▁no▁8｜>",
                    "<｜hy_place▁holder▁no▁2｜>"
                ]
            ] as [String: Any]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            try Task.checkCancellation()
            throw TranslationError.connection(config.baseURL)
        }

        defer { bytes.task.cancel() }
        try checkResponse(response, config: config)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = object["error"] as? String {
                throw TranslationError.backend(error)
            }
            if let message = object["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty, !onText(content) { return }
            if object["done"] as? Bool == true {
                if object["done_reason"] as? String == "length" {
                    throw TranslationError.degenerateResponse
                }
                return
            }
        }
        try Task.checkCancellation()
        throw TranslationError.unexpectedResponse
    }

    // MARK: - OpenAI-compatible

    private func runOpenAI(
        prompt: String,
        config: BackendConfig,
        onText: (String) -> Bool
    ) async throws {
        guard let url = openAIEndpoint(base: config.baseURL, path: "chat/completions") else {
            throw TranslationError.invalidURL(config.baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "stream": true,
            "temperature": config.temperature,
            "top_p": config.topP,
            "max_tokens": 4096,
            "stop": [
                "hy_end",
                "<｜hy_place▁holder▁no▁8｜>",
                "<｜hy_place▁holder▁no▁2｜>"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            try Task.checkCancellation()
            throw TranslationError.connection(config.baseURL)
        }

        defer { bytes.task.cancel() }
        try checkResponse(response, config: config)

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            var payload = line.dropFirst(5)
            if payload.first == " " { payload = payload.dropFirst() }
            if payload == "[DONE]" { return }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TranslationError.backend(message)
            }
            if let choices = object["choices"] as? [[String: Any]],
               let first = choices.first {
                let message = (first["delta"] ?? first["message"]) as? [String: Any]
                if let content = message?["content"] as? String,
                   !content.isEmpty, !onText(content) { return }
                if let reason = first["finish_reason"] as? String, !reason.isEmpty {
                    if reason == "length" { throw TranslationError.degenerateResponse }
                    guard reason == "stop" || reason == "end_turn" else {
                        throw TranslationError.unexpectedResponse
                    }
                    return
                }
            }
        }
        try Task.checkCancellation()
        throw TranslationError.unexpectedResponse
    }

    // MARK: - Helpers

    private func openAIEndpoint(base: String, path: String) -> URL? {
        var value = base
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/v1") {
            return URL(string: value + "/" + path)
        }
        return URL(string: value + "/v1/" + path)
    }

    private func checkResponse(
        _ response: URLResponse, config: BackendConfig
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.connection(config.baseURL)
        }
        switch http.statusCode {
        case 200:
            return
        case 404:
            throw TranslationError.modelNotFound(config.model)
        case 429:
            let header = http.value(forHTTPHeaderField: "Retry-After")
            throw TranslationError.rateLimited(retryAfter: Self.retryDelay(header))
        default:
            throw TranslationError.http(http.statusCode)
        }
    }

    static func retryDelay(_ header: String?, now: Date = .now) -> TimeInterval? {
        guard let value = header?.trimmingCharacters(in: .whitespaces) else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    private func debugLog(_ message: String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEEPLOFM_DEBUG"] == "1" || environment["HYMT_DEBUG"] == "1" else { return }
        guard let data = ("[DeepL-oFM] " + message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}

/// Scans only new text and enough trailing characters to detect a split marker.
/// Перевіряє новий фрагмент і короткий хвіст для маркерів на стику.
struct TranslationOutput {
    private static let markers = ["hy-assistant", "hy-user", "hy_end", "<｜", "<|", "</|", "｜hy"]
        .map { Data($0.utf8) }
    private static let overlap = (markers.map(\.count).max() ?? 1) - 1

    let maxBytes: Int
    private var bytes = Data()
    private(set) var exceededLimit = false

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    mutating func append(_ piece: String) -> Bool {
        let overlap = min(Self.overlap, bytes.count)
        let remaining = maxBytes - bytes.count
        // Leave room to detect a marker that straddles the output limit.
        // Залишаємо запас для маркера на межі довжини відповіді.
        let fragment = piece.utf8.prefix(remaining + Self.overlap + 1)
        var window = Data(bytes.suffix(overlap))
        window.append(contentsOf: fragment)
        let folded = Data(window.lazy.map { (65...90).contains($0) ? $0 + 32 : $0 })
        if let offset = Self.markers.compactMap({ folded.range(of: $0)?.lowerBound }).min() {
            if offset < overlap {
                bytes.removeLast(overlap - offset)
            } else if offset - overlap <= remaining {
                bytes.append(contentsOf: window[overlap..<offset])
            } else {
                exceededLimit = true
            }
            return false
        }
        guard fragment.count <= remaining else {
            exceededLimit = true
            return false
        }
        bytes.append(contentsOf: fragment)
        return true
    }
}
