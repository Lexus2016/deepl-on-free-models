import Foundation
import SwiftUI

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

    static func instruction(style: TranslationStyle, tone: TranslationTone, targetLanguage: String) -> String {
        if style == .auto && tone == .standard {
            return "Translate the following text into \(targetLanguage). Note that you should only output the translated result without any additional explanation:"
        }

        var descriptor = styleDescriptor(style)
        if tone != .standard, let suffix = toneSuffix(tone) {
            descriptor += "; \(suffix)"
        }
        return "Please translate the following text into \(targetLanguage). Note that the translation style must strictly conform to [\(descriptor)]:"
    }

    static func prompt(text: String, style: TranslationStyle, tone: TranslationTone, targetLanguage: String) -> String {
        instruction(style: style, tone: tone, targetLanguage: targetLanguage) + "\n\n" + text
    }

    /// Headings and list items are translated on their own, so they need a
    /// stricter instruction: the regular prompt sometimes treats a lone word
    /// as part of the instruction and leaks chat-template tokens.
    static func headingInstruction(style: TranslationStyle, tone: TranslationTone, targetLanguage: String) -> String {
        if style == .auto && tone == .standard {
            return "Translate this heading into \(targetLanguage). Output only the translated heading, without any additional explanation:"
        }
        var descriptor = styleDescriptor(style)
        if tone != .standard, let suffix = toneSuffix(tone) {
            descriptor += "; \(suffix)"
        }
        return "Please translate this heading into \(targetLanguage). Note that the translation style must strictly conform to [\(descriptor)] and output only the translated heading:"
    }

    static func headingPrompt(text: String, style: TranslationStyle, tone: TranslationTone, targetLanguage: String) -> String {
        headingInstruction(style: style, tone: tone, targetLanguage: targetLanguage) + "\n\n" + text
    }

    static func preview(style: TranslationStyle, tone: TranslationTone, targetLanguage: String) -> String {
        instruction(style: style, tone: tone, targetLanguage: targetLanguage) + "\n\n{текст для перекладу}"
    }
}
