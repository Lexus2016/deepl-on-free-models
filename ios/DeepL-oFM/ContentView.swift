import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var settings = IOSSettings()
    @StateObject private var model = TranslationModel()

    @State private var sourceCode = "auto"
    @State private var mode: ResultViewMode = .preview
    @State private var showSettings = false
    @State private var copied = false

    private var language: AppLanguage { settings.interfaceLanguage }

    private var resultForCopy: String {
        switch mode {
        case .preview, .markdown:
            return model.translatedText
        case .text:
            return IOSMarkdown.plain(model.translatedText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    languageCard
                    sourceCard
                    translateButton
                    if settings.needsAPIKey,
                       settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            showSettings = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                Text(L10n.t("Add your API key in Settings.", language))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(IOSTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(IOSTheme.chrome)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    resultCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                ZStack {
                    IOSTheme.window
                    RadialGradient(
                        colors: [IOSTheme.accent.opacity(0.14), .clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 420
                    )
                }
                .ignoresSafeArea()
            )
            .navigationTitle("DeepL-oFM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(IOSTheme.chrome, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(IOSTheme.secondary)
                    }
                    .accessibilityLabel(L10n.t("Settings", language))
                }
            }
            .sheet(isPresented: $showSettings) {
                IOSSettingsView(settings: settings)
                    .preferredColorScheme(.dark)
            }
        }
        .tint(IOSTheme.accent)
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
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(IOSTheme.raised))
                    .overlay(Circle().strokeBorder(IOSTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Swap languages", language))

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
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IOSTheme.tertiary)
            }
            .foregroundStyle(IOSTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(IOSTheme.raised))
            .overlay(Capsule().strokeBorder(IOSTheme.border, lineWidth: 1))
        }
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
        if source == "auto" {
            sourceCode = target
            if let detected = model.detected, detected.code != target {
                settings.targetCode = detected.code
            }
        } else {
            sourceCode = target
            settings.targetCode = source
        }
    }

    // MARK: - Source

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("Source", language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSTheme.secondary)
                Spacer()
                if !model.sourceText.isEmpty {
                    Button {
                        model.sourceText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(IOSTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Clear", language))
                }
            }

            ZStack(alignment: .topLeading) {
                if model.sourceText.isEmpty {
                    Text(L10n.t("Enter or paste text…", language))
                        .font(.system(size: 17))
                        .foregroundStyle(IOSTheme.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.sourceText)
                    .font(.system(size: 17))
                    .foregroundStyle(IOSTheme.text)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .frame(minHeight: 150)
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
                model.translate(settings: settings)
            } label: {
                HStack(spacing: 8) {
                    if model.isTranslating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(
                        model.isTranslating
                            ? L10n.t("Translating…", language)
                            : L10n.t("Translate now", language)
                    )
                    .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(IOSTheme.gradient))
            }
            .buttonStyle(.plain)
            .disabled(
                model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.isTranslating
                || (settings.needsAPIKey && settings.apiKey.isEmpty)
            )
            .opacity(
                model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (settings.needsAPIKey && settings.apiKey.isEmpty)
                    ? 0.55 : 1
            )

            if model.isTranslating, model.total > 0 {
                ProgressView(
                    value: Double(model.completed),
                    total: Double(max(model.total, 1))
                )
                .tint(IOSTheme.accent)
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
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("Copy", language))

                    ShareLink(item: resultForCopy) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(IOSTheme.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(L10n.t("Share", language))
                }
            }

            Picker("", selection: $mode) {
                ForEach(ResultViewMode.allCases) { item in
                    Text(L10n.t(item.titleKey, language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .tint(IOSTheme.accent)

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

    @ViewBuilder
    private var resultBody: some View {
        if model.translatedText.isEmpty {
            if model.isTranslating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Translating…", language))
                        .font(.system(size: 13))
                        .foregroundStyle(IOSTheme.tertiary)
                }
            } else {
                Text(L10n.t("Translation will appear here", language))
                    .font(.system(size: 13))
                    .foregroundStyle(IOSTheme.tertiary)
            }
        } else {
            switch mode {
            case .preview:
                Text(IOSMarkdown.rendered(model.translatedText))
                    .font(.system(size: 16))
                    .foregroundStyle(IOSTheme.text)
                    .textSelection(.enabled)
            case .text:
                Text(IOSMarkdown.plain(model.translatedText))
                    .font(.system(size: 16))
                    .foregroundStyle(IOSTheme.text)
                    .textSelection(.enabled)
            case .markdown:
                Text(model.translatedText)
                    .font(.system(size: 13, design: .monospaced))
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
