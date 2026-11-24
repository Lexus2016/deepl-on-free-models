import Foundation
import Security

struct IOSTranslationConfiguration: Codable, Equatable {
    var provider: Provider
    var baseURL: String
    var model: String
    var apiKey: String
    var targetCode: String
    var interfaceLanguage: AppLanguage
    var style: TranslationStyle
    var tone: TranslationTone

    var target: Language {
        Language.with(code: targetCode) ?? Language.with(code: "en")!
    }

    var backend: BackendConfig {
        BackendConfig(
            kind: provider.kind,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            temperature: 0.7,
            topP: 0.6,
            topK: 20,
            repetitionPenalty: 1.05,
            contextWindow: 8192,
            requiresAPIKey: provider.requiresKey
        )
    }
}

enum SystemTranslationSettings {
    private static let item: [String: Any]? = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SystemTranslationKeychainAccessGroup") as? String,
              group.hasSuffix(".ua.admin.hymt.ios.translation") else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessGroup as String: group,
            kSecAttrService as String: "ua.admin.hymt.ios.system-translation",
            kSecAttrAccount as String: "configuration"
        ]
    }()

    static func load() -> IOSTranslationConfiguration? {
        guard var query = item else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(IOSTranslationConfiguration.self, from: data)
    }

    @discardableResult
    static func save(_ configuration: IOSTranslationConfiguration) -> Bool {
        guard let item, let data = try? JSONEncoder().encode(configuration) else { return false }
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(item as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var record = item
        record[kSecValueData as String] = data
        record[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(record as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return SecItemUpdate(item as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return addStatus == errSecSuccess
    }
}
