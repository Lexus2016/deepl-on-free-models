use serde_json::json;
use tauri_plugin_updater::UpdaterExt;

const TEST_KEY: &str = include_str!("fixtures/update.pub");
const TEST_SIGNATURE: &str = include_str!("fixtures/update.sig");
const TEST_PAYLOAD: &[u8] = b"DeepL-oFM updater verification fixture\n";

fn manifest(version: &str) -> serde_json::Value {
    json!({
        "version": version,
        "platforms": {
            "windows-x86_64": {
                "url": "https://example.test/windows-setup.exe",
                "signature": TEST_SIGNATURE.trim()
            }
        }
    })
}

#[test]
fn rejects_modified_packages_forged_versions_and_downgrades() {
    let mut context = tauri::test::mock_context(tauri::test::noop_assets());
    context.config_mut().plugins.0.insert(
        "updater".into(),
        json!({
            "pubkey": TEST_KEY.trim(),
            "endpoints": ["https://example.test/update.json"]
        }),
    );
    let app = tauri::test::mock_builder()
        .plugin(
            tauri_plugin_updater::Builder::new()
                .pubkey(TEST_KEY.trim())
                .build(),
        )
        .build(context)
        .expect("mock updater");
    let updater = app
        .updater_builder()
        .target("windows-x86_64")
        .build()
        .expect("build updater");
    let update = updater
        .restore_update(manifest("2.0.4"))
        .expect("read manifest")
        .expect("new version");
    assert!(update.verify(TEST_PAYLOAD).is_ok());
    assert!(matches!(
        update.verify(b"modified package"),
        Err(tauri_plugin_updater::Error::Minisign(_))
    ));
    let wrong_version = updater
        .restore_update(manifest("2.0.5"))
        .expect("read changed manifest")
        .expect("announced version");
    assert!(matches!(
        wrong_version.verify(TEST_PAYLOAD),
        Err(tauri_plugin_updater::Error::SignedVersionMismatch { .. })
    ));
    assert!(updater
        .restore_update(manifest("0.1.0"))
        .expect("current version")
        .is_none());
    assert!(updater
        .restore_update(manifest("0.0.9"))
        .expect("older version")
        .is_none());
}
