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
