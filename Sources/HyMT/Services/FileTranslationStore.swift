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

    private let service = TranslationService()
    private var task: Task<Void, Never>?

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

        let config = settings.snapshot
        let style = settings.lastStyle
        let tone = settings.lastTone

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try DocumentTranslator.read(url: url)
                let stream = service.stream(
                    text: document.text,
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
                    case .progress(let done, let all):
                        self.completed = done
                        self.total = all
                    case .warning:
                        self.warningCount += 1
                    case .stats:
                        break
                    }
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
                    translated: buffer,
                    to: output
                )

                self.outputURL = output
                self.completed = self.total
                self.state = .finished
            } catch is CancellationError {
                self.state = .idle
            } catch let error as DocumentError {
                self.state = .failed(error.message(language))
            } catch {
                self.state = .failed(
                    L10n.t("The file could not be translated.", language)
                )
            }
        }
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
