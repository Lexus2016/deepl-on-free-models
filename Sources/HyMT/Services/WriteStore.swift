import Foundation

@MainActor
final class WriteStore: ObservableObject {
    @Published var sourceText = ""
    @Published var resultText = ""
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var durationMs: Int?
    @Published var languageCode: String
    @Published var languageWasChosen = false
    @Published var mode: ResultViewMode = .preview

    private let service = TranslationService()
    private var task: Task<Void, Never>?

    func updateDetectedLanguage() {
        guard !languageWasChosen,
              let detected = Language.detect(sourceText) else { return }
        languageCode = detected.code
    }

    init() {
        languageCode = UserDefaults.standard.string(forKey: "hymt.lastTarget") ?? "en"
    }

    func improve(settings: AppSettings, interfaceLanguage: AppLanguage) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let language = Language.with(code: languageCode) else {
            return
        }

        let cloud = [Provider.groq, .openRouter, .cerebras, .ollamaCloud]
        if cloud.contains(settings.provider),
           settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = L10n.t("Add your API key in Settings.", interfaceLanguage)
            return
        }

        task?.cancel()
        isWorking = true
        resultText = ""
        errorMessage = nil
        durationMs = nil

        let config = settings.snapshot
        let languageName = language.englishName
        let prompt = """
        You are an editor. Rewrite the following text in \(languageName). Improve
        clarity, grammar, tone and style. Preserve the meaning, Markdown syntax,
        lists and line breaks. Return only the rewritten text, without
        explanations or quotes.

        \(text)
        """
        let started = Date()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = service.streamRaw(prompt: prompt, config: config)
                var buffer = ""
                for try await event in stream {
                    if Task.isCancelled { return }
                    if case .chunk(let piece) = event {
                        buffer += piece
                        self.resultText = buffer
                    }
                }
                self.isWorking = false
                self.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            } catch is CancellationError {
                self.isWorking = false
            } catch let translation as TranslationError {
                self.isWorking = false
                self.errorMessage = translation.message(interfaceLanguage)
            } catch {
                self.isWorking = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        isWorking = false
    }
}
