import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store: FileTranslationStore

    @State private var dropTargeted = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if store.selectedURL == nil {
                    dropZone
                    if case .failed(let message) = store.state {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                    }
                } else {
                    fileContent
                }
            }
            .frame(maxWidth: 740, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.window)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("Files", language))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(L10n.t("Translate a document and save the result in its original format.", language))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(L10n.t("Drop a file here or choose one", language))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(L10n.t("Supported formats: TXT, Markdown, PDF and DOCX.", language))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }

            Button {
                store.chooseFile(language: language)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "folder")
                    Text(L10n.t("Choose a file…", language))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    dropTargeted ? Theme.accent : Theme.border,
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7, 5])
                )
        )
    }

    // MARK: - Selected file

    private var fileContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            fileCard

            HStack(spacing: 10) {
                Text(L10n.t("Source language", language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                LanguagePicker(
                    selection: Language.with(code: store.sourceCode) ?? .auto,
                    includeAuto: true,
                    detected: store.detectedSource,
                    width: 230
                ) { option in
                    store.sourceCode = option.code
                }
                .disabled(store.isWorking || store.isSaving || store.state == .finished)
            }

            HStack(spacing: 10) {
                Text(L10n.t("Translate to", language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                LanguagePicker(
                    selection: Language.with(code: store.targetCode) ?? .auto,
                    includeAuto: false,
                    detected: nil,
                    labelKey: "Translate to",
                    width: 230
                ) { option in
                    store.targetCode = option.code
                }
                .disabled(store.isWorking || store.isSaving || store.state == .finished)

                Spacer()

                Button(L10n.t("Clear", language)) {
                    store.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .disabled(store.isWorking || store.isSaving)
            }

            switch store.state {
            case .idle:
                Button {
                    store.translate(settings: app.settings, language: language)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text(L10n.t("Translate now", language))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.primary))
                }
                .buttonStyle(.plain)

            case .working:
                progressCard

            case .finished:
                finishedCard

            case .failed(let message):
                errorCard(message)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var fileCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.chromeRaised)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.fileName ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(kindTitle)
                    if let size = store.formattedSize {
                        Text("·")
                        Text(size)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
            }

            Spacer()

            Button {
                store.reset()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.chromeRaised))
            }
            .buttonStyle(.plain)
            .disabled(store.isWorking || store.isSaving)
            .accessibilityLabel(L10n.t("Remove file", language))
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t(store.isPreparingOutput ? "Preparing file…" : "Translating…", language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(store.percent)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .monospacedDigit()
            }

            if store.total > 0 {
                ProgressView(
                    value: Double(store.completed),
                    total: Double(max(store.total, 1))
                )
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .accessibilityLabel(L10n.t("Translation progress", language))
                Text(L10n.format(
                    "Translating… %d of %d",
                    language,
                    store.completed,
                    store.total
                ))
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if store.usingFallback, let label = store.fallbackLabel {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(L10n.t("Fallback", language)): \(label)")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.tertiary)
            }

            Button(L10n.t("Stop", language)) {
                store.cancel()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondary)
        }
    }

    private var finishedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("Translation complete", language))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(store.outputName ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if store.warningCount > 0 {
                Text(L10n.format(
                    "Some paragraphs are still in the original language (%d).",
                    language,
                    store.warningCount
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.warning)
            }

            if let error = store.saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warning)
            }

            HStack(spacing: 10) {
                Button {
                    store.saveOutput(language: language)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                        Text(L10n.t(store.isSaving ? "Saving…" : "Save translation…", language))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.primary))
                }
                .buttonStyle(.plain)
                .disabled(store.isSaving)

                Button(L10n.t("Translate another file", language)) {
                    store.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .disabled(store.isSaving)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L10n.t("Retry", language)) {
                store.translate(settings: app.settings, language: language)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.danger)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0x2A1A1C))
        )
    }

    // MARK: - Helpers

    private var iconName: String {
        switch store.kind {
        case .pdf: return "doc.richtext"
        case .docx: return "doc.text"
        case .markdown: return "text.alignleft"
        default: return "doc.plaintext"
        }
    }

    private var kindTitle: String {
        switch store.kind {
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .markdown: return "Markdown"
        case .text: return "TXT"
        case .none: return ""
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !store.isSaving, let provider = providers.first else { return false }
        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                store.select(url: url, language: language)
            }
        }
        return true
    }
}
