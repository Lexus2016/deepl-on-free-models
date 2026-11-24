use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use ofm_app::{AppController, AppState};
use serde::Serialize;
use tauri::{AppHandle, Manager};
use tauri_plugin_updater::{Update, UpdaterExt};
use tokio::sync::Mutex;

#[derive(Default)]
pub struct Updates {
    pending: Mutex<Option<Pending>>,
    automatic_install: AtomicBool,
}

struct Pending {
    update: Update,
    verified_package: Option<Vec<u8>>,
}

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    version: Option<String>,
    ready: bool,
}

pub fn enabled(config: &tauri::Config) -> bool {
    cfg!(windows) && config.plugins.0.contains_key("updater")
}

impl Updates {
    pub fn configure(&self, app: &AppHandle, automatic_install: bool) -> bool {
        let enabled = enabled(app.config());
        self.automatic_install
            .store(enabled && automatic_install, Ordering::Release);
        enabled
    }

    pub async fn check(&self, app: &AppHandle) -> Result<Status, String> {
        let mut pending = self.pending.try_lock().map_err(|_| "busy")?;
        let update = app
            .updater_builder()
            .timeout(Duration::from_secs(15))
            // On Windows the updater calls its exit hook before it attempts
            // to spawn the installer. Keep the UI alive if that attempt fails.
            .on_before_exit(|| {})
            .build()
            .map_err(update_error)?
            .check()
            .await
            .map_err(update_error)?;
        match update {
            Some(update)
                if pending.as_ref().is_some_and(|current| {
                    current.update.version == update.version
                        && current.update.signature == update.signature
                        && current.update.download_url == update.download_url
                }) => {}
            Some(update) => {
                *pending = Some(Pending {
                    update,
                    verified_package: None,
                });
            }
            None => *pending = None,
        }
        Ok(status(&pending))
    }

    pub async fn download(&self) -> Result<Status, String> {
        let mut pending = self.pending.try_lock().map_err(|_| "busy")?;
        let current = pending.as_mut().ok_or("unavailable")?;
        if current.verified_package.is_none() {
            current.update.timeout = Some(Duration::from_secs(120));
            let bytes = current
                .update
                .download(|_, _| {}, || {})
                .await
                .map_err(update_error)?;
            current.verified_package = Some(bytes);
        }
        Ok(status(&pending))
    }

    pub fn install(&self, controller: &AppController, restart: bool) -> Result<(), String> {
        let pending = self.pending.try_lock().map_err(|_| "busy")?;
        let current = pending.as_ref().ok_or("unavailable")?;
        let package = current.verified_package.as_deref().ok_or("unavailable")?;
        if has_active_work(&controller.state()) {
            return Err("busy".to_owned());
        }
        log::info!("Installing verified update {}", current.update.version);
        current
            .update
            .clone()
            .restart_after_install(restart)
            .install(package)
            .map_err(update_error)
    }
}

pub fn quit(app: &AppHandle) {
    let shared = app.state::<crate::Shared>();
    if shared.updates.automatic_install.load(Ordering::Acquire) {
        // An intentional quit is a safe point to apply a previously verified
        // update. If no package is ready or the installer fails, quit normally.
        let _ = shared.updates.install(&shared.controller, false);
    }
    app.exit(0);
}

fn status(pending: &Option<Pending>) -> Status {
    pending
        .as_ref()
        .map_or_else(Status::default, |current| Status {
            version: Some(current.update.version.clone()),
            ready: current.verified_package.is_some(),
        })
}

fn has_active_work(state: &AppState) -> bool {
    state.is_translating
        || state.write.in_progress
        || state.file_job.as_ref().is_some_and(|file| {
            matches!(file.state.as_str(), "reading" | "translating" | "writing")
        })
}

fn update_error(error: tauri_plugin_updater::Error) -> String {
    use tauri_plugin_updater::Error;
    log::warn!("Windows update failed: {error}");
    match error {
        Error::Minisign(_)
        | Error::Base64(_)
        | Error::SignatureUtf8(_)
        | Error::SignedVersionMismatch { .. }
        | Error::MissingSignedVersion => "invalid-package",
        _ => "failed",
    }
    .to_owned()
}

#[cfg(feature = "updater-smoke")]
pub fn run_smoke(app: &AppHandle, args: &[String]) {
    let Some(mode) = args
        .iter()
        .find_map(|arg| arg.strip_prefix("--updater-smoke="))
    else {
        return;
    };
    let install = mode == "install";
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let result = smoke(&app, install).await;
        match result {
            Ok(()) => app.exit(0),
            Err(error) => {
                log::error!("Updater smoke failed: {error}");
                app.exit(1);
            }
        }
    });
}

#[cfg(feature = "updater-smoke")]
async fn smoke(app: &AppHandle, install: bool) -> Result<(), String> {
    if !enabled(app.config()) {
        return Err("updater not configured".to_owned());
    }
    let shared = app.state::<crate::Shared>();
    let status = shared.updates.check(app).await?;
    if status.version.is_none() {
        return Err("test manifest did not offer an update".to_owned());
    }
    match (install, shared.updates.download().await) {
        (true, Ok(state)) if state.ready => shared.updates.install(&shared.controller, false),
        (false, Err(error)) if error == "invalid-package" => {
            log::info!("Updater smoke rejected the untrusted package");
            Ok(())
        }
        _ => Err("unexpected update verification result".to_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ofm_app::FileJob;

    #[test]
    fn waits_until_text_write_and_file_jobs_are_idle() {
        let mut state = AppState {
            is_translating: true,
            ..AppState::default()
        };
        assert!(has_active_work(&state));
        state.is_translating = false;
        state.write.in_progress = true;
        assert!(has_active_work(&state));
        state.write.in_progress = false;
        for phase in [
            "reading",
            "translating",
            "writing",
            "done",
            "failed",
            "cancelled",
        ] {
            state.file_job = Some(FileJob {
                state: phase.to_owned(),
                ..FileJob::default()
            });
            assert_eq!(
                has_active_work(&state),
                matches!(phase, "reading" | "translating" | "writing")
            );
        }
    }
}
