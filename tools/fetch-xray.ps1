#requires -Version 5.1
<#
Downloads Xray-core for Windows x64 into .\bin and verifies the pinned SHA-256.
The binary and geo datasets are intentionally NOT stored in git.

Pinned release: v26.11.9
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\fetch-xray.ps1
#>
param(
    [string]$Version = 'v26.11.9',
    [string]$Sha256 = '1262522266337b824f07beb8e1375786b437683b3890105469088f8e17e0a69d',
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (!$Root) { $Root = Split-Path -Parent $PSScriptRoot }

$bin = Join-Path $Root 'bin'
$url = 'https://github.com/XTLS/Xray-core/releases/download/' + $Version + '/Xray-windows-64.zip'
$tmp = Join-Path $env:TEMP ('xray-' + $Version + '.zip')

Write-Host ('downloading ' + $url)
& curl.exe -L --fail --silent --show-error -o $tmp $url
if ($LASTEXITCODE -ne 0) { throw 'download failed' }

$hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
Write-Host ('sha256 ' + $hash)
if ($hash -ne $Sha256.ToLower()) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw ('SHA-256 mismatch: expected ' + $Sha256 + ', got ' + $hash)
}

New-Item -ItemType Directory -Path $bin -Force | Out-Null
$zipDir = Join-Path $env:TEMP ('xray-' + $Version)
if (Test-Path -LiteralPath $zipDir) { Remove-Item -LiteralPath $zipDir -Recurse -Force }
Expand-Archive -LiteralPath $tmp -DestinationPath $zipDir -Force
foreach ($n in @('xray.exe', 'geoip.dat', 'geosite.dat')) {
    $src = Join-Path $zipDir $n
    if (!(Test-Path -LiteralPath $src)) { throw ('missing in archive: ' + $n) }
    Copy-Item -LiteralPath $src -Destination (Join-Path $bin $n) -Force
}

Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zipDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'bin\xray.exe, bin\geoip.dat, bin\geosite.dat are ready'
