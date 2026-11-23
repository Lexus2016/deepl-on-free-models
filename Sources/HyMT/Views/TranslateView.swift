import SwiftUI

struct TranslateView: View {
    @EnvironmentObject private var app: AppState
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            LanguageBar()
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                SourcePane()
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.border).frame(width: 1)
                TargetPane(copied: $copied)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.editor)
    }
}

struct LanguageBar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                LanguagePicker(
                    selection: app.sourceLanguage,
                    includeAuto: true,
                    detected: app.detectedLanguage
                ) { language in
                    app.sourceLanguage = language
                }
                swapButton
                LanguagePicker(
                    selection: app.targetLanguage,
                    includeAuto: false,
                    detected: nil
                ) { language in
                    app.targetLanguage = language
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.chromeRaised.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderSoft, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)

            ViewThatFits(in: .horizontal) {
                StyleToneControls()
                StyleToneControls(compact: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(Theme.chrome)
    }

    private var swapButton: some View {
        Button {
            app.swapLanguages()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.chromeRaised))
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L10n.t("Swap languages (⇧⌘S)", app.settings.interfaceLanguage))
    }
}

struct LanguagePicker: View {
    @EnvironmentObject private var app: AppState
    let selection: Language
    let includeAuto: Bool
    let detected: Language?
    let onSelect: (Language) -> Void

    private var language: AppLanguage { app.settings.interfaceLanguage }

    @State private var open = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var displayName: String {
        if selection == .auto, let detected {
            return "\(Language.auto.displayName(in: language)) · \(detected.displayName(in: language))"
        }
        return selection.displayName(in: language)
    }

