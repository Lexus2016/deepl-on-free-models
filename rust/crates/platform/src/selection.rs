//! Capture the text selected in the foreground application.
//!
//! Windows reads UI Automation text ranges without touching the clipboard.
//! macOS uses the system copy shortcut. Other platforms are unsupported.

use std::time::Duration;

/// Whether selected-text capture works on this platform.
pub const fn is_supported() -> bool {
    cfg!(any(windows, target_os = "macos"))
}

/// Return the text selected in the foreground window, or `None`.
///
/// Call off the UI thread. Windows applies the timeout to UI Automation
/// transactions; macOS uses it to wait for the pasteboard update.
pub fn capture(timeout: Duration) -> Option<String> {
    #[cfg(windows)]
    {
        windows_impl::capture(timeout)
    }
    #[cfg(target_os = "macos")]
    {
        macos_impl::capture(timeout)
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        let _ = timeout;
        unsupported::log_once();
        None
    }
}

#[cfg(not(any(windows, target_os = "macos")))]
mod unsupported {
    use std::sync::Once;

    static LOGGED: Once = Once::new();

    pub(super) fn log_once() {
        LOGGED.call_once(|| {
            log::info!("selected-text capture is not supported on this platform");
        });
    }
}

#[cfg(windows)]
mod windows_impl {
    use std::time::Duration;

    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER,
        COINIT_MULTITHREADED,
    };
    use windows::Win32::UI::Accessibility::{
        CUIAutomation8, IUIAutomation2, IUIAutomationTextPattern, UIA_TextPatternId,
    };

    const MAX_SELECTION: i32 = 128_000;

    struct ComSession;

    impl Drop for ComSession {
        fn drop(&mut self) {
            // SAFETY: A successful CoInitializeEx on this thread is paired here.
            unsafe { CoUninitialize() };
        }
    }

    pub(super) fn capture(timeout: Duration) -> Option<String> {
        // SAFETY: This worker owns the COM initialization and all UI Automation
        // interfaces. No keyboard input or clipboard writes are performed.
        unsafe {
            CoInitializeEx(None, COINIT_MULTITHREADED).ok().ok()?;
            let _session = ComSession;
            let automation: IUIAutomation2 =
                CoCreateInstance(&CUIAutomation8, None, CLSCTX_INPROC_SERVER).ok()?;
            let timeout_ms = timeout.as_millis().clamp(1, u32::MAX.into()) as u32;
            automation.SetConnectionTimeout(timeout_ms).ok()?;
            automation.SetTransactionTimeout(timeout_ms).ok()?;

            let focused = automation.GetFocusedElement().ok()?;
            if focused.CurrentIsPassword().ok()?.as_bool() {
                return None;
            }
            let selected = focused
                .GetCurrentPatternAs::<IUIAutomationTextPattern>(UIA_TextPatternId)
                .ok()?
                .GetSelection()
                .ok()?;
            let range_count = selected.Length().ok()?;
            if !(1..=64).contains(&range_count) {
                return None;
            }
            let mut text = String::new();
            let mut remaining = MAX_SELECTION + 1;
            for i in 0..range_count {
                let range = selected.GetElement(i).ok()?;
                let piece = range.GetText(remaining).ok()?;
                if !piece.is_empty() {
                    if !text.is_empty() {
                        text.push('\n');
                        remaining -= 1;
                    }
                    remaining -= i32::try_from(piece.len()).ok()?;
                    if remaining <= 0 {
                        return None;
                    }
                    text.push_str(&piece.to_string());
                }
            }
            if text.trim().is_empty() {
                return None;
            }
            let current = automation.GetFocusedElement().ok()?;
            automation
                .CompareElements(&focused, &current)
                .ok()?
                .as_bool()
                .then_some(text)
        }
    }
}

#[cfg(target_os = "macos")]
mod macos_impl {
    use std::process::Command;
    use std::thread::sleep;
    use std::time::{Duration, Instant};

    use arboard::Clipboard;

    fn clipboard_text() -> Option<String> {
        let mut clipboard = Clipboard::new().ok()?;
        clipboard.get_text().ok()
    }

    /// Upper bound for `osascript` itself; without Accessibility permission it
    /// can otherwise wait for a system dialog indefinitely.
    const OSASCRIPT_LIMIT: Duration = Duration::from_secs(2);

    fn send_command_c() -> bool {
        let mut command = Command::new("/usr/bin/osascript");
        command.args([
            "-e",
            r#"tell application "System Events" to keystroke "c" using command down"#,
        ]);
        let Ok(mut child) = command.spawn() else {
            log::info!("could not run osascript");
            return false;
        };
        let deadline = Instant::now() + OSASCRIPT_LIMIT;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    if status.success() {
                        return true;
                    }
                    log::info!(
                        "osascript could not send Cmd+C (status {status}); check Accessibility"
                    );
                    return false;
                }
                Ok(None) => {}
                Err(error) => {
                    log::info!("could not wait for osascript: {error}");
                    return false;
                }
            }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                log::info!("osascript did not finish in time; check Accessibility permission");
                return false;
            }
            sleep(Duration::from_millis(20));
        }
    }

    pub(super) fn capture(timeout: Duration) -> Option<String> {
        let before = clipboard_text();
        // Accessibility permission is required; without it `osascript` exits
        // with a non-zero status and the feature degrades to `None`.
        if !send_command_c() {
            return None;
        }

        let deadline = Instant::now() + timeout;
        loop {
            if let Some(text) = clipboard_text() {
                if !text.is_empty() && before.as_deref() != Some(text.as_str()) {
                    return Some(text);
                }
            }
            if Instant::now() >= deadline {
                break;
            }
            sleep(Duration::from_millis(20));
        }
        log::info!("no clipboard update after Cmd+C; the selection was not captured");
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn support_matches_the_platform() {
        assert_eq!(is_supported(), cfg!(any(windows, target_os = "macos")));
    }

    #[test]
    fn capture_without_support_is_a_silent_none() {
        if is_supported() {
            return;
        }
        assert_eq!(capture(Duration::from_millis(5)), None);
        // A second call must not panic or block either.
        assert_eq!(capture(Duration::ZERO), None);
    }
}
