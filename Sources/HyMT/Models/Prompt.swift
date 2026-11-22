import Foundation

enum TranslationStyle: String, Codable, CaseIterable, Identifiable {
    case auto
    case literal
    case natural

    var id: String { rawValue }

    /// English key, localised at the call site.
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .literal: return "Literal"
        case .natural: return "Natural"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "The model picks a natural style"
        case .literal: return "Word for word, without free paraphrase"
        case .natural: return "Conveys meaning rather than wording"
        }
    }
}

enum TranslationTone: String, Codable, CaseIterable, Identifiable {
    case standard
    case formal
    case casual

    var id: String { rawValue }

    /// English key, localised at the call site.
    var title: String {
        switch self {
        case .standard: return "Default"
        case .formal: return "Formal"
        case .casual: return "Casual"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "No extra tone"
        case .formal: return "Formal and professional"
        case .casual: return "Casual and conversational"
        }
    }
}

/// Builds the exact instruction Hy-MT2 was trained on (see the model card).
/// The instruction and the source text travel in a single user message:
/// the model has no default system prompt.
enum PromptBuilder {

    private static let markdownClause = "Preserve Markdown syntax exactly (headings, lists, bold, italic, links, inline code); translate only the human-readable text."

    static func styleDescriptor(_ style: TranslationStyle) -> String {
        switch style {
        case .auto, .natural:
            return "natural and idiomatic, conveying the meaning rather than the wording"
        case .literal:
            return "literal, word for word"
        }
    }

    static func toneSuffix(_ tone: TranslationTone) -> String? {
        switch tone {
        case .standard: return nil
        case .formal: return "formal and professional"
        case .casual: return "casual and conversational"
        }
    }

    static func instruction(
        style: TranslationStyle,
        tone: TranslationTone,
        targetLanguage: String,
        preserveMarkdown: Bool = false
    ) -> String {
        let clause = preserveMarkdown ? " " + markdownClause : ""
        let base: String
        if style == .auto && tone == .standard {
            base = "Translate the following text into \(targetLanguage).\(clause) Note that you should only output the translated result without any additional explanation:"
        } else {
            var descriptor = styleDescriptor(style)
            if tone != .standard, let suffix = toneSuffix(tone) {
                descriptor += "; \(suffix)"
            }
            base = "Please translate the following text into \(targetLanguage).\(clause) Note that the translation style must strictly conform to [\(descriptor)]:"
        }
        return base
    }

    static func prompt(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        targetLanguage: String,
        preserveMarkdown: Bool = false
    ) -> String {
        instruction(
            style: style,
            tone: tone,
            targetLanguage: targetLanguage,
            preserveMarkdown: preserveMarkdown
        ) + "\n\n" + text
    }

    /// Headings and list items are translated on their own, so they need a
    /// stricter instruction: the regular prompt sometimes treats a lone word
    /// as part of the instruction and leaks chat-template tokens.
    static func headingInstruction(
        style: TranslationStyle,
        tone: TranslationTone,
        targetLanguage: String,
        preserveMarkdown: Bool = false
    ) -> String {
        let clause = preserveMarkdown ? " " + markdownClause : ""
        let base: String
        if style == .auto && tone == .standard {
            base = "Translate this heading into \(targetLanguage).\(clause) Output only the translated heading, without any additional explanation:"
        } else {
            var descriptor = styleDescriptor(style)
            if tone != .standard, let suffix = toneSuffix(tone) {
                descriptor += "; \(suffix)"
            }
            base = "Please translate this heading into \(targetLanguage).\(clause) Note that the translation style must strictly conform to [\(descriptor)] and output only the translated heading:"
        }
        return base
    }

    static func headingPrompt(
        text: String,
        style: TranslationStyle,
        tone: TranslationTone,
        targetLanguage: String,
        preserveMarkdown: Bool = false
    ) -> String {
        headingInstruction(
            style: style,
            tone: tone,
            targetLanguage: targetLanguage,
            preserveMarkdown: preserveMarkdown
        ) + "\n\n" + text
    }

    /// A style-free fallback for models that return an empty stream for the
    /// regular prompt. It is intentionally short and ends with a colon.
    static func plainInstruction(targetLanguage: String) -> String {
        "Translate the following text into \(targetLanguage). Output only the translated text, without any additional explanation:"
    }

    static func plainPrompt(text: String, targetLanguage: String) -> String {
        plainInstruction(targetLanguage: targetLanguage) + "\n\n" + text
    }

    static func preview(
        style: TranslationStyle,
        tone: TranslationTone,
        targetLanguage: String,
        sample: String = "Hello, world!"
    ) -> String {
        instruction(style: style, tone: tone, targetLanguage: targetLanguage) + "\n\n" + sample
    }
}
