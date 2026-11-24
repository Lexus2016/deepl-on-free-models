import SwiftUI
import UIKit

struct InlineTranslationView: View {
    let sourceText: String
    var onTranslationStarted: () -> Void = {}
    var onReplace: ((String) -> Void)?
    let configuration: IOSTranslationConfiguration?
    @StateObject private var model = TranslationModel()
    @State private var targetCode = "en"
    @State private var copied = false

    private var language: AppLanguage { configuration?.interfaceLanguage ?? .system }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(sourceText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("shared-source-text")

                if let configuration {
                    LabeledContent(L10n.t("Provider", language), value: configuration.provider.title)
                        .font(.subheadline)

                    LabeledContent(L10n.t("Target language", language)) {
                        IOSLanguagePicker(selection: $targetCode, language: language, titleKey: "Target language") {
                            Text(Language.with(code: targetCode)?.displayName(in: language) ?? "")
                        }
                    }

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
                    .accessibilityIdentifier("shared-translate")
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
                .accessibilityIdentifier("shared-translation-result")
            HStack {
                Button {
                    UIPasteboard.general.string = model.plainText
                    copied = true
                } label: {
                    Label(L10n.t("Copy", language), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("shared-copy-translation")
                if let onReplace, model.warningCount == 0 {
                    Button(L10n.t("Replace with translation", language)) {
                        onReplace(model.plainText)
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
        onTranslationStarted()
    }
}

struct IOSLanguagePicker<Caption: View>: View {
    @Binding var selection: String
    let language: AppLanguage
    let titleKey: String
    var includeAuto = false
    @ViewBuilder let caption: () -> Caption
    @State private var isOpen = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        Button {
            query = ""
            isOpen = true
        } label: {
            caption()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L10n.t(titleKey, language))
        .accessibilityValue((Language.with(code: selection) ?? .auto).displayName(in: language))
        .sheet(isPresented: $isOpen) {
            NavigationStack {
                optionsList
                    .navigationTitle(L10n.t(titleKey, language))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.t("Cancel", language)) { isOpen = false }
                        }
                    }
            }
        }
    }

    private var optionsList: some View {
        let options = Language.pickerOptions(in: language, includeAuto: includeAuto, query: query)
        return VStack(spacing: 0) {
            TextField(L10n.t("Search language", language), text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let first = options.first {
                        choose(first)
                    }
                }
                .padding()

            List {
                if options.isEmpty {
                    Text(L10n.t("Nothing found", language)).foregroundStyle(.secondary)
                }
                ForEach(options) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack {
                            Text(option.displayName(in: language))
                            Spacer()
                            if selection == option.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(selection == option.code ? .isSelected : [])
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .id(query)
        }
        .onAppear { searchFocused = true }
    }

    private func choose(_ option: Language) {
        selection = option.code
        isOpen = false
    }
}
