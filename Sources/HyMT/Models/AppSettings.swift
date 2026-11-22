import Foundation
import SwiftUI

enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: return "Ollama"
        case .openAI: return "OpenAI-сумісний"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .openAI: return "http://127.0.0.1:1234/v1"
        }
    }
}

struct BackendConfig: Sendable {
    var kind: BackendKind
    var baseURL: String
    var model: String
    var apiKey: String
    var temperature: Double
    var topP: Double
    var topK: Int
    var repetitionPenalty: Double
    var contextWindow: Int
}

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
        didSet { store(showInMenuBar, Keys.showInMenuBar) }
    }
    @Published var keepHistory: Bool {
        didSet { store(keepHistory, Keys.keepHistory) }
    }
    @Published var interfaceLanguage: AppLanguage {
        didSet { store(interfaceLanguage.rawValue, Keys.interfaceLanguage) }
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
        static let temperature = "hymt.temperature"
        static let topP = "hymt.topP"
        static let topK = "hymt.topK"
        static let repetitionPenalty = "hymt.repetitionPenalty"
        static let contextWindow = "hymt.contextWindow"
        static let autoTranslate = "hymt.autoTranslate"
        static let debounce = "hymt.debounce"
        static let hotKey = "hymt.hotKey"
        static let showInMenuBar = "hymt.showInMenuBar"
        static let keepHistory = "hymt.keepHistory"
        static let interfaceLanguage = "hymt.interfaceLanguage"
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
        self.showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        self.keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        self.interfaceLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.interfaceLanguage) ?? "") ?? .system
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
