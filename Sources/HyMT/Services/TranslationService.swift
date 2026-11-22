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
    case connection(String)
    case http(Int, String)
    case backend(String)
    case modelNotFound(String)
    case emptyResponse
    case degenerateResponse

    func message(_ language: AppLanguage) -> String {
        switch self {
        case .invalidURL(let value):
            return L10n.format("Invalid server URL: %@", language, value)
        case .emptyModel:
            return L10n.t("No model name in settings.", language)
        case .connection(let host):
            return L10n.format("Could not connect to %@. Check that the server is running.", language, host)
        case .http(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
            if short.isEmpty {
                return L10n.format("Server returned error %@.", language, String(code))
            }
            return L10n.format("Server returned error %@: %@", language, String(code), short)
        case .backend(let message):
            return message
        case .modelNotFound(let model):
            return L10n.format("Model “%@” not found on the server.", language, model)
        case .emptyResponse:
            return L10n.t("The model returned an empty translation. Try again.", language)
        case .degenerateResponse:
            return L10n.t("The model could not produce a stable translation. Try again or switch the style/model.", language)
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
        let lines = text.components(separatedBy: "\n")
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

    private static func splitSentences(_ text: String, limit: Int) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            if let substring, !substring.isEmpty {
                sentences.append(substring)
            }
        }
        if sentences.isEmpty { sentences = [text] }

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

    func stream(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        target: Language,
        config: BackendConfig
    ) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !config.model.isEmpty else { throw TranslationError.emptyModel }
                    let chunks = TextChunker.chunks(from: text)
                    var completed = 0
                    for chunk in chunks {
                        if Task.isCancelled { break }
                        if !chunk.separatorBefore.isEmpty {
                            if case .terminated = continuation.yield(.chunk(chunk.separatorBefore)) {
                                return
                            }
                        }
                        let segment = parseSegment(chunk.text)
                            ?? Segment(prefix: "", body: chunk.text)
                        var prefix = segment.prefix
                        var body = segment.body

                        // Model lists and URLs must stay byte-for-byte: keep the
                        // left side of "IDs — description" and translate only
                        // the description.
                        if let mixed = splitMixedLine(body) {
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
                            targetLanguage: target.englishName
                        )
                        let neutralPrompt = PromptBuilder.prompt(
                            text: body,
                            style: .auto,
                            tone: .standard,
                            targetLanguage: target.englishName
                        )

                        let primary: String
                        let alternate: String
                        if body.count <= 80 {
                            primary = neutralHeading
                            alternate = neutralPrompt
                        } else {
                            primary = PromptBuilder.prompt(
                                text: body,
                                style: style,
                                tone: tone,
                                targetLanguage: target.englishName
                            )
                            alternate = neutralPrompt
                        }

                        var warning = false
                        var translated: String
                        do {
                            translated = try await bufferedTranslation(
                                primary: primary,
                                alternate: alternate,
                                source: body,
                                target: target,
                                config: config
                            )
                            translated = TokenRestorer.restore(source: body, translated: translated)
                            translated = TokenRestorer.preserveTrailingPunctuation(
                                source: body,
                                translated: translated
                            )
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
                            continuation.yield(.warning)
                        }
                        completed += 1
                        continuation.yield(.progress(completed, chunks.count))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
            #"^(\s*(?:[-*•–—]|\d+[.)])\s+)(.+)$"#
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

    private func splitMixedLine(_ text: String) -> (keep: String, translate: String)? {
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

        let hasSlash = left.contains("/")
        let isSingleToken = !left.contains(" ")
            && latin >= 8
            && left.contains(where: { $0.isNumber })
        guard hasSlash || isSingleToken else { return nil }

        return (left + " — ", right)
    }

    private func bufferedTranslation(
        primary: String,
        alternate: String,
        source: String,
        target: Language,
        config: BackendConfig
    ) async throws -> String {
        let prompts = [primary, alternate]
        for (promptIndex, prompt) in prompts.enumerated() {
            let attempts = promptIndex == 0 ? 3 : 2
            for attempt in 0..<attempts {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                var retryConfig = config
                if attempt > 0 {
                    retryConfig.temperature = min(config.temperature, 0.3)
                }
                let maxLength = max(200, source.count * 4 + 100)
                let raw = try await collect(
                    prompt: prompt,
                    config: retryConfig,
                    maxLength: maxLength,
                    target: target
                )
                if let clean = validated(raw, source: source, target: target) {
                    return clean
                }
            }
        }
        throw TranslationError.degenerateResponse
    }

    private func validated(_ raw: String, source: String, target: Language) -> String? {
        let sanitized = OutputSanitizer.clean(raw)
        guard !sanitized.isEmpty else { return nil }

        let cleaned = sanitized.replacingOccurrences(
            of: #"\s*\n\s*"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

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

        let cjkTargets = ["zh", "zh-Hant", "yue"]
        if !cjkTargets.contains(target.code) {
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
        }

        if source.count >= 40, cleaned.count > source.count * 4 {
            return nil
        }

        if cleaned.count > 120 {
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

    private func collect(
        prompt: String,
        config: BackendConfig,
        maxLength: Int,
        target: Language
    ) async throws -> String {
        var text = ""
        let stream = AsyncThrowingStream<TranslationEvent, Error> { continuation in
            let task = Task {
                do {
                    switch config.kind {
                    case .ollama:
                        _ = try await runOllama(prompt: prompt, config: config, continuation: continuation)
                    case .openAI:
                        _ = try await runOpenAI(prompt: prompt, config: config, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        for try await event in stream {
            if case .chunk(let piece) = event {
                text += piece
                if let cut = degenerateIndex(in: text, target: target) {
                    text = String(text[..<cut])
                    break
                }
                if text.count >= maxLength {
                    text = String(text.prefix(maxLength))
                    break
                }
            }
        }
        return text
    }

    private func degenerateIndex(in text: String, target: Language) -> String.Index? {
        let markers = ["hy-Assistant", "hy-User", "hy_end", "<｜", "<|", "</|", "｜hy"]
        var earliest: String.Index?
        for marker in markers {
            if let range = text.range(of: marker, options: .caseInsensitive),
               earliest == nil || range.lowerBound < earliest! {
                earliest = range.lowerBound
            }
        }

        let cjkTargets = ["zh", "zh-Hant", "yue"]
        if !cjkTargets.contains(target.code) {
            if let cjk = text.firstIndex(where: { character in
                character.unicodeScalars.contains { scalar in
                    (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
                }
            }), earliest == nil || cjk < earliest! {
                earliest = cjk
            }
        }
        return earliest
    }

    // MARK: - Ollama

    @discardableResult
    private func runOllama(
        prompt: String,
        config: BackendConfig,
        continuation: AsyncThrowingStream<TranslationEvent, Error>.Continuation
    ) async throws -> Int {
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
            "keep_alive": "30m",
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
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw TranslationError.connection(config.baseURL)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.connection(config.baseURL)
        }
        guard http.statusCode == 200 else {
            let body = try await collect(bytes)
            if http.statusCode == 404 {
                throw TranslationError.modelNotFound(config.model)
            }
            throw TranslationError.http(http.statusCode, body)
        }

        var produced = 0
        for try await line in bytes.lines {
            if Task.isCancelled { return produced }
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = object["error"] as? String {
                throw TranslationError.backend(error)
            }
            if let message = object["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                produced += content.trimmingCharacters(in: .whitespacesAndNewlines).count
                if case .terminated = continuation.yield(.chunk(content)) { return produced }
            }
            if object["done"] as? Bool == true {
                var tps: Double?
                if let count = object["eval_count"] as? Double,
                   let nanos = object["eval_duration"] as? Double,
                   nanos > 0 {
                    tps = count / (nanos / 1_000_000_000)
                }
                continuation.yield(.stats(tokensPerSecond: tps))
            }
        }
        return produced
    }

    // MARK: - OpenAI-compatible

    @discardableResult
    private func runOpenAI(
        prompt: String,
        config: BackendConfig,
        continuation: AsyncThrowingStream<TranslationEvent, Error>.Continuation
    ) async throws -> Int {
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
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw TranslationError.connection(config.baseURL)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.connection(config.baseURL)
        }
        guard http.statusCode == 200 else {
            let body = try await collect(bytes)
            if http.statusCode == 404 {
                throw TranslationError.modelNotFound(config.model)
            }
            throw TranslationError.http(http.statusCode, body)
        }

        var produced = 0
        for try await line in bytes.lines {
            if Task.isCancelled { return produced }
            guard line.hasPrefix("data:") else { continue }
            var payload = line.dropFirst(5)
            if payload.first == " " { payload = payload.dropFirst() }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TranslationError.backend(message)
            }
            if let choices = object["choices"] as? [[String: Any]],
               let first = choices.first {
                if let delta = first["delta"] as? [String: Any],
                   let content = delta["content"] as? String,
                   !content.isEmpty {
                    produced += content.trimmingCharacters(in: .whitespacesAndNewlines).count
                    if case .terminated = continuation.yield(.chunk(content)) { return produced }
                }
                if let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String,
                   !content.isEmpty {
                    produced += content.trimmingCharacters(in: .whitespacesAndNewlines).count
                    if case .terminated = continuation.yield(.chunk(content)) { return produced }
                }
            }
        }
        return produced
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

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 64_000 { break }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
