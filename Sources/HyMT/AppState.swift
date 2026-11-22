import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation
import Sparkle

@MainActor
final class AppState: NSObject, ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case translate
        case history
        case settings

        var id: String { rawValue }

        func title(_ language: AppLanguage) -> String {
            switch self {
            case .translate: return L10n.t("Translate text", language)
            case .history: return L10n.t("History", language)
            case .settings: return L10n.t("Settings", language)
            }
        }

        var icon: String {
            switch self {
            case .translate: return "character.bubble"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }
    }

    enum BackendStatus: Equatable {
        case unknown
        case checking
        case ready
        case modelMissing
        case error(String)
    }

    // MARK: Published state

    @Published var tab: Tab = .translate
    @Published var sourceText: String = ""
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var translationCompleted: Int = 0
    @Published var translationTotal: Int = 0
    @Published var translationWarningCount: Int = 0
    @Published var errorMessage: String?
    @Published var tokensPerSecond: Double?
    @Published var lastDurationMs: Int?

    @Published var sourceLanguage: Language {
        didSet {
            settings.lastSourceCode = sourceLanguage.code
            detectedLanguage = sourceLanguage == .auto ? Language.detect(sourceText, preferred: settings.interfaceLanguage) : nil
        }
    }
    @Published var targetLanguage: Language {
        didSet {
            settings.lastTargetCode = targetLanguage.code
            if oldValue != targetLanguage { retranslateIfPossible() }
        }
    }
    @Published var style: TranslationStyle {
        didSet {
            settings.lastStyle = style
            if oldValue != style { retranslateIfPossible() }
        }
    }
    @Published var tone: TranslationTone {
        didSet {
            settings.lastTone = tone
            if oldValue != tone { retranslateIfPossible() }
        }
    }

    @Published var detectedLanguage: Language?
    @Published var backendStatus: BackendStatus = .unknown
    @Published var probeMessage: String = ""
    @Published var hotKeyActive: Bool = false
    @Published var hotKeyMessage: String = ""
    @Published var selectionHotKeyActive: Bool = false
    @Published var selectionHotKeyMessage: String = ""
    @Published var accessibilityGranted: Bool = AXIsProcessTrusted()
    @Published var providerModels: [String] = []
    @Published var providerModelsSource: Provider?
    @Published var modelsLoading: Bool = false
    @Published var modelsError: String?
    @Published var showCatalog: Bool = false
    @Published var updateStatus: String?

    // MARK: Dependencies

    let settings: AppSettings
    let history: HistoryStore
    private(set) var updaterController: SPUStandardUpdaterController!

    private let translator = TranslationService()
    private let hotKeys = HotKeyManager()
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?

    private var currentGeneration = UUID()
    private var lastCompletedKey: String?
    private var suppressRetranslation = false
    private var didBootstrap = false
    private var didActivateWindow = false

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.history = HistoryStore()
        self.sourceLanguage = Language.with(code: settings.lastSourceCode) ?? .auto
        self.targetLanguage = Language.with(code: settings.lastTargetCode) ?? Language.with(code: "en") ?? .auto
        self.style = settings.lastStyle
        self.tone = settings.lastTone
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        // SUEnableAutomaticChecks in Info.plist only suppresses the first-run
        // permission prompt. Seed the user default once so daily checks are on
        // by default; an explicit user choice is never overwritten.
        if UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil {
            updaterController.updater.automaticallyChecksForUpdates = true
        }
        configureBindings()
        registerHotKeys()
        if settings.showInMenuBar { installStatusItem() }
    }

    // MARK: - Lifecycle

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        debugLog("accessibility trusted: \(AXIsProcessTrusted())")
        checkConnection()

        // Sparkle starts on the next run loop; refresh once so the update
        // toggles show the real state instead of their pre-start defaults.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.debugLog(
                "updates: automaticChecks=\(self.updaterController.updater.automaticallyChecksForUpdates) "
                + "automaticDownloads=\(self.updaterController.updater.automaticallyDownloadsUpdates) "
                + "default=\(UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks"))"
            )
            self.objectWillChange.send()
        }

        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--prefill"), arguments.count > index + 1 {
            let text = arguments[index + 1]
            sourceText = text
            detectedLanguage = Language.detect(text, preferred: settings.interfaceLanguage)
            translate(force: true)
        }
        if arguments.contains("--translate-clipboard") {
            translateClipboard()
        }
        if arguments.contains("--connect") {
            connectAndLoadModels()
        }
        if arguments.contains("--catalog") {
            showCatalog = true
        }
        if arguments.contains("--check-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.checkForUpdates()
            }
        }
        if let index = arguments.firstIndex(of: "--tab"), arguments.count > index + 1 {
            switch arguments[index + 1] {
            case "settings": tab = .settings
            case "history": tab = .history
            default: tab = .translate
            }
        }
    }

    func attach(window: NSWindow) {
        mainWindow = window
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(hex: 0x111216)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 1000, height: 640)

        guard !didActivateWindow else { return }
        didActivateWindow = true
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Translation

    func sourceChanged(_ text: String) {
        sourceText = text
        detectedLanguage = sourceLanguage == .auto ? Language.detect(text, preferred: settings.interfaceLanguage) : nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cancelTranslation()
            translatedText = ""
            errorMessage = nil
            lastDurationMs = nil
            tokensPerSecond = nil
            translationCompleted = 0
            translationTotal = 0
            translationWarningCount = 0
            return
        }
        guard settings.autoTranslate, !suppressRetranslation else { return }

        debounceTask?.cancel()
        let delay = max(0.1, settings.debounce)
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.translate(force: false)
        }
    }

    func translate(force: Bool) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            isTranslating = false
            return
        }

        var target = targetLanguage
        if sourceLanguage == .auto,
           let detected = Language.detect(trimmed, preferred: settings.interfaceLanguage),
           detected == target {
            let interface = settings.interfaceLanguage.resolved
            let preferredCode: String
            switch interface {
            case .uk: preferredCode = "uk"
            case .ru: preferredCode = "ru"
            default: preferredCode = "en"
            }
            var fallback = Language.with(code: preferredCode)
            if fallback == nil || fallback == detected {
                fallback = Language.with(code: detected.code == "en" ? "uk" : "en")
            }
            if let fallback, fallback != detected {
                suppressRetranslation = true
                targetLanguage = fallback
                suppressRetranslation = false
                target = fallback
            }
        }

        let style = self.style
        let tone = self.tone
        let config = settings.snapshot
        let key = "\(trimmed)|\(target.code)|\(style.rawValue)|\(tone.rawValue)|\(config.kind.rawValue)|\(config.baseURL)|\(config.model)"

        if !force, key == lastCompletedKey {
            return
        }

        translationTask?.cancel()
        debounceTask?.cancel()
        let generation = UUID()
        currentGeneration = generation
        isTranslating = true
        errorMessage = nil
        translatedText = ""
        translationCompleted = 0
        translationTotal = 0
        translationWarningCount = 0
        lastDurationMs = nil
        tokensPerSecond = nil
        debugLog("translate start: model=\(config.model) target=\(target.englishName) style=\(style.rawValue) tone=\(tone.rawValue) chars=\(trimmed.count)")

        let started = Date()
        let engine = "\(self.settings.provider.title) · \(config.model)"

        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = self.translator.stream(
                    text: trimmed,
                    style: style,
                    tone: tone,
                    target: target,
                    config: config
                )
                var buffer = ""
                for try await event in stream {
                    if Task.isCancelled || self.currentGeneration != generation { return }
                    switch event {
                    case .chunk(let piece):
                        buffer += piece
                    case .stats(let tps):
                        self.tokensPerSecond = tps
                    case .progress(let completed, let total):
                        self.translationCompleted = completed
                        self.translationTotal = total
                    case .warning:
                        self.translationWarningCount += 1
                    }
                }
                guard !Task.isCancelled, self.currentGeneration == generation else { return }

                let duration = Int(Date().timeIntervalSince(started) * 1000)
                self.translatedText = OutputSanitizer.clean(buffer)
                self.translationCompleted = self.translationTotal
                self.debugLog("translate done in \(duration) ms: \(self.translatedText)")
                self.isTranslating = false
                if self.translationWarningCount > 0 {
                    self.errorMessage = L10n.format(
                        "Some lines could not be translated (%d); they are left in the source language.",
                        self.settings.interfaceLanguage,
                        self.translationWarningCount
                    )
                }
                self.lastDurationMs = duration
                self.lastCompletedKey = key
                self.backendStatus = .ready
                self.probeMessage = L10n.t("Connection works.", self.settings.interfaceLanguage)

                if self.settings.keepHistory {
                    self.history.add(HistoryEntry(
                        sourceText: trimmed,
                        translatedText: self.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceCode: self.sourceLanguage.code,
                        targetCode: target.code,
                        style: style,
                        tone: tone,
                        engine: engine,
                        durationMs: duration
                    ))
                }
            } catch {
                guard self.currentGeneration == generation else { return }
                self.isTranslating = false
                if error is CancellationError { return }
                self.debugLog("translate error: \(error.localizedDescription)")
                let language = self.settings.interfaceLanguage
                let message = (error as? TranslationError)?.message(language) ?? error.localizedDescription
                self.errorMessage = message
                if let translationError = error as? TranslationError,
                   case .connection = translationError {
                    self.backendStatus = .error(message)
                }
            }
        }
    }

    private func retranslateIfPossible() {
        guard !suppressRetranslation else { return }
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        translate(force: true)
    }

    func cancelTranslation() {
        translationTask?.cancel()
        debounceTask?.cancel()
        currentGeneration = UUID()
        isTranslating = false
    }

    func clearSource() {
        cancelTranslation()
        sourceText = ""
        translatedText = ""
        errorMessage = nil
        detectedLanguage = nil
        lastDurationMs = nil
        tokensPerSecond = nil
        translationCompleted = 0
        translationTotal = 0
        translationWarningCount = 0
    }

    func swapLanguages() {
        let detected: Language
        if sourceLanguage == .auto {
            detected = Language.detect(sourceText, preferred: settings.interfaceLanguage) ?? Language.with(code: "en") ?? .auto
        } else {
            detected = sourceLanguage
        }
        guard detected != .auto else { return }

        suppressRetranslation = true
        let oldSource = sourceText
        let oldTranslation = translatedText
        let oldTarget = targetLanguage

        targetLanguage = detected
        sourceLanguage = oldTarget
        sourceText = oldTranslation
        translatedText = oldSource
        detectedLanguage = nil
        suppressRetranslation = false

        if !sourceText.isEmpty {
            translate(force: true)
        }
    }

    func translateClipboard() {
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        showWindow()
        guard !clipboard.isEmpty else { return }

        tab = .translate
        suppressRetranslation = true
        sourceText = clipboard
        translatedText = ""
        suppressRetranslation = false
        detectedLanguage = sourceLanguage == .auto ? Language.detect(clipboard, preferred: settings.interfaceLanguage) : nil
        translate(force: true)
    }

    func copyTranslation() {
        let text = translatedText
        guard !text.isEmpty else { return }
        ClipboardWriter.copy(text)
    }

    func copySource() {
        guard !sourceText.isEmpty else { return }
        ClipboardWriter.copy(sourceText)
    }

    // MARK: - Updates

    func checkForUpdates() {
        updateStatus = L10n.t("Checking for updates…", settings.interfaceLanguage)
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    func speakSource() {
        let language = sourceLanguage == .auto ? (Language.detect(sourceText, preferred: settings.interfaceLanguage) ?? .auto) : sourceLanguage
        Speaker.shared.speak(sourceText, language: language)
    }

    func speakTranslation() {
        Speaker.shared.speak(translatedText, language: targetLanguage)
    }

    func loadHistory(_ entry: HistoryEntry) {
        suppressRetranslation = true
        sourceLanguage = Language.with(code: entry.sourceCode) ?? .auto
        targetLanguage = Language.with(code: entry.targetCode) ?? targetLanguage
        style = entry.style
        tone = entry.tone
        sourceText = entry.sourceText
        translatedText = entry.translatedText
        errorMessage = nil
        lastDurationMs = entry.durationMs
        tokensPerSecond = nil
        suppressRetranslation = false
        detectedLanguage = sourceLanguage == .auto ? Language.detect(entry.sourceText, preferred: settings.interfaceLanguage) : nil
        tab = .translate
    }

    var isSourceLanguageAuto: Bool { sourceLanguage == .auto }

    private func debugLog(_ message: String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEEPLOFM_DEBUG"] == "1" || environment["HYMT_DEBUG"] == "1" else { return }
        guard let data = ("[DeepL-oFM] " + message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    // MARK: - Connection

    func checkConnection() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            await self?.runProbe()
        }
    }

    func scheduleProbe() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.runProbe()
        }
    }

    func connectAndLoadModels() {
        let language = settings.interfaceLanguage
        let provider = settings.provider
        let config = settings.snapshot

        modelsTask?.cancel()
        modelsLoading = true
        modelsError = nil
        backendStatus = .checking
        probeMessage = L10n.t("Checking connection…", language)

        if provider.requiresKey && config.apiKey.isEmpty {
            let message = L10n.format("Enter the API key for %@ in Settings first.", language, provider.title)
            modelsLoading = false
            modelsError = message
            probeMessage = message
            backendStatus = .error(message)
            return
        }

        modelsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await Probe.models(config)
                guard !Task.isCancelled else { return }
                let sorted = models.sorted()
                self.providerModels = sorted
                self.providerModelsSource = provider
                self.modelsLoading = false
                if sorted.isEmpty {
                    let message = L10n.t("The server returned no models.", language)
                    self.modelsError = message
                    self.backendStatus = .modelMissing
                    self.probeMessage = message
                } else if Probe.model(config.model, isListedIn: sorted) {
                    self.backendStatus = .ready
                    self.probeMessage = L10n.format("Connection works. Model “%@” is available.", language, config.model)
                } else {
                    self.backendStatus = .modelMissing
                    let listed = sorted.prefix(5).joined(separator: ", ")
                    self.probeMessage = L10n.format(
                        "Server responds, but model “%@” is missing. Available: %@.",
                        language,
                        config.model,
                        listed.isEmpty ? "—" : listed
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? TranslationError)?.message(language) ?? error.localizedDescription
                self.modelsLoading = false
                self.providerModels = []
                self.providerModelsSource = nil
                self.modelsError = message
                self.backendStatus = .error(message)
                self.probeMessage = message
            }
        }
    }

    private func runProbe() async {
        backendStatus = .checking
        let language = settings.interfaceLanguage
        probeMessage = L10n.t("Checking connection…", language)
        let config = settings.snapshot

        if settings.provider.requiresKey && config.apiKey.isEmpty {
            let message = L10n.format("Enter the API key for %@ in Settings first.", language, settings.provider.title)
            backendStatus = .error(message)
            probeMessage = message
            return
        }

        do {
            let models = try await Probe.models(config)
            debugLog("probe \(config.baseURL): \(models.count) models, has=\(Probe.model(config.model, isListedIn: models))")
            if models.isEmpty {
                backendStatus = .modelMissing
                probeMessage = L10n.t("The server returned no models.", language)
            } else if Probe.model(config.model, isListedIn: models) {
                backendStatus = .ready
                probeMessage = L10n.format("Connection works. Model “%@” is available.", language, config.model)
            } else {
                backendStatus = .modelMissing
                let listed = models.prefix(5).joined(separator: ", ")
                probeMessage = L10n.format(
                    "Server responds, but model “%@” is missing. Available: %@.",
                    language,
                    config.model,
                    listed.isEmpty ? "—" : listed
                )
            }
        } catch {
            let message = (error as? TranslationError)?.message(language) ?? error.localizedDescription
            backendStatus = .error(message)
            probeMessage = message
        }
    }

    // MARK: - Selected text

    func translateSelection() {
        let language = settings.interfaceLanguage
        guard AXIsProcessTrusted() else {
            accessibilityGranted = false
            promptAccessibility()
            showWindow()
            errorMessage = L10n.t("Accessibility access is required to copy the selected text.", language)
            return
        }

        let pasteboard = NSPasteboard.general
        let initialChange = pasteboard.changeCount
        postCommandC()

        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            var captured: String?
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if Task.isCancelled { return }
                if pasteboard.changeCount != initialChange,
                   let text = pasteboard.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    captured = text
                    break
                }
            }

            self.showWindow()
            guard let text = captured else {
                self.errorMessage = L10n.t(
                    "Could not copy the selected text. Check Accessibility access.",
                    self.settings.interfaceLanguage
                )
                return
            }

            self.tab = .translate
            self.suppressRetranslation = true
            self.sourceText = text
            self.translatedText = ""
            self.errorMessage = nil
            self.lastDurationMs = nil
            self.tokensPerSecond = nil
            self.suppressRetranslation = false
            self.detectedLanguage = self.sourceLanguage == .auto ? Language.detect(text, preferred: settings.interfaceLanguage) : nil
            self.translate(force: true)
        }
    }

    private func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibility()
        }
    }

    func refreshAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Hot key and menu bar

    private func configureBindings() {
        settings.$hotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        settings.$selectionHotKey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.registerHotKeys() }
            .store(in: &cancellables)

        settings.$interfaceLanguage
            .dropFirst()
            .sink { [weak self] _ in
                self?.registerHotKeys()
                self?.refreshAccessibility()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshAccessibility() }
            .store(in: &cancellables)

        settings.$showInMenuBar
            .dropFirst()
            .sink { [weak self] show in
                if show { self?.installStatusItem() } else { self?.removeStatusItem() }
            }
            .store(in: &cancellables)

        settings.$provider
            .dropFirst()
            .sink { [weak self] _ in
                self?.providerModels = []
                self?.providerModelsSource = nil
                self?.modelsError = nil
                self?.scheduleProbe()
            }
            .store(in: &cancellables)
        settings.$apiKey
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleProbe() }
            .store(in: &cancellables)
        settings.$baseURL
            .dropFirst()
            .sink { [weak self] _ in
                self?.providerModels = []
                self?.providerModelsSource = nil
                self?.modelsError = nil
                self?.scheduleProbe()
            }
            .store(in: &cancellables)
        settings.$model
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleProbe() }
            .store(in: &cancellables)
    }

    private func registerHotKeys() {
        let language = settings.interfaceLanguage
        let clipboardCombo = settings.hotKey
        let selectionCombo = settings.selectionHotKey

        let clipboardOK = hotKeys.register(clipboardCombo, id: 1) { [weak self] in
            Task { @MainActor in self?.translateClipboard() }
        }
        let selectionOK = hotKeys.register(selectionCombo, id: 2) { [weak self] in
            Task { @MainActor in self?.translateSelection() }
        }

        debugLog("hotkey register \(clipboardCombo.displayString(language)): \(clipboardOK); selection \(selectionCombo.displayString(language)): \(selectionOK)")
        hotKeyActive = clipboardOK
        selectionHotKeyActive = selectionOK
        hotKeyMessage = clipboardOK
            ? L10n.format("%@ — active", language, clipboardCombo.displayString(language))
            : L10n.format("Could not register %@. The shortcut may be taken.", language, clipboardCombo.displayString(language))
        selectionHotKeyMessage = selectionOK
            ? L10n.format("%@ — active", language, selectionCombo.displayString(language))
            : L10n.format("Could not register %@. The shortcut may be taken.", language, selectionCombo.displayString(language))
        updateStatusMenu()
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "DeepL-oFM")
            image?.isTemplate = true
            button.image = image
        }
        statusItem = item
        updateStatusMenu()
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func updateStatusMenu() {
        guard let item = statusItem else { return }
        let language = settings.interfaceLanguage
        let menu = NSMenu()

        let open = NSMenuItem(title: L10n.t("Open DeepL-oFM", language), action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let selectionItem = NSMenuItem(
            title: L10n.format("Translate selection (%@)", language, settings.selectionHotKey.displayString(language)),
            action: #selector(menuTranslateSelection),
            keyEquivalent: ""
        )
        selectionItem.target = self
        menu.addItem(selectionItem)

        let clipboardItem = NSMenuItem(
            title: L10n.format("Translate clipboard (%@)", language, settings.hotKey.displayString(language)),
            action: #selector(menuTranslateClipboard),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: L10n.t("Quit", language), action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func menuOpen() {
        showWindow()
    }

    @objc private func menuTranslateClipboard() {
        translateClipboard()
    }

    @objc private func menuTranslateSelection() {
        translateSelection()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}

extension AppState: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStatus = L10n.format(
            "Update available: %@",
            settings.interfaceLanguage,
            item.displayVersionString
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateStatus = L10n.t("You're up to date.", settings.interfaceLanguage)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateStatus = L10n.format(
            "Update check failed: %@",
            settings.interfaceLanguage,
            error.localizedDescription
        )
    }
}
