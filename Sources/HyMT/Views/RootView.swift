import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var escapeMonitor: Any?

    private var language: AppLanguage { app.settings.interfaceLanguage }

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Group {
                switch app.tab {
                case .translate:
                    TranslateView()
                case .write:
                    WriteView(store: app.write)
                case .files:
                    FilesView(store: app.files)
                case .history:
                    HistoryView(history: app.history)
                case .settings:
                    SettingsView(settings: app.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            StatusBar()
        }
        .frame(minWidth: 880, minHeight: 580)
        .background(Theme.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .background(
            WindowAccessor { window in
                app.attach(window: window)
            }
            .frame(width: 0, height: 0)
        )
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
            .accessibilityLabel(L10n.t("Connection status", language))
            .accessibilityValue(app.settings.model)
            .accessibilityIdentifier("connection-settings")

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
            .accessibilityLabel(L10n.t("More actions", language))
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.primary)
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
            Image(systemName: app.usingFallback ? "arrow.triangle.swap" : "circle.fill")
                .font(.system(size: app.usingFallback ? 10 : 6))
                .foregroundStyle(app.usingFallback ? Theme.warning : statusColor)
                .accessibilityHidden(true)
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
