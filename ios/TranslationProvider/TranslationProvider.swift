import ExtensionKit
import SwiftUI
import TranslationUIProvider

@main
struct DeepLoFMTranslationProvider: TranslationUIProviderExtension {
    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            InlineTranslationView(
                sourceText: context.inputText.map { String($0.characters) } ?? "",
                onTranslationStarted: { context.expandSheet() },
                onReplace: replacement(in: context),
                configuration: SystemTranslationSettings.load()
            )
        }
    }

    private func replacement(in context: any TranslationUIProviderContext) -> ((String) -> Void)? {
        guard context.allowsReplacement else { return nil }
        return { context.finish(translation: AttributedString($0)) }
    }
}
