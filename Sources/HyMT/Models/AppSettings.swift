import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {

    // MARK: Connection

    @Published var provider: Provider {
        didSet {
            store(provider.rawValue, Keys.provider)
            guard oldValue != provider else { return }
            if baseURL.isEmpty || baseURL == oldValue.baseURL {
                baseURL = provider.baseURL
            }
            apiKey = Keychain.read(provider.keyAccount)
        }
    }

    /// Kept in the Keychain, one item per provider. Never written to disk in
    /// clear text and never committed to the repository.
    @Published var apiKey: String {
        didSet { Keychain.write(apiKey, account: provider.keyAccount) }
    }

    @Published var baseURL: String {
        didSet { store(baseURL, Keys.baseURL) }
    }
    @Published var model: String {
        didSet { store(model, Keys.model) }
    }

    // MARK: Fallback provider

    @Published var fallbackEnabled: Bool {
        didSet { store(fallbackEnabled, Keys.fallbackEnabled) }
    }
    @Published var fallbackProvider: Provider {
        didSet {
            store(fallbackProvider.rawValue, Keys.fallbackProvider)
            guard oldValue != fallbackProvider else { return }
            if fallbackBaseURL.isEmpty || fallbackBaseURL == oldValue.baseURL {
                fallbackBaseURL = fallbackProvider.baseURL
            }
            fallbackAPIKey = Keychain.read(fallbackProvider.keyAccount)
            fallbackModel = ""
        }
    }
    @Published var fallbackAPIKey: String {
        didSet { Keychain.write(fallbackAPIKey, account: fallbackProvider.keyAccount) }
    }
    @Published var fallbackBaseURL: String {
        didSet { store(fallbackBaseURL, Keys.fallbackBaseURL) }
    }
    @Published var fallbackModel: String {
        didSet { store(fallbackModel, Keys.fallbackModel) }
    }

    // MARK: Generation

    @Published var temperature: Double {
        didSet { store(temperature, Keys.temperature) }
    }
    @Published var topP: Double {
        didSet { store(topP, Keys.topP) }
    }
    @Published var topK: Int {
        didSet { store(topK, Keys.topK) }
    }
    @Published var repetitionPenalty: Double {
        didSet { store(repetitionPenalty, Keys.repetitionPenalty) }
    }
    @Published var contextWindow: Int {
        didSet { store(contextWindow, Keys.contextWindow) }
    }

    // MARK: Behaviour

    @Published var autoTranslate: Bool {
        didSet { store(autoTranslate, Keys.autoTranslate) }
    }
    @Published var debounce: Double {
        didSet { store(debounce, Keys.debounce) }
    }
    @Published var hotKey: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Keys.hotKey)
            }
        }
    }
    @Published var showInMenuBar: Bool {
        didSet {
            store(showInMenuBar, Keys.showInMenuBar)
            // Never leave the app without a way to reach it.
            if !showInMenuBar && !showInDock { showInDock = true }
        }
    }
    @Published var showInDock: Bool {
        didSet {
            store(showInDock, Keys.showInDock)
            if !showInDock && !showInMenuBar { showInMenuBar = true }
        }
    }
    @Published var keepHistory: Bool {
        didSet { store(keepHistory, Keys.keepHistory) }
    }
    @Published var warmUpOnLaunch: Bool {
        didSet { store(warmUpOnLaunch, Keys.warmUpOnLaunch) }
    }
    @Published var interfaceLanguage: AppLanguage {
        didSet { store(interfaceLanguage.rawValue, Keys.interfaceLanguage) }
    }
    @Published var resultView: ResultViewMode {
        didSet { store(resultView.rawValue, Keys.resultView) }
    }
    @Published var selectionHotKey: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(selectionHotKey) {
                defaults.set(data, forKey: Keys.selectionHotKey)
            }
        }
    }

    // MARK: Last selection

    @Published var lastStyle: TranslationStyle {
        didSet { store(lastStyle.rawValue, Keys.lastStyle) }
    }
    @Published var lastTone: TranslationTone {
        didSet { store(lastTone.rawValue, Keys.lastTone) }
    }
    @Published var lastTargetCode: String {
        didSet { store(lastTargetCode, Keys.lastTarget) }
    }
    @Published var lastSourceCode: String {
        didSet { store(lastSourceCode, Keys.lastSource) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let provider = "hymt.provider"
        static let backend = "hymt.backend"
        static let baseURL = "hymt.baseURL"
        static let model = "hymt.model"
        static let fallbackEnabled = "hymt.fallbackEnabled"
        static let fallbackProvider = "hymt.fallbackProvider"
        static let fallbackBaseURL = "hymt.fallbackBaseURL"
        static let fallbackModel = "hymt.fallbackModel"
        static let temperature = "hymt.temperature"
        static let topP = "hymt.topP"
        static let topK = "hymt.topK"
        static let repetitionPenalty = "hymt.repetitionPenalty"
        static let contextWindow = "hymt.contextWindow"
        static let autoTranslate = "hymt.autoTranslate"
        static let debounce = "hymt.debounce"
        static let hotKey = "hymt.hotKey"
        static let showInMenuBar = "hymt.showInMenuBar"
        static let showInDock = "hymt.showInDock"
        static let keepHistory = "hymt.keepHistory"
        static let warmUpOnLaunch = "hymt.warmUpOnLaunch"
        static let interfaceLanguage = "hymt.interfaceLanguage"
        static let resultView = "hymt.resultView"
        static let selectionHotKey = "hymt.selectionHotKey"
        static let lastStyle = "hymt.lastStyle"
        static let lastTone = "hymt.lastTone"
        static let lastTarget = "hymt.lastTarget"
        static let lastSource = "hymt.lastSource"
    }

    init() {
        let legacyBackend = BackendKind(rawValue: defaults.string(forKey: Keys.backend) ?? "") ?? .ollama
        let storedBaseURL = defaults.string(forKey: Keys.baseURL) ?? legacyBackend.defaultBaseURL
        let storedProvider = defaults.string(forKey: Keys.provider).flatMap(Provider.init(rawValue:))
        let provider = storedProvider ?? Provider.infer(backend: legacyBackend, baseURL: storedBaseURL)
        self.provider = provider
        self.apiKey = Keychain.read(provider.keyAccount)
        self.baseURL = storedBaseURL
        self.model = defaults.string(forKey: Keys.model) ?? "hy-mt2:7b"

        let fallbackProvider = defaults.string(forKey: Keys.fallbackProvider)
            .flatMap(Provider.init(rawValue:)) ?? .ollama
        self.fallbackEnabled = defaults.object(forKey: Keys.fallbackEnabled) as? Bool ?? false
        self.fallbackProvider = fallbackProvider
        self.fallbackAPIKey = Keychain.read(fallbackProvider.keyAccount)
        self.fallbackBaseURL = defaults.string(forKey: Keys.fallbackBaseURL) ?? fallbackProvider.baseURL
        self.fallbackModel = defaults.string(forKey: Keys.fallbackModel) ?? ""

        let temperature = defaults.object(forKey: Keys.temperature) as? Double ?? 0.7
        let topP = defaults.object(forKey: Keys.topP) as? Double ?? 0.6
        let topK = defaults.object(forKey: Keys.topK) as? Int ?? 20
        let repetitionPenalty = defaults.object(forKey: Keys.repetitionPenalty) as? Double ?? 1.05
        let contextWindow = defaults.object(forKey: Keys.contextWindow) as? Int ?? 8192
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repetitionPenalty = repetitionPenalty
        self.contextWindow = contextWindow

        self.autoTranslate = defaults.object(forKey: Keys.autoTranslate) as? Bool ?? true
        self.debounce = defaults.object(forKey: Keys.debounce) as? Double ?? 0.45
        if let data = defaults.data(forKey: Keys.hotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.hotKey = combo
        } else {
            self.hotKey = .standard
        }
        let storedMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        let storedDock = defaults.object(forKey: Keys.showInDock) as? Bool ?? true
        self.showInMenuBar = storedMenuBar
        // Never leave the app without a way to reach it.
        self.showInDock = (storedMenuBar || storedDock) ? storedDock : true
        self.keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        self.warmUpOnLaunch = defaults.object(forKey: Keys.warmUpOnLaunch) as? Bool ?? true
        self.interfaceLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.interfaceLanguage) ?? "") ?? .system
        self.resultView = ResultViewMode(rawValue: defaults.string(forKey: Keys.resultView) ?? "") ?? .preview
        if let data = defaults.data(forKey: Keys.selectionHotKey),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.selectionHotKey = combo
        } else {
            self.selectionHotKey = .selection
        }

        self.lastStyle = TranslationStyle(rawValue: defaults.string(forKey: Keys.lastStyle) ?? "") ?? .auto
        self.lastTone = TranslationTone(rawValue: defaults.string(forKey: Keys.lastTone) ?? "") ?? .standard
        self.lastTargetCode = defaults.string(forKey: Keys.lastTarget) ?? "en"
        self.lastSourceCode = defaults.string(forKey: Keys.lastSource) ?? "auto"

        defaults.set(provider.rawValue, forKey: Keys.provider)
    }

    private func store<T>(_ value: T, _ key: String) {
        defaults.set(value, forKey: key)
    }

    var kind: BackendKind { provider.kind }

    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? provider.baseURL : value
    }

    var snapshot: BackendConfig {
        BackendConfig(
            kind: kind,
            baseURL: normalizedBaseURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            topP: topP,
            topK: topK,
            repetitionPenalty: repetitionPenalty,
            contextWindow: contextWindow
        )
    }

    var normalizedFallbackBaseURL: String {
        var value = fallbackBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? fallbackProvider.baseURL : value
    }

    var fallbackConfig: BackendConfig? {
        let value = fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fallbackEnabled, !value.isEmpty else { return nil }
        return BackendConfig(
            kind: fallbackProvider.kind,
            baseURL: normalizedFallbackBaseURL,
            model: value,
            apiKey: Keychain.read(fallbackProvider.keyAccount)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            topP: topP,
            topK: topK,
            repetitionPenalty: repetitionPenalty,
            contextWindow: contextWindow
        )
    }

    var fallbackProbeConfig: BackendConfig {
        BackendConfig(
            kind: fallbackProvider.kind,
            baseURL: normalizedFallbackBaseURL,
            model: fallbackModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: Keychain.read(fallbackProvider.keyAccount)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            topP: topP,
            topK: topK,
            repetitionPenalty: repetitionPenalty,
            contextWindow: contextWindow
        )
    }

    var installCommand: String? {
        ModelCatalog.installCommand(for: model)
    }

    func apply(provider: Provider, model: String? = nil) {
        self.provider = provider
        self.baseURL = provider.baseURL
        if let model, !model.isEmpty {
            self.model = model
        }
    }

    func apply(entry: CatalogEntry) {
        apply(provider: entry.provider, model: entry.modelID)
    }

    func clearKey() {
        apiKey = ""
        Keychain.delete(provider.keyAccount)
    }
}
