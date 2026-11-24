import AppKit

/// Receives the selection from the Services pasteboard.
/// Отримує виділений текст через окремий буфер системної служби.
@MainActor
final class SelectionTranslationService: NSObject {
    private let translate: (String) -> Void

    init(translate: @escaping (String) -> Void) {
        self.translate = translate
    }

    @objc(translateSelection:userData:error:)
    func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let text = RichTextPasteboard.markdown(from: pasteboard)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            error.pointee = L10n.t("No selectable text found.", .system) as NSString
            return
        }
        translate(text)
    }
}
