import XCTest
@testable import HyMT

final class HistoryStoreTests: XCTestCase {
    @MainActor
    func testQueuedAddAndClearWaitForLegacyHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appendingPathComponent("HyMT/history.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = entry("Hello", "Привіт")
        try JSONEncoder().encode([existing]).write(to: legacy)

        let store = HistoryStore(directory: folder)
        let new = entry("Good morning", "Доброго ранку")
        store.add(new)
        store.flush()
        let current = folder.appendingPathComponent("DeepL-oFM/history.json")
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode([HistoryEntry].self, from: Data(contentsOf: current)).map(\.id), [new.id, existing.id])

        store.clear()
        store.flush()
        XCTAssertTrue(try decoder.decode([HistoryEntry].self, from: Data(contentsOf: current)).isEmpty)
        XCTAssertEqual(try decoder.decode([HistoryEntry].self, from: Data(contentsOf: legacy)).map(\.id), [existing.id])
    }

    private func entry(_ source: String, _ result: String) -> HistoryEntry {
        HistoryEntry(
            sourceText: source, translatedText: result, sourceCode: "en", targetCode: "uk",
            style: .auto, tone: .standard, engine: "test", durationMs: 20
        )
    }
}
