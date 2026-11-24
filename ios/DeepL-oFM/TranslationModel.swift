import Foundation

@MainActor
final class TranslationModel: ObservableObject {
    @Published var sourceText = ""
    @Published var translatedText = ""
    private(set) var plainText = ""
    private(set) var renderedText = AttributedString()
    @Published private(set) var hasInput = false
    @Published var isTranslating = false
    @Published var completed = 0
    @Published var total = 0
    @Published var warningCount = 0
    @Published var errorMessage: String?
    @Published var detected: Language?
    @Published var durationMs: Int?
    @Published var tokensPerSecond: Double?

    private let service = TranslationService()
    private var task: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        if isTranslating { isTranslating = false }
    }

    func sourceDidChange(language: AppLanguage) {
        invalidateResult()
        hasInput = sourceText.contains { !$0.isWhitespace }
        detectionTask?.cancel()
        guard hasInput else {
            detected = nil
            return
        }
        let sample = String(sourceText.prefix(600))
        detectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.detected = Language.detect(sample, preferred: language)
        }
    }

    func invalidateResult() {
        cancel()
        if !translatedText.isEmpty {
            translatedText = ""
            plainText = ""
            renderedText = AttributedString()
        }
        errorMessage = nil
        durationMs = nil
        completed = 0
        total = 0
        tokensPerSecond = nil
        warningCount = 0
    }

    func translate(configuration: IOSTranslationConfiguration, sourceCode: String) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let language = configuration.interfaceLanguage
        invalidateResult()
        detectionTask?.cancel()

        if configuration.provider.requiresKey, configuration.apiKey.isEmpty {
            errorMessage = L10n.t("Add your API key in Settings.", language)
            return
        }

        isTranslating = true
        let source = Language.with(code: sourceCode)
        detected = source ?? Language.detect(text, preferred: language)

        let target = configuration.target
        let style = configuration.style
        let tone = configuration.tone
        let config = configuration.backend
        let started = Date()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = service.stream(
                    text: text,
                    style: style,
                    tone: tone,
                    target: target,
                    config: config,
                    sourceLanguage: source
                )
                var buffer = ""
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .chunk(let piece):
                        buffer += piece
                    case .stats(let speed):
                        self.tokensPerSecond = speed
                    case .progress(let done, let all):
                        self.completed = done
                        self.total = all
                    case .warning:
                        self.warningCount += 1
                    }
                }
                let text = buffer
                let display = await Self.makeDisplay(text)
                try Task.checkCancellation()
                self.plainText = display.plain
                self.renderedText = display.rendered
                self.translatedText = text
                self.isTranslating = false
                self.durationMs = Int(Date().timeIntervalSince(started) * 1000)
                if self.warningCount > 0 {
                    self.errorMessage = L10n.format(
                        "Some lines could not be translated (%d); they are left in the source language.",
                        language,
                        self.warningCount
                    )
                }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.isTranslating = false
                self.errorMessage = (error as? TranslationError)?.message(language) ?? error.localizedDescription
            }
        }
    }
    private nonisolated static func makeDisplay(_ text: String) async -> (plain: String, rendered: AttributedString) {
        (IOSMarkdown.plain(text), IOSMarkdown.rendered(text))
    }

}
