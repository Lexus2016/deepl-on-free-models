# Exercise a real in-place NSIS update with an ephemeral Tauri signing key.
# Перевіряє оновлення NSIS із тимчасовим ключем у тестовому середовищі.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) "deepl-update-$([Guid]::NewGuid())"
New-Item -ItemType Directory -Path $root | Out-Null
$baseDir = Join-Path $root 'installed'
$public = Join-Path $root 'public'
New-Item -ItemType Directory -Path $public | Out-Null
$env:APPDATA = Join-Path $root 'appdata'
$log = Join-Path $env:APPDATA 'DeepL-oFM/deepl-ofm.log'
$keyPath = Join-Path $root 'update.key'
$config = Join-Path $root 'updater.json'
$port = 8193
$endpoint = "http://127.0.0.1:$port/update.json"
$bundle = Join-Path $PSScriptRoot '../../target/release/bundle/nsis'
$server = $null
$app = Join-Path $baseDir 'ofm-desktop.exe'

function Assert-ExitCode($Process, $Expected) {
    if ($Process.ExitCode -ne $Expected) {
        throw "Expected exit code $Expected, received $($Process.ExitCode)."
    }
}

function Invoke-AppCheck([string] $mode) {
    $process = Start-Process $app -ArgumentList "--updater-smoke=$mode" -PassThru
    try {
        if (-not $process.WaitForExit(90000)) { throw 'Update test timed out.' }
        Assert-ExitCode $process 0
    } finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

try {
    # Tauri's test key is generated on this runner. Keep the command output and private key out of logs.
    & npx --yes '@tauri-apps/cli@2.12.6' signer generate --ci --password '' --write-keys $keyPath *> $null
    if ($LASTEXITCODE) { throw 'Could not generate the ephemeral update key.' }
    $env:TAURI_SIGNING_PRIVATE_KEY = $keyPath
    $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = ''
    & "$PSScriptRoot/updater-config.ps1" -PublicKeyPath "$keyPath.pub" -OutputPath $config -Endpoint $endpoint -LoopbackTest

    $installers = @{}
    foreach ($version in @('0.0.1', '0.0.2')) {
        $override = Get-Content -LiteralPath $config -Raw | ConvertFrom-Json -AsHashtable
        $override.version = $version
        $override | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $config -Encoding utf8
        & "$PSScriptRoot/build.ps1" -UpdaterConfig $config -UpdaterSmoke
        $name = "DeepL-oFM_${version}_x64-setup.exe"
        $installers[$version] = Join-Path $root $name
        Copy-Item -LiteralPath (Join-Path $bundle $name) -Destination $root
        if ($version -eq '0.0.2') {
            $sig = (Get-Content -LiteralPath (Join-Path $bundle "$name.sig") -Raw).Trim()
        }
    }

    Assert-ExitCode (Start-Process $installers['0.0.1'] -ArgumentList "/S /D=$baseDir" -Wait -PassThru) 0
    if (-not (Test-Path $app)) { throw 'The baseline app did not install.' }
    $server = Start-Process python -ArgumentList "-m http.server $port --bind 127.0.0.1" -WorkingDirectory $public -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ($true) {
        try { Invoke-WebRequest "http://127.0.0.1:$port/" -TimeoutSec 2 | Out-Null; break }
        catch { if ([DateTime]::UtcNow -ge $deadline) { throw }; Start-Sleep -Milliseconds 200 }
    }

    $target = $installers['0.0.2']
    Copy-Item -LiteralPath $target -Destination $public
    [IO.File]::WriteAllText((Join-Path $public 'tampered.exe'), 'not the signed package')
    $feed = @{ version = '0.0.2'; platforms = @{
        'windows-x86_64' = @{ signature = $sig; url = "http://127.0.0.1:$port/tampered.exe" }
    } }
    $feedPath = Join-Path $public 'update.json'
    $feed | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $feedPath -Encoding utf8
    Invoke-AppCheck 'reject'

    $feed.platforms['windows-x86_64'].url = "http://127.0.0.1:$port/$([IO.Path]::GetFileName($target))"
    $feed.version = '0.0.3'
    $feed | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $feedPath -Encoding utf8
    Invoke-AppCheck 'reject'

    $feed.version = '0.0.2'
    $feed | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $feedPath -Encoding utf8
    $settings = Join-Path $env:APPDATA 'DeepL-oFM/settings.json'
    New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
    '{"model":"updater-test-keeps-settings"}' | Set-Content -LiteralPath $settings -Encoding utf8
    Invoke-AppCheck 'install'
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    do {
        try {
            $newVersion = (Get-Item -LiteralPath $app).VersionInfo.ProductVersion
            if ($newVersion -eq '0.0.2') { break }
        } catch {}
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($newVersion -ne '0.0.2') { throw "Did not install the signed upgrade (version: $newVersion)." }
    if ((Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).model -ne 'updater-test-keeps-settings') {
        throw 'Updating changed the existing settings.'
    }
    Clear-Content -LiteralPath $log
    $updated = Start-Process $app -ArgumentList '--debug' -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while (-not (Select-String -LiteralPath $log -SimpleMatch 'WebView requested startup actions' -Quiet)) {
            if ($updated.HasExited -or [DateTime]::UtcNow -ge $deadline) { throw 'Updated app did not initialize.' }
            Start-Sleep -Milliseconds 500
        }
    } finally {
        if (-not $updated.HasExited) { Stop-Process -Id $updated.Id }
    }
    Write-Host 'Modified bytes and a forged version were rejected; the signed update launched and preserved settings.'
} finally {
    if (Test-Path $log) { Get-Content -LiteralPath $log -Tail 40 }
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id }
    $uninstaller = Join-Path $baseDir 'uninstall.exe'
    if (Test-Path $uninstaller) { Start-Process $uninstaller -ArgumentList '/S' -Wait }
    Remove-Item Env:TAURI_SIGNING_PRIVATE_KEY, Env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
}
