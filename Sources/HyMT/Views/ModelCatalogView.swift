import AppKit
import SwiftUI

struct ModelCatalogSheet: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    @State private var tab: Provider
    @State private var query = ""
    @State private var freeOnly = false
    @State private var serverModels: [String] = []
    @State private var serverLoading = false
    @State private var serverError: String?
    @State private var serverProvider: Provider?

    private var language: AppLanguage { settings.interfaceLanguage }

    private let tabs: [Provider] = [.ollama, .ollamaCloud, .openRouter, .groq, .cerebras]

    init(settings: AppSettings, onClose: @escaping () -> Void) {
        self.settings = settings
        self.onClose = onClose
        let initial = ModelCatalogSheet.tabsStatic.contains(settings.provider) ? settings.provider : .ollama
        _tab = State(initialValue: initial)
    }

    private static let tabsStatic: [Provider] = [.ollama, .ollamaCloud, .openRouter, .groq, .cerebras]

    private var filteredEntries: [CatalogEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ModelCatalog.entries(for: tab).filter { entry in
            if freeOnly && !entry.isFree { return false }
            guard !needle.isEmpty else { return true }
            return entry.title.lowercased().contains(needle)
                || entry.summary.lowercased().contains(needle)
                || entry.modelID.lowercased().contains(needle)
        }
    }

    private var filteredServerModels: [String] {
        guard serverProvider == tab else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return serverModels
            .filter { needle.isEmpty || $0.lowercased().contains(needle) }
            .prefix(80)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            controls
            Rectangle().fill(Theme.border).frame(height: 1)
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 760, height: 620)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("Model catalog", language))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(L10n.t("Ready translators for local use and cloud options with free tiers.", language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.chromeRaised))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.chrome)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                SegmentedChoice(
                    options: tabs,
                    title: { provider in provider == .ollama ? L10n.t("Local", language) : provider.title },
                    selection: $tab
                )
                .frame(width: 560)
                Spacer()
            }

            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                    TextField(L10n.t("Search model", language), text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text)
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
                .frame(width: 260)

                Toggle(L10n.t("Free only", language), isOn: $freeOnly)
                    .toggleStyle(.switch)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)

                Spacer()

                Button {
                    loadServerModels()
                } label: {
                    HStack(spacing: 6) {
                        if serverLoading {
                            ProgressView().controlSize(.mini)
                        }
                        Text(L10n.t("Fetch from server", language))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.chromeRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(serverLoading)
            }

            if let serverError {
                Text(serverError)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.chrome)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if !filteredServerModels.isEmpty {
                    sectionTitle(L10n.t("Found on the server", language))
                    ForEach(filteredServerModels, id: \.self) { model in
                        serverRow(model)
                    }
                }

                if !filteredEntries.isEmpty {
                    sectionTitle(serverProvider == tab && !filteredServerModels.isEmpty
                                 ? L10n.t("Recommended", language)
                                 : L10n.t("Models", language))
                }

                ForEach(filteredEntries) { entry in
                    entryRow(entry)
                }

                if filteredEntries.isEmpty && filteredServerModels.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.tertiary)
                        Text(L10n.t("Nothing found", language))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.window)
        .onChange(of: tab) { _, _ in
            serverModels = []
            serverError = nil
            serverProvider = nil
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
            Text(L10n.t("Need another model? Type its ID into the Model field — any model your server supports will work.", language))
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.chrome)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func entryRow(_ entry: CatalogEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    ForEach(entry.badges, id: \.self) { badge in
                        SmallChip(
                            text: L10n.t(badge, language),
                            color: badge == "Free" ? Theme.success : Theme.secondary,
                            background: badge == "Free" ? Theme.success.opacity(0.12) : Theme.chromeRaised
                        )
                    }
                }
                Text(L10n.t(entry.summary, language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(entry.modelID)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                    if let command = entry.installCommand {
                        Text("·")
                            .foregroundStyle(Theme.tertiary)
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        IconButton(systemName: "doc.on.doc", help: L10n.t("Copy install command", language)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                settings.apply(entry: entry)
                onClose()
            } label: {
                Text(L10n.t("Choose", language))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.chromeRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }

    private func serverRow(_ model: String) -> some View {
        HStack(spacing: 12) {
            Text(model)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.text)
            Spacer()
            Button {
                settings.apply(provider: tab, model: model)
                onClose()
            } label: {
                Text(L10n.t("Choose", language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.chromeRaised)
                    )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.chrome)
        )
    }

    private func loadServerModels() {
        serverLoading = true
        serverError = nil
        serverProvider = nil
        serverModels = []

        let provider = tab
        let key = provider == settings.provider ? settings.apiKey : Keychain.read(provider.keyAccount)
        if provider.requiresKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            serverError = L10n.format("Enter the API key for %@ in Settings first.", language, provider.title)
            serverLoading = false
            return
        }

        let config = BackendConfig(
            kind: provider.kind,
            baseURL: provider.baseURL,
            model: settings.model,
            apiKey: key,
            temperature: settings.temperature,
            topP: settings.topP,
            topK: settings.topK,
            repetitionPenalty: settings.repetitionPenalty,
            contextWindow: settings.contextWindow
        )

        Task {
            do {
                let models = try await Probe.models(config)
                await MainActor.run {
                    serverModels = models.sorted()
                    serverProvider = provider
                    serverLoading = false
                }
            } catch {
                await MainActor.run {
                    serverError = error.localizedDescription
                    serverLoading = false
                }
            }
        }
    }
}
