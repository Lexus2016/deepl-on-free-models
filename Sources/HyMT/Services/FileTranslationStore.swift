import AppKit
import Foundation

@MainActor
final class FileTranslationStore: ObservableObject {
    enum State: Equatable {
        case idle
        case working
        case finished
        case failed(String)
    }

    @Published var selectedURL: URL?
    @Published var kind: DocumentKind?
    @Published var targetCode: String
    @Published var state: State = .idle
    @Published var completed = 0
    @Published var total = 0
    @Published var warningCount = 0
    @Published var outputURL: URL?
    @Published var usingFallback = false
    @Published var fallbackLabel: String?

    private let service = TranslationService()
    private var task: Task<Void, Never>?

    private static let cloudProviders: Set<Provider> = [
        .groq, .openRouter, .cerebras, .ollamaCloud
    ]

    init() {
        targetCode = UserDefaults.standard.string(forKey: "hymt.lastTarget") ?? "en"
    }

    var percent: Int {
        guard total > 0 else { return 0 }
        return min(100, Int((Double(completed) / Double(total) * 100).rounded()))
    }

    var isWorking: Bool { state == .working }

    var fileName: String? { selectedURL?.lastPathComponent }

    var outputName: String? { outputURL?.lastPathComponent }

    var formattedSize: String? {
        guard let selectedURL,
              let values = try? selectedURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    func chooseFile(language: AppLanguage) {
        let panel = NSOpenPanel()
        panel.title = L10n.t("Translate file…", language)
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = DocumentTranslator.supportedContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        select(url: url, language: language)
    }

    func select(url: URL, language: AppLanguage) {
        guard let kind = DocumentKind.from(url: url) else {
            state = .failed(L10n.t("This file type is not supported.", language))
            return
        }
        task?.cancel()
        removeTemporaryOutput()
        selectedURL = url
        self.kind = kind
        outputURL = nil
        completed = 0
        total = 0
        warningCount = 0
        usingFallback = false
        fallbackLabel = nil
        state = .idle
    }

    func translate(settings: AppSettings, language: AppLanguage) {
        guard let url = selectedURL,
              let target = Language.with(code: targetCode) else { return }

        task?.cancel()
        removeTemporaryOutput()
        state = .working
        completed = 0
        total = 0
        warningCount = 0
        outputURL = nil
        usingFallback = false
        fallbackLabel = nil

        let primary = settings.snapshot
        let fallback = settings.fallbackConfig
        let fallbackProvider = settings.fallbackProvider
        let fallbackModel = settings.fallbackModel
        let style = settings.lastStyle
        let tone = settings.lastTone

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try DocumentTranslator.read(url: url)
                let units = Self.translationUnits(for: document)
                self.total = units.filter {
                    !$0.trimmingCharacters(in: .whitespaces).isEmpty
                }.count

                var config = primary
                var provider = settings.provider
                var switched = false
                var translatedUnits: [String] = []

                for unit in units {
                    if Task.isCancelled { return }
                    let trimmed = unit.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        translatedUnits.append("")
                        continue
                    }

                    let translated: String
                    do {
                        translated = try await self.translateBlock(
                            trimmed,
                            target: target,
                            style: style,
                            tone: tone,
                            config: config,
                            retryRateLimit: fallback == nil
                        )
                    } catch {
                        guard let fallback, !switched else { throw error }
                        switched = true
                        self.usingFallback = true
                        self.fallbackLabel = "\(fallbackProvider.title) · \(fallbackModel)"
                        NSLog(
                            "DeepL-oFM file translation switched to fallback: %@",
                            fallbackProvider.rawValue
                        )
                        config = fallback
                        provider = fallbackProvider
                        translated = try await self.translateBlock(
                            trimmed,
                            target: target,
                            style: style,
                            tone: tone,
                            config: fallback,
                            retryRateLimit: true
                        )
                    }

                    translatedUnits.append(
                        translated.replacingOccurrences(of: "\n", with: " ")
                    )
                    self.completed += 1

                    // Groq's free tier allows 30 requests per minute. The
                    // paragraph-level request means far fewer calls than lines.
                    if Self.cloudProviders.contains(provider) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                    }
                }

                let translatedText: String
                switch document.kind {
                case .pdf, .docx:
                    translatedText = translatedUnits.joined(separator: "\n")
                case .text, .markdown:
                    translatedText = translatedUnits.joined(separator: "\n\n")
                }

                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DeepL-oFM-Files", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let base = url.deletingPathExtension().lastPathComponent
                let name = "\(base)_\(target.code).\(document.kind.fileExtension)"
                let output = directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: output)
                try DocumentTranslator.write(
                    document: document,
                    translated: translatedText,
                    to: output
                )

                self.outputURL = output
                self.completed = self.total
                self.state = .finished
            } catch is CancellationError {
                self.state = .idle
            } catch let error as DocumentError {
                NSLog("DeepL-oFM file read/write failed: %@", String(describing: error))
                self.state = .failed(error.message(language))
            } catch let error as TranslationError {
                NSLog("DeepL-oFM file translation error: %@", String(describing: error))
                self.state = .failed(error.message(language))
            } catch {
                NSLog("DeepL-oFM file translation failed: %@", String(describing: error))
                let detail = error.localizedDescription
                self.state = .failed(
                    detail.isEmpty
                        ? L10n.t("The file could not be translated.", language)
                        : detail
                )
            }
        }
    }

    private static func translationUnits(for document: OpenedDocument) -> [String] {
        switch document.kind {
        case .pdf, .docx:
            if !document.paragraphs.isEmpty {
                return document.paragraphs
            }
            return document.text.components(separatedBy: "\n")
        case .text, .markdown:
            return document.text.components(separatedBy: "\n\n")
        }
    }

    private func translateBlock(
        _ text: String,
        target: Language,
        style: TranslationStyle,
        tone: TranslationTone,
        config: BackendConfig,
        retryRateLimit: Bool
    ) async throws -> String {
        var lastError: Error?
        let attempts = retryRateLimit ? 2 : 1

        for attempt in 0..<attempts {
            do {
                let stream = service.streamBlock(
                    text: text,
                    style: style,
                    tone: tone,
                    target: target,
                    config: config
                )
                var buffer = ""
                for try await event in stream {
                    if Task.isCancelled { throw CancellationError() }
                    switch event {
                    case .chunk(let piece):
                        buffer += piece
                    case .warning:
                        self.warningCount += 1
                    default:
                        break
                    }
                }
                let cleaned = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    throw TranslationError.emptyResponse
                }
                return cleaned
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TranslationError {
                if retryRateLimit,
                   case .http(let code, _) = error,
                   code == 429,
                   attempt == 0 {
                    lastError = error
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? TranslationError.emptyResponse
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
        completed = 0
        total = 0
        removeTemporaryOutput()
    }

    func saveOutput(language: AppLanguage) {
        guard let outputURL else { return }
        let panel = NSSavePanel()
        panel.title = L10n.t("Save translation…", language)
        panel.nameFieldStringValue = outputURL.lastPathComponent
        if let kind, let type = kind.contentType {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: outputURL, to: destination)
        } catch {
            state = .failed(L10n.t("The file could not be saved.", language))
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        removeTemporaryOutput()
        selectedURL = nil
        kind = nil
        outputURL = nil
        usingFallback = false
        fallbackLabel = nil
        state = .idle
        completed = 0
        total = 0
    }

    private func removeTemporaryOutput() {
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
    }
}
