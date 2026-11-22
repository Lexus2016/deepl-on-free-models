import SwiftUI

struct IOSSettingsView: View {
    @ObservedObject var settings: IOSSettings
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage { settings.interfaceLanguage }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.t("Provider", language), selection: $settings.provider) {
                        ForEach(Provider.iosProviders) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    TextField(L10n.t("Server address", language), text: $settings.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(L10n.t("API key", language), text: $settings.apiKey)
                    TextField(L10n.t("Model", language), text: $settings.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(L10n.t("Provider", language))
                } footer: {
                    Text(L10n.t(
                        "Cloud providers need a key. A Mac on the same network can be used as a custom server.",
                        language
                    ))
                }

                Section {
                    Picker(L10n.t("Interface language", language), selection: $settings.interfaceLanguage) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.pickerTitle(current: settings.interfaceLanguage))
                                .tag(item)
                        }
                    }
                    Picker(L10n.t("Style", language), selection: $settings.style) {
                        ForEach(TranslationStyle.allCases) { style in
                            Text(L10n.t(style.title, language)).tag(style)
                        }
                    }
                    Picker(L10n.t("Tone", language), selection: $settings.tone) {
                        ForEach(TranslationTone.allCases) { tone in
                            Text(L10n.t(tone.title, language)).tag(tone)
                        }
                    }
                } header: {
                    Text(L10n.t("Translation", language))
                }

                Section {
                    HStack {
                        Text(L10n.t("Version", language))
                        Spacer()
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                            ?? "1.0.10"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/Lexus2016/deepl-on-free-models")!) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text(L10n.t("About", language))
                }
            }
            .scrollContentBackground(.hidden)
            .background(IOSTheme.window)
            .navigationTitle(L10n.t("Settings", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language)) {
                        dismiss()
                    }
                }
            }
            .tint(IOSTheme.accent)
        }
    }
}
