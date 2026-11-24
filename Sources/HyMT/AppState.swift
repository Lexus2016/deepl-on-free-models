import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation
import Sparkle

extension Notification.Name {
    static let showMainWindow = Notification.Name("ua.admin.hymt.showMainWindow")
}

@MainActor
final class AppState: NSObject, ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case translate
        case write
        case files
        case history
        case settings

        var id: String { rawValue }

        func title(_ language: AppLanguage) -> String {
            switch self {
            case .translate: return L10n.t("Translate text", language)
            case .write: return L10n.t("Improve text", language)
            case .files: return L10n.t("Files", language)
            case .history: return L10n.t("History", language)
            case .settings: return L10n.t("Settings", language)
            }
        }

        var icon: String {
            switch self {
            case .translate: return "character.bubble"
            case .write: return "wand.and.stars"
            case .files: return "doc.text"
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
    @Published var sourceText: String = "" {
        didSet { sourceCharacterCount = sourceText.count }
    }
    @Published var translatedText: String = "" {
        didSet { translatedCharacterCount = translatedText.count }
    }
    private(set) var sourceCharacterCount = 0
    private(set) var translatedCharacterCount = 0
    @Published var isTranslating: Bool = false
    @Published var translationCompleted: Int = 0
    @Published var translationTotal: Int = 0
    @Published var translationWarningCount: Int = 0
    @Published var errorMessage: String?
    @Published var tokensPerSecond: Double?
    @Published var lastDurationMs: Int?
    @Published var windowRequest = 0
    @Published var speaking: SpeakTarget?
    let files = FileTranslationStore()
    let write = WriteStore()

    @Published var sourceLanguage: Language {
        didSet {
            settings.lastSourceCode = sourceLanguage.code
            scheduleLanguageDetection()
            if oldValue != sourceLanguage { retranslateIfPossible() }
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
    @Published var fallbackModels: [String] = []
    @Published var fallbackModelsLoading: Bool = false
    @Published var fallbackModelsError: String?
    @Published var usingFallback: Bool = false

    // MARK: Dependencies

    let settings: AppSettings
    let history: HistoryStore
    private(set) var updaterController: SPUStandardUpdaterController!

    private let translator = TranslationService()
    private let hotKeys = HotKeyManager()
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?
    private var fallbackModelsTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?

    private var currentGeneration = UUID()
    private var lastCompletedKey: TranslationKey?
    private struct TranslationKey: Equatable {
        let text: String
        let source: Language
        let target: Language
        let style: TranslationStyle
        let tone: TranslationTone
        let config: BackendConfig
    }
    private var suppressRetranslation = false
    private var didBootstrap = false
    private var didActivateWindow = false
    private var selectionService: SelectionTranslationService?

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
        Speaker.shared.onFinish = { [weak self] in
            self?.speaking = nil
        }
        configureBindings()
        let service = SelectionTranslationService { [weak self] text in
            self?.translateReceivedText(text)
        }
        selectionService = service
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [history] _ in history.flush() }
            .store(in: &cancellables)
        registerHotKeys()
        if settings.showInMenuBar { installStatusItem() }
        applyActivationPolicy()
    }

    private func applyActivationPolicy() {
        let visible = mainWindow?.isVisible == true
        let policy: NSApplication.ActivationPolicy =
            (settings.showInDock || visible) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    // MARK: - Lifecycle

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        debugLog("accessibility trusted: \(AXIsProcessTrusted())")
        let immediateWork = CommandLine.arguments.contains("--prefill")
            || CommandLine.arguments.contains("--translate-clipboard")
        if settings.warmUpOnLaunch {
            connectAndLoadModels()
            if settings.provider.isLocal, !immediateWork {
                warmUpModel()
            }
        } else {
            checkConnection()
        }

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
        if let index = arguments.firstIndex(of: "--open-file"), arguments.count > index + 1 {
            let url = URL(fileURLWithPath: arguments[index + 1])
            tab = .files
            files.select(url: url, language: settings.interfaceLanguage)
        }
        if let index = arguments.firstIndex(of: "--write-text"), arguments.count > index + 1 {
            tab = .write
            write.sourceText = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.write.improve(
                    settings: self.settings,
                    interfaceLanguage: self.settings.interfaceLanguage
                )
            }
        }
        if arguments.contains("--translate-file") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.files.translate(
                    settings: self.settings,
                    language: self.settings.interfaceLanguage
                )
            }
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
        if arguments.contains("--load-fallback-models") {
            loadFallbackModels()
        }
        if let index = arguments.firstIndex(of: "--tab"), arguments.count > index + 1 {
            switch arguments[index + 1] {
            case "settings": tab = .settings
            case "files": tab = .files
            case "write": tab = .write
            case "history": tab = settings.keepHistory ? .history : .translate
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
        window.minSize = NSSize(width: 880, height: 580)
        window.delegate = self
        if let close = window.standardWindowButton(.closeButton) {
            close.target = self
            close.action = #selector(hideMainWindow)
        }

        guard !didActivateWindow else { return }
        didActivateWindow = true
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            self.applyActivationPolicy()
        }
    }

    func showWindow() {
        let regular: NSApplication.ActivationPolicy = .regular
        if NSApp.activationPolicy() != regular {
            NSApp.setActivationPolicy(regular)
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            applyActivationPolicy()
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            applyActivationPolicy()
        } else {
            // The window was destroyed (for example after a close on another
            // path): ask SwiftUI to create the scene again.
            windowRequest += 1
        }
    }

    @objc private func hideMainWindow() {
        mainWindow?.orderOut(nil)
        applyActivationPolicy()
    }

}

