import Foundation
import Combine

@MainActor
final class WriteStore: ObservableObject {
    @Published var sourceText = "" {
        didSet {
            guard oldValue != sourceText else { return }
            cancel()
            if !resultText.isEmpty { resultText = "" }
            if errorMessage != nil { errorMessage = nil }
            if durationMs != nil { durationMs = nil }
        }
    }
    @Published var resultText = ""
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var durationMs: Int?
    @Published var languageCode: String
    @Published var languageWasChosen = false
    @Published var mode: ResultViewMode = .preview

    private let service = TranslationService()
    private var task: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?

    func updateDetectedLanguage() {
        detectionTask?.cancel()
        guard !languageWasChosen else { return }
        let input = sourceText
        detectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, !languageWasChosen,
                  let detected = Language.detect(input),
                  detected.code != languageCode else { return }
            languageCode = detected.code
        }
    }

    init() {
        languageCode = UserDefaults.standard.string(forKey: "hymt.lastTarget") ?? "en"
    }

    #if os(macOS)
    func improve(settings: AppSettings, interfaceLanguage: AppLanguage) {
        improve(primary: settings.snapshot, fallback: settings.fallbackConfig, interfaceLanguage: interfaceLanguage)
    }
    #endif

    func improve(primary: BackendConfig, fallback: BackendConfig? = nil, interfaceLanguage: AppLanguage) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = languageWasChosen ? nil : Language.detect(text)
        guard !text.isEmpty, let language = detected ?? Language.with(code: languageCode) else {
            return
        }

        let fallback = fallback.flatMap { primary.usesSameEndpoint(as: $0) ? nil : $0 }

        task?.cancel()
        isWorking = true
        resultText = ""
        errorMessage = nil
        durationMs = nil

        let languageName = language.englishName
        let prompt = """
        You are an editor. Rewrite the following text in \(languageName). Improve
        clarity, grammar, tone and style. Preserve the meaning, Markdown syntax,
        lists and line breaks. Return only the rewritten text, without
        explanations or quotes.

        \(text)
        """
        let started = ContinuousClock.now

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result: String
                do {
                    result = try await service.rewrite(
                        prompt: prompt, config: primary, retryRateLimit: fallback == nil
                    )
                } catch {
                    try Task.checkCancellation()
                    guard let fallback else { throw error }
                    result = try await service.rewrite(prompt: prompt, config: fallback)
                }
                try Task.checkCancellation()
                self.resultText = result
                self.isWorking = false
                let elapsed = started.duration(to: .now).components
                self.durationMs = Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.isWorking = false
                self.errorMessage = (error as? TranslationError)?.message(interfaceLanguage) ?? error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isWorking { isWorking = false }
    }
}
