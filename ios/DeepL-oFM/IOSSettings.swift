import Foundation
import SwiftUI

extension Provider {
    /// Local servers point at the phone itself, so iOS offers the cloud
    /// providers and a custom (LAN) endpoint.
    static let iosProviders: [Provider] = [
        .groq, .openRouter, .cerebras, .ollamaCloud, .custom
    ]

    var iosDefaultModel: String {
        switch self {
        case .groq, .openRouter: return "openai/gpt-oss-120b"
        case .cerebras: return "gpt-oss-120b"
        case .ollamaCloud: return "gpt-oss:120b"
        default: return "hy-mt2:7b"
        }
    }


}

@MainActor
final class IOSSettings: ObservableObject {
    @Published var provider: Provider {
        didSet {
            store(provider.rawValue, Keys.provider)
            guard oldValue != provider else { return }
            store(baseURL, "\(Keys.baseURL).\(oldValue.rawValue)")
            store(model, "\(Keys.model).\(oldValue.rawValue)")
            baseURL = defaults.string(forKey: "\(Keys.baseURL).\(provider.rawValue)") ?? provider.baseURL
            model = defaults.string(forKey: "\(Keys.model).\(provider.rawValue)") ?? provider.iosDefaultModel
            apiKey = Keychain.read(provider.keyAccount)
        }
    }
    @Published var apiKey: String {
        didSet { Keychain.write(apiKey, account: provider.keyAccount) }
    }
    @Published var baseURL: String {
        didSet { store(baseURL, Keys.baseURL) }
    }
    @Published var model: String {
        didSet { store(model, Keys.model) }
    }
    @Published var targetCode: String {
        didSet { store(targetCode, Keys.target) }
    }
    @Published var interfaceLanguage: AppLanguage {
        didSet { store(interfaceLanguage.rawValue, Keys.interface) }
    }
    @Published var style: TranslationStyle {
        didSet { store(style.rawValue, Keys.style) }
    }
    @Published var tone: TranslationTone {
        didSet { store(tone.rawValue, Keys.tone) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let provider = "ios.provider"
        static let baseURL = "ios.baseURL"
        static let model = "ios.model"
        static let target = "ios.target"
        static let interface = "ios.interface"
        static let style = "ios.style"
        static let tone = "ios.tone"
    }

    init() {
        let stored = defaults.string(forKey: Keys.provider)
            .flatMap(Provider.init(rawValue:)) ?? .groq
        let provider = Provider.iosProviders.contains(stored) ? stored : .groq
        self.provider = provider
        self.apiKey = Keychain.read(provider.keyAccount)
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? provider.baseURL
        self.model = defaults.string(forKey: Keys.model) ?? provider.iosDefaultModel

        let systemCode = Locale.current.language.languageCode?.identifier ?? "en"
        let defaultTarget = Language.with(code: systemCode) != nil ? systemCode : "en"
        self.targetCode = defaults.string(forKey: Keys.target) ?? defaultTarget

        self.interfaceLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.interface) ?? ""
        ) ?? .system
        self.style = TranslationStyle(
            rawValue: defaults.string(forKey: Keys.style) ?? ""
        ) ?? .auto
        self.tone = TranslationTone(
            rawValue: defaults.string(forKey: Keys.tone) ?? ""
        ) ?? .standard
    }

    var target: Language {
        translationConfiguration.target
    }

    var needsAPIKey: Bool { provider.requiresKey }

    var normalizedBaseURL: String {
        guard provider == .custom else { return provider.baseURL }
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? provider.baseURL : value
    }

    var snapshot: BackendConfig {
        translationConfiguration.backend
    }

    var translationConfiguration: IOSTranslationConfiguration {
        IOSTranslationConfiguration(
            provider: provider,
            baseURL: normalizedBaseURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            targetCode: targetCode,
            interfaceLanguage: interfaceLanguage,
            style: style,
            tone: tone
        )
    }

    private func store<T>(_ value: T, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
