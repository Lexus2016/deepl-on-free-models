"""System tray icon and its menu (ported from the macOS status-item code in AppState.swift)."""

from __future__ import annotations

from PySide6.QtCore import QObject, Signal
from PySide6.QtGui import QAction
from PySide6.QtWidgets import QMenu, QSystemTrayIcon

from ..i18n import t
from . import icons


class TrayIcon(QObject):
    """Tray integration: show the window, translate the clipboard, open settings, quit."""

    quitRequested = Signal()
    settingsRequested = Signal()

    def __init__(self, controller, window, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.controller = controller
        self.window = window
        self._icon = QSystemTrayIcon(self)
        self._icon.setIcon(icons.icon("translate", size=22))
        self._icon.setToolTip("DeepL-oFM")

        self._menu = QMenu()
        self._show_action = QAction(t("Open DeepL-oFM"), self._menu)
        self._clip_action = QAction(t("Translate clipboard"), self._menu)
        self._settings_action = QAction(t("Settings"), self._menu)
        self._quit_action = QAction(t("Quit DeepL-oFM"), self._menu)
        for action in (self._show_action, self._clip_action):
            self._menu.addAction(action)
        self._menu.addSeparator()
        self._menu.addAction(self._settings_action)
        self._menu.addSeparator()
        self._menu.addAction(self._quit_action)

        self._show_action.triggered.connect(self._show_window)
        self._clip_action.triggered.connect(self.controller.translate_clipboard)
        self._settings_action.triggered.connect(self.settingsRequested.emit)
        self._quit_action.triggered.connect(self.quitRequested.emit)
        self._icon.activated.connect(self._on_activated)
        self._icon.setContextMenu(self._menu)

    # ------------------------------------------------------------------ api
    def show(self) -> None:
        self._icon.setVisible(True)

    def hide(self) -> None:
        self._icon.setVisible(False)

    def is_visible(self) -> bool:
        return self._icon.isVisible()

    def notify(self, title: str, message: str) -> None:
        if self._icon.isVisible() and QSystemTrayIcon.supportsMessages():
            self._icon.showMessage(title, message, icons.icon("translate"), 4000)

    def retranslate_ui(self) -> None:
        self._show_action.setText(t("Open DeepL-oFM"))
        self._clip_action.setText(t("Translate clipboard"))
        self._settings_action.setText(t("Settings"))
        self._quit_action.setText(t("Quit DeepL-oFM"))

    # -------------------------------------------------------------- internal
    def _show_window(self) -> None:
        self.window.show()
        self.window.raise_()
        self.window.activateWindow()

    def _on_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self._show_window()
