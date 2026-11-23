"""Main window shell: header, tab navigation, pages, menu and status bar.

Counterpart of ``Sources/HyMT/Views/RootView.swift`` plus the menu wiring from
``DeepL-oFMApp.swift``.
"""

from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import QSize, Qt, QTimer, QUrl
from PySide6.QtGui import QAction, QActionGroup, QDesktopServices, QKeySequence
from PySide6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QStackedWidget,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from .. import APP_NAME, __version__
from ..i18n import t
from . import icons
from .theme import Theme

log = logging.getLogger(__name__)

GITHUB_URL = "https://github.com/Lexus2016/deepl-on-free-models"


class _TabButton(QToolButton):
    """Header tab: icon and label on one row, soft accent pill when active."""

    def __init__(self, icon_name: str, label: str, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._icon_name = icon_name
        self._active = False
        self.setCheckable(True)
        self.setAutoExclusive(True)
        self.setToolButtonStyle(Qt.ToolButtonTextBesideIcon)
        self.setIconSize(QSize(17, 17))
        self.setCursor(Qt.PointingHandCursor)
        self.setObjectName("tabButton")
        self.setMinimumHeight(34)
        self.set_label(label)
        Theme.changed.connect(lambda *_: self._apply_style())

    def set_label(self, label: str) -> None:
        self.setText(label)
        self._apply_style()

    def set_active(self, active: bool) -> None:
        self._active = active
        self.setChecked(active)
        self._apply_style()

    def _apply_style(self) -> None:
        palette = Theme.palette()
        background = palette.accent_soft if self._active else "transparent"
        colour = palette.accent if self._active else palette.muted
        weight = 600 if self._active else 500
        self.setIcon(icons.icon(self._icon_name, colour, 17))
        self.setStyleSheet(
            f"""
            QToolButton {{
                background: {background};
                color: {colour};
                border: none;
                border-radius: 8px;
                padding: 6px 14px;
                font-size: 13px;
                font-weight: {weight};
            }}
            QToolButton:hover {{
                background: {palette.card_hover};
                color: {palette.text};
            }}
            """
        )


class MainWindow(QMainWindow):
    """Shell that hosts the four tabs and the settings dialogs."""

    def __init__(self, controller: Any, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.controller = controller
        self.tray = None
        self._settings_dialog = None
        self._catalog_dialog = None

        self.setWindowTitle(APP_NAME)
        self.resize(1180, 780)
        self.setMinimumSize(960, 620)
        self.setWindowIcon(icons.icon("translate", size=128))

        self._build_ui()
        self._build_menu()
        self._connect()
        self.retranslate_ui()
        self._sync_tab(self.controller.tab)

    # ------------------------------------------------------------------- ui
    def _build_ui(self) -> None:
        central = QWidget(self)
        central.setObjectName("root")
        outer = QVBoxLayout(central)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        outer.addWidget(self._build_header())

        self.stack = QStackedWidget(central)
        outer.addWidget(self.stack, 1)

        self.pages: dict[str, QWidget] = {}
        self._add_page("translate", self._make_view("translate", "TranslateView"))
        self._add_page("files", self._make_view("files", "FilesView"))
        self._add_page("write", self._make_view("write", "WriteView"))
        self._add_page("history", self._make_view("history", "HistoryView"))

        outer.addWidget(self._build_status_bar())
        self.setCentralWidget(central)

    def _make_view(self, key: str, class_name: str) -> QWidget:
        """Instantiate a tab view, degrading to a placeholder if it is not ready."""
        try:
            from importlib import import_module

            module = import_module(f"deepl_ofm.ui.{key}_view")
            view_class = getattr(module, class_name)
            return view_class(self.controller)
        except Exception:  # noqa: BLE001 - a broken tab must not kill the window
            log.exception("could not create %s", class_name)
            placeholder = QWidget()
            layout = QVBoxLayout(placeholder)
            message = QLabel(t("%s is unavailable.") % key.capitalize())
            message.setAlignment(Qt.AlignCenter)
            layout.addWidget(message)
            return placeholder

    def _add_page(self, key: str, widget: QWidget) -> None:
        self.pages[key] = widget
        self.stack.addWidget(widget)

    def _build_header(self) -> QWidget:
        header = QWidget()
        header.setObjectName("header")
        header.setFixedHeight(60)
        header.setStyleSheet(
            f"QWidget#header {{ background: {Theme.palette().panel}; "
            f"border-bottom: 1px solid {Theme.palette().border}; }}"
        )
        layout = QHBoxLayout(header)
        layout.setContentsMargins(20, 8, 16, 8)
        layout.setSpacing(10)

        logo = QLabel()
        logo.setPixmap(icons.pixmap("translate", Theme.palette().accent, 26))
        logo.setFixedSize(30, 30)
        layout.addWidget(logo)

        self.title = QLabel(APP_NAME)
        self.title.setStyleSheet(
            f"color: {Theme.palette().text}; font-size: 15px; font-weight: 600;"
        )
        layout.addWidget(self.title)
        layout.addSpacing(28)

        self.tab_buttons: dict[str, _TabButton] = {}
        for key in ("translate", "files", "write", "history"):
            button = _TabButton("translate" if key == "translate" else key, key.capitalize())
            button.clicked.connect(lambda _checked=False, name=key: self._on_tab_clicked(name))
            self.tab_buttons[key] = button
            layout.addWidget(button)

        layout.addStretch(1)

        self.settings_button = QToolButton()
        self.settings_button.setObjectName("iconButton")
        self.settings_button.setToolTip(t("Settings"))
        self.settings_button.setCursor(Qt.PointingHandCursor)
        self.settings_button.setAutoRaise(True)
        self.settings_button.clicked.connect(self.open_settings)
        layout.addWidget(self.settings_button)
        return header

    def _build_status_bar(self) -> QWidget:
        bar = QWidget()
        bar.setObjectName("statusBar")
        bar.setFixedHeight(32)
        bar.setStyleSheet(
            f"QWidget#statusBar {{ background: {Theme.palette().panel}; "
            f"border-top: 1px solid {Theme.palette().border}; }}"
        )
        layout = QHBoxLayout(bar)
        layout.setContentsMargins(20, 0, 16, 0)
        layout.setSpacing(8)

        self.status_dot = QLabel("●")
        self.status_dot.setObjectName("statusDot")
        layout.addWidget(self.status_dot)

        self.status_label = QLabel("")
        self.status_label.setObjectName("statusText")
        layout.addWidget(self.status_label)

        layout.addStretch(1)

        self.metrics_label = QLabel("")
        self.metrics_label.setObjectName("statusMetrics")
        layout.addWidget(self.metrics_label)

        self.speak_stop = QPushButton("")
        self.speak_stop.setObjectName("linkButton")
        self.speak_stop.setCursor(Qt.PointingHandCursor)
        self.speak_stop.setFlat(True)
        self.speak_stop.clicked.connect(self.controller.stop_speaking)
        self.speak_stop.hide()
        layout.addWidget(self.speak_stop)

        self.error_label = QLabel("")
        self.error_label.setObjectName("statusError")
        self.error_label.hide()
        layout.addWidget(self.error_label)
        return bar

    def _build_menu(self) -> None:
        menu = self.menuBar()

        self.file_menu = menu.addMenu(t("File"))
        self.action_new = QAction(t("New translation"), self)
        self.action_new.setShortcut(QKeySequence.New)
        self.action_new.triggered.connect(self._new_translation)
        self.file_menu.addAction(self.action_new)

        self.action_open = QAction(t("Open file…"), self)
        self.action_open.setShortcut(QKeySequence.Open)
        self.action_open.triggered.connect(self._open_file)
        self.file_menu.addAction(self.action_open)
        self.file_menu.addSeparator()

        self.action_quit = QAction(t("Quit DeepL-oFM"), self)
        self.action_quit.setShortcut(QKeySequence.Quit)
        self.action_quit.triggered.connect(QApplication.instance().quit)
        self.file_menu.addAction(self.action_quit)

        self.edit_menu = menu.addMenu(t("Edit"))
        self.action_copy_translation = QAction(t("Copy translation"), self)
        self.action_copy_translation.setShortcut(QKeySequence("Ctrl+Shift+C"))
        self.action_copy_translation.triggered.connect(self.controller.copy_translation)
        self.edit_menu.addAction(self.action_copy_translation)

        self.action_copy_source = QAction(t("Copy source"), self)
        self.action_copy_source.triggered.connect(self.controller.copy_source)
        self.edit_menu.addAction(self.action_copy_source)

        self.action_paste = QAction(t("Paste"), self)
        self.action_paste.setShortcut(QKeySequence.Paste)
        self.action_paste.triggered.connect(self._paste_into_source)
        self.edit_menu.addAction(self.action_paste)

        self.action_clear = QAction(t("Clear"), self)
        self.action_clear.triggered.connect(self.controller.clear_source)
        self.edit_menu.addAction(self.action_clear)

        self.view_menu = menu.addMenu(t("View"))
        group = QActionGroup(self)
        group.setExclusive(True)
        self.view_actions: dict[str, QAction] = {}
        for mode, label in (
            ("preview", t("Preview")),
            ("text", t("Plain text")),
            ("markdown", t("Markdown")),
        ):
            action = QAction(label, self, checkable=True)
            action.triggered.connect(lambda _checked=False, value=mode: self.controller.set_result_view(value))
            group.addAction(action)
            self.view_menu.addAction(action)
            self.view_actions[mode] = action
        self.view_menu.addSeparator()
        self.action_hotkeys = QAction(t("Translate clipboard"), self)
        self.action_hotkeys.setShortcut(QKeySequence("Ctrl+Alt+T"))
        self.action_hotkeys.triggered.connect(self.controller.translate_clipboard)
        self.view_menu.addAction(self.action_hotkeys)

        self.settings_menu = menu.addMenu(t("Settings"))
        self.action_settings = QAction(t("Settings…"), self)
        self.action_settings.setShortcut(QKeySequence("Ctrl+,"))
        self.action_settings.triggered.connect(self.open_settings)
        self.settings_menu.addAction(self.action_settings)

        self.action_catalog = QAction(t("Model catalog…"), self)
        self.action_catalog.triggered.connect(self.open_catalog)
        self.settings_menu.addAction(self.action_catalog)

        self.language_menu = self.settings_menu.addMenu(t("Interface language"))

        self.help_menu = menu.addMenu(t("Help"))
        self.action_about = QAction(t("About DeepL-oFM"), self)
        self.action_about.triggered.connect(self._show_about)
        self.help_menu.addAction(self.action_about)
        self.action_site = QAction(t("Website"), self)
        self.action_site.triggered.connect(lambda: QDesktopServices.openUrl(QUrl(GITHUB_URL)))
        self.help_menu.addAction(self.action_site)

    # -------------------------------------------------------------- signals
    def _connect(self) -> None:
        c = self.controller
        c.tabChanged.connect(self._sync_tab)
        c.backendStatusChanged.connect(self._sync_status)
        c.probeMessageChanged.connect(self._sync_status)
        c.errorRaised.connect(self._show_error)
        c.copyFeedback.connect(self._show_feedback)
        c.interfaceLanguageChanged.connect(self._on_language_changed)
        c.metricsChanged.connect(self._sync_metrics)
        c.resultViewChanged.connect(self._sync_view_mode)
        c.speakingChanged.connect(self._sync_speaking)
        c.settingsChanged.connect(self._sync_settings_actions)

    # ------------------------------------------------------------- commands
    def present(self) -> None:
        self.showNormal()
        self.raise_()
        self.activateWindow()

    def select_tab(self, key: str) -> None:
        self._on_tab_clicked(key)

    def set_source_text(self, text: str, translate: bool = False) -> None:
        view = self.pages.get("translate")
        if hasattr(view, "set_source_text"):
            view.set_source_text(text)
        else:
            self.controller.set_source_text(text)
        if translate:
            self.controller.translate(force=True)

    def open_settings(self) -> None:
        try:
            from .settings_view import SettingsView

            if self._settings_dialog is None:
                self._settings_dialog = SettingsView(self.controller, self)
            self._settings_dialog.exec()
        except Exception:  # noqa: BLE001
            log.exception("settings dialog failed")
            self._show_error(t("Settings are unavailable."))

    def open_catalog(self) -> None:
        try:
            from .catalog_view import CatalogView

            if self._catalog_dialog is None:
                self._catalog_dialog = CatalogView(self.controller, self)
            self._catalog_dialog.exec()
        except Exception:  # noqa: BLE001
            log.exception("catalog dialog failed")

    # -------------------------------------------------------------- internal
    def _on_tab_clicked(self, key: str) -> None:
        self.controller.set_tab(key)
        self._sync_tab(key)

    def _sync_tab(self, key: str) -> None:
        if key not in self.pages:
            return
        self.stack.setCurrentWidget(self.pages[key])
        for name, button in self.tab_buttons.items():
            button.set_active(name == key)
            button.setChecked(name == key)

    def _new_translation(self) -> None:
        self.controller.clear_source()
        self._sync_tab("translate")
        self.controller.set_tab("translate")
        view = self.pages.get("translate")
        if hasattr(view, "focus_source"):
            view.focus_source()

    def _open_file(self) -> None:
        self._sync_tab("files")
        self.controller.set_tab("files")
        view = self.pages.get("files")
        if hasattr(view, "pick_file"):
            QTimer.singleShot(0, view.pick_file)

    def _paste_into_source(self) -> None:
        text = QApplication.clipboard().text()
        if not text.strip():
            return
        view = self.pages.get("translate")
        if hasattr(view, "paste_text"):
            view.paste_text(text)
        else:
            self.controller.set_source_text(text)

    def _sync_status(self, _value: str = "") -> None:
        status = self.controller.backend_status
        colors = {
            "connected": Theme.palette().success,
            "failed": Theme.palette().danger,
            "checking": Theme.palette().warning,
            "warming": Theme.palette().warning,
            "unknown": Theme.palette().faint,
        }
        self.status_dot.setStyleSheet(f"color: {colors.get(status, Theme.palette().faint)};")
        label = {
            "connected": t("Connected"),
            "failed": self.controller.probe_message or t("Server unavailable"),
            "checking": t("Connecting…"),
            "warming": t("Loading the translator…"),
            "unknown": t("Not connected"),
        }.get(status, status)
        settings = self.controller.settings
        model = settings.snapshot().model or t("No model")
        self.status_label.setText(f"{label}  ·  {settings.provider.title}  ·  {model}")

    def _sync_metrics(self) -> None:
        parts = []
        if self.controller.tokens_per_second:
            parts.append(f"{self.controller.tokens_per_second:.1f} t/s")
        if self.controller.last_duration_ms:
            parts.append(f"{self.controller.last_duration_ms / 1000:.1f}s")
        if self.controller.using_fallback:
            parts.append(t("Fallback"))
        self.metrics_label.setText("  ·  ".join(parts))

    def _sync_view_mode(self, mode: str) -> None:
        action = self.view_actions.get(mode)
        if action is not None:
            action.setChecked(True)

    def _sync_speaking(self, target: str) -> None:
        self.speak_stop.setVisible(bool(target))
        if target:
            self.speak_stop.setText(t("Stop"))

    def _sync_settings_actions(self) -> None:
        self._sync_status()

    def _show_error(self, message: str) -> None:
        self.error_label.setText(message)
        self.error_label.setStyleSheet(f"color: {Theme.palette().danger};")
        self.error_label.show()
        QTimer.singleShot(6000, self.error_label.hide)

    def _show_feedback(self, message: str) -> None:
        if self.tray is not None:
            self.tray.notify(APP_NAME, message)
        self.status_label.setText(message)
        QTimer.singleShot(2500, self._sync_status)

    def _show_about(self) -> None:
        from PySide6.QtWidgets import QMessageBox

        QMessageBox.about(
            self,
            t("About DeepL-oFM"),
            f"<b>{APP_NAME}</b> {__version__}<br><br>"
            + t("A native translator for local and cloud models.")
            + "<br><br>MIT · "
            + f'<a href="{GITHUB_URL}">{GITHUB_URL}</a>',
        )

    def _on_language_changed(self, _code: str) -> None:
        self.retranslate_ui()

    # ------------------------------------------------------------ close/tray
    def closeEvent(self, event) -> None:  # noqa: N802 - Qt API
        if self.tray is not None and self.tray.is_visible():
            event.ignore()
            self.hide()
            self.tray.notify(APP_NAME, t("The app is still running in the tray."))
            return
        super().closeEvent(event)

    # ---------------------------------------------------------- retranslate
    def retranslate_ui(self) -> None:
        labels = {
            "translate": t("Translate"),
            "files": t("Files"),
            "write": t("Write"),
            "history": t("History"),
        }
        for key, button in self.tab_buttons.items():
            button.set_label(labels[key])
        self.settings_button.setIcon(icons.icon("settings", Theme.palette().muted, 18))
        self.settings_button.setToolTip(t("Settings"))

        self.title.setText(APP_NAME)
        self.file_menu.setTitle(t("File"))
        self.edit_menu.setTitle(t("Edit"))
        self.view_menu.setTitle(t("View"))
        self.settings_menu.setTitle(t("Settings"))
        self.help_menu.setTitle(t("Help"))
        self.language_menu.setTitle(t("Interface language"))
        self.action_new.setText(t("New translation"))
        self.action_open.setText(t("Open file…"))
        self.action_quit.setText(t("Quit DeepL-oFM"))
        self.action_copy_translation.setText(t("Copy translation"))
        self.action_copy_source.setText(t("Copy source"))
        self.action_paste.setText(t("Paste"))
        self.action_clear.setText(t("Clear"))
        self.action_hotkeys.setText(t("Translate clipboard"))
        self.action_settings.setText(t("Settings…"))
        self.action_catalog.setText(t("Model catalog…"))
        self.action_about.setText(t("About DeepL-oFM"))
        self.action_site.setText(t("Website"))
        self.view_actions["preview"].setText(t("Preview"))
        self.view_actions["text"].setText(t("Plain text"))
        self.view_actions["markdown"].setText(t("Markdown"))
        self._build_language_menu()
        for page in self.pages.values():
            if hasattr(page, "retranslate_ui"):
                page.retranslate_ui()
        self._sync_status()

    def _build_language_menu(self) -> None:
        from ..core.languages import AppLanguage

        self.language_menu.clear()
        group = QActionGroup(self)
        group.setExclusive(True)
        current = self.controller.settings.interface_language
        for language in AppLanguage:
            action = QAction(language.picker_title, self, checkable=True)
            action.setChecked(language == current)
            action.triggered.connect(
                lambda _checked=False, value=language: self._set_language(value)
            )
            group.addAction(action)
            self.language_menu.addAction(action)

    def _set_language(self, language) -> None:
        self.controller.set_interface_language(language)