    private var filtered: [Language] {
        var list = includeAuto ? [Language.auto] + Language.all : Language.all
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            list = list.filter { language in
                let names = [
                    language.localName,
                    language.englishName,
                    language.displayName(in: self.language),
                    language.displayName(in: .uk),
                    language.displayName(in: .ru),
                    language.code
                ]
                return names.contains { $0.lowercased().contains(needle) }
            }
        }
        return list
    }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 7) {
                Text(displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(width: 164)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(displayName)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            popover
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                TextField(L10n.t("Search language", language), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { language in
                        Button {
                            onSelect(language)
                            open = false
                            query = ""
                        } label: {
                            HStack(spacing: 8) {
                                Text(language.displayName(in: self.language))
                                    .font(.system(size: 12.5, weight: language == selection ? .semibold : .regular))
                                    .foregroundStyle(Theme.text)
                                if language == .auto {
                                    Text(L10n.t("Auto", self.language))
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Theme.tertiary)
                                }
                                Spacer()
                                if language == selection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(language == selection ? Theme.accentSoft : Color.clear)
                        .hoverHighlight(enabled: language != selection)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 290, height: 350)
        .background(Theme.chrome)
        .preferredColorScheme(.dark)
        .onAppear { searchFocused = true }
    }
}

struct StyleToneControls: View {
    @EnvironmentObject private var app: AppState
    var compact = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        HStack(spacing: 2) {
            StyleToneSegment(
                icon: "textformat",
                title: L10n.t("Style", language),
                value: L10n.t(app.style.title, language),
                tint: Theme.accent,
                compact: compact
            ) {
                ForEach(TranslationStyle.allCases) { style in
                    Button {
                        app.style = style
                    } label: {
                        if app.style == style {
                            Label(
                                "\(L10n.t(style.title, language)) — \(L10n.t(style.detail, language))",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text("\(L10n.t(style.title, language)) — \(L10n.t(style.detail, language))")
                        }
                    }
                }
            }

            Rectangle()
                .fill(Theme.borderSoft)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            StyleToneSegment(
                icon: "waveform",
                title: L10n.t("Tone", language),
                value: L10n.t(app.tone.title, language),
                tint: Theme.accentAlt,
                compact: compact
            ) {
                ForEach(TranslationTone.allCases) { tone in
                    Button {
                        app.tone = tone
                    } label: {
                        if app.tone == tone {
                            Label(
                                "\(L10n.t(tone.title, language)) — \(L10n.t(tone.detail, language))",
                                systemImage: "checkmark"
                            )
                        } else {
                            Text("\(L10n.t(tone.title, language)) — \(L10n.t(tone.detail, language))")
                        }
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.chromeRaised.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct StyleToneSegment<Content: View>: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    let compact: Bool
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.3 : 0.16))
                    Image(systemName: icon)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 19, height: 19)

                if !compact {
                    (
                        Text(title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Theme.tertiary)
                        + Text("  ")
                        + Text(value)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Theme.text)
                    )
                    .lineLimit(1)
                    .fixedSize()
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.tertiary.opacity(hovering ? 1 : 0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Theme.chromeRaised : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .help("\(title) · \(value)")
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

struct SourcePane: View {
    @EnvironmentObject private var app: AppState
    @State private var preview = false

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var binding: Binding<String> {
        Binding(
            get: { app.sourceText },
            set: { app.sourceChanged($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Theme.editor
                if app.sourceText.isEmpty {
                    Text(L10n.t("Enter or paste text…", language))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tertiary)
                        .padding(.top, SourceTextEditor.textInset.height + 4)
                        .padding(.leading, SourceTextEditor.textInset.width)
                        .allowsHitTesting(false)
                }
                if preview {
                    MarkdownPreview(markdown: app.sourceText, textInset: SourceTextEditor.textInset) { text in
                        // Pasting while the pane is rendered replaces the text
                        // and returns to the editor, so the clipboard is never
                        // swallowed by the read-only view.
                        app.sourceChanged(text)
                        preview = false
                    }
                    .padding(.trailing, 18)
                } else {
                    SourceTextEditor(text: binding) {
                        // A rich paste arrives as Markdown: show what it looks
                        // like, the eye toggle brings the raw text back.
                        preview = true
                    }
                    .accessibilityLabel(L10n.t("Source", language))
                    .accessibilityIdentifier("source-editor")
                    .padding(.trailing, 18)
                }

                VStack {
                    HStack {
                        Spacer()
                        if !app.sourceText.isEmpty {
                            IconButton(systemName: "xmark", help: L10n.t("Clear", language)) {
                                app.clearSource()
                            }
                            .padding(8)
                        }
                    }
                    Spacer()
                }
            }

            PaneFooter(
                left: [
                    PaneAction(
                        icon: app.speaking == .source ? "stop.fill" : "speaker.wave.2",
                        help: L10n.t(
                            app.speaking == .source ? "Stop" : "Listen to the original",
                            language
                        ),
                        active: !app.sourceText.isEmpty
                    ) {
                        app.speakSource()
                    },
                    PaneAction(icon: "doc.on.clipboard", help: L10n.t("Paste from clipboard", language), active: true) {
                        app.translateClipboard()
                        if MarkdownDetector.contains(app.sourceText) { preview = true }
                    },
                    PaneAction(
                        icon: preview ? "chevron.left.forwardslash.chevron.right" : "eye",
                        help: L10n.t(preview ? "Show Markdown source" : "Show rendered Markdown", language),
                        active: !app.sourceText.isEmpty
                    ) {
                        preview.toggle()
                    }
                ],
                right: [
                    PaneAction(icon: "doc.on.doc", help: L10n.t("Copy the original", language), active: !app.sourceText.isEmpty) {
                        app.copySource()
                    }
                ],
                counter: L10n.characters(app.sourceCharacterCount, language)
            )
        }
        .background(Theme.editor)
    }
}

struct TargetPane: View {
    @EnvironmentObject private var app: AppState
    @Binding var copied: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var viewMode: Binding<ResultViewMode> {
        Binding(
            get: { app.settings.resultView },
            set: { app.settings.resultView = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Theme.editorAlt

                if app.translatedText.isEmpty {
                    VStack(spacing: 10) {
                        if app.isTranslating {
                            if app.translationTotal > 0 {
                                HStack(spacing: 8) {
                                    ProgressView(
                                        value: Double(app.translationCompleted),
                                        total: Double(max(app.translationTotal, 1))
                                    )
                                    .progressViewStyle(.linear)
                                    .tint(Theme.accent)
                                    .frame(width: 180)
                                    Text("\(app.translationPercent)%")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.secondary)
                                        .monospacedDigit()
                                }
                                Text(L10n.format(
                                    "Translating… %d of %d",
                                    language,
                                    app.translationCompleted,
                                    app.translationTotal
                                ))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.tertiary)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.t("Translating…", language))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.tertiary)
                            }
                            Button(L10n.t("Stop", language)) { app.cancelTranslation() }
                                .accessibilityIdentifier("stop-translation")
                        } else if app.errorMessage != nil {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Theme.danger.opacity(0.8))
                            Text(L10n.t("Translation failed", language))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.tertiary)
                        } else {
                            Image(systemName: "character.bubble")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Theme.tertiary)
                            Text(L10n.t("Translation will appear here", language))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.tertiary)
                            if !app.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    app.translate(force: true)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(L10n.t("Translate now", language))
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(Theme.primary)
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch app.settings.resultView {
                    case .preview:
                        MarkdownPreview(markdown: app.translatedText)
                            .padding(.trailing, 4)
                    case .text:
                        ResultText(
                            text: MarkdownRenderer.plainText(app.translatedText)
                        )
                    case .markdown:
                        ResultText(
                            text: app.translatedText
                        )
                    }
                }

                if let error = app.errorMessage {
                    VStack {
                        Spacer()
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.danger)
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.text.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button(L10n.t("Retry", language)) {
                                app.translate(force: true)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(hex: 0x2A1A1C))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1)
                        )
                        .padding(12)
                    }
                }
            }

            PaneFooter(
                left: [
                    PaneAction(
                        icon: app.speaking == .translation ? "stop.fill" : "speaker.wave.2",
                        help: L10n.t(
                            app.speaking == .translation ? "Stop" : "Listen to the translation",
                            language
                        ),
                        active: !app.translatedText.isEmpty
                    ) {
                        app.speakTranslation()
                    }
                ],
                accessory: AnyView(
                    ResultViewSwitch(selection: viewMode, language: language)
                ),
                right: [
                    PaneAction(icon: "arrow.clockwise", help: L10n.t("Translate again", language), active: !app.sourceText.isEmpty && !app.isTranslating) {
                        app.translate(force: true)
                    },
                    PaneAction(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        help: L10n.t(app.settings.resultView.copyHelpKey, language),
                        title: L10n.t("Copy", language),
                        active: !app.translatedText.isEmpty
                    ) {
                        app.copyTranslation()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copied = false }
                        }
                    }
                ],
                counter: app.translatedText.isEmpty ? "" : L10n.characters(app.translatedCharacterCount, language)
            )
        }
        .background(Theme.editorAlt)

    }
}

