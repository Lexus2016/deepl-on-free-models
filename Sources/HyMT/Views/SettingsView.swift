import AppKit
import Carbon.HIToolbox
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var settings: AppSettings
    @State private var modelFilter = ""
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?
    @AppStorage("SUEnableAutomaticChecks") private var automaticChecks = true
    @AppStorage("SUAutomaticallyUpdate") private var automaticDownloads = false

    private var language: AppLanguage { settings.interfaceLanguage }

    var body: some View {
        ZStack {
            settingsContent

            if app.showCatalog {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {}

                ModelCatalogSheet(settings: settings) {
                    app.showCatalog = false
                }
                .background(Theme.window)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 12)
                .onExitCommand { app.showCatalog = false }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.showCatalog)
    }

    private var settingsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionCard
                    fallbackCard.id("fallback")
                    if app.providerModelsSource == settings.provider || app.modelsLoading || app.modelsError != nil {
                        providerModelsCard
                    }
                    generationCard
                    behaviourCard
                    hotKeyCard.id("hotkey")
                    promptCard
                    aboutCard.id("about")
                }
                .frame(maxWidth: 820)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.window)
            .scrollIndicators(.hidden)
            .onAppear {
                let arguments = CommandLine.arguments
                guard arguments.contains("--scroll-hotkey")
                    || arguments.contains("--scroll-about")
                    || arguments.contains("--scroll-fallback") else { return }
                let target: String
                if arguments.contains("--scroll-about") {
                    target = "about"
                } else if arguments.contains("--scroll-fallback") {
                    target = "fallback"
                } else {
                    target = "hotkey"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Connection

    private var connectionCard: some View {
        SettingsCard(
            title: L10n.t("Model and provider", language),
            subtitle: L10n.t("Local models run offline and for free. Cloud models answer faster but need a key.", language)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(Provider.allCases) { provider in
                        providerButton(provider)
                    }
                }

                Text(settings.provider.detail(language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FieldRow(label: L10n.t("API key", language)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            SecureField(L10n.t("API key", language), text: $settings.apiKey)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Theme.editor)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Theme.border, lineWidth: 1)
                                )
                            if let url = settings.provider.keyURL {
                                Link(L10n.t("Get key ↗", language), destination: url)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        Text(L10n.t("Can be empty for local servers. Stored in the macOS Keychain, never in the repository.", language))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                FieldRow(label: L10n.t("Server address", language)) {
                    TextInput(placeholder: settings.provider.baseURL, text: $settings.baseURL, monospaced: true)
                }

                FieldRow(label: L10n.t("Model", language)) {
                    HStack(spacing: 8) {
                        TextInput(placeholder: "hy-mt2:7b", text: $settings.model, monospaced: true)
                        Button {
                            app.showCatalog = true
                        } label: {
                            Text(L10n.t("Model catalog…", language))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
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
                    }
                }

                Text(L10n.t("For difficult texts, use Hy-MT2 30B or a cloud model.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)

                HStack(spacing: 10) {
                    Button {
                        app.connectAndLoadModels()
                    } label: {
                        HStack(spacing: 7) {
                            if app.modelsLoading {
                                ProgressView().controlSize(.mini)
                            }
                            Text(L10n.t("Connect", language))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
                    .disabled(app.modelsLoading)

                    probeBadge
                }

                if settings.kind == .ollama, app.backendStatus != .ready, let command = settings.installCommand {
                    HStack(spacing: 8) {
                        Text(command)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.tertiary)
                            .textSelection(.enabled)
                        IconButton(systemName: "doc.on.doc", help: L10n.t("Copy install command", language)) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                    }
                }
            }
        }
    }

    private func providerButton(_ provider: Provider) -> some View {
        let selected = settings.provider == provider
        return Button {
            settings.apply(provider: provider)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: provider.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(L10n.t(provider.title, language))
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Theme.text : Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.accentSoft : Theme.editor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var probeBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(probeColor)
                .frame(width: 6, height: 6)
            Text(app.probeMessage.isEmpty ? L10n.t("Not checked yet", language) : app.probeMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var probeColor: Color {
        switch app.backendStatus {
        case .ready: return Theme.success
        case .checking, .unknown, .modelMissing: return Theme.warning
        case .error: return Theme.danger
        }
    }

    // MARK: - Provider models

    private var filteredModels: [String] {
        let needle = modelFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return app.providerModels }
        return app.providerModels.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    private var fallbackCard: some View {
        SettingsCard(
            title: L10n.t("Fallback provider", language),
            subtitle: L10n.t("Used automatically when the primary provider fails.", language)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    L10n.t("Use a fallback provider", language),
                    isOn: $settings.fallbackEnabled
                )
                .toggleStyle(.switch)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)

                if settings.fallbackEnabled {
                    FieldRow(label: L10n.t("Provider", language)) {
                        Picker("", selection: $settings.fallbackProvider) {
                            ForEach(Provider.allCases) { provider in
                                Text(L10n.t(provider.title, language)).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    FieldRow(label: L10n.t("Server address", language)) {
                        TextInput(
                            placeholder: settings.fallbackProvider.baseURL,
                            text: $settings.fallbackBaseURL,
                            monospaced: true
                        )
                    }

                    FieldRow(label: L10n.t("API key", language)) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                SecureField(L10n.t("API key", language), text: $settings.fallbackAPIKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Theme.editor)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Theme.border, lineWidth: 1)
                                    )
                                if let url = settings.fallbackProvider.keyURL {
                                    Link(L10n.t("Get key ↗", language), destination: url)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            Text(L10n.t("Uses the Keychain key for this provider.", language))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }

                    FieldRow(label: L10n.t("Model", language)) {
                        HStack(spacing: 8) {
                            TextInput(
                                placeholder: settings.fallbackProvider.isLocal ? "hy-mt2:7b" : "model-id",
                                text: $settings.fallbackModel,
                                monospaced: true
                            )
                            Button {
                                app.loadFallbackModels()
                            } label: {
                                HStack(spacing: 6) {
                                    if app.fallbackModelsLoading {
                                        ProgressView().controlSize(.mini)
                                    }
                                    Text(L10n.t("Load models", language))
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
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
                            .disabled(app.fallbackModelsLoading)
                        }
                    }

                    if let error = app.fallbackModelsError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !app.fallbackModels.isEmpty {
                        FieldRow(label: L10n.t("Choose model", language)) {
                            Picker("", selection: $settings.fallbackModel) {
                                Text(L10n.t("Choose a model", language)).tag("")
                                ForEach(app.fallbackModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 360, alignment: .leading)
                        }
                    }

                    Text(L10n.t("If the primary provider fails, the same text is retried with these settings.", language))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var providerModelsCard: some View {
        SettingsCard(
            title: L10n.t("Models on the server", language),
            subtitle: app.modelsLoading
                ? L10n.t("Checking connection…", language)
                : L10n.format("Models: %d", language, app.providerModels.count)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                        TextField(L10n.t("Filter by name", language), text: $modelFilter)
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
                    .frame(width: 300)

                    Button {
                        app.connectAndLoadModels()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L10n.t("Refresh", language))
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
                    .disabled(app.modelsLoading)

                    Spacer()
                }

                if let modelsError = app.modelsError {
                    Text(modelsError)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !app.providerModels.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredModels, id: \.self) { model in
                                Button {
                                    settings.model = model
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(model)
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        if settings.model == model {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(settings.model == model ? Theme.accentSoft : Color.clear)
                                )
                                .hoverHighlight(enabled: settings.model != model)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .scrollIndicators(.hidden)
                }

                Text(L10n.t("Select a model from the list or type its ID.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .onChange(of: app.providerModelsSource) { _, _ in
            modelFilter = ""
        }
    }

    // MARK: - Generation

    private var generationCard: some View {
        SettingsCard(
            title: L10n.t("Generation parameters", language),
            subtitle: L10n.t("Defaults match Tencent’s recommendations for Hy-MT2 7B.", language)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ValueSlider(title: L10n.t("Temperature", language), value: $settings.temperature, range: 0...1.5)
                ValueSlider(title: "Top-p", value: $settings.topP, range: 0.1...1.0)
                ValueSlider(title: L10n.t("Repetition", language), value: $settings.repetitionPenalty, range: 1.0...1.5)

                FieldRow(label: "Top-k") {
                    HStack(spacing: 10) {
                        Stepper(value: $settings.topK, in: 1...100) {
                            Text("\(settings.topK)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.text)
                        }
                        .frame(width: 110)
                        Text(L10n.t("Only this many most likely tokens are considered while decoding.", language))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                FieldRow(label: L10n.t("Context", language)) {
                    Picker("", selection: $settings.contextWindow) {
                        Text("2 048").tag(2048)
                        Text("4 096").tag(4096)
                        Text("8 192").tag(8192)
                        Text("16 384").tag(16384)
                        Text("32 768").tag(32768)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
    }

    // MARK: - Behaviour

    private var speechVoices: [AVSpeechSynthesisVoice] {
        var list = Speaker.voices(for: app.targetLanguage.code)
        if !settings.speechVoiceID.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: settings.speechVoiceID),
           !list.contains(where: { $0.identifier == chosen.identifier }) {
            list.insert(chosen, at: 0)
        }
        return list
    }

    private var behaviourCard: some View {
        SettingsCard(title: L10n.t("Behavior", language), subtitle: nil) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.t("Translate automatically while typing", language), isOn: $settings.autoTranslate)
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.text)
                    .font(.system(size: 12.5))

                if settings.autoTranslate {
                    ValueSlider(
                        title: L10n.t("Delay", language),
                        value: $settings.debounce,
                        range: 0.2...2.0,
                        unit: language.resolved == .en ? " s" : " с"
                    )
                }

                Toggle(L10n.t("Keep translation history", language), isOn: $settings.keepHistory)
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.text)
                    .font(.system(size: 12.5))

                loginItemControls

                Toggle(L10n.t("Load the translator at launch", language), isOn: $settings.warmUpOnLaunch)
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.text)
                    .font(.system(size: 12.5))

                Text(L10n.t("Connects to the provider, refreshes the model list and warms up a local model.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L10n.t("Menu bar icon", language), isOn: $settings.showInMenuBar)
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.text)
                    .font(.system(size: 12.5))

                Toggle(L10n.t("Dock icon", language), isOn: $settings.showInDock)
                    .toggleStyle(.switch)
                    .foregroundStyle(Theme.text)
                    .font(.system(size: 12.5))

                Text(L10n.t("The Dock icon appears while the window is open. Turn this on to keep it in the Dock all the time.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FieldRow(label: L10n.t("Voice", language)) {
                    Picker("", selection: $settings.speechVoiceID) {
                        Text(L10n.t("Automatic", language)).tag("")
                        ForEach(speechVoices, id: \.identifier) { voice in
                            Text("\(voice.name) — \(voice.language)")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 280)
                }

                Text(L10n.t("For better voices, download Enhanced or Premium voices in System Settings → Accessibility → Spoken Content.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                FieldRow(label: L10n.t("Interface language", language)) {
                    Picker("", selection: $settings.interfaceLanguage) {
                        ForEach(AppLanguage.allCases) { languageOption in
                            Text(languageOption.pickerTitle(current: language))
                                .tag(languageOption)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
        }
    }

    private var loginItemControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(L10n.t("Open at login", language), isOn: Binding(
                get: { loginItemStatus == .enabled },
                set: setLoginItemEnabled
            ))
            .toggleStyle(.switch)
            .foregroundStyle(Theme.text)
            .font(.system(size: 12.5))

            if let loginItemError {
                Text(loginItemError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if loginItemStatus == .requiresApproval {
                Text(L10n.t("Allow DeepL-oFM to open at login in System Settings.", language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Open System Settings", language)) {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
            }
        }
        .onAppear { refreshLoginItemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
        }
    }

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        if status != loginItemStatus { loginItemError = nil }
        loginItemStatus = status
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        refreshLoginItemStatus()
        loginItemError = nil
        guard enabled != (loginItemStatus == .enabled) else { return }

        if loginItemStatus == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
        } catch {
            refreshLoginItemStatus()
            if loginItemStatus != .requiresApproval, enabled != (loginItemStatus == .enabled) {
                loginItemError = L10n.format("Could not change Open at login. %@", language, error.localizedDescription)
            }
        }
    }

    // MARK: - Hot key

    private var hotKeyCard: some View {
        SettingsCard(
            title: L10n.t("Hot key", language),
            subtitle: L10n.t("Copy text anywhere and press the shortcut — DeepL-oFM opens and translates the clipboard.", language)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FieldRow(label: L10n.t("Translate clipboard", language)) {
                    HStack(spacing: 12) {
                        HotKeyRecorder(combo: $settings.hotKey, defaultCombo: .standard, language: language)
                        Text(app.hotKeyMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(app.hotKeyActive ? Theme.success : Theme.danger)
                    }
                }

                FieldRow(label: L10n.t("Selected text", language)) {
                    HStack(spacing: 12) {
                        HotKeyRecorder(combo: $settings.selectionHotKey, defaultCombo: .selection, language: language)
                        Text(app.selectionHotKeyMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(app.selectionHotKeyActive ? Theme.success : Theme.danger)
                    }
                }

                Text(L10n.t("Select text in any app and press the shortcut — DeepL-oFM copies it and translates.", language))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Circle()
                        .fill(app.accessibilityGranted ? Theme.success : Theme.warning)
                        .frame(width: 6, height: 6)
                    Text(
                        L10n.t("Accessibility access", language)
                            + ": "
                            + L10n.t(app.accessibilityGranted ? "Granted" : "Not granted", language)
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    if !app.accessibilityGranted {
                        Button(L10n.t("Open System Settings", language)) {
                            app.promptAccessibility()
                            app.openAccessibilitySettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)

                        Button(L10n.t("Check access", language)) {
                            app.refreshAccessibility()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }

                if !app.accessibilityGranted {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("If access is already granted, remove DeepL-oFM from the Accessibility list and add the current app again — a permission from an older build does not apply.", language))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Bundle.main.bundlePath)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.tertiary.opacity(0.8))
                            .textSelection(.enabled)
                    }
                }

                Text(L10n.t("At least one modifier is required — ⌘, ⌥ or ⌃. Press Esc to cancel.", language))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                Text(L10n.t("Examples: ⌥⌘T or ⌥⌘C.", language))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .onAppear { app.refreshAccessibility() }
    }

    // MARK: - Prompt

    private var promptCard: some View {
        SettingsCard(
            title: L10n.t("System prompt", language),
            subtitle: L10n.t("Hy-MT2 has no system prompt: instruction and text go in one message. Wording follows the model card.", language)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                FieldRow(label: L10n.t("Style", language)) {
                    SegmentedChoice(
                        options: TranslationStyle.allCases,
                        title: { L10n.t($0.title, language) },
                        selection: $app.style
                    )
                    .frame(width: 340)
                }
                FieldRow(label: L10n.t("Tone", language)) {
                    SegmentedChoice(
                        options: TranslationTone.allCases,
                        title: { L10n.t($0.title, language) },
                        selection: $app.tone
                    )
                    .frame(width: 460)
                }

                Text(PromptBuilder.preview(
                    style: app.style,
                    tone: app.tone,
                    targetLanguage: app.targetLanguage.englishName,
                    sample: L10n.t("Sample text", language)
                ))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.editor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsCard(title: L10n.t("About", language), subtitle: nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("DeepL-oFM \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("·")
                        .foregroundStyle(Theme.tertiary)
                    Text(L10n.t("local translator for macOS", language))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
                Text(L10n.t("Model: Hy-MT2 7B (Tencent Hy). License and model card on Hugging Face.", language))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)

                DividerLine()
                    .padding(.vertical, 4)

                HStack(spacing: 10) {
                    Button {
                        app.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.t("Check for Updates…", language))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
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

                    Text(L10n.t("Updates are signed and notarized.", language))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }

                if let status = app.updateStatus {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(
                    L10n.t("Automatically check for updates", language),
                    isOn: $automaticChecks
                )
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .onChange(of: automaticChecks) { _, value in
                    app.automaticallyChecksForUpdates = value
                }

                Toggle(
                    L10n.t("Automatically download and install updates", language),
                    isOn: $automaticDownloads
                )
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .onChange(of: automaticDownloads) { _, value in
                    app.automaticallyDownloadsUpdates = value
                }

                HStack(spacing: 14) {
                    Link("huggingface.co/tencent/Hy-MT2-7B", destination: URL(string: "https://huggingface.co/tencent/Hy-MT2-7B")!)
                    Link(L10n.t("DeepL-oFM on GitHub", language), destination: URL(string: "https://github.com/Lexus2016/deepl-on-free-models")!)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
                .frame(width: 150, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(Theme.accent)
                .frame(maxWidth: 260)
            Text(String(format: "%.2f", value) + unit)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 60, alignment: .leading)
        }
    }
}

struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo
    var defaultCombo: KeyCombo = .standard
    var language: AppLanguage = .system
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? L10n.t("Press a combination…", language) : combo.displayString(language))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Theme.text : Theme.secondary)
                    .frame(minWidth: 130)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(recording ? Theme.accentSoft : Theme.chromeRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(recording ? Theme.accent : Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if !isDefaultCombo {
                Button(L10n.t("Reset", language)) {
                    combo = defaultCombo
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
            }
        }
        .onDisappear { stop() }
    }

    private var isDefaultCombo: Bool {
        combo.keyCode == defaultCombo.keyCode && combo.modifiers == defaultCombo.modifiers
    }

    private func start() {
        guard !recording else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                return nil
            }
            combo = KeyCombo(
                keyCode: UInt32(event.keyCode),
                modifiers: UInt(flags.rawValue),
                label: event.charactersIgnoringModifiers
            )
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
