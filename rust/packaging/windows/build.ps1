param([string] $SigningConfig)

# A signing override asks Tauri to sign the app during bundling.
# Перевизначення підпису застосовується в Tauri під час пакування.
$ErrorActionPreference = 'Stop'
$configArgs = @()
if ($SigningConfig) {
    $configArgs = @('--config', (Resolve-Path -LiteralPath $SigningConfig).Path)
}

Push-Location (Join-Path $PSScriptRoot '../../crates/desktop')
try {
    & npx --yes '@tauri-apps/cli@2.12.6' build --bundles nsis @configArgs -- --locked
    if ($LASTEXITCODE -ne 0) {
        throw "Tauri installer build failed ($LASTEXITCODE)."
    }
} finally {
    Pop-Location
}
