import Foundation

/// Curated translation models the app knows how to apply with one click.
/// The list is intentionally small and editable: anything else can be typed
/// into the model field, and cloud providers can list their own models.
struct CatalogEntry: Identifiable, Hashable {
    let id: String
    let provider: Provider
    let modelID: String
    let title: String
    let summary: String
    let badges: [String]
    let isFree: Bool
    let installCommand: String?
}

enum ModelCatalog {

    static let entries: [CatalogEntry] = localEntries + ollamaCloudEntries + openRouterEntries + groqEntries + cerebrasEntries

    static let localEntries: [CatalogEntry] = [
        CatalogEntry(
            id: "local-hy-mt2-7b",
            provider: .ollama,
            modelID: "hy-mt2:7b",
            title: "Hy-MT2 7B",
            summary: "Tencent's specialised translation model. The default for this app.",
            badges: ["33 languages", "≈4.6 GB", "recommended"],
            isFree: true,
            installCommand: "ollama pull maternion/hy-mt2:7b && ollama cp maternion/hy-mt2:7b hy-mt2:7b"
        ),
        CatalogEntry(
            id: "local-hy-mt2-1.8b",
            provider: .ollama,
            modelID: "hy-mt2:1.8b",
            title: "Hy-MT2 1.8B",
            summary: "The same model in a lighter size: fast even on weaker Macs.",
            badges: ["33 languages", "light", "fast"],
            isFree: true,
            installCommand: "ollama pull maternion/hy-mt2:1.8b && ollama cp maternion/hy-mt2:1.8b hy-mt2:1.8b"
        ),
        CatalogEntry(
            id: "local-hy-mt2-30b",
            provider: .ollama,
            modelID: "hy-mt2:30b",
            title: "Hy-MT2 30B-A3B",
            summary: "The highest-quality MoE version. Needs a lot of memory.",
            badges: ["33 languages", "MoE", "large"],
            isFree: true,
            installCommand: "ollama pull maternion/hy-mt2:30b-a3b && ollama cp maternion/hy-mt2:30b-a3b hy-mt2:30b"
        ),
        CatalogEntry(
            id: "local-translategemma-4b",
            provider: .ollama,
            modelID: "translategemma:4b",
            title: "TranslateGemma 4B",
            summary: "Google's translation model built on Gemma 3.",
            badges: ["55 languages", "≈3 GB"],
            isFree: true,
            installCommand: "ollama pull translategemma:4b"
        ),
        CatalogEntry(
            id: "local-translategemma-12b",
            provider: .ollama,
            modelID: "translategemma:12b",
            title: "TranslateGemma 12B",
            summary: "A larger TranslateGemma for stronger machines.",
            badges: ["55 languages", "≈8 GB"],
            isFree: true,
            installCommand: "ollama pull translategemma:12b"
        ),
        CatalogEntry(
            id: "local-qwen35-mt-2b",
            provider: .ollama,
            modelID: "qwen3.5-mt:2b",
            title: "Qwen3.5-MT 2B",
            summary: "A compact model tuned only to translate — no explanations or reasoning.",
            badges: ["translation", "2B"],
            isFree: true,
            installCommand: "ollama pull kaelri/qwen3.5-mt:2b"
        ),
        CatalogEntry(
            id: "local-aya-expanse-8b",
            provider: .ollama,
            modelID: "aya-expanse:8b",
            title: "Aya Expanse 8B",
            summary: "Cohere's multilingual model with a good speed-quality balance.",
            badges: ["23 languages", "8B"],
            isFree: true,
            installCommand: "ollama pull aya-expanse:8b"
        ),
        CatalogEntry(
            id: "local-qwen3-8b",
            provider: .ollama,
            modelID: "qwen3:8b",
            title: "Qwen3 8B",
            summary: "A general model; translates well but may add explanations.",
            badges: ["universal", "8B"],
            isFree: true,
            installCommand: "ollama pull qwen3:8b"
        )
    ]