extension AppState: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        applyActivationPolicy()
        return false
    }
}

extension AppState {
    // MARK: - Translation

    private func scheduleLanguageDetection() {
        detectionTask?.cancel()
        guard sourceLanguage == .auto, !sourceText.isEmpty else {
            detectedLanguage = nil
            return
        }
        let input = String(sourceText.prefix(600))
        let language = settings.interfaceLanguage
        detectionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled else { return }
            let detected = Language.detect(input, preferred: language)
            if detected != detectedLanguage { detectedLanguage = detected }
        }
    }

    func sourceChanged(_ text: String) {
        guard text != sourceText else { return }
        cancelTranslation()
        sourceText = text
        scheduleLanguageDetection()
        lastCompletedKey = nil
        resetTranslationResult()

        guard !text.isEmpty, settings.autoTranslate, !suppressRetranslation else { return }
        let delay = max(0.1, settings.debounce)
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.translate(force: false)
        }
    }

    private func resetTranslationResult() {
        if !translatedText.isEmpty { translatedText = "" }
        if errorMessage != nil { errorMessage = nil }
        if lastDurationMs != nil { lastDurationMs = nil }
        if tokensPerSecond != nil { tokensPerSecond = nil }
        if translationCompleted != 0 { translationCompleted = 0 }
        if translationTotal != 0 { translationTotal = 0 }
        if translationWarningCount != 0 { translationWarningCount = 0 }
        if usingFallback { usingFallback = false }
    }

    func translate(force: Bool) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translatedText = ""
            isTranslating = false
            return
        }

        let source = sourceLanguage
        let target = targetLanguage
        let style = self.style
        let tone = self.tone
        let config = settings.snapshot
        let key = TranslationKey(text: trimmed, source: source, target: target, style: style, tone: tone, config: config)

        if !force, key == lastCompletedKey {
            return
        }

        translationTask?.cancel()
        debounceTask?.cancel()
        let generation = UUID()
        currentGeneration = generation
        resetTranslationResult()
        isTranslating = true
        debugLog("translate start: model=\(config.model) target=\(target.englishName) style=\(style.rawValue) tone=\(tone.rawValue) chars=\(trimmed.count)")

        let primaryEngine = "\(settings.provider.title) · \(config.model)"
        let fallbackConfig = settings.fallbackConfig.flatMap { config.usesSameEndpoint(as: $0) ? nil : $0 }
        let fallbackEngine = fallbackConfig.map {
            "\(settings.fallbackProvider.title) · \($0.model) (fallback)"
        }

        translationTask = Task { [weak self] in
            guard let self else { return }
            let result: (text: String, warnings: Int, duration: Int)
            var engine = primaryEngine

            do {
                result = try await self.performTranslation(
                    text: trimmed,
                    style: style,
                    tone: tone,
                    target: target,
                    config: config,
                    generation: generation,
                    retryRateLimit: fallbackConfig == nil,
                    source: source
                )
            } catch is CancellationError {
                return
            } catch {
                guard self.currentGeneration == generation, !Task.isCancelled else { return }
                let primaryError = error
                if let fallbackConfig {
                    self.debugLog("primary failed, using fallback: \(error.localizedDescription)")
                    self.usingFallback = true
                    self.translationCompleted = 0
                    self.translationTotal = 0
                    self.translationWarningCount = 0
                    self.tokensPerSecond = nil
                    do {
                        result = try await self.performTranslation(
                            text: trimmed,
                            style: style,
                            tone: tone,
                            target: target,
                            config: fallbackConfig,
                            generation: generation,
                            retryRateLimit: true,
                            source: source
                        )
                        engine = fallbackEngine ?? engine
                    } catch is CancellationError {
                        return
                    } catch {
                        guard self.currentGeneration == generation, !Task.isCancelled else { return }
                        self.isTranslating = false
                        self.usingFallback = false
                        self.presentTranslationError(error, generation: generation)
                        return
                    }
                } else {
                    self.isTranslating = false
                    self.presentTranslationError(primaryError, generation: generation)
                    return
                }
            }

            guard !Task.isCancelled, self.currentGeneration == generation else { return }
            let duration = result.duration
            self.translatedText = result.text
            self.translationCompleted = self.translationTotal
            self.translationWarningCount = result.warnings
            self.debugLog("Translation finished in \(duration) ms.")
            self.isTranslating = false
            if result.warnings > 0 {
                self.errorMessage = L10n.format(
                    "Some lines could not be translated (%d); they are left in the source language.",
                    self.settings.interfaceLanguage,
                    result.warnings
                )
            }
            self.lastDurationMs = duration
            self.lastCompletedKey = result.warnings == 0 ? key : nil
            self.backendStatus = .ready
            self.probeMessage = L10n.t(
                self.usingFallback ? "Fallback provider works." : "Connection works.",
                self.settings.interfaceLanguage
            )

            if self.settings.keepHistory {
                self.history.add(HistoryEntry(
                    sourceText: trimmed,
                    translatedText: self.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceCode: source.code,
                    targetCode: target.code,
                    style: style,
                    tone: tone,
                    engine: engine,
                    durationMs: duration
                ))
            }
        }
    }

    private func performTranslation(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        target: Language,
        config: BackendConfig,
        generation: UUID,
        retryRateLimit: Bool,
        source: Language
    ) async throws -> (text: String, warnings: Int, duration: Int) {
        let started = Date()
        let stream = translator.stream(
            text: text,
            style: style,
            tone: tone,
            target: target,
            config: config,
            retryRateLimit: retryRateLimit,
            sourceLanguage: source
        )
        var buffer = ""
        var warnings = 0
        for try await event in stream {
            if Task.isCancelled || currentGeneration != generation {
                throw CancellationError()
            }
            switch event {
            case .chunk(let piece):
                buffer += piece
            case .stats(let tps):
                tokensPerSecond = tps
            case .progress(let completed, let total):
                if translationCompleted != completed { translationCompleted = completed }
                if translationTotal != total { translationTotal = total }
            case .warning:
                warnings += 1
            }
        }
        if Task.isCancelled || currentGeneration != generation {
            throw CancellationError()
        }
        return (
            OutputSanitizer.clean(buffer),
            warnings,
            Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    private func presentTranslationError(_ error: Error, generation: UUID) {
        guard currentGeneration == generation else { return }
        if error is CancellationError { return }
        debugLog("translate error: \(error.localizedDescription)")
        let language = settings.interfaceLanguage
        let message = (error as? TranslationError)?.message(language) ?? error.localizedDescription
        errorMessage = message
        if let translationError = error as? TranslationError,
           case .connection = translationError {
            backendStatus = .error(message)
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
        if isTranslating { isTranslating = false }
    }

    func clearSource() {
        cancelTranslation()
        detectionTask?.cancel()
        sourceText = ""
        detectedLanguage = nil
        lastCompletedKey = nil
        resetTranslationResult()
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
        if !oldTranslation.isEmpty {
            sourceText = oldTranslation
            translatedText = oldSource
        }
        detectedLanguage = nil
        suppressRetranslation = false

        if !sourceText.isEmpty {
            translate(force: true)
        }
    }

    func translateClipboard() {
        // Keep the formatting of a copied page or document: HTML/RTF becomes
        // Markdown, so headings, lists and links survive translation.
        let clipboard = (RichTextPasteboard.markdown() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipboard.isEmpty else {
            showWindow()
            return
        }
        translateReceivedText(clipboard)
    }

    private func translateReceivedText(_ text: String) {
        showWindow()
        tab = .translate
        suppressRetranslation = true
        sourceText = text
        translatedText = ""
        errorMessage = nil
        lastDurationMs = nil
        tokensPerSecond = nil
        suppressRetranslation = false
        detectedLanguage = sourceLanguage == .auto ? Language.detect(text, preferred: settings.interfaceLanguage) : nil
        translate(force: true)
    }

    func copyTranslation() {
        let text = translatedText
        guard !text.isEmpty else { return }
        switch settings.resultView {
        case .preview:
            ClipboardWriter.copy(text)
        case .text:
            ClipboardWriter.copyPlain(MarkdownRenderer.plainText(text))
        case .markdown:
            ClipboardWriter.copyPlain(text)
        }
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

    enum SpeakTarget {
        case source
        case translation
    }

    var translationPercent: Int {
        guard translationTotal > 0 else { return 0 }
        let value = Double(translationCompleted) / Double(translationTotal)
        return min(100, Int((value * 100).rounded()))
    }

    func speakSource() {
        if speaking == .source {
            stopSpeaking()
            return
        }
        let language = sourceLanguage == .auto
            ? (Language.detect(sourceText, preferred: settings.interfaceLanguage) ?? .auto)
            : sourceLanguage
        if Speaker.shared.speak(
            sourceText,
            language: language,
            voiceID: settings.speechVoiceID
        ) {
            speaking = .source
        }
    }

    func speakTranslation() {
        if speaking == .translation {
            stopSpeaking()
            return
        }
        if Speaker.shared.speak(
            translatedText,
            language: targetLanguage,
            voiceID: settings.speechVoiceID
        ) {
            speaking = .translation
        }
    }

    func stopSpeaking() {
        Speaker.shared.stop()
        speaking = nil
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
        modelsTask?.cancel()
        modelsLoading = false
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            await self?.runProbe()
        }
    }

    func scheduleProbe() {
        modelsTask?.cancel()
        modelsLoading = false
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

        probeTask?.cancel()
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

    func loadFallbackModels() {
        let language = settings.interfaceLanguage
        let provider = settings.fallbackProvider
        let config = settings.fallbackProbeConfig

        fallbackModelsTask?.cancel()
        fallbackModelsLoading = true
        fallbackModelsError = nil

        if provider.requiresKey && config.apiKey.isEmpty {
            fallbackModelsLoading = false
            fallbackModelsError = L10n.format(
                "Enter the API key for %@ in Settings first.",
                language,
                provider.title
            )
            return
        }

        fallbackModelsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await Probe.models(config)
                guard !Task.isCancelled else { return }
                self.fallbackModels = models.sorted()
                self.fallbackModelsLoading = false
                if models.isEmpty {
                    self.fallbackModelsError = L10n.t("The server returned no models.", language)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.fallbackModelsLoading = false
                self.fallbackModels = []
                self.fallbackModelsError = (error as? TranslationError)?.message(language) ?? error.localizedDescription
            }
        }
    }

    private func warmUpModel() {
        guard settings.warmUpOnLaunch, settings.provider.isLocal else { return }
        let config = settings.snapshot
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.translator.warmUp(config: config)
            self.debugLog("warm-up \(config.model): \(ok)")
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
            try Task.checkCancellation()
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
            guard !Task.isCancelled else { return }
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
                if pasteboard.changeCount != initialChange {
                    let plain = pasteboard.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !plain.isEmpty {
                        captured = RichTextPasteboard.markdown() ?? plain
                        break
                    }
                }
            }

            guard let text = captured else {
                self.showWindow()
                self.errorMessage = L10n.t(
                    "Could not copy the selected text. Check Accessibility access.",
                    self.settings.interfaceLanguage
                )
                return
            }

            self.translateReceivedText(text)
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

        settings.$showInDock
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyActivationPolicy()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.$keepHistory
            .dropFirst()
            .sink { [weak self] keep in
                guard let self else { return }
                if !keep, self.tab == .history {
                    self.tab = .translate
                }
                self.objectWillChange.send()
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
        settings.$fallbackProvider
            .dropFirst()
            .sink { [weak self] _ in
                self?.fallbackModels = []
                self?.fallbackModelsError = nil
                self?.fallbackModelsTask?.cancel()
                self?.fallbackModelsLoading = false
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        settings.$fallbackBaseURL
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.fallbackModelsTask?.cancel()
                self?.fallbackModels = []
                self?.fallbackModelsLoading = false
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

    func setHotKey(_ combo: KeyCombo, forSelection: Bool) {
        guard registerHotKey(combo, forSelection: forSelection) else { return }
        if forSelection {
            settings.selectionHotKey = combo
        } else {
            settings.hotKey = combo
        }
        updateStatusMenu()
    }

    private func registerHotKeys() {
        _ = registerHotKey(settings.hotKey, forSelection: false)
        _ = registerHotKey(settings.selectionHotKey, forSelection: true)
        updateStatusMenu()
    }

    private func registerHotKey(_ combo: KeyCombo, forSelection: Bool) -> Bool {
        let language = settings.interfaceLanguage
        let registered = hotKeys.register(combo, id: forSelection ? 2 : 1) { [weak self] in
            Task { @MainActor in
                if forSelection {
                    self?.translateSelection()
                } else {
                    self?.translateClipboard()
                }
            }
        }
        let display = combo.displayString(language)
        let message = registered
            ? L10n.format("%@ — active", language, display)
            : L10n.format("Could not register %@. The shortcut may be taken.", language, display)
        if forSelection {
            selectionHotKeyActive = registered
            selectionHotKeyMessage = message
        } else {
            hotKeyActive = registered
            hotKeyMessage = message
        }
        return registered
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
