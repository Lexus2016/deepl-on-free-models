import XCTest
@testable import HyMT

final class TranslationServiceTests: XCTestCase {
    func testModelListIsSplit() throws {
        let result = try XCTUnwrap(
            TranslationService.splitMixedLine(
                "tencent/hy-mt2-7b, google/gemma-4-31b-it:free — translation models"
            )
        )
        XCTAssertEqual(result.keep, "tencent/hy-mt2-7b, google/gemma-4-31b-it:free — ")
        XCTAssertEqual(result.translate, "translation models")
    }

    func testSingleModelIDIsSplit() {
        let result = TranslationService.splitMixedLine("llama-3.3-70b-versatile — a model")
        XCTAssertEqual(result?.keep, "llama-3.3-70b-versatile — ")
    }

    func testHyphenatedModelIDIsSplit() {
        let result = TranslationService.splitMixedLine("gpt-oss-120b — a model")
        XCTAssertEqual(result?.keep, "gpt-oss-120b — ")
    }

    func testProseWithSlashIsNotSplit() {
        XCTAssertNil(TranslationService.splitMixedLine("Use HTTP/2 — it is faster"))
    }

    func testTwoNamesWithSlashAreNotSplit() {
        XCTAssertNil(TranslationService.splitMixedLine("Google/YouTube — platforms"))
    }

    func testCJKScriptIncludesJapanese() {
        XCTAssertTrue(TranslationService.usesCJKScript("ja"))
        XCTAssertTrue(TranslationService.usesCJKScript("zh-Hant"))
        XCTAssertFalse(TranslationService.usesCJKScript("en"))
    }

    func testUkrainianAlphabet() {
        XCTAssertTrue(TranslationService.usesAllowedCyrillic("Привіт, це український текст.", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("маў", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("цѯнструмент", target: "uk"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("коштуђуце", target: "uk"))
    }

    func testRussianAlphabet() {
        XCTAssertTrue(TranslationService.usesAllowedCyrillic("Привет, это русский текст.", target: "ru"))
        XCTAssertFalse(TranslationService.usesAllowedCyrillic("Привіт", target: "ru"))
    }

    func testPreambleIsStripped() {
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Ось переклад тексту: «Привіт». Далі текст.",
                source: "Hello. More text."
            ),
            "Привіт. Далі текст."
        )
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Here is the translation: Hello.",
                source: "Привіт."
            ),
            "Hello."
        )
        XCTAssertEqual(
            TranslationService.stripPreamble(
                "Звісно! Цей пакет коштує 57 доларів.",
                source: "The bundle costs $57."
            ),
            "Цей пакет коштує 57 доларів."
        )
    }

    func testTargetScriptPresence() {
        XCTAssertTrue(TranslationService.hasTargetScript("Привіт", target: "uk"))
        XCTAssertFalse(TranslationService.hasTargetScript("Hello", target: "uk"))
        XCTAssertTrue(TranslationService.hasTargetScript("Hello", target: "en"))
        XCTAssertFalse(TranslationService.hasTargetScript("Привіт", target: "en"))
        XCTAssertTrue(TranslationService.hasTargetScript("こんにちは", target: "ja"))
        XCTAssertFalse(TranslationService.hasTargetScript("Hello", target: "ja"))
    }
}

extension TranslationServiceTests {
    func testSplitStopMarkerPreservesUnicode() {
        let expected = String(repeating: "é", count: 80) + " • 👩🏽‍💻 cafe\u{0301}"
        var output = TranslationOutput(maxBytes: 1_000)
        XCTAssertTrue(output.append(expected + "<"))
        XCTAssertFalse(output.append("｜hy_ending"))
        XCTAssertEqual(output.text, expected)
    }

    func testByteLimitRejectsInsteadOfCuttingAnEmoji() {
        var output = TranslationOutput(maxBytes: 4)
        XCTAssertTrue(output.append("éé"))
        XCTAssertFalse(output.append("😀"))
        XCTAssertTrue(output.exceededLimit)
        XCTAssertEqual(output.text, "éé")

        var exact = TranslationOutput(maxBytes: 4)
        XCTAssertFalse(exact.append("ééHY_END"))
        XCTAssertFalse(exact.exceededLimit)
        XCTAssertEqual(exact.text, "éé")
    }

