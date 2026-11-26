#requires -Version 5.1
<#
Secret scanner for the NOMIND Connect repository.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-secrets.ps1 -Staged
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-secrets.ps1 -Path README.md, engine.ps1

Exit codes: 0 = clean, 1 = findings, 2 = bad usage.

A line may be exempted with the marker:  secret-scan:ignore
#>
param(
    [switch]$Staged,
    [string[]]$Path,
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if (!$Root) { $Root = (Get-Location).Path }
$Root = (Resolve-Path -LiteralPath $Root).Path

$rules = @(
    @{ Name = 'VPN share link';      Pattern = '(?i)\b(?:vless|trojan|hysteria2?|tuic)://[^\s"''<>]{4,}@[^\s"''<>]{2,}:\d{2,5}|\bvmess://[A-Za-z0-9+/=]{16,}|\bss://[A-Za-z0-9+/=_\-]{12,}' },
    @{ Name = 'UUID';                Pattern = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b' },
    @{ Name = 'GitHub token';        Pattern = '\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b' },
    @{ Name = 'GitHub fine-grained'; Pattern = '\bgithub_pat_[A-Za-z0-9_]{22,}\b' },
    @{ Name = 'Polza API key';       Pattern = '\bpza_[A-Za-z0-9_\-]{10,}\b' },
    @{ Name = 'OpenAI-style key';    Pattern = '\bsk-[A-Za-z0-9_\-]{20,}\b' },
    @{ Name = 'AWS access key';      Pattern = '\bAKIA[0-9A-Z]{16}\b' },
    @{ Name = 'Private key block';   Pattern = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' },
    @{ Name = 'Subscription URL';    Pattern = '(?i)https?://[^\s"''<>]+/(?:sub|subscription|subs)/[A-Za-z0-9_\-]{8,}' },
    @{ Name = 'HWID value';          Pattern = '(?i)"hwid"\s*:\s*"[A-Za-z0-9+/=_\-]{8,}"' },
    @{ Name = 'Public IP with port'; Pattern = '\b(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}\b' }
)

function Test-PrivateIP([string]$m) {
    if ($m -match '^(?:127\.|10\.|192\.168\.|169\.254\.|0\.0\.0\.0)') { return $true }
    if ($m -match '^172\.(?:1[6-9]|2[0-9]|3[01])\.') { return $true }
    if ($m -match '^100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') { return $true }
    return $false
}

$files = New-Object System.Collections.ArrayList

if ($Staged) {
    Push-Location $Root
    try {
        $names = @(& git diff --cached --name-only --diff-filter=ACMR)
        foreach ($n in $names) { if ($n) { [void]$files.Add(($n -replace '\\', '/')) } }
    } finally { Pop-Location }
}
elseif ($Path -and $Path.Count -gt 0) {
    foreach ($p in $Path) {
        $full = $p
        if (![IO.Path]::IsPathRooted($full)) { $full = Join-Path $Root $p }
        if (Test-Path -LiteralPath $full -PathType Container) {
            Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$files.Add(($_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'))
            }
        } elseif (Test-Path -LiteralPath $full) {
            $rel = $full
            if ($full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
                $rel = $full.Substring($Root.Length).TrimStart('\', '/')
            }
            [void]$files.Add(($rel -replace '\\', '/'))
        }
    }
}
else {
    Write-Host 'secret-scan: nothing to scan (use -Staged or -Path)'
    exit 2
}

$unique = @($files | Sort-Object -Unique)
if ($unique.Count -eq 0) {
    Write-Host 'secret-scan: no files to scan'
    exit 0
}

$findings = New-Object System.Collections.ArrayList
$seen = @{}

foreach ($rel in $unique) {
    $full = Join-Path $Root ($rel -replace '/', '\')
    $bytes = $null
    if (Test-Path -LiteralPath $full) {
        $bytes = [IO.File]::ReadAllBytes($full)
    } else {
        Push-Location $Root
        try {
            $raw = @(& git show (':' + $rel) 2>$null)
            if ($LASTEXITCODE -ne 0) { $raw = @() }
        } finally { Pop-Location }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($raw -join "`n"))
    }
    if (!$bytes -or $bytes.Length -eq 0) { continue }
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { continue }   # binary file, skipped

    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match 'secret-scan:ignore') { continue }
        foreach ($rule in $rules) {
            $ms = [regex]::Matches($line, $rule.Pattern)
            if ($ms.Count -eq 0) { continue }
            foreach ($m in $ms) {
                if ($rule.Name -eq 'Public IP with port' -and (Test-PrivateIP $m.Value)) { continue }
                $key = $rel + '|' + $rule.Name + '|' + $i
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $preview = $m.Value
                if ($preview.Length -gt 10) { $preview = $preview.Substring(0, 10) + '...' }
                [void]$findings.Add([pscustomobject]@{
                    File = $rel; Line = ($i + 1); Rule = $rule.Name; Preview = $preview
                })
            }
        }
    }
}

Write-Host ('secret-scan: checked ' + $unique.Count + ' file(s)')

if ($findings.Count -eq 0) {
    Write-Host 'secret-scan: clean' -ForegroundColor Green
    exit 0
}

foreach ($f in $findings) {
    Write-Host ('  ' + $f.File + ':' + $f.Line + '  [' + $f.Rule + ']  ' + $f.Preview)
}
Write-Host ('secret-scan: ' + $findings.Count + ' finding(s) - do NOT push') -ForegroundColor Red
exit 1
