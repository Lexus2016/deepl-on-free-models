import SwiftUI

struct WriteView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store: WriteStore

    @State private var copied = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                languageRow
                sourceCard
                improveButton
                resultCard
            }
            .padding(24)
        }
        .background(Theme.window)
        .onChange(of: store.sourceText) { _, _ in
            store.updateDetectedLanguage()
        }
        .onAppear {
            store.updateDetectedLanguage()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DeepL Write")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(L10n.t("Improve clarity, grammar and style while keeping the meaning.", language))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private var languageRow: some View {
        HStack(spacing: 10) {
            Text(L10n.t("Improve in", language))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Picker("", selection: Binding(
                get: { store.languageCode },
                set: {
                    store.languageCode = $0
                    store.languageWasChosen = true
                }
            )) {
                ForEach(Language.all) { item in
                    Text(item.displayName(in: language)).tag(item.code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)
            Spacer()
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Source", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if !store.sourceText.isEmpty {
                    Button {
                        store.sourceText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Clear", language))
                }
            }

            ZStack(alignment: .topLeading) {
                if store.sourceText.isEmpty {
                    Text(L10n.t("Type or paste text to improve", language))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $store.sourceText)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.editor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var improveButton: some View {
        Button {
            store.improve(settings: app.settings, interfaceLanguage: language)
        } label: {
            HStack(spacing: 8) {
                if store.isWorking {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(
                    store.isWorking
                        ? L10n.t("Improving…", language)
                        : L10n.t("Improve text", language)
                )
                .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.accentGradient))
        }
        .buttonStyle(.plain)
        .disabled(
            store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || store.isWorking
        )
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.t("Result", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)

                Spacer()

                if !store.resultText.isEmpty {
                    Button {
                        ClipboardWriter.copy(store.resultText)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? Theme.success : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("Copy", language))
                }

                Picker("", selection: $store.mode) {
                    ForEach(ResultViewMode.allCases) { item in
                        Text(L10n.t(item.titleKey, language)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            Group {
                if store.resultText.isEmpty {
                    if store.isWorking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t("Improving…", language))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.tertiary)
                        }
                    } else {
                        Text(L10n.t("Improved text will appear here", language))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                } else {
                    switch store.mode {
                    case .preview:
                        MarkdownPreview(markdown: store.resultText)
                    case .text:
                        ResultText(
                            text: MarkdownRenderer.plainText(store.resultText),
                            translating: false,
                            caretVisible: false
                        )
                    case .markdown:
                        ResultText(
                            text: store.resultText,
                            translating: false,
                            caretVisible: false
                        )
                    }
                }
            }
            .frame(minHeight: 220, maxHeight: 320, alignment: .topLeading)

            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.danger)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: 0x2A1A1C))
                )
            }

            if let ms = store.durationMs {
                Text(L10n.seconds(Double(ms) / 1000, language))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
