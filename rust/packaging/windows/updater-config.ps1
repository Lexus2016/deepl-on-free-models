param(
    [Parameter(Mandatory)][string] $PublicKeyPath,
    [Parameter(Mandatory)][string] $OutputPath,
    [string] $Endpoint = 'https://lexus2016.github.io/deepl-on-free-models/windows-update.json',
    [switch] $LoopbackTest
)

# Generate an override containing only public updater settings.
# Створює конфігурацію лише з публічними параметрами оновлення.
$ErrorActionPreference = 'Stop'
$uri = [Uri]$Endpoint
if (-not $uri.IsAbsoluteUri -or ($LoopbackTest -and $uri.Host -ne '127.0.0.1') -or
    (-not $LoopbackTest -and $uri.Scheme -ne 'https')) {
    throw 'Use HTTPS for releases and 127.0.0.1 for isolated upgrade tests.'
}
$key = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
if ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key)) -notmatch '^untrusted comment:') {
    throw 'Expected a Tauri updater public key.'
}
$config = @{
    bundle = @{ createUpdaterArtifacts = $true; windows = @{ allowDowngrades = $false } }
    plugins = @{ updater = @{
        pubkey = $key
        endpoints = @($Endpoint)
        requireSignedVersion = $true
        windows = @{ installMode = 'passive' }
    } }
}
if ($LoopbackTest) { $config.plugins.updater.dangerousInsecureTransportProtocol = $true }
$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding utf8
