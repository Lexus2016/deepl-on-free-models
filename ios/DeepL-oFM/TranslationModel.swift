import Foundation

@MainActor
final class TranslationModel: ObservableObject {
    @Published var sourceText = ""
    @Published var translatedText = ""
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

    func cancel() {
        task?.cancel()
        isTranslating = false
    }

    func translate(settings: IOSSettings) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let language = settings.interfaceLanguage

        if settings.needsAPIKey,
           settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = L10n.t("Add your API key in Settings.", language)
            return
        }

        task?.cancel()
        isTranslating = true
        translatedText = ""
        errorMessage = nil
        warningCount = 0
        completed = 0
        total = 0
        durationMs = nil
        tokensPerSecond = nil
        detected = Language.detect(text, preferred: language)

        let target = settings.target
        let style = settings.style
        let tone = settings.tone
        let config = settings.snapshot
        let started = Date()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = service.stream(
                    text: text,
                    style: style,
                    tone: tone,
                    target: target,
                    config: config
                )
                var buffer = ""
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .chunk(let piece):
                        buffer += piece
                        self.translatedText = buffer
                    case .stats(let speed):
                        self.tokensPerSecond = speed
                    case .progress(let done, let all):
                        self.completed = done
                        self.total = all
                    case .warning:
                        self.warningCount += 1
                    }
                }
                self.isTranslating = false
                self.durationMs = Int(Date().timeIntervalSince(started) * 1000)
                if self.warningCount > 0 {
                    self.errorMessage = L10n.format(
                        "Some lines could not be translated (%d); they are left in the source language.",
                        language,
                        self.warningCount
                    )
                }
            } catch is CancellationError {
                self.isTranslating = false
            } catch let translation as TranslationError {
                self.isTranslating = false
                self.errorMessage = translation.message(language)
            } catch {
                self.isTranslating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
