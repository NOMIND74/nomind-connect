#requires -Version 5.1
<#
Secret scanner for the NOMIND Connect repository.

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-secrets.ps1 -Staged
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scan-secrets.ps1 -Path README.md, engine.ps1

Exit codes: 0 = clean, 1 = findings, 2 = bad usage.

A line may be exempted with the marker:  secret-scan:ignore <reason>
The reason must be at least 8 characters, so an accidental marker does not
silently hide a real secret.

-Staged reads the blob from the git index (git cat-file blob), not the working
tree: what you see in the commit is exactly what gets scanned.
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
    @{ Name = 'Public IP with port'; Pattern = '\b(?:\d{1,3}\.){3}\d{1,3}:\d{2,5}\b' },
    @{ Name = 'JWT';                 Pattern = '\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b' },
    @{ Name = 'Generic secret value'; Pattern = '(?i)\b(?:api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\s*[:=]\s*["''][^"''{}\$]{16,}["'']' },
    @{ Name = 'Telegram bot token';  Pattern = '\b\d{8,10}:[A-Za-z0-9_\-]{35}\b' }
)

function Test-PrivateIP([string]$m) {
    if ($m -match '^(?:127\.|10\.|192\.168\.|169\.254\.|0\.0\.0\.0)') { return $true }
    if ($m -match '^172\.(?:1[6-9]|2[0-9]|3[01])\.') { return $true }
    if ($m -match '^100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') { return $true }
    return $false
}

function Test-Ignorable([string]$line) {
    $m = [regex]::Match($line, '(?i)secret-scan:ignore\s*(\S{8,})')
    return $m.Success
}

# base64 of a whole subscription or a single link hides it from plain regexes.
function Find-EncodedSecrets([string]$line, [string]$rel, [int]$lineNo, $findings, $seen) {
    $ms = [regex]::Matches($line, '[A-Za-z0-9+/=_\-]{40,}')
    foreach ($m in $ms) {
        $s = $m.Value -replace '-', '+' -replace '_', '/'
        switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
        $decoded = ''
        try { $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s)) } catch { continue }
        if ($decoded -notmatch '(?i)(?:vless|vmess|trojan|hysteria2?|tuic|ss)://|https?://[^\s]+/(?:sub|subscription|subs)/') { continue }
        $key = $rel + '|base64|' + $lineNo
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$findings.Add([pscustomobject]@{
            File = $rel; Line = ($lineNo + 1); Rule = 'Base64-encoded link'; Preview = '<' + $m.Value.Length + ' chars>'
        })
    }
}

$files = New-Object System.Collections.ArrayList
$useIndex = $false

if ($Staged) {
    $useIndex = $true
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
    $bytes = $null
    if ($useIndex) {
        # Scan the exact blob that is staged for commit.
        $tmp = [IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath 'git' -ArgumentList @('cat-file', 'blob', (':' + $rel)) -WorkingDirectory $Root -RedirectStandardOutput $tmp -WindowStyle Hidden -PassThru -Wait
            if ($p.ExitCode -eq 0) { $bytes = [IO.File]::ReadAllBytes($tmp) }
        } catch { $bytes = $null }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    } else {
        $full = Join-Path $Root ($rel -replace '/', '\')
        if (Test-Path -LiteralPath $full) { $bytes = [IO.File]::ReadAllBytes($full) }
    }
    if (!$bytes -or $bytes.Length -eq 0) { continue }

    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) {
        # Binary: still look for link strings and key headers in the raw bytes.
        $latin = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
        foreach ($rule in $rules) {
            $ms = [regex]::Matches($latin, $rule.Pattern)
            if ($ms.Count -eq 0) { continue }
            foreach ($m in $ms) {
                if ($rule.Name -eq 'Public IP with port' -and (Test-PrivateIP $m.Value)) { continue }
                $key = $rel + '|bin|' + $rule.Name
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$findings.Add([pscustomobject]@{
                    File = $rel; Line = 0; Rule = ('binary: ' + $rule.Name); Preview = ('<' + $m.Value.Length + ' chars>')
                })
            }
        }
        continue
    }

    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if (Test-Ignorable $line) { continue }
        foreach ($rule in $rules) {
            $ms = [regex]::Matches($line, $rule.Pattern)
            if ($ms.Count -eq 0) { continue }
            foreach ($m in $ms) {
                if ($rule.Name -eq 'Public IP with port' -and (Test-PrivateIP $m.Value)) { continue }
                $key = $rel + '|' + $rule.Name + '|' + $i
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$findings.Add([pscustomobject]@{
                    File = $rel; Line = ($i + 1); Rule = $rule.Name; Preview = ('<' + $m.Value.Length + ' chars>')
                })
            }
        }
        Find-EncodedSecrets $line $rel $i $findings $seen
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
