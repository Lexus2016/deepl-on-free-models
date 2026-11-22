import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store: FileTranslationStore

    @State private var dropTargeted = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if store.selectedURL == nil {
                dropZone
            } else {
                fileContent
            }

            Spacer(minLength: 0)
        }
        .padding(28)
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
            HStack(spacing: 8) {
                fileBadge("PDF", color: Color(hex: 0xE5534B))
                fileBadge("DOCX", color: Color(hex: 0x4A8CF7))
                fileBadge("TXT", color: Color(hex: 0x8B93A1))
                fileBadge("MD", color: Color(hex: 0x3ECF8E))
            }

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
                .background(Capsule().fill(Theme.accentGradient))
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
                Text(L10n.t("Translate to", language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)

                Picker("", selection: $store.targetCode) {
                    ForEach(Language.all) { item in
                        Text(item.displayName(in: language)).tag(item.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 230)
                .disabled(store.isWorking)

                Spacer()

                Button(L10n.t("Clear", language)) {
                    store.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .disabled(store.isWorking)
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
                    .background(Capsule().fill(Theme.accentGradient))
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
            .disabled(store.isWorking)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("Translating…", language))
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
                    "Some lines could not be translated (%d); they are left in the source language.",
                    language,
                    store.warningCount
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.warning)
            }

            HStack(spacing: 10) {
                Button {
                    store.saveOutput(language: language)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.down")
                        Text(L10n.t("Save translation…", language))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accentGradient))
                }
                .buttonStyle(.plain)

                Button(L10n.t("Translate another file", language)) {
                    store.reset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
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

    private func fileBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.9))
            )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
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
