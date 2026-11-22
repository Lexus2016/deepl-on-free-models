import AppKit
import SwiftUI

/// Plain-text source editor with one improvement over SwiftUI's `TextEditor`:
/// pasting from a browser or a word processor converts the HTML/RTF flavour of
/// the clipboard into Markdown instead of collapsing it into plain text.
struct SourceTextEditor: NSViewRepresentable {
    @Binding var text: String

    var fontSize: CGFloat = 17
    var lineSpacing: CGFloat = 7
    var onRichPaste: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textView = SourceTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .init(hex: 0xEDEFF3)
        textView.insertionPointColor = .init(hex: 0x3B7BF6)
        textView.typingAttributes = baseAttributes
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.onRichPaste = onRichPaste
        applyBaseAttributes(to: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SourceTextView else { return }
        context.coordinator.text = $text
        textView.onRichPaste = onRichPaste

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            applyBaseAttributes(to: textView)
            let length = (text as NSString).length
            textView.setSelectedRange(
                NSRange(location: min(selection.location, length), length: 0)
            )
        }
        // The interface language can change the colour scheme while the view
        // is alive; keep the editor in sync with the theme.
        textView.textColor = .init(hex: 0xEDEFF3)
        textView.insertionPointColor = .init(hex: 0x3B7BF6)
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(hex: 0xEDEFF3),
            .paragraphStyle: paragraphStyle
        ]
    }

    private func applyBaseAttributes(to textView: NSTextView) {
        textView.typingAttributes = baseAttributes
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
        }
    }
}

/// `NSTextView` sends paste through the responder chain; overriding `paste(_:)`
/// is the one hook that sees the rich clipboard before AppKit flattens it.
final class SourceTextView: NSTextView {
    var onRichPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        let plain = NSPasteboard.general.string(forType: .string)
        if let markdown = RichTextPasteboard.markdown(), markdown != plain {
            insertText(markdown, replacementRange: selectedRange())
            // Let the paste finish before the pane swaps the editor for the
            // rendered preview.
            DispatchQueue.main.async { [weak self] in self?.onRichPaste?() }
            return
        }
        super.paste(sender)
    }
}