    func testRetryAfterSupportsSecondsAndHTTPDates() {
        let epoch = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TranslationService.retryDelay(" 2 ", now: epoch), 2)
        XCTAssertEqual(TranslationService.retryDelay("Thu, 01 Jan 1970 00:00:05 GMT", now: epoch), 5)
        XCTAssertEqual(TranslationService.retryDelay("Thu, 01 Jan 1970 00:00:00 GMT", now: Date()), 0)
        XCTAssertNil(TranslationService.retryDelay("nan", now: epoch))
        XCTAssertNil(TranslationService.retryDelay("-1", now: epoch))
    }

    func testProviderStreamKeepsCompletedOutputOnly() async throws {
        let result = try await stream(from: "complete").0
        XCTAssertEqual(result, "Good morning.\nThe meeting is at nine.")
        do {
            _ = try await stream(from: "interrupted")
            XCTFail("A response without a terminal event must fail.")
        } catch TranslationError.unexpectedResponse {}
    }

    func testRateLimitIsReturnedImmediatelyWhenFallbackIsAvailable() async throws {
        let service = stubService()
        do {
            _ = try await service.translateBlock(
                text: "Guten Morgen.", style: .auto, tone: .standard,
                target: try XCTUnwrap(Language.with(code: "en")),
                config: stubConfig("limited"), retryRateLimit: false
            )
            XCTFail("The primary rate limit must be handed to the fallback.")
        } catch TranslationError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 20)
        }
    }

    func testCancellationInterruptsRateLimitSleep() async throws {
        let service = stubService()
        let config = stubConfig("limited")
        let target = try XCTUnwrap(Language.with(code: "en"))
        let task = Task {
            try await service.translateBlock(
                text: "Guten Morgen.", style: .auto, tone: .standard, target: target, config: config
            )
        }
        try await Task.sleep(for: .milliseconds(80))
        let started = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        }
    }

    private func stream(from host: String) async throws -> (String, Bool) {
        try await stubService().translateBlock(
            text: "Guten Morgen.\nDie Besprechung ist um neun.", style: .auto, tone: .standard,
            target: XCTUnwrap(Language.with(code: "en")), config: stubConfig(host)
        )
    }

    private func stubService() -> TranslationService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationStub.self]
        return TranslationService(session: URLSession(configuration: configuration))
    }

    private func stubConfig(_ host: String) -> BackendConfig {
        BackendConfig(
            kind: .openAI, baseURL: "https://\(host).example.test", model: "test", apiKey: "",
            temperature: 0.1, topP: 0.6, topK: 20, repetitionPenalty: 1, contextWindow: 8192
        )
    }
}

private final class TranslationStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let limited = url.host?.hasPrefix("limited.") == true
        let response = HTTPURLResponse(
            url: url, statusCode: limited ? 429 : 200, httpVersion: "HTTP/1.1",
            headerFields: limited ? ["Retry-After": "20"] : ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !limited {
            var body = #"data: {"choices":[{"delta":{"content":"Good morning.\nThe meeting is at nine."}}]}"# + "\n\n"
            if url.host?.hasPrefix("complete.") == true { body += "data: [DONE]\n\n" }
            client?.urlProtocol(self, didLoad: Data(body.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension TranslationServiceTests {
    @MainActor
    func testFilesSwitchOnceToFallbackAndPreserveParagraphs() async throws {
        let suite = "HyMTTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom", forKey: "hymt.provider")
        defaults.set("https://limited.example.test", forKey: "hymt.baseURL")
        defaults.set("test", forKey: "hymt.model")
        defaults.set(true, forKey: "hymt.fallbackEnabled")
        defaults.set("custom", forKey: "hymt.fallbackProvider")
        defaults.set("https://complete.example.test", forKey: "hymt.fallbackBaseURL")
        defaults.set("test", forKey: "hymt.fallbackModel")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        let body = "Guten Morgen.\nDie Besprechung ist um neun."
        let fencedCode = "```swift\n\nlet n = 10\n```"
        try [body, fencedCode, body].joined(separator: "\n\n").write(to: file, atomically: true, encoding: .utf8)

        let store = FileTranslationStore(service: stubService())
        defer { store.reset() }
        store.select(url: file, language: .en)
        store.targetCode = "en"
        store.translate(settings: AppSettings(defaults: defaults), language: .en)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while store.isWorking, .now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(store.state, .finished)
        XCTAssertTrue(store.usingFallback)
        XCTAssertEqual(store.total, 2)
        XCTAssertEqual(store.completed, 2)
        let output = try XCTUnwrap(store.outputURL)
        let translated = "Good morning.\nThe meeting is at nine."
        XCTAssertEqual(
            try String(contentsOf: output, encoding: .utf8),
            [translated, fencedCode, translated].joined(separator: "\n\n")
        )
    }
}

extension TranslationServiceTests {
    @MainActor
    func testCancellingFileDuringRetryLeavesNoOutputAndAllowsRestart() async throws {
        let suite = "HyMTTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom", forKey: "hymt.provider")
        defaults.set("https://limited.example.test", forKey: "hymt.baseURL")
        defaults.set("test", forKey: "hymt.model")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Guten Morgen.\nDie Besprechung ist um neun.".write(to: file, atomically: true, encoding: .utf8)

        let store = FileTranslationStore(service: stubService())
        defer { store.reset() }
        let settings = AppSettings(defaults: defaults)
        store.select(url: file, language: .en)
        store.targetCode = "en"
        store.translate(settings: settings, language: .en)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(store.isWorking)

        store.cancel()
        XCTAssertNil(store.outputURL)
        XCTAssertEqual(store.state, .idle)

        settings.baseURL = "https://complete.example.test"
        store.translate(settings: settings, language: .en)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while store.isWorking, .now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.state, .finished)
        XCTAssertEqual(store.completed, 1)
        XCTAssertNotNil(store.outputURL)
    }
}

extension TranslationServiceTests {
    func testMarkdownBlockStructureDetectsDroppedHeadingAndListItems() {
        let source = "# Title\n- One\n  - Two\n1. Three"
        let valid = "# Заголовок\n* Один\n  + Два\n1. Три"
        let incomplete = "* Один\n* Два\n1. Три"
        XCTAssertEqual(TranslationService.markdownStructure(source), TranslationService.markdownStructure(valid))
        XCTAssertNotEqual(TranslationService.markdownStructure(source), TranslationService.markdownStructure(incomplete))
    }
}
