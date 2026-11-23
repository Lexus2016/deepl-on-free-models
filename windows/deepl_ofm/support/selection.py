"""Capture the text selected in the foreground Windows application.

Counterpart of the ``⌘C`` dance in ``Sources/HyMT/AppState.swift``
(``translateSelection``): the app presses Copy in the other program and reads
what landed on the clipboard.  Unlike macOS this needs no Accessibility grant,
but there are three Windows-specific traps that this module handles:

1. the global hotkey fires while Ctrl and Alt are still physically held down, so
   a naive synthetic Ctrl+C reaches the target as Ctrl+Alt+C and does nothing —
   we wait (briefly) for the keys to be released and force-release them if not;
2. the clipboard may not be updated yet — we wait for the clipboard sequence
   number to change instead of sleeping for a fixed time;
3. an elevated target (UIPI) silently ignores synthetic input — the caller gets
   an empty string, not a stale clipboard.

The module is Windows-only and import-safe everywhere; Qt is not imported so it
can run from any thread.
"""

from __future__ import annotations

import ctypes
import logging
import sys
import time

logger = logging.getLogger(__name__)

_WINDOWS = sys.platform == "win32"

VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12
VK_LWIN = 0x5B
VK_RWIN = 0x5C
VK_C = 0x43
KEYEVENTF_KEYUP = 0x0002
CF_UNICODETEXT = 13
_MODIFIERS = (VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN)


def is_supported() -> bool:
    """Selected-text translation is implemented for Windows only."""
    return _WINDOWS


def capture_selection(*, timeout_ms: int = 700, modifier_wait_ms: int = 300) -> str:
    """Return the text selected in the foreground window, or ``""``.

    Blocks for at most ``modifier_wait_ms + timeout_ms``; call it from the GUI
    thread before the window is shown, so nothing visibly freezes.
    """
    if not _WINDOWS:
        return ""
    try:
        user32 = ctypes.windll.user32
    except Exception:  # pragma: no cover - only on non-Windows
        return ""
    try:
        user32.GetClipboardSequenceNumber.restype = ctypes.c_uint32
        before = int(user32.GetClipboardSequenceNumber())
    except Exception:
        before = -1

    _wait_for_modifier_release(modifier_wait_ms)
    _send_ctrl_c()

    deadline = time.monotonic() + timeout_ms / 1000.0
    while time.monotonic() < deadline:
        try:
            if int(user32.GetClipboardSequenceNumber()) != before:
                time.sleep(0.02)  # let the owner publish the data
                return _clipboard_text()
        except Exception:  # pragma: no cover - defensive
            break
        time.sleep(0.01)
    logger.info("no clipboard update after Ctrl+C; the selection was not captured")
    return ""


# --------------------------------------------------------------------------
# Windows helpers
# --------------------------------------------------------------------------
def _modifier_is_down(user32: object, key: int) -> bool:
    try:
        return bool(user32.GetAsyncKeyState(key) & 0x8000)
    except Exception:  # pragma: no cover - defensive
        return False


def _wait_for_modifier_release(timeout_ms: int) -> bool:
    """Wait until the user lets go of the hotkey modifiers."""
    if not _WINDOWS:
        return True
    user32 = ctypes.windll.user32
    deadline = time.monotonic() + timeout_ms / 1000.0
    while time.monotonic() < deadline:
        if not any(_modifier_is_down(user32, key) for key in _MODIFIERS):
            return True
        time.sleep(0.01)
    # The user is still holding the combination: release it synthetically so the
    # target sees a plain Ctrl+C. Windows resyncs on the next physical key event.
    for key in _MODIFIERS:
        try:
            user32.keybd_event(key, 0, KEYEVENTF_KEYUP, 0)
        except Exception:  # pragma: no cover - defensive
            pass
    time.sleep(0.03)
    return False


def _send_ctrl_c() -> None:
    user32 = ctypes.windll.user32
    try:
        user32.keybd_event(VK_CONTROL, 0, 0, 0)
        time.sleep(0.01)
        user32.keybd_event(VK_C, 0, 0, 0)
        time.sleep(0.01)
        user32.keybd_event(VK_C, 0, KEYEVENTF_KEYUP, 0)
        time.sleep(0.01)
        user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)
    except Exception:  # pragma: no cover - defensive
        logger.debug("could not send Ctrl+C", exc_info=True)


def _clipboard_text() -> str:
    """Read CF_UNICODETEXT without Qt, so this works off the GUI thread too."""
    if not _WINDOWS:
        return ""
    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    handle = None
    try:
        if not user32.OpenClipboard(None):
            return ""
        handle = user32.GetClipboardData(CF_UNICODETEXT)
        if not handle:
            return ""
        pointer = kernel32.GlobalLock(handle)
        if not pointer:
            return ""
        try:
            return ctypes.wstring_at(pointer)
        finally:
            kernel32.GlobalUnlock(handle)
    except Exception:  # pragma: no cover - defensive
        logger.debug("could not read the clipboard", exc_info=True)
        return ""
    finally:
        try:
            user32.CloseClipboard()
        except Exception:  # pragma: no cover - defensive
            pass
