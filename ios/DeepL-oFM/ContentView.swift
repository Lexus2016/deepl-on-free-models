import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var settings = IOSSettings()
    @StateObject private var model = TranslationModel()

    @AppStorage("ios.source") private var sourceCode = "auto"
    @FocusState private var sourceFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: ResultViewMode = .preview
    @State private var showSettings = false
    @State private var copied = false

    private var language: AppLanguage { settings.interfaceLanguage }

    private var resultForCopy: String {
        mode == .text ? model.plainText : model.translatedText
    }

    private var needsSetup: Bool {
        settings.needsAPIKey && settings.snapshot.apiKey.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 12) {
                        languageCard
                        sourceCard
                        translateButton
                        if needsSetup {
                            Button {
                                sourceFocused = false
                                showSettings = true
                            } label: {
                                Label(L10n.t("Add your API key in Settings.", language), systemImage: "key")
                                    .font(.subheadline)
                                    .foregroundStyle(IOSTheme.accent)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(IOSTheme.chrome, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        resultCard.id("translation-result")
                    }
                    .frame(maxWidth: 620)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.translatedText) { _, text in
                    guard !text.isEmpty else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        reader.scrollTo("translation-result", anchor: .top)
                    }
                }
            }
            .background(IOSTheme.window.ignoresSafeArea())
            .navigationTitle("DeepL-oFM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(IOSTheme.chrome, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sourceFocused = false
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(IOSTheme.text)
                    }
                    .accessibilityLabel(L10n.t("Settings", language))
                    .accessibilityIdentifier("translation-settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                IOSSettingsView(settings: settings)
            }
        }
        .tint(IOSTheme.accent)
        .onChange(of: model.sourceText) { _, _ in model.sourceDidChange(language: language) }
        .onChange(of: settings.targetCode) { _, _ in model.invalidateResult() }
        .onChange(of: sourceCode) { _, _ in model.invalidateResult() }
        .onChange(of: settings.snapshot) { _, _ in model.invalidateResult() }
        .onChange(of: settings.style) { _, _ in model.invalidateResult() }
        .onChange(of: settings.tone) { _, _ in model.invalidateResult() }
    }

    // MARK: - Language bar

    private var languageCard: some View {
        HStack(spacing: 8) {
            languageMenu(selection: $sourceCode, includeAuto: true, detected: model.detected)

            Button {
                swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IOSTheme.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(IOSTheme.raised))
                    .overlay(Circle().strokeBorder(IOSTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Swap languages", language))
            .disabled(sourceCode == "auto" && model.detected == nil)

            languageMenu(
                selection: $settings.targetCode,
                includeAuto: false,
                detected: nil
            )
        }
    }

    private func languageMenu(
        selection: Binding<String>,
        includeAuto: Bool,
        detected: Language?
    ) -> some View {
        Menu {
            if includeAuto {
                Button {
                    selection.wrappedValue = "auto"
                } label: {
                    if selection.wrappedValue == "auto" {
                        Label(L10n.t("Auto-detect", language), systemImage: "checkmark")
                    } else {
                        Text(L10n.t("Auto-detect", language))
                    }
                }
                Divider()
            }
            ForEach(Language.all) { item in
                Button {
                    selection.wrappedValue = item.code
                } label: {
                    if selection.wrappedValue == item.code {
                        Label(item.displayName(in: language), systemImage: "checkmark")
                    } else {
                        Text(item.displayName(in: language))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(for: selection.wrappedValue, detected: detected))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IOSTheme.tertiary)
            }
            .foregroundStyle(IOSTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(IOSTheme.raised))
            .overlay(Capsule().strokeBorder(IOSTheme.border, lineWidth: 1))
        }
        .accessibilityLabel(L10n.t(includeAuto ? "Source language" : "Target language", language))
        .accessibilityValue(label(for: selection.wrappedValue, detected: detected))
    }

    private func label(for code: String, detected: Language?) -> String {
        if code == "auto" {
            let auto = L10n.t("Auto-detect", language)
            guard let detected else { return auto }
            return "\(auto) · \(detected.displayName(in: language))"
        }
        return (Language.with(code: code) ?? .auto).displayName(in: language)
    }

    private func swapLanguages() {
        let source = sourceCode
        let target = settings.targetCode
        guard let original = source == "auto" ? model.detected : Language.with(code: source),
              original.code != target else { return }
        let previousResult = model.translatedText
        sourceCode = target
        settings.targetCode = original.code
        if !previousResult.isEmpty { model.sourceText = previousResult }
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Source", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSTheme.secondary)
                Spacer()
                if sourceFocused {
                    Button {
                        sourceFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundStyle(IOSTheme.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Done", language))
                }
                if model.sourceText.isEmpty {
                    PasteButton(payloadType: String.self) { items in
                        if let text = items.first { model.sourceText = text }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(L10n.t("Paste from clipboard", language))
                } else {
                    Button {
                        model.sourceText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(IOSTheme.tertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Clear", language))
                }
            }

            ZStack(alignment: .topLeading) {
                if model.sourceText.isEmpty {
                    Text(L10n.t("Enter or paste text…", language))
                        .font(.body)
                        .foregroundStyle(IOSTheme.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $model.sourceText)
                    .font(.body)
                    .foregroundStyle(IOSTheme.text)
                    .scrollContentBackground(.hidden)
                    .focused($sourceFocused)
                    .accessibilityLabel(L10n.t("Source", language))
                    .accessibilityIdentifier("source-editor")
                    .frame(minHeight: 146)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(IOSTheme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(IOSTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Translate

    private var translateButton: some View {
        VStack(spacing: 8) {
            Button {
                if model.isTranslating {
                    model.cancel()
                } else {
                    sourceFocused = false
                    model.translate(settings: settings, sourceCode: sourceCode)
                }
            } label: {
                Label(
                    L10n.t(model.isTranslating ? "Stop" : "Translate now", language),
                    systemImage: model.isTranslating ? "stop.fill" : "arrow.right"
                )
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(model.isTranslating ? IOSTheme.raised : IOSTheme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.isTranslating && (!model.hasInput || needsSetup))
            .opacity(model.isTranslating || (model.hasInput && !needsSetup) ? 1 : 0.55)
            .accessibilityIdentifier("start-or-stop-translation")

            if model.isTranslating {
                if model.total > 0 {
                    ProgressView(value: Double(model.completed), total: Double(model.total)) {
                        Text(L10n.t("Translating…", language)).font(.footnote)
                    } currentValueLabel: {
                        Text((Double(model.completed) / Double(model.total)).formatted(.percent.precision(.fractionLength(0))))
                            .font(.footnote.monospacedDigit())
                    }
                    .tint(IOSTheme.accent)
                } else {
                    ProgressView(L10n.t("Translating…", language))
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.t("Result", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSTheme.secondary)

                Spacer()

                if !model.translatedText.isEmpty {
                    Button {
                        copyResult()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? IOSTheme.accentAlt : IOSTheme.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Copy", language))

                    ShareLink(item: resultForCopy) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(IOSTheme.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.t("Share", language))
                }
            }

            if !model.translatedText.isEmpty {
                ViewThatFits {
                    resultModePicker.pickerStyle(.segmented)
                    resultModePicker.pickerStyle(.menu)
                }
                .tint(IOSTheme.accent)
            }

            resultBody
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(IOSTheme.raised.opacity(0.6))
                )

            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(IOSTheme.warning)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(IOSTheme.text.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: 0x2A1A1C))
                )
            }

            HStack(spacing: 10) {
                if let ms = model.durationMs {
                    Text(L10n.seconds(Double(ms) / 1000, language))
                    if let speed = model.tokensPerSecond, speed > 0 {
                        Text(L10n.speed(speed, language))
                    }
                    Text(L10n.characters(model.translatedText.count, language))
                }
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(IOSTheme.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(IOSTheme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(IOSTheme.border, lineWidth: 1)
        )
    }

    private var resultModePicker: some View {
        Picker(L10n.t("Result", language), selection: $mode) {
            ForEach(ResultViewMode.allCases) { item in
                Text(L10n.t(item.titleKey, language)).tag(item)
            }
        }
        .accessibilityIdentifier("result-mode")
    }

    @ViewBuilder
    private var resultBody: some View {
        if model.translatedText.isEmpty {
            if !model.isTranslating && model.errorMessage == nil {
                Text(L10n.t("Translation will appear here", language))
                    .font(.subheadline)
                    .foregroundStyle(IOSTheme.tertiary)
            }
        } else {
            switch mode {
            case .preview:
                Text(model.renderedText).font(.body)
                    .foregroundStyle(IOSTheme.text)
                    .textSelection(.enabled)
            case .text:
                Text(model.plainText).font(.body)
                    .foregroundStyle(IOSTheme.text)
                    .textSelection(.enabled)
            case .markdown:
                Text(model.translatedText).font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(IOSTheme.text)
                    .textSelection(.enabled)
            }
        }
    }

    private func copyResult() {
        UIPasteboard.general.string = resultForCopy
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}
