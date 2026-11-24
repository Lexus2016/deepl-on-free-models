import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareTranslationSheet(
            loadText: { [weak self] in await self?.readSharedText() ?? "" },
            close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            configuration: SystemTranslationSettings.load()
        ))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func readSharedText() async -> String {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var textParts: [String] = []
        for item in items {
            var parts: [String] = []
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) else { continue }
                let value = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier)
                let text = (value as? String)
                    ?? (value as? NSAttributedString)?.string
                    ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(text)
                }
            }
            if parts.isEmpty, let text = item.attributedContentText?.string {
                parts.append(text)
            }
            textParts.append(contentsOf: parts)
        }
        return textParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ShareTranslationSheet: View {
    let loadText: () async -> String
    let close: () -> Void
    let configuration: IOSTranslationConfiguration?
    @State private var sourceText: String?

    private var language: AppLanguage { configuration?.interfaceLanguage ?? .system }

    var body: some View {
        NavigationStack {
            Group {
                if let sourceText {
                    if sourceText.isEmpty {
                        Text(language.resolved == .uk ? "Не отримано тексту для перекладу." : "No text was shared.")
                            .foregroundStyle(.secondary)
                            .padding(16)
                    } else {
                        InlineTranslationView(sourceText: sourceText, configuration: configuration)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("DeepL-oFM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", language), action: close)
                        .accessibilityIdentifier("shared-close")
                }
            }
        }
        .task { sourceText = await loadText() }
    }
}
