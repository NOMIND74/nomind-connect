#requires -Version 5.1
<#
Publishes a signed NOMIND Connect release.

Steps:
  1. build the installer (build-installer.ps1) with the version from version.txt;
  2. compute SHA-256 of the installer;
  3. sign the manifest payload with the ECDSA P-256 private key (DPAPI);
  4. commit version.txt + version.json through publish.ps1;
  5. create a GitHub release and upload the installer and version.json.

The private key must exist:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-keygen.ps1

Examples:
  .\release.ps1 -Notes "Faster ping, shutdown fix"
  .\release.ps1 -Version 1.0.2 -Notes "..." -Draft
#>
param(
    [string]$Version,
    [string]$Notes,
    [switch]$Draft,
    [switch]$SkipBuild,
    [switch]$SkipCommit
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$root = $PSScriptRoot
$setup = Join-Path $root 'NOMIND-Connect-Setup.exe'
$manifestFile = Join-Path $root 'version.json'
$keyFile = Join-Path $env:USERPROFILE '.config\nomind\update-signing-key.bin'

function Fail([string]$text) { throw ('release: ' + $text) }

if (!$Version) {
    $Version = ([IO.File]::ReadAllText((Join-Path $root 'version.txt'))).Trim()
}
if ($Version -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { Fail ('bad version: ' + $Version) }

# --- repository ---
$gh = 'gh'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$repo = ''
try { $repo = (& $gh repo view --json nameWithOwner --jq .nameWithOwner 2>$null | Out-String).Trim() } catch { }
if (!$repo -or $repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Fail 'cannot detect GitHub repository (run gh auth login first)' }

$updater = Join-Path $root 'updater.ps1'
$up = [IO.File]::ReadAllText($updater)
if ($up -match "\`$script:UpdateRepo\s*=\s*'OWNER/") {
    Fail ("set `$script:UpdateRepo = '" + $repo + "' in updater.ps1 before releasing")
}

# --- build ---
if (!$SkipBuild) {
    & (Join-Path $root 'build-installer.ps1')
    if ($LASTEXITCODE -ne 0) { Fail 'build failed' }
}
if (!(Test-Path -LiteralPath $setup)) { Fail ('installer not found: ' + $setup) }

$sha = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLower()
$url = 'https://github.com/' + $repo + '/releases/download/v' + $Version + '/NOMIND-Connect-Setup.exe'
$published = Get-Date -Format 'yyyy-MM-dd'
if (!$Notes) { $Notes = 'NOMIND Connect ' + $Version }

# --- sign (payload must match Get-UpdatePayload in updater.ps1) ---
if (!(Test-Path -LiteralPath $keyFile)) {
    Fail ('signing key not found: ' + $keyFile + '  (run tools\update-keygen.ps1)')
}
$enc = [IO.File]::ReadAllBytes($keyFile)
$json = [Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'CurrentUser'))
$k = $json | ConvertFrom-Json

$cp = New-Object System.Security.Cryptography.ECParameters
$cp.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
$pt = New-Object System.Security.Cryptography.ECPoint
$pt.X = [Convert]::FromBase64String([string]$k.x)
$pt.Y = [Convert]::FromBase64String([string]$k.y)
$cp.Q = $pt
$cp.D = [Convert]::FromBase64String([string]$k.d)

$ec = [System.Security.Cryptography.ECDsa]::Create()
try {
    $ec.ImportParameters($cp)
    $payload = $Version + "`n" + $sha + "`n" + $url + "`n" + $published
    $sig = $ec.SignData([Text.Encoding]::UTF8.GetBytes($payload), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
} finally { $ec.Dispose() }

$manifest = [ordered]@{
    version   = $Version
    url       = $url
    sha256    = $sha
    published = $published
    notes     = $Notes
    signature = [Convert]::ToBase64String($sig)
}
[IO.File]::WriteAllText($manifestFile, ($manifest | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $root 'version.txt'), ($Version + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host ('release: ' + $Version + '  sha256=' + $sha)

# --- commit the manifest and version ---
if (!$SkipCommit) {
    & (Join-Path $root 'publish.ps1') -Message ('release: v' + $Version) -Push
    if ($LASTEXITCODE -ne 0) { Fail 'publish failed' }
}

# --- GitHub release ---
$relArgs = @('release', 'create', ('v' + $Version), $setup, $manifestFile,
             '--title', ('NOMIND Connect ' + $Version), '--notes', $Notes)
if ($Draft) { $relArgs += '--draft' }
& $gh @relArgs
if ($LASTEXITCODE -ne 0) { Fail 'gh release create failed' }

Write-Host ('release: published v' + $Version + ' to ' + $repo) -ForegroundColor Green
