import AppKit
import Foundation
import Darwin

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
    @Published private(set) var saveError: String?
    @Published private(set) var isSaving = false
    @Published private(set) var isPreparingOutput = false
    private(set) var formattedSize: String?

    private let service: TranslationService
    private var task: Task<Void, Never>?

    init(service: TranslationService = TranslationService()) {
        self.service = service
        targetCode = UserDefaults.standard.string(forKey: "hymt.lastTarget") ?? "en"
    }

    var percent: Int {
        guard total > 0 else { return 0 }
        return min(100, Int((Double(completed) / Double(total) * 100).rounded()))
    }

    var isWorking: Bool { state == .working }

    var fileName: String? { selectedURL?.lastPathComponent }

    var outputName: String? { outputURL?.lastPathComponent }

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
        guard !isSaving else { return }
        guard let kind = DocumentKind.from(url: url), !url.hasDirectoryPath else {
            state = .failed(L10n.t("This file type is not supported.", language))
            return
        }
        task?.cancel()
        removeTemporaryOutput()
        formattedSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
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
        guard !isSaving, let url = selectedURL,
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
        let fallback = settings.fallbackConfig.flatMap { primary.usesSameEndpoint(as: $0) ? nil : $0 }
        let primaryProvider = settings.provider
        let fallbackProvider = settings.fallbackProvider
        let fallbackModel = settings.fallbackModel
        let style = settings.lastStyle
        let tone = settings.lastTone

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let (document, units) = try await Self.performFileWork {
                    let document = try DocumentTranslator.read(url: url)
                    return (document, Self.translationUnits(for: document))
                }
                try Task.checkCancellation()
                self.total = units.lazy.filter(\.needsTranslation).count

                var config = primary
                var provider = primaryProvider
                var switched = false
                var nextGroqRequest: ContinuousClock.Instant?
                let clock = ContinuousClock()
                var translatedUnits: [String] = []
                translatedUnits.reserveCapacity(units.count)

                for unit in units {
                    try Task.checkCancellation()
                    guard unit.needsTranslation else {
                        translatedUnits.append(unit.text)
                        continue
                    }

                    if provider == .groq {
                        if let nextGroqRequest { try await clock.sleep(until: nextGroqRequest) }
                        nextGroqRequest = clock.now.advanced(by: .milliseconds(2_200))
                    }

                    let translation: (text: String, warning: Bool)
                    do {
                        translation = try await service.translateBlock(
                            text: unit.text, style: style, tone: tone, target: target, config: config,
                            retryRateLimit: fallback == nil || switched
                        )
                    } catch {
                        try Task.checkCancellation()
                        guard let fallback, !switched else {
                            if case TranslationError.degenerateResponse = error {
                                translatedUnits.append(unit.text)
                                self.warningCount += 1
                                self.completed += 1
                                continue
                            }
                            throw error
                        }
                        switched = true
                        self.usingFallback = true
                        self.fallbackLabel = "\(fallbackProvider.title) · \(fallbackModel)"
                        config = fallback
                        provider = fallbackProvider
                        if provider == .groq {
                            nextGroqRequest = clock.now.advanced(by: .milliseconds(2_200))
                        }
                        do {
                            translation = try await service.translateBlock(
                                text: unit.text, style: style, tone: tone, target: target, config: fallback
                            )
                        } catch TranslationError.degenerateResponse {
                            translation = (unit.text, true)
                        }
                    }
                    try Task.checkCancellation()
                    translatedUnits.append(translation.text)
                    self.completed += 1
                    if translation.warning { self.warningCount += 1 }
                }

                if self.total > 0, self.warningCount == self.total {
                    throw TranslationError.degenerateResponse
                }
                self.isPreparingOutput = true
                let prepared = translatedUnits
                let output = try await Self.performFileWork {
                    try Self.createOutput(document: document, translatedUnits: prepared, target: target)
                }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
                    return
                }
                self.outputURL = output
                self.isPreparingOutput = false
                self.state = .finished
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.isPreparingOutput = false
                if let error = error as? DocumentError {
                    self.state = .failed(error.message(language))
                } else if let error = error as? TranslationError {
                    self.state = .failed(error.message(language))
                } else {
                    self.state = .failed(L10n.t("The file could not be translated.", language))
                }
            }
        }
    }

    private struct TranslationUnit: Sendable {
        let text: String
        let needsTranslation: Bool
    }

    private nonisolated static func translationUnits(for document: OpenedDocument) -> [TranslationUnit] {
        switch document.kind {
        case .pdf, .docx:
            return document.paragraphs.map {
                TranslationUnit(text: $0, needsTranslation: !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        case .text, .markdown:
            return DocumentTranslator.textUnits(in: document.text, markdown: document.kind == .markdown)
                .map { TranslationUnit(text: $0.text, needsTranslation: $0.translate) }
        }
    }

    private nonisolated static func performFileWork<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let operation = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private nonisolated static func createOutput(
        document: OpenedDocument, translatedUnits: [String], target: Language
    ) throws -> URL {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepL-oFM-Files", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = document.url.deletingPathExtension().lastPathComponent
        let output = directory.appendingPathComponent("\(base)_\(target.code).\(document.kind.fileExtension)")
        do {
            try DocumentTranslator.write(document: document, translatedUnits: translatedUnits, to: output)
            try Task.checkCancellation()
            return output
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
        completed = 0
        total = 0
        warningCount = 0
        usingFallback = false
        fallbackLabel = nil
        isPreparingOutput = false
        removeTemporaryOutput()
    }

    func saveOutput(language: AppLanguage) {
        guard !isSaving, let outputURL else { return }
        let panel = NSSavePanel()
        panel.title = L10n.t("Save translation…", language)
        panel.nameFieldStringValue = outputURL.lastPathComponent
        if let kind, let type = kind.contentType { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        saveError = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await Self.performFileWork {
                    try Self.saveCopy(from: outputURL, to: destination)
                }
            } catch {
                saveError = L10n.t("The file could not be saved.", language)
            }
        }
    }

    nonisolated static func saveCopy(from source: URL, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".hymt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        let result = staging.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                rename(from, to)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func reset() {
        guard !isSaving else { return }
        task?.cancel()
        task = nil
        removeTemporaryOutput()
        selectedURL = nil
        formattedSize = nil
        kind = nil
        warningCount = 0
        isPreparingOutput = false
        outputURL = nil
        usingFallback = false
        fallbackLabel = nil
        state = .idle
        completed = 0
        total = 0
    }

    private func removeTemporaryOutput() {
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
        }
        outputURL = nil
        saveError = nil
        isPreparingOutput = false
    }
}
