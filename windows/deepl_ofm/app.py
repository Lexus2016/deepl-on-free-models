"""Application entry point: Qt bootstrap, theme, window, tray and global hotkeys.

Counterpart of ``Sources/HyMT/DeepL-oFMApp.swift``.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtWidgets import QApplication

from . import APP_ID, APP_NAME, __version__
from .controller import AppController
from .i18n import t
from .ui import icons
from .ui.main_window import MainWindow
from .ui.theme import Theme

log = logging.getLogger(__name__)


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="DeepL-oFM", description="DeepL-oFM for Windows")
    parser.add_argument("--prefill", metavar="TEXT", default="", help="start with this source text")
    parser.add_argument("--tab", choices=["translate", "files", "write", "history"], default=None)
    parser.add_argument("--version", action="version", version=f"{APP_NAME} {__version__}")
    parser.add_argument("--debug", action="store_true", help="verbose logging")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="start the full application, then quit after a moment (diagnostics)",
    )
    return parser.parse_args(argv)


def _log_directory() -> Path:
    base = Path(os.environ.get("APPDATA", Path.home() / ".config"))
    return base / "DeepL-oFM" / "logs"


def _configure_logging(debug: bool) -> None:
    level = logging.DEBUG if debug or os.environ.get("DEEPLOFM_DEBUG") else logging.INFO
    handlers: list[logging.Handler] = []
    try:
        from logging.handlers import RotatingFileHandler

        directory = _log_directory()
        directory.mkdir(parents=True, exist_ok=True)
        handlers.append(
            RotatingFileHandler(
                directory / "app.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8"
            )
        )
    except OSError:  # a read-only profile must not stop the app
        pass
    if sys.stderr is not None:
        handlers.append(logging.StreamHandler())
    if not handlers:
        # pythonw.exe has no stderr and the profile may be read-only.
        handlers.append(logging.NullHandler())
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        handlers=handlers,
    )


SINGLE_INSTANCE_KEY = "DeepL-oFM-instance"


def _notify_running_instance() -> bool:
    """Return True when another copy is already running (and ask it to show up)."""
    socket = QLocalSocket()
    socket.connectToServer(SINGLE_INSTANCE_KEY)
    if not socket.waitForConnected(250):
        return False
    socket.write(b"show")
    socket.flush()
    socket.waitForBytesWritten(250)
    socket.disconnectFromServer()
    return True


def _install_instance_server(window) -> QLocalServer:
    """Listen for a second launch and bring the existing window forward."""
    QLocalServer.removeServer(SINGLE_INSTANCE_KEY)
    server = QLocalServer(window)
    server.listen(SINGLE_INSTANCE_KEY)

    def on_connection() -> None:
        connection = server.nextPendingConnection()
        if connection is None:
            return
        connection.readyRead.connect(lambda: connection.readAll())
        connection.disconnected.connect(connection.deleteLater)
        window.present()

    server.newConnection.connect(on_connection)
    return server


class _Hotkeys:
    """Binds the configured combos to controller commands (Windows RegisterHotKey)."""

    def __init__(self, controller: AppController) -> None:
        self.controller = controller
        self.manager = None
        self._registered: dict[str, object] = {}
        self._pending = False
        try:
            from .services.hotkeys import HotkeyManager

            self.manager = HotkeyManager()
            self.manager.triggered.connect(self._on_triggered)
            self.manager.error.connect(self._on_error)
        except Exception:  # noqa: BLE001 - hotkeys are optional
            log.debug("hotkey manager unavailable", exc_info=True)

    def register_all(self) -> None:
        if self.manager is None:
            self.controller.hotkey_message = t("Global hotkeys are only available on Windows.")
            self.controller.hotkeyStatusChanged.emit("translate", self.controller.hotkey_message)
            return

        settings = self.controller.settings
        combos = {
            "translate": settings.hot_key,
            "selection": settings.selection_hot_key,
        }
        if combos == self._registered:
            return
        # Settings changed: release the old bindings before claiming the new ones,
        # otherwise RegisterHotKey fails with "already registered" for the same id.
        self.manager.unregister_all()
        self._registered = dict(combos)
        for action, combo in combos.items():
            ok = self.manager.register(action, combo)
            message = "" if ok else t("Hotkey does not work")
            if action == "translate":
                self.controller.hotkey_message = message
            else:
                self.controller.selection_hotkey_message = message
            self.controller.hotkeyStatusChanged.emit(action, message)

    def schedule_reregister(self) -> None:
        """Coalesce settings changes and re-register once the UI settles."""
        if self._pending or self.manager is None:
            return
        from PySide6.QtCore import QTimer

        self._pending = True
        QTimer.singleShot(250, self._reregister)

    def _reregister(self) -> None:
        self._pending = False
        try:
            self.register_all()
        except Exception:  # noqa: BLE001 - a hotkey problem must not kill the app
            log.debug("hotkey re-registration failed", exc_info=True)

    def _on_triggered(self, action: str) -> None:
        if action == "translate":
            self.controller.translate_clipboard()
        elif action == "selection":
            self.controller.translate_selection()

    def _on_error(self, message: str) -> None:
        log.warning("hotkey error: %s", message)

    def stop(self) -> None:
        if self.manager is not None:
            self.manager.unregister_all()


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    _configure_logging(args.debug)

    QApplication.setAttribute(Qt.AA_DontUseNativeMenuBar, False)
    app = QApplication(sys.argv[:1])
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(APP_NAME)
    app.setOrganizationName("ua.admin.hymt")
    app.setApplicationVersion(__version__)
    app.setDesktopFileName(APP_ID)

    if _notify_running_instance():
        log.info("another DeepL-oFM instance is running; asked it to show the window")
        return 0

    Theme.apply(app)
    icon = icons.icon("translate", size=128)
    if not icon.isNull():
        app.setWindowIcon(icon)

    controller = AppController()
    window = MainWindow(controller)
    instance_server = _install_instance_server(window)  # noqa: F841 - kept alive by Qt

    tray = None
    try:
        from .ui.tray import TrayIcon

        tray = TrayIcon(controller, window)
        controller.interfaceLanguageChanged.connect(lambda _code: tray.retranslate_ui())
        tray.settingsRequested.connect(window.open_settings)
        tray.quitRequested.connect(app.quit)
        window.tray = tray
        if controller.settings.show_in_menu_bar:
            tray.show()
        else:
            app.setQuitOnLastWindowClosed(True)
    except Exception:  # noqa: BLE001 - tray may be unavailable in a bare session
        log.debug("tray unavailable", exc_info=True)

    hotkeys = _Hotkeys(controller)
    hotkeys.register_all()
    controller.settingsChanged.connect(hotkeys.schedule_reregister)

    controller.windowRequested.connect(window.present)

    if args.prefill:
        window.set_source_text(args.prefill, translate=True)
    if args.tab:
        window.select_tab(args.tab)

    window.show()
    controller.bootstrap()
    if args.self_test:
        from PySide6.QtCore import QTimer

        QTimer.singleShot(1500, app.quit)

    try:
        exit_code = app.exec()
    finally:
        hotkeys.stop()
        controller.shutdown()
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
