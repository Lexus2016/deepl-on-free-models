import AppKit
import Foundation
import SwiftUI

/// Renders Markdown into an attributed string styled for the app's dark
/// interface. Uses the system Markdown parser for structure, then maps
/// headings, lists, quotes, code and links to fonts and paragraph styles.
enum MarkdownRenderer {

    static func render(_ markdown: String, fontSize: CGFloat = 17) -> NSAttributedString {
        let source = markdown.trimmingCharacters(in: .newlines)
        guard !source.isEmpty else { return NSAttributedString() }
        guard let parsed = try? AttributedString(markdown: source) else {
            return NSAttributedString(
                string: source,
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor(hex: 0xEDEFF3)
                ]
            )
        }

        var blocks: [Block] = []
        for run in parsed.runs {
            let intent = run.presentationIntent
            let key = intent?.components.first?.identity ?? -1
            if blocks.last?.key != key {
                blocks.append(Block(intent: intent))
            }
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }
            let inline = run.inlinePresentationIntent
            blocks[blocks.count - 1].spans.append(
                Span(
                    text: text,
                    bold: inline?.contains(.stronglyEmphasized) ?? false,
                    italic: inline?.contains(.emphasized) ?? false,
                    code: inline?.contains(.code) ?? false,
                    link: run.link
                )
            )
        }

        return assemble(blocks, fontSize: fontSize)
    }

    // MARK: - Model

    private struct Span {
        let text: String
        let bold: Bool
        let italic: Bool
        let code: Bool
        let link: URL?
    }

    private struct Block {
        let key: Int
        let headingLevel: Int?
        let listOrdinal: Int?
        let listOrdered: Bool
        let listLevel: Int
        let quote: Bool
        let code: Bool
        var spans: [Span] = []

        init(intent: PresentationIntent?) {
            var heading: Int?
            var ordinal: Int?
            var ordered: Bool?
            var lists = 0
            var quote = false
            var code = false

            for component in intent?.components ?? [] {
                switch component.kind {
                case .header(let level):
                    heading = level
                case .listItem(let value):
                    ordinal = value
                case .orderedList:
                    if ordered == nil { ordered = true }
                    lists += 1
                case .unorderedList:
                    if ordered == nil { ordered = false }
                    lists += 1
                case .blockQuote:
                    quote = true
                case .codeBlock:
                    code = true
                default:
                    break
                }
            }

            self.key = intent?.components.first?.identity ?? -1
            self.headingLevel = heading
            self.listOrdinal = ordinal
            self.listOrdered = ordered ?? false
            self.listLevel = max(0, lists - 1)
            self.quote = quote
            self.code = code
        }
    }

    // MARK: - Assembly

    private static func assemble(_ blocks: [Block], fontSize: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            let start = output.length

            if let ordinal = block.listOrdinal {
                let marker = block.listOrdered ? "\(ordinal).\t" : "•\t"
                output.append(NSAttributedString(
                    string: marker,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: fontSize),
                        .foregroundColor: NSColor(hex: 0x9BA1AC)
                    ]
                ))
            }

            for span in block.spans {
                output.append(styled(span, in: block, fontSize: fontSize))
            }

            if block.code {
                while output.length > start, output.string.hasSuffix("\n") {
                    output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
                }
            }

            guard output.length > start else { continue }
            if index < blocks.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }

            output.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(for: block, fontSize: fontSize),
                range: NSRange(location: start, length: output.length - start)
            )
        }

        return output
    }

    private static func styled(_ span: Span, in block: Block, fontSize: CGFloat) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [:]
        var text = span.text

        if block.code {
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: fontSize * 0.8, weight: .regular)
            attributes[.foregroundColor] = NSColor(hex: 0xD7DCE6)
            attributes[.backgroundColor] = NSColor(hex: 0x1E222B)
        } else {
            let size = block.headingLevel.map { headingSize(level: $0, base: fontSize) } ?? fontSize
            var weight: NSFont.Weight = block.headingLevel == nil
                ? .regular
                : (size >= fontSize * 1.2 ? .bold : .semibold)
            if span.bold { weight = .bold }

            var font = NSFont.systemFont(ofSize: size, weight: weight)
            if span.italic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if span.code {
                font = NSFont.monospacedSystemFont(
                    ofSize: size * 0.86,
                    weight: span.bold ? .semibold : .regular
                )
                attributes[.backgroundColor] = NSColor(hex: 0x20242D)
            }
            attributes[.font] = font

            if block.quote {
                attributes[.foregroundColor] = NSColor(hex: 0x9BA1AC)
            } else {
                attributes[.foregroundColor] = NSColor(hex: 0xEDEFF3)
            }

            if let link = span.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor(hex: 0x5B95FF)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }

        if !block.code, text.contains("\n") {
            text = text.replacingOccurrences(of: "\n", with: " ")
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func headingSize(level: Int, base: CGFloat) -> CGFloat {
        switch level {
        case 1: return base * 1.45
        case 2: return base * 1.22
        case 3: return base * 1.08
        default: return base
        }
    }

    private static func paragraphStyle(for block: Block, fontSize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = block.code ? 3 : 7

        if block.listOrdinal != nil {
            let indent = 2 + CGFloat(block.listLevel) * 18
            style.firstLineHeadIndent = indent
            style.headIndent = indent + 20
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 20)]
            style.paragraphSpacing = 5
        } else if block.quote {
            style.firstLineHeadIndent = 14
            style.headIndent = 14
            style.paragraphSpacing = 11
        } else if block.code {
            style.firstLineHeadIndent = 12
            style.headIndent = 12
            style.paragraphSpacing = 13
            style.paragraphSpacingBefore = 4
        } else if block.headingLevel != nil {
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 10
        } else {
            style.paragraphSpacing = 13
        }

        return style
    }
}

/// Read-only rendered Markdown, selectable and scrollable. The source string
/// stays Markdown for editing and copying; this view is only what the eye sees.
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    var fontSize: CGFloat = 17

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textView = PreviewTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(hex: 0x5B95FF),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.render(markdown: markdown, fontSize: fontSize, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.scheduleRender(
            markdown: markdown,
            fontSize: fontSize,
            scrollView: scrollView
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        private var lastMarkdown: String?
        private var lastFontSize: CGFloat?
        private var pending: DispatchWorkItem?

        func scheduleRender(markdown: String, fontSize: CGFloat, scrollView: NSScrollView) {
            guard markdown != lastMarkdown || fontSize != lastFontSize else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.render(markdown: markdown, fontSize: fontSize, scrollView: scrollView)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func render(markdown: String, fontSize: CGFloat, scrollView: NSScrollView) {
            guard markdown != lastMarkdown || fontSize != lastFontSize else { return }
            lastMarkdown = markdown
            lastFontSize = fontSize
            guard let textView, let storage = textView.textStorage else { return }

            let origin = scrollView.contentView.bounds.origin
            storage.setAttributedString(MarkdownRenderer.render(markdown, fontSize: fontSize))
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

/// Links are opened by the coordinator; the text view itself only needs to
/// stop AppKit from beeping when a link is clicked in a read-only view.
final class PreviewTextView: NSTextView {
    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let delegate else { return }
        _ = delegate.textView?(self, clickedOnLink: link, at: charIndex)
    }
}
