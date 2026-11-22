import Foundation

enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case ollama
    case openAI

    var id: String { rawValue }

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
