import SwiftUI
import UIKit

struct IOSWriteView: View {
    @ObservedObject var settings: IOSSettings
    @StateObject private var store = WriteStore()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var sourceFocused: Bool

    private var language: AppLanguage { settings.interfaceLanguage }

    private var writingLanguage: Binding<String> {
        Binding(get: { store.languageCode }, set: { code in
            store.languageWasChosen = true
            store.languageCode = code
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("Source", language)) {
                    TextEditor(text: $store.sourceText)
                        .frame(minHeight: 120)
                        .focused($sourceFocused)
                        .accessibilityIdentifier("write-editor")
                        .onChange(of: store.sourceText) { _, _ in store.updateDetectedLanguage() }

                    LabeledContent(L10n.t("Source language", language)) {
                        IOSLanguagePicker(selection: writingLanguage, language: language, titleKey: "Source language") {
                            Text(Language.with(code: store.languageCode)?.displayName(in: language) ?? "")
                        }
                    }

                    Button(L10n.t(store.isWorking ? "Stop" : "Improve text", language)) {
                        if store.isWorking {
                            store.cancel()
                        } else {
                            sourceFocused = false
                            store.improve(primary: settings.snapshot, interfaceLanguage: language)
                        }
                    }
                    .accessibilityIdentifier("write-improve")
                    .disabled(!store.isWorking && store.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = store.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                }
                if !store.resultText.isEmpty {
                    Section(L10n.t("Result", language)) {
                        Text(store.resultText).textSelection(.enabled)
                        Button(L10n.t("Copy", language)) {
                            UIPasteboard.general.string = store.resultText
                        }
                        ShareLink(item: store.resultText) {
                            Label(L10n.t("Share", language), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("write-share")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.t("Improve text", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language)) { dismiss() }
                }
            }
            .onDisappear { store.cancel() }
        }
    }
}
