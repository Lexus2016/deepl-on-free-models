import Foundation
import Combine

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
    @Published private(set) var isLoading = true
    @Published private(set) var hasStorageError = false

    private let disk: HistoryDisk

    init(directory: URL? = nil) {
        let support = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        disk = HistoryDisk(support: support)
        update { _ in false }
    }

    func add(_ entry: HistoryEntry) {
        guard !entry.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        update { entries in
            if let first = entries.first,
               first.sourceText == entry.sourceText,
               first.translatedText == entry.translatedText,
               first.targetCode == entry.targetCode {
                return false
            }
            entries.insert(entry, at: 0)
            if entries.count > 400 { entries.removeLast(entries.count - 400) }
            return true
        }
    }

    func remove(_ entry: HistoryEntry) {
        update { entries in
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
            entries.remove(at: index)
            return true
        }
    }

    func clear() {
        update { entries in
            entries.removeAll()
            return true
        }
    }

    func flush() {
        disk.flush()
    }

    private func update(_ change: @escaping @Sendable (inout [HistoryEntry]) -> Bool) {
        disk.update(change) { [weak self] entries, failed in
            self?.entries = entries
            self?.hasStorageError = failed
            self?.isLoading = false
        }
    }
}

private final class HistoryDisk: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ua.admin.hymt.history", qos: .utility)
    private let support: URL
    private var entries: [HistoryEntry]?

    init(support: URL) {
        self.support = support
    }

    func update(
        _ change: @escaping @Sendable (inout [HistoryEntry]) -> Bool,
        publish: @escaping @MainActor @Sendable ([HistoryEntry], Bool) -> Void
    ) {
        queue.async {
            var failed = false
            let folder = self.support.appendingPathComponent("DeepL-oFM", isDirectory: true)
            let file = folder.appendingPathComponent("history.json")
            do {
                if self.entries == nil {
                    let legacy = self.support.appendingPathComponent("HyMT/history.json")
                    if FileManager.default.fileExists(atPath: file.path) {
                        self.entries = try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: file))
                    } else if FileManager.default.fileExists(atPath: legacy.path) {
                        let data = try Data(contentsOf: legacy)
                        let history = try JSONDecoder().decode([HistoryEntry].self, from: data)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try data.write(to: file, options: .atomic)
                        self.entries = history
                    } else {
                        self.entries = []
                    }
                }
                if var updated = self.entries, change(&updated) {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let data = try JSONEncoder().encode(updated)
                    try data.write(to: file, options: .atomic)
                    self.entries = updated
                }
            } catch {
                failed = true
            }
            let snapshot = self.entries ?? []
            let storageError = failed
            DispatchQueue.main.async { publish(snapshot, storageError) }
        }
    }

    func flush() {
        queue.sync {}
    }
}
