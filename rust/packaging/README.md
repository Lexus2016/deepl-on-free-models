# Windows installer / Інсталятор Windows

From the repository root on Windows 11 x64, with Rust, MSVC build tools and Node.js installed:

З кореня репозиторію на Windows 11 x64 із встановленими Rust, засобами складання MSVC та Node.js:

```powershell
./rust/packaging/windows/build.ps1
./rust/packaging/windows/smoke.ps1
```

The NSIS installer is in `rust/target/release/bundle/nsis/`. The smoke test uses a temporary installation and profile, opens the installed WebView, and uninstalls the app. Run it on a test account. GitHub Actions publishes the tested installer as a short-lived artifact.

Інсталятор NSIS зберігається в `rust/target/release/bundle/nsis/`. Перевірка встановлює програму в тимчасову папку, відкриває WebView і видаляє програму. Використовуйте тестовий обліковий запис. GitHub Actions зберігає перевірений інсталятор як тимчасовий артефакт.

## Public release / Публічний випуск

Pass a local Tauri configuration override with `-SigningConfig`. Use `bundle.windows.certificateThumbprint`, `digestAlgorithm` and `timestampUrl` for an installed Authenticode certificate, or `bundle.windows.signCommand` for a signing service. Tauri signs during bundling, including the executable inside the installer. On a clean Windows test machine, verify that `Get-AuthenticodeSignature` reports `Valid` and the expected publisher for both the installer and the installed executable. Test upgrades and a fresh sign-in with startup enabled before publishing.

Передайте локальне перевизначення конфігурації Tauri через `-SigningConfig`. Для встановленого сертифіката Authenticode використайте `bundle.windows.certificateThumbprint`, `digestAlgorithm` і `timestampUrl`, а для служби підпису — `bundle.windows.signCommand`. Tauri підписує програму під час пакування, зокрема виконуваний файл усередині інсталятора. На чистій тестовій Windows перевірте через `Get-AuthenticodeSignature` стан `Valid` і очікуваного видавця для інсталятора та встановленої програми. Перед публікацією перевірте оновлення та повторний вхід зі ввімкненим автозапуском.

## Automatic updates / Автоматичні оновлення

Windows checks for updates once a day by default. The user can disable checks or opt in to automatic download and installation on quit. The updater validates the installer signature and the signed version. It never installs a package that failed verification.

Windows за замовчуванням перевіряє оновлення раз на добу. Користувач може вимкнути перевірки або дозволити автоматичне завантаження та встановлення після виходу. Механізм оновлення перевіряє підпис інсталятора і підписаний номер версії. Файл, який не пройшов перевірку, не встановлюється.

For a production build, keep the Tauri updater signing key in protected storage and create the public configuration with `updater-config.ps1`. Use both `-UpdaterConfig` and `-SigningConfig` with `build.ps1`. Keep the same updater key across release versions. The Tauri CLI uses `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.

Для публічної збірки зберігайте ключ оновлень Tauri в захищеному сховищі та створіть публічну конфігурацію через `updater-config.ps1`. Передайте `-UpdaterConfig` і `-SigningConfig` у `build.ps1`. Використовуйте той самий ключ оновлення для наступних версій. Tauri читає `TAURI_SIGNING_PRIVATE_KEY` і `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.

1. Verify both Authenticode signatures, run `smoke-update.ps1` on Windows, and upgrade an installed copy with the production package. / Перевірте обидва підписи Authenticode, запустіть `smoke-update.ps1` на Windows і перевірте оновлення встановленої програми публічним пакетом.
2. Publish the installer and its `.sig` on the Windows release tag `windows-v<version>`. Use `--latest=false` to keep the macOS download link pointing to the macOS release. / Опублікуйте інсталятор і його `.sig` у випуску `windows-v<version>`. Передайте `--latest=false`, щоб посилання для Mac і далі відкривало випуск macOS.
3. Download those assets over HTTPS and use `release-manifest.py` with `minisign` to verify the package and create `windows-update.json`. For subsequent releases pass the current public feed as `--previous`. Deploy the feed after the release assets are readable. / Завантажте ці файли через HTTPS і виконайте `release-manifest.py` із `minisign`, щоб перевірити пакет і створити `windows-update.json`. Під час наступних випусків передайте поточний публічний маніфест через `--previous`. Розгортайте маніфест після того, як файли випуску доступні.
