import ExtensionKit
import SwiftUI
import TranslationUIProvider
import UIKit

@main
struct DeepLoFMTranslationProvider: TranslationUIProviderExtension {
    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            SelectedTranslationView(context: context)
        }
    }
}

struct SelectedTranslationView: View {
    let context: any TranslationUIProviderContext
    @StateObject private var model = TranslationModel()
    @State private var configuration: IOSTranslationConfiguration?
    @State private var targetCode = "en"
    @State private var copied = false

    private var language: AppLanguage { configuration?.interfaceLanguage ?? .system }
    private var sourceText: String { context.inputText.map { String($0.characters) } ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let configuration {
                    Text(sourceText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    LabeledContent(L10n.t("Provider", language), value: configuration.provider.title)
                        .font(.subheadline)

                    Picker(L10n.t("Target language", language), selection: $targetCode) {
                        ForEach(Language.all) { option in
                            Text(option.displayName(in: language)).tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        if model.isTranslating {
                            model.cancel()
                        } else {
                            translate(configuration)
                        }
                    } label: {
                        Label(
                            L10n.t(model.isTranslating ? "Stop" : "Translate now", language),
                            systemImage: model.isTranslating ? "stop.fill" : "translate"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasInput)

                    if model.isTranslating {
                        ProgressView(L10n.t("Translating…", language))
                    }
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !model.translatedText.isEmpty {
                        result
                    }
                } else {
                    Text(L10n.t("Open DeepL-oFM and set up your translation provider first.", language))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .onAppear {
            configuration = SystemTranslationSettings.load()
            targetCode = configuration?.target.code ?? "en"
            updateSource()
        }
        .onChange(of: sourceText) { _, _ in updateSource() }
        .onChange(of: targetCode) { _, _ in
            copied = false
            model.invalidateResult()
        }
        .onDisappear { model.cancel() }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.renderedText)
                .textSelection(.enabled)
            HStack {
                Button {
                    UIPasteboard.general.string = model.plainText
                    copied = true
                } label: {
                    Label(L10n.t("Copy", language), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if context.allowsReplacement, model.warningCount == 0 {
                    Button(L10n.t("Replace with translation", language)) {
                        context.finish(translation: AttributedString(model.plainText))
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func updateSource() {
        copied = false
        model.sourceText = sourceText
        model.sourceDidChange(language: language)
    }

    private func translate(_ configuration: IOSTranslationConfiguration) {
        var request = configuration
        request.targetCode = targetCode
        copied = false
        model.translate(configuration: request, sourceCode: "auto")
        context.expandSheet()
    }
}