/// Three ways to read the result: rendered Markdown, markup-free text, and
/// the raw Markdown source. The active mode also decides what Copy writes.
struct ResultViewSwitch: View {
    @Binding var selection: ResultViewMode
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ResultViewMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(selection == mode ? Theme.text : Theme.tertiary)
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selection == mode ? Theme.chromeRaised : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(L10n.t(mode.helpKey, language))
                .accessibilityLabel(L10n.t(mode.titleKey, language))
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.editor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.borderSoft, lineWidth: 1)
        )
    }
}

/// Selectable text for the "Text only" and "Markdown" result modes.
struct ResultText: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 17))
                .lineSpacing(7)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

        }
        .scrollIndicators(.hidden)
    }
}

struct PaneAction: Identifiable {
    var id: String { help }
    let icon: String
    let help: String
    var title: String? = nil
    var active: Bool = true
    let action: () -> Void
}

struct PaneFooter: View {
    let left: [PaneAction]
    var accessory: AnyView? = nil
    let right: [PaneAction]
    let counter: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(left) { item in
                IconButton(systemName: item.icon, help: item.help, active: item.active, action: item.action)
            }
            if let accessory {
                accessory
                    .padding(.leading, 4)
            }
            Spacer()
            Text(counter)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
            ForEach(right) { item in
                if let title = item.title {
                    Button(action: item.action) {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(title)
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.chromeRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .disabled(!item.active)
                    .opacity(item.active ? 1 : 0.45)
                    .help(item.help)
                } else {
                    IconButton(systemName: item.icon, help: item.help, active: item.active, action: item.action)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.borderSoft).frame(height: 1)
        }
    }
}
