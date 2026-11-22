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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Theme.border).frame(width: 1)
                TargetPane(copied: $copied)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.editor)
    }
}

struct LanguageBar: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
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

            HStack(spacing: 8) {
                Spacer()
                StyleToneControls()
            }
        }
        .padding(.horizontal, 16)
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(minWidth: 118)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
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
            } label: {
                chip(
                    text: "\(L10n.t("Style", language)) · \(L10n.t(app.style.title, language))",
                    icon: "textformat"
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
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
            } label: {
                chip(
                    text: "\(L10n.t("Tone", language)) · \(L10n.t(app.tone.title, language))",
                    icon: "waveform"
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func chip(text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.tertiary)
        }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.chromeRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
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
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
                if preview {
                    MarkdownPreview(markdown: app.sourceText)
                        .padding(.trailing, 18)
                } else {
                    SourceTextEditor(text: binding) {
                        // A rich paste arrives as Markdown: show what it looks
                        // like, the eye toggle brings the raw text back.
                        preview = true
                    }
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
                    PaneAction(icon: "speaker.wave.2", help: L10n.t("Listen to the original", language), active: !app.sourceText.isEmpty) {
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
                counter: L10n.characters(app.sourceText.count, language)
            )
        }
        .background(Theme.editor)
    }
}

struct TargetPane: View {
    @EnvironmentObject private var app: AppState
    @Binding var copied: Bool
    @State private var caretVisible = false
    @AppStorage("hymt.markdownPreview") private var markdownPreview = true

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Theme.editorAlt

                if app.translatedText.isEmpty {
                    VStack(spacing: 10) {
                        if app.isTranslating {
                            if app.translationTotal > 0 {
                                ProgressView(
                                    value: Double(app.translationCompleted),
                                    total: Double(max(app.translationTotal, 1))
                                )
                                .progressViewStyle(.linear)
                                .tint(Theme.accent)
                                .frame(width: 220)
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
                                        Capsule().fill(Theme.accentGradient)
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if markdownPreview {
                    MarkdownPreview(markdown: app.translatedText)
                        .padding(.trailing, 4)
                } else {
                    ScrollView {
                        HStack(alignment: .top, spacing: 1) {
                            Text(app.translatedText)
                                .font(.system(size: 17))
                                .lineSpacing(7)
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                            if app.isTranslating {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: 2, height: 18)
                                    .opacity(caretVisible ? 1 : 0)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                }

                if app.isTranslating, markdownPreview, !app.translatedText.isEmpty {
                    VStack {
                        ProgressView(
                            value: Double(app.translationCompleted),
                            total: Double(max(app.translationTotal, 1))
                        )
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(height: 2)
                        Spacer()
                    }
                    .allowsHitTesting(false)
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
                    PaneAction(icon: "speaker.wave.2", help: L10n.t("Listen to the translation", language), active: !app.translatedText.isEmpty) {
                        app.speakTranslation()
                    },
                    PaneAction(
                        icon: markdownPreview ? "chevron.left.forwardslash.chevron.right" : "eye",
                        help: L10n.t(markdownPreview ? "Show Markdown source" : "Show rendered Markdown", language),
                        active: !app.translatedText.isEmpty
                    ) {
                        markdownPreview.toggle()
                    }
                ],
                right: [
                    PaneAction(icon: "arrow.clockwise", help: L10n.t("Translate again", language), active: !app.sourceText.isEmpty) {
                        app.translate(force: true)
                    },
                    PaneAction(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        help: L10n.t("Copy translation (Markdown + formatting)", language),
                        title: L10n.t("Copy", language),
                        active: !app.translatedText.isEmpty
                    ) {
                        app.copyTranslation()
                        withAnimation(.easeOut(duration: 0.15)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                            withAnimation(.easeOut(duration: 0.2)) { copied = false }
                        }
                    }
                ],
                counter: app.translatedText.isEmpty ? "" : L10n.characters(app.translatedText.count, language)
            )
        }
        .background(Theme.editorAlt)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                caretVisible = true
            }
        }
    }
}

struct PaneAction: Identifiable {
    let id = UUID()
    let icon: String
    let help: String
    var title: String? = nil
    var active: Bool = true
    let action: () -> Void
}

struct PaneFooter: View {
    let left: [PaneAction]
    let right: [PaneAction]
    let counter: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(left) { item in
                IconButton(systemName: item.icon, help: item.help, active: item.active, action: item.action)
            }
            Spacer()
            Text(counter)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
                .monospacedDigit()
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
