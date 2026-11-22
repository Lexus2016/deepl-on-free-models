import Foundation

/// A place a model can run. `kind` decides the wire protocol; the rest is
/// presentation and defaults.
enum Provider: String, Codable, CaseIterable, Identifiable {
    case ollama
    case ollamaCloud
    case lmStudio
    case omlx
    case llamaCpp
    case openRouter
    case groq
    case cerebras
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: return "Ollama"
        case .ollamaCloud: return "Ollama Cloud"
        case .lmStudio: return "LM Studio"
        case .omlx: return "oMLX"
        case .llamaCpp: return "llama.cpp"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .custom: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .ollamaCloud: return "cloud"
        case .lmStudio: return "square.stack.3d.up"
        case .omlx: return "bolt.horizontal"
        case .llamaCpp: return "terminal"
        case .openRouter: return "arrow.triangle.branch"
        case .groq: return "wind"
        case .cerebras: return "cpu"
        case .custom: return "slider.horizontal.3"
        }
    }

    var kind: BackendKind {
        switch self {
        case .ollama: return .ollama
        default: return .openAI
        }
    }

    var baseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .ollamaCloud: return "https://ollama.com/v1"
        case .lmStudio: return "http://127.0.0.1:1234/v1"
        case .omlx: return "http://127.0.0.1:50220/v1"
        case .llamaCpp: return "http://127.0.0.1:8080/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .custom: return "http://127.0.0.1:1234/v1"
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .lmStudio, .omlx, .llamaCpp: return true
        default: return false
        }
    }

    var requiresKey: Bool {
        switch self {
        case .openRouter, .groq, .cerebras, .ollamaCloud: return true
        default: return false
        }
    }

    var keyURL: URL? {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai")
        case .ollamaCloud: return URL(string: "https://ollama.com/settings/keys")
        default: return nil
        }
    }

    var keyAccount: String { "provider:" + rawValue }

    /// English key, localised through L10n at the call site.
    var detailKey: String {
        switch self {
        case .ollama:
            return "Local Ollama server. The model must be pulled with ollama pull."
        case .ollamaCloud:
            return "Ollama Cloud through a direct API key. No local server is needed."
        case .lmStudio:
            return "LM Studio with its local server enabled. The model ID is shown in LM Studio."
        case .omlx:
            return "oMLX — an MLX server for Apple Silicon. Enable the OpenAI-compatible API."
        case .llamaCpp:
            return "llama-server with --api. The default address is port 8080."
        case .openRouter:
            return "Hundreds of models with one key. Free models are marked :free."
        case .groq:
            return "Very fast cloud. Has a free tier with request limits."
        case .cerebras:
            return "Fastest inference for open models. Has a free tier with limits."
        case .custom:
            return "Any OpenAI-compatible server: your proxy, vLLM, LocalAI, Together, and so on."
        }
    }

    func detail(_ language: AppLanguage) -> String {
        L10n.t(detailKey, language)
    }

    static func infer(backend: BackendKind, baseURL: String) -> Provider {
        let value = baseURL.lowercased()
        if value.contains("ollama.com") { return .ollamaCloud }
        if backend == .ollama { return .ollama }
        if value.contains("openrouter.ai") { return .openRouter }
        if value.contains("api.groq.com") { return .groq }
        if value.contains("cerebras.ai") { return .cerebras }
        if value.contains(":1234") { return .lmStudio }
        if value.contains(":50220") { return .omlx }
        if value.contains(":8080") { return .llamaCpp }
        return .custom
    }
}
