import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var dropTargeted = false
    @State private var escapeMonitor: Any?

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch app.tab {
                case .translate:
                    TranslateView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView(settings: app.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar()
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(
            ZStack {
                Theme.window
                RadialGradient(
                    colors: [Theme.accent.opacity(0.10), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 900
                )
                RadialGradient(
                    colors: [Theme.accentAlt.opacity(0.06), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 800
                )
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .background(
            WindowAccessor { window in
                app.attach(window: window)
            }
            .frame(width: 0, height: 0)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else {
                    url = nil
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    app.openDocument(at: url)
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Theme.text)
                        Text(L10n.t("Drop a file to translate", language))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.chromeRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1)
                    )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .task {
            app.bootstrap()
        }
        .onChange(of: app.windowRequest) { _, _ in
            openWindow(id: "main")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            app.showWindow()
        }
        .onAppear {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53,
                      app.tab == .settings,
                      let window = NSApp.keyWindow,
                      !(window is NSPanel),
                      window.attachedSheet == nil else {
                    return event
                }
                app.tab = .translate
                return nil
            }
        }
        .onDisappear {
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
            }
            escapeMonitor = nil
        }
    }
}

struct TopBar: View {
    @EnvironmentObject private var app: AppState

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var statusColor: Color {
        switch app.backendStatus {
        case .ready: return Theme.success
        case .checking, .unknown, .modelMissing: return Theme.warning
        case .error: return Theme.danger
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                logo
                Text("DeepL-oFM")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize()
            }

            HStack(spacing: 4) {
                ForEach(AppState.Tab.allCases.filter { tab in
                    tab != .settings && (tab != .history || app.settings.keepHistory)
                }) { tab in
                    tabButton(tab)
                }
                fileMenu
            }

            Spacer(minLength: 12)

            Button {
                app.tab = .settings
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: app.settings.provider.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(app.settings.model)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Theme.editor)
                )
                .overlay(
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help(L10n.t("Connection status", language))

            Menu {
                Button(L10n.format("Translate clipboard (%@)", language, app.settings.hotKey.displayString(language))) {
                    app.translateClipboard()
                }
                Button(L10n.format("Translate selection (%@)", language, app.settings.selectionHotKey.displayString(language))) {
                    app.translateSelection()
                }
                Divider()
                Button(L10n.t("Check connection", language)) {
                    app.checkConnection()
                    app.tab = .settings
                }
                Button(L10n.t("Check for Updates…", language)) {
                    app.checkForUpdates()
                }
                if app.settings.keepHistory {
                    Button(L10n.t("History", language)) { app.tab = .history }
                }
                Button {
                    app.tab = .settings
                } label: {
                    if app.tab == .settings {
                        Label(L10n.t("Settings", language), systemImage: "checkmark")
                    } else {
                        Text(L10n.t("Settings", language))
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 56)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var fileMenu: some View {
        Menu {
            Button(L10n.t("Translate file…", language)) {
                app.openDocument()
            }
            Button(L10n.t("Save translation…", language)) {
                app.saveTranslation()
            }
            .disabled(app.document == nil || app.translatedText.isEmpty)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.t("File", language))
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(app.document == nil ? Theme.secondary : Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(app.document == nil ? Color.clear : Theme.chromeRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(app.document == nil ? Color.clear : Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L10n.t("Translate file…", language))
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x2F6BFF), Color(hex: 0x11B8C7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .help(L10n.t("DeepL-oFM — local translation", language))
    }

    private func tabButton(_ tab: AppState.Tab) -> some View {
        let active = app.tab == tab
        return Button {
            app.tab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.title(language))
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(active ? Theme.text : Theme.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Theme.chromeRaised : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(active ? Theme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

struct StatusBar: View {
    @EnvironmentObject private var app: AppState

    private var language: AppLanguage { app.settings.interfaceLanguage }

    private var statusColor: Color {
        switch app.backendStatus {
        case .ready: return Theme.success
        case .checking, .unknown, .modelMissing: return Theme.warning
        case .error: return Theme.danger
        }
    }

    private var statusText: String {
        switch app.backendStatus {
        case .ready:
            return "\(app.settings.model) · \(L10n.t(app.settings.provider.title, language))"
        case .checking:
            return L10n.t("Checking connection…", language)
        case .modelMissing:
            return L10n.format("Model “%@” not found", language, app.settings.model)
        case .error:
            return L10n.t("Server unavailable", language)
        case .unknown:
            return app.settings.model
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)

            if app.usingFallback {
                SmallChip(
                    text: L10n.t("fallback", language),
                    color: Theme.warning,
                    background: Theme.warning.opacity(0.12)
                )
            }

            Spacer(minLength: 12)

            Text(L10n.format("%@ — translate clipboard", language, app.settings.hotKey.displayString(language)))
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)

            Spacer(minLength: 12)

            if let duration = app.lastDurationMs {
                Text(L10n.seconds(Double(duration) / 1000, language))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
            if let tps = app.tokensPerSecond, tps > 0 {
                Text(L10n.speed(tps, language))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Theme.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
