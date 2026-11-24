# Confirm that the packaged app initializes its WebView. Run on a test account.
# Перевіряє ініціалізацію WebView встановленої програми. Запускати в тестовому обліковому записі.
$ErrorActionPreference = 'Stop'

$bundleDir = Join-Path $PSScriptRoot '../../target/release/bundle/nsis'
$installers = @(Get-ChildItem $bundleDir -Filter '*-setup.exe')
if ($installers.Count -ne 1) {
    throw "Expected one installer, found $($installers.Count)."
}

$scratch = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$testDir = Join-Path $scratch "deepl-smoke/$([Guid]::NewGuid())"
$installDir = Join-Path $testDir 'installed'
$env:APPDATA = $testDir
$logPath = Join-Path $env:APPDATA 'DeepL-oFM/deepl-ofm.log'
$appPath = Join-Path $installDir 'ofm-desktop.exe'
$uninstaller = Join-Path $installDir 'uninstall.exe'
$app = $null
try {
    $setup = Start-Process $installers[0].FullName -ArgumentList "/S /D=$installDir" -Wait -PassThru
    if ($setup.ExitCode -ne 0 -or -not (Test-Path $appPath)) {
        throw "Installation failed with exit code $($setup.ExitCode)."
    }
    $app = Start-Process $appPath -ArgumentList '--debug' -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $ready = $false
    do {
        $app.Refresh()
        if ($app.HasExited) { throw "App exited before loading the WebView ($($app.ExitCode))." }
        if ((Test-Path $logPath) -and
            (Select-String -LiteralPath $logPath -SimpleMatch 'WebView requested startup actions' -Quiet)) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw 'The installed WebView did not initialize within 60 seconds.' }
    Write-Host 'Installed application initialized the WebView and requested startup state.'
} finally {
    if ($app -and -not $app.HasExited) {
        $app.Kill()
        $app.WaitForExit()
    }
    if (Test-Path $uninstaller) {
        $result = Start-Process $uninstaller -ArgumentList '/S' -Wait -PassThru
        if ($result.ExitCode -ne 0) { throw "Uninstaller returned $($result.ExitCode)." }
    }
}
$deadline = [DateTime]::UtcNow.AddSeconds(20)
while ((Test-Path $appPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 250
}
if (Test-Path $appPath) { throw 'Uninstall left the application executable behind.' }
Write-Host 'Uninstaller removed the application executable.'
