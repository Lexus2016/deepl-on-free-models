import AppKit
import Darwin
import SwiftUI

@main
struct DeepLoFMApp: App {
    static func main() {
        let descriptor: Int32
        do {
            guard let acquired = try AppInstance.acquire() else {
                AppInstance.reopen()
                return
            }
            descriptor = acquired
        } catch {
            let alert = NSAlert()
            let language = AppLanguage.systemResolved
            alert.messageText = L10n.t("Could not open DeepL-oFM.", language)
            alert.informativeText = L10n.t("Quit DeepL-oFM if it is running, then try again.", language)
            alert.runModal()
            return
        }
        defer { close(descriptor) }

        // Builds before 14 have no process lock. Route the launch to the
        // installed copy if one of those builds is still running.
        // Попередні збірки не використовують блокування процесу.
        if AppInstance.reopenLegacyInstance() { return }
        run()
    }

    private static func run() {
        runSwiftUIApp(Self.self)
    }

    private static func runSwiftUIApp<Application: App>(_ application: Application.Type) {
        Application.main()
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup("DeepL-oFM", id: "main") {
            RootView()
                .environmentObject(app)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1220, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("Translate file…", app.settings.interfaceLanguage)) {
                    app.tab = .files
                    app.files.chooseFile(language: app.settings.interfaceLanguage)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(L10n.t("Save translation…", app.settings.interfaceLanguage)) {
                    app.files.saveOutput(language: app.settings.interfaceLanguage)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(app.files.outputURL == nil)
            }

            CommandGroup(after: .appInfo) {
                Button(L10n.t("Check for Updates…", app.settings.interfaceLanguage)) {
                    app.checkForUpdates()
                }
            }

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

                Button(L10n.t("Back to translation", app.settings.interfaceLanguage)) {
                    app.tab = .translate
                }
                .keyboardShortcut(.cancelAction)
                .disabled(app.tab != .settings)
            }
        }
    }
}

enum AppInstance {
    static let bundleID = "ua.admin.hymt"
    static let reopenRequest = Notification.Name("ua.admin.hymt.reopen-process")

    static func acquire(at url: URL? = nil) throws -> Int32? {
        let lockURL: URL
        if let url {
            lockURL = url
        } else {
            let selector = Int32(_CS_DARWIN_USER_TEMP_DIR)
            let count = confstr(selector, nil, 0)
            guard count > 0 else { throw POSIXError(.ENOENT) }
            var path = [CChar](repeating: 0, count: count)
            guard confstr(selector, &path, path.count) == count else { throw POSIXError(.EIO) }
            lockURL = path.withUnsafeBufferPointer {
                URL(fileURLWithPath: String(cString: $0.baseAddress!), isDirectory: true)
                    .appendingPathComponent("ua.admin.hymt.instance.lock")
            }
        }
        let descriptor = open(lockURL.path, O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
        let failure = errno
        close(descriptor)
        if failure == EWOULDBLOCK { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
    }

    static func reopen() {
        DistributedNotificationCenter.default().postNotificationName(
            reopenRequest, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    @MainActor
    static func reopenLegacyInstance() -> Bool {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: {
            guard $0.processIdentifier != getpid(), !$0.isTerminated,
                  let url = $0.bundleURL, let bundle = Bundle(url: url),
                  let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  let build = Int(version) else { return false }
            return build < 14
        }), let url = running.bundleURL else { return false }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: options)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let showInDock = UserDefaults.standard.object(forKey: "hymt.showInDock") as? Bool ?? true
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reopenFromDuplicate), name: AppInstance.reopenRequest, object: nil
        )
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    @objc private func reopenFromDuplicate() {
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
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
            if let window = sender.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                NotificationCenter.default.post(name: .showMainWindow, object: nil)
            }
        }
        return true
    }
}
