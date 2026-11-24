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

The Windows release uses the NSIS installer and may trigger a Microsoft Defender
SmartScreen warning about an unrecognized app or publisher because it does not
yet have an Authenticode publisher signature. Download from this project's
GitHub release and compare its SHA-256 with the release notes. If Windows
Security reports a specific threat, stop and report the detection.

Версію для Windows поширюємо через інсталятор NSIS. Через відсутність
підпису видавця Authenticode Microsoft Defender SmartScreen може попередити
про нерозпізнаний застосунок або видавця. Завантажуйте файл із випуску цього
проєкту на GitHub і звіряйте контрольну суму SHA-256. Якщо «Безпека Windows»
повідомляє про конкретну загрозу, не запускайте файл і повідомте про виявлення.


Pass a local Tauri configuration override with `-SigningConfig`. Use `bundle.windows.certificateThumbprint`, `digestAlgorithm` and `timestampUrl` for an installed Authenticode certificate, or `bundle.windows.signCommand` for a signing service. Tauri signs during bundling, including the executable inside the installer. On a clean Windows test machine, verify that `Get-AuthenticodeSignature` reports `Valid` and the expected publisher for both the installer and the installed executable. Test upgrades and a fresh sign-in with startup enabled before publishing.

Передайте локальне перевизначення конфігурації Tauri через `-SigningConfig`. Для встановленого сертифіката Authenticode використайте `bundle.windows.certificateThumbprint`, `digestAlgorithm` і `timestampUrl`, а для служби підпису — `bundle.windows.signCommand`. Tauri підписує програму під час пакування, зокрема виконуваний файл усередині інсталятора. На чистій тестовій Windows перевірте через `Get-AuthenticodeSignature` стан `Valid` і очікуваного видавця для інсталятора та встановленої програми. Перед публікацією перевірте оновлення та повторний вхід зі ввімкненим автозапуском.

## Automatic updates / Автоматичні оновлення

Windows checks for updates once a day by default. The user can disable checks or opt in to automatic download and installation on quit. The updater validates the installer signature and the signed version. It never installs a package that failed verification.

Windows за замовчуванням перевіряє оновлення раз на добу. Користувач може вимкнути перевірки або дозволити автоматичне завантаження та встановлення після виходу. Механізм оновлення перевіряє підпис інсталятора і підписаний номер версії. Файл, який не пройшов перевірку, не встановлюється.

For public builds, keep the Tauri updater signing key in protected storage and create the public configuration with `updater-config.ps1`. Use `-UpdaterConfig` with `build.ps1`. Add `-SigningConfig` when shipping with a publisher signature. Keep the same updater key across release versions. The Tauri CLI uses `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.

Для публічних збірок зберігайте ключ оновлень Tauri в захищеному сховищі та створіть публічну конфігурацію через `updater-config.ps1`. Передайте `-UpdaterConfig` у `build.ps1`. Для випуску з підписом видавця додайте `-SigningConfig`. Використовуйте той самий ключ оновлення для наступних версій. Tauri читає `TAURI_SIGNING_PRIVATE_KEY` і `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.

1. For signed public releases verify both Authenticode signatures. For every release run `smoke-update.ps1` on Windows, and upgrade an installed copy with the production package. / Для випусків із підписом видавця перевірте обидва підписи Authenticode. Для кожного випуску запустіть `smoke-update.ps1` на Windows і перевірте оновлення встановленої програми публічним пакетом.
2. Publish the installer and its `.sig` on the Windows release tag `windows-v<version>`. Use `--latest=false` to keep the macOS download link pointing to the macOS release. / Опублікуйте інсталятор і його `.sig` у випуску `windows-v<version>`. Передайте `--latest=false`, щоб посилання для Mac і далі відкривало випуск macOS.
3. Download those assets over HTTPS and use `release-manifest.py` with `minisign` to verify the package and create `windows-update.json`. For subsequent releases pass the current public feed as `--previous`. Deploy the feed after the release assets are readable. / Завантажте ці файли через HTTPS і виконайте `release-manifest.py` із `minisign`, щоб перевірити пакет і створити `windows-update.json`. Під час наступних випусків передайте поточний публічний маніфест через `--previous`. Розгортайте маніфест після того, як файли випуску доступні.

The manual **Windows release package** workflow on `main` uses the
`windows-release` environment and its `TAURI_SIGNING_PRIVATE_KEY` secret.
It builds with the checked-in public key, tests installation on Windows,
and uploads the installer and its update signature as a temporary artifact.

Ручний сценарій **Windows release package** у гілці `main` використовує
середовище `windows-release` і його секрет `TAURI_SIGNING_PRIVATE_KEY`.
Він збирає пакет із відкритим ключем із репозиторію, перевіряє встановлення
на Windows і зберігає інсталятор та підпис оновлення як тимчасовий артефакт.
