import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

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
            logo

            HStack(spacing: 4) {
                ForEach(AppState.Tab.allCases) { tab in
                    tabButton(tab)
                }
            }

            Spacer(minLength: 12)

            Button {
                app.tab = .settings
            } label: {
                HStack(spacing: 7) {
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
                Button(L10n.t("History", language)) { app.tab = .history }
                Button(L10n.t("Settings", language)) { app.tab = .settings }
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
        .help(L10n.t("HyMT — local translation", language))
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
