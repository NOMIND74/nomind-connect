#requires -Version 5.1
<#
Creates the ECDSA P-256 signing key for NOMIND Connect update manifests.

The private key is stored OUTSIDE the repository, protected with DPAPI for the
current Windows user only:
  %USERPROFILE%\.config\nomind\update-signing-key.bin

The public key is printed as base64 (X || Y). Paste it into updater.ps1
($script:UpdatePubKey). Publishing the public key is safe.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-keygen.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update-keygen.ps1 -Force
#>
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$dir = Join-Path $env:USERPROFILE '.config\nomind'
$file = Join-Path $dir 'update-signing-key.bin'

if ((Test-Path -LiteralPath $file) -and !$Force) {
    throw ('signing key already exists: ' + $file + '  (use -Force to replace it)')
}

if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$ec = [System.Security.Cryptography.ECDsa]::Create()
try {
    $ec.KeySize = 256
    $p = $ec.ExportParameters($true)
    $payload = [ordered]@{
        curve = 'nistP256'
        d     = [Convert]::ToBase64String($p.D)
        x     = [Convert]::ToBase64String($p.Q.X)
        y     = [Convert]::ToBase64String($p.Q.Y)
    } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    [IO.File]::WriteAllBytes($file, $enc)
    $pub = [Convert]::ToBase64String($p.Q.X + $p.Q.Y)
} finally { $ec.Dispose() }

Write-Host ('private key: ' + $file + '  (DPAPI, current user only)')
Write-Host 'public key (paste into updater.ps1 as $script:UpdatePubKey):'
Write-Host $pub
