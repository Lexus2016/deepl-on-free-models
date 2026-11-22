import Foundation

enum TranslationEvent: Sendable {
    case chunk(String)
    case stats(tokensPerSecond: Double?)
}

enum TranslationError: LocalizedError {
    case invalidURL(String)
    case emptyModel
    case connection(String)
    case http(Int, String)
    case backend(String)
    case modelNotFound(String)
    case emptyResponse

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

    static func chunks(from text: String) -> [TextChunk] {
        guard text.count > limit else {
            return [TextChunk(text: text, separatorBefore: "")]
        }

        struct Piece {
            let text: String
            let separator: String
        }

        var pieces: [Piece] = []
        let paragraphs = text.components(separatedBy: "\n\n")
        for (index, paragraph) in paragraphs.enumerated() {
            let paragraphSeparator = index == 0 ? "" : "\n\n"
            guard paragraph.count > limit else {
                pieces.append(Piece(text: paragraph, separator: paragraphSeparator))
                continue
            }
            let sentences = splitSentences(paragraph, limit: limit)
            for (sentenceIndex, sentence) in sentences.enumerated() {
                pieces.append(Piece(
                    text: sentence,
                    separator: sentenceIndex == 0 ? paragraphSeparator : " "
                ))
            }
        }

        var result: [TextChunk] = []
        var buffer = ""
        var bufferSeparator = ""

        for piece in pieces {
            if buffer.isEmpty {
                buffer = piece.text
                bufferSeparator = piece.separator
                continue
            }
            if buffer.count + piece.separator.count + piece.text.count <= limit {
                buffer += piece.separator + piece.text
            } else {
                result.append(TextChunk(text: buffer, separatorBefore: result.isEmpty ? "" : bufferSeparator))
                buffer = piece.text
                bufferSeparator = piece.separator
            }
        }
        if !buffer.isEmpty {
            result.append(TextChunk(text: buffer, separatorBefore: result.isEmpty ? "" : bufferSeparator))
        }
        return result
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
                    for chunk in chunks {
                        if Task.isCancelled { break }
                        if !chunk.separatorBefore.isEmpty {
                            if case .terminated = continuation.yield(.chunk(chunk.separatorBefore)) {
                                return
                            }
                        }
                        let prompt = PromptBuilder.prompt(
                            text: chunk.text,
                            style: style,
                            tone: tone,
                            targetLanguage: target.englishName
                        )
                        var produced = 0
                        for attempt in 0..<3 {
                            if attempt > 0 {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                            }
                            switch config.kind {
                            case .ollama:
                                produced = try await runOllama(prompt: prompt, config: config, continuation: continuation)
                            case .openAI:
                                produced = try await runOpenAI(prompt: prompt, config: config, continuation: continuation)
                            }
                            if produced > 0 { break }
                        }
                        if produced == 0 {
                            throw TranslationError.emptyResponse
                        }
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
