import AppKit
import SwiftUI

@main
struct DeepLoFMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("DeepL-oFM") {
            RootView()
                .environmentObject(app)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1220, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu(L10n.t("Translation", app.settings.interfaceLanguage)) {
                Button(L10n.t("Translate now", app.settings.interfaceLanguage)) {
                    app.translate(force: true)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button(L10n.t("Translate clipboard", app.settings.interfaceLanguage)) {
                    app.translateClipboard()
                }

                Button(L10n.t("Translate selection", app.settings.interfaceLanguage)) {
                    app.translateSelection()
                }

                Button(L10n.t("Swap languages", app.settings.interfaceLanguage)) {
                    app.swapLanguages()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button(L10n.t("Copy translation", app.settings.interfaceLanguage)) {
                    app.copyTranslation()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button(L10n.t("Settings…", app.settings.interfaceLanguage)) {
                    app.showWindow()
                    app.tab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
