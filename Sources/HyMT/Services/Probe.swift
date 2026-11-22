import Foundation

enum Probe {

    static func models(_ config: BackendConfig) async throws -> [String] {
        let url: URL?
        switch config.kind {
        case .ollama:
            url = URL(string: config.baseURL + "/api/tags")
        case .openAI:
            var base = config.baseURL
            while base.hasSuffix("/") { base.removeLast() }
            url = URL(string: base.hasSuffix("/v1") ? base + "/models" : base + "/v1/models")
        }
        guard let url else { throw TranslationError.invalidURL(config.baseURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslationError.connection(config.baseURL)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.connection(config.baseURL)
        }
        guard http.statusCode == 200 else {
            throw TranslationError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.backend("Сервер повернув неочікувану відповідь.")
        }

        switch config.kind {
        case .ollama:
            let models = object["models"] as? [[String: Any]] ?? []
            return models.compactMap { $0["name"] as? String ?? $0["model"] as? String }
        case .openAI:
            let models = object["data"] as? [[String: Any]] ?? []
            return models.compactMap { $0["id"] as? String }
        }
    }

    static func model(_ name: String, isListedIn models: [String]) -> Bool {
        let target = name.lowercased()
        if models.isEmpty { return true }
        return models.contains { listed in
            let value = listed.lowercased()
            return value == target || value.hasPrefix(target + ":") || value.hasSuffix("/" + target)
        }
    }
}
