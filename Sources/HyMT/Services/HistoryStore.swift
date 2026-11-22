import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date = Date()
    var sourceText: String
    var translatedText: String
    var sourceCode: String
    var targetCode: String
    var style: TranslationStyle
    var tone: TranslationTone
    var engine: String
    var durationMs: Int
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let limit = 400
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent("DeepL-oFM", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let target = folder.appendingPathComponent("history.json")
        let legacy = support
            .appendingPathComponent("HyMT", isDirectory: true)
            .appendingPathComponent("history.json")
        if !FileManager.default.fileExists(atPath: target.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            // The app was called HyMT before 1.0.5. Copy the old history once;
            // never mutate the old file, so a failed migration is recoverable.
            try? FileManager.default.copyItem(at: legacy, to: target)
        }

        fileURL = target
        load()
    }

    func add(_ entry: HistoryEntry) {
        guard !entry.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let first = entries.first,
           first.sourceText == entry.sourceText,
           first.translatedText == entry.translatedText,
           first.targetCode == entry.targetCode {
            return
        }
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
