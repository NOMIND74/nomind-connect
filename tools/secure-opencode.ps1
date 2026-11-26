#requires -Version 5.1
<#
Moves the Polza API key out of opencode.json into the POLZA_API_KEY
user environment variable.

Run this AFTER rotating the key at https://polza.ai: the old key was exposed
in plain text and must be considered compromised.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\secure-opencode.ps1 -ApiKey pza_NEW_KEY

Then restart OpenCode so it picks up the environment variable.
#>
param(
    [Parameter(Mandatory = $true)][string]$ApiKey
)

$ErrorActionPreference = 'Stop'

if ($ApiKey -notmatch '^[A-Za-z0-9_\-]{20,}$') {
    throw 'API key looks invalid (expected at least 20 chars: letters, digits, _ or -)'
}

$cfg = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
if (!(Test-Path -LiteralPath $cfg)) { throw ('config not found: ' + $cfg) }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $cfg -Destination ($cfg + '.bak-' + $stamp) -Force
Write-Host ('backup: ' + $cfg + '.bak-' + $stamp)

$json = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
if (!$json.provider -or !$json.provider.polza -or !$json.provider.polza.options) {
    throw 'provider.polza.options not found in opencode.json'
}

$json.provider.polza.options.apiKey = '{env:POLZA_API_KEY}'
$text = $json | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($cfg, $text, (New-Object Text.UTF8Encoding($false)))

[Environment]::SetEnvironmentVariable('POLZA_API_KEY', $ApiKey, 'User')
[Environment]::SetEnvironmentVariable('POLZA_API_KEY', $ApiKey, 'Process')

Write-Host 'opencode.json now references {env:POLZA_API_KEY}'
Write-Host 'POLZA_API_KEY is stored in the current user environment (HKCU), not in the repo'
Write-Host 'Restart OpenCode to apply.'
