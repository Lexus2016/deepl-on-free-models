import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var confirmClear = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var filtered: [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return app.history.entries }
        return app.history.entries.filter { entry in
            entry.sourceText.lowercased().contains(needle)
                || entry.translatedText.lowercased().contains(needle)
                || (Language.with(code: entry.targetCode)?.displayName(in: language).lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry)
                            Rectangle().fill(Theme.borderSoft).frame(height: 1)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.window)
        .alert(L10n.t("Clear history?", language), isPresented: $confirmClear) {
            Button(L10n.t("Cancel", language), role: .cancel) {}
            Button(L10n.t("Clear", language), role: .destructive) { app.history.clear() }
        } message: {
            Text(L10n.t("All saved translations will be deleted permanently.", language))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.t("History", language))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(app.history.entries.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
                    .monospacedDigit()
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                TextField(L10n.t("Search in history", language), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .frame(width: 200)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.editor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )

            Button {
                confirmClear = true
            } label: {
                Text(L10n.t("Clear", language))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(app.history.entries.isEmpty ? Theme.tertiary : Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.editor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(app.history.entries.isEmpty)
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(Theme.chrome)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text(query.isEmpty ? L10n.t("History is empty", language) : L10n.t("Nothing found", language))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text(query.isEmpty
                 ? L10n.t("Translations will be saved here automatically.", language)
                 : L10n.t("Try another query.", language))
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRow: View {
    @EnvironmentObject private var app: AppState
    let entry: HistoryEntry
    @State private var copied = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = language.resolved == .en ? "MMM d, HH:mm" : "d MMM, HH:mm"
        return formatter.string(from: entry.date)
    }

    private var sourceLanguage: String {
        let value = Language.with(code: entry.sourceCode) ?? .auto
        return value.displayName(in: language)
    }

    private var targetLanguage: String {
        Language.with(code: entry.targetCode)?.displayName(in: language) ?? entry.targetCode
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(sourceLanguage.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                    Text(targetLanguage.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)

                    SmallChip(text: L10n.t(entry.style.title, language), color: Theme.secondary, background: Theme.editor)
                    if entry.tone != .standard {
                        SmallChip(text: L10n.t(entry.tone.title, language), color: Theme.secondary, background: Theme.editor)
                    }

                    Spacer(minLength: 12)
                    Text(dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }

                Text(entry.sourceText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                Text(entry.translatedText.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                app.loadHistory(entry)
            }

            HStack(spacing: 4) {
                IconButton(systemName: copied ? "checkmark" : "doc.on.doc", help: L10n.t("Copy translation", language)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.translatedText, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copied = false }
                    }
                }
                IconButton(systemName: "trash", help: L10n.t("Delete entry", language)) {
                    app.history.remove(entry)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Theme.window)
        .hoverHighlight()
    }
}