    static let ollamaCloudEntries: [CatalogEntry] = [
        CatalogEntry(
            id: "oc-gemma4-31b",
            provider: .ollamaCloud,
            modelID: "gemma4:31b",
            title: "Gemma 4 31B",
            summary: "Gemma 4 in Ollama Cloud. Fast and strong for general translation.",
            badges: ["Cloud", "31B", "fast"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "oc-deepseek-v41-flash",
            provider: .ollamaCloud,
            modelID: "deepseek-v4.1-flash",
            title: "DeepSeek V4.1 Flash",
            summary: "A fast cloud model from DeepSeek with a large context.",
            badges: ["Cloud", "1M", "fast"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "oc-mistral-large-4",
            provider: .ollamaCloud,
            modelID: "mistral-large-4",
            title: "Mistral Large 4",
            summary: "Mistral's general-purpose model in Ollama Cloud.",
            badges: ["Cloud", "large"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "oc-nemotron-3-ultra",
            provider: .ollamaCloud,
            modelID: "nemotron-3-ultra",
            title: "Nemotron 3 Ultra",
            summary: "NVIDIA's high-throughput model for difficult texts.",
            badges: ["Cloud", "large", "slower"],
            isFree: false,
            installCommand: nil
        )
    ]

    static let openRouterEntries: [CatalogEntry] = [
        CatalogEntry(
            id: "or-hy-mt2-7b",
            provider: .openRouter,
            modelID: "tencent/hy-mt2-7b",
            title: "Hy-MT2 7B",
            summary: "The same translation model in the cloud. Very cheap, no download.",
            badges: ["33 languages", "specialised", "cheap"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-hy-mt2-18b",
            provider: .openRouter,
            modelID: "tencent/hy-mt2-1.8b",
            title: "Hy-MT2 1.8B",
            summary: "The cheapest Hy-MT2 option on OpenRouter.",
            badges: ["33 languages", "cheapest"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-hy-mt2-30b",
            provider: .openRouter,
            modelID: "tencent/hy-mt2-30b-a3b",
            title: "Hy-MT2 30B-A3B",
            summary: "The highest-quality Hy-MT2 version on OpenRouter.",
            badges: ["33 languages", "MoE"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-gemma-4-31b-free",
            provider: .openRouter,
            modelID: "google/gemma-4-31b-it:free",
            title: "Gemma 4 31B",
            summary: "Google's free model with a large context. Good general translation.",
            badges: ["Free", "262K", "31B"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-gemma-4-26b-free",
            provider: .openRouter,
            modelID: "google/gemma-4-26b-a4b-it:free",
            title: "Gemma 4 26B A4B",
            summary: "A free MoE version of Gemma 4: faster than 31B.",
            badges: ["Free", "MoE", "fast"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-nemotron-ultra-free",
            provider: .openRouter,
            modelID: "nvidia/nemotron-3-ultra-550b-a55b:free",
            title: "Nemotron 3 Ultra",
            summary: "A large free NVIDIA model for difficult texts.",
            badges: ["Free", "550B", "slower"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-ling-flash-free",
            provider: .openRouter,
            modelID: "inclusionai/ling-3.2-flash:free",
            title: "Ling 3.2 Flash",
            summary: "A free fast model with a 1M-token context.",
            badges: ["Free", "1M", "fast"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-gemini-31-lite",
            provider: .openRouter,
            modelID: "google/gemini-3.1-flash-lite",
            title: "Gemini 3.1 Flash Lite",
            summary: "Cheap and very fast general translation from Google.",
            badges: ["1M", "fast", "cheap"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-qwen37-flash",
            provider: .openRouter,
            modelID: "qwen/qwen3.7-flash",
            title: "Qwen3.7 Flash",
            summary: "The cheapest fast Qwen model for bulk translation.",
            badges: ["1M", "cheapest"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "or-gpt5-mini",
            provider: .openRouter,
            modelID: "openai/gpt-5-mini",
            title: "GPT-5 Mini",
            summary: "Reliable general translation from OpenAI.",
            badges: ["400K", "universal"],
            isFree: false,
            installCommand: nil
        )
    ]

    static let groqEntries: [CatalogEntry] = [
        CatalogEntry(
            id: "groq-gpt-oss-120b",
            provider: .groq,
            modelID: "openai/gpt-oss-120b",
            title: "GPT-OSS 120B",
            summary: "OpenAI's flagship open model on Groq's fast inference.",
            badges: ["Free tier", "~500 t/s", "120B"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "groq-gpt-oss-20b",
            provider: .groq,
            modelID: "openai/gpt-oss-20b",
            title: "GPT-OSS 20B",
            summary: "The fastest option for short texts.",
            badges: ["Free tier", "~1000 t/s", "20B"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "groq-llama-33-70b",
            provider: .groq,
            modelID: "llama-3.3-70b-versatile",
            title: "Llama 3.3 70B",
            summary: "Meta's proven general-purpose model.",
            badges: ["~280 t/s", "70B"],
            isFree: false,
            installCommand: nil
        ),
        CatalogEntry(
            id: "groq-qwen38-27b",
            provider: .groq,
            modelID: "qwen/qwen3.8-27b",
            title: "Qwen3.8 27B",
            summary: "A fresh Qwen with strong translation; preview status.",
            badges: ["~450 t/s", "preview"],
            isFree: false,
            installCommand: nil
        )
    ]

    static let cerebrasEntries: [CatalogEntry] = [
        CatalogEntry(
            id: "cerebras-gpt-oss-120b",
            provider: .cerebras,
            modelID: "gpt-oss-120b",
            title: "GPT-OSS 120B",
            summary: "Around 3000 tokens per second — the fastest option for long texts.",
            badges: ["Free tier", "~3000 t/s", "120B"],
            isFree: true,
            installCommand: nil
        ),
        CatalogEntry(
            id: "cerebras-qwen38-27b",
            provider: .cerebras,
            modelID: "qwen-3.8-27b",
            title: "Qwen3.8 27B",
            summary: "A fast Qwen with good multilingual translation.",
            badges: ["Free tier", "~1850 t/s"],
            isFree: true,
            installCommand: nil
        )
    ]

    static func entries(for provider: Provider) -> [CatalogEntry] {
        switch provider {
        case .ollama, .lmStudio, .omlx, .llamaCpp:
            return localEntries
        case .ollamaCloud:
            return ollamaCloudEntries
        case .openRouter:
            return openRouterEntries
        case .groq:
            return groqEntries
        case .cerebras:
            return cerebrasEntries
        case .custom:
            return []
        }
    }

    static func installCommand(for model: String) -> String? {
        entries.first { $0.modelID == model }?.installCommand
    }
}
