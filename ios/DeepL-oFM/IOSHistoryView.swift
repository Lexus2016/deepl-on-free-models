import SwiftUI
import UIKit

struct IOSHistoryView: View {
    @ObservedObject var history: HistoryStore
    var language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmsClear = false

    private var filtered: [HistoryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.sourceText.localizedStandardContains(search) || $0.translatedText.localizedStandardContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if history.hasStorageError {
                    Text(L10n.t("Could not read or save translation history.", language))
                        .foregroundStyle(.secondary)
                }
                if history.isLoading {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        L10n.t(query.isEmpty ? "History is empty" : "Nothing found", language),
                        systemImage: query.isEmpty ? "clock" : "magnifyingglass"
                    )
                }
                ForEach(filtered) { entry in
                    NavigationLink {
                        detail(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.sourceText).lineLimit(2)
                            Text(entry.translatedText).lineLimit(2).foregroundStyle(.secondary)
                            Text(entry.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("history-entry")
                    .swipeActions {
                        Button(role: .destructive) { history.remove(entry) } label: {
                            Label(L10n.t("Delete", language), systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: L10n.t("Search in history", language))
            .navigationTitle(L10n.t("History", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language)) { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        confirmsClear = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L10n.t("Clear history?", language))
                    .disabled(history.entries.isEmpty)
                }
            }
            .confirmationDialog(L10n.t("Clear history?", language), isPresented: $confirmsClear) {
                Button(L10n.t("Clear", language), role: .destructive) { history.clear() }
            }
        }
    }

    private func detail(_ entry: HistoryEntry) -> some View {
        List {
            Section(L10n.t("Source", language)) {
                Text(entry.sourceText).textSelection(.enabled)
            }
            Section(L10n.t("Translation", language)) {
                Text(entry.translatedText).textSelection(.enabled)
                Button(L10n.t("Copy translation", language)) {
                    UIPasteboard.general.string = entry.translatedText
                }
            }
        }
        .navigationTitle(L10n.t("Translation", language))
    }
}
