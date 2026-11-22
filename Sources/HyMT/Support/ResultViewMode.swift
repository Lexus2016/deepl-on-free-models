import Foundation

/// How the result pane shows the translation. The mode also decides what the
/// Copy button puts on the clipboard.
enum ResultViewMode: String, CaseIterable, Identifiable {
    case preview
    case text
    case markdown

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .preview: return "eye"
        case .text: return "text.alignleft"
        case .markdown: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var titleKey: String {
        switch self {
        case .preview: return "Preview"
        case .text: return "Text only"
        case .markdown: return "Markdown"
        }
    }

    var helpKey: String {
        switch self {
        case .preview: return "Show rendered Markdown"
        case .text: return "Show plain text"
        case .markdown: return "Show Markdown source"
        }
    }

    var copyHelpKey: String {
        switch self {
        case .preview: return "Copy translation (formatted text)"
        case .text: return "Copy translation (plain text)"
        case .markdown: return "Copy translation (Markdown)"
        }
    }
}
