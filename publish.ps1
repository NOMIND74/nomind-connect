#requires -Version 5.1
<#
Publish NOMIND Connect to GitHub using an explicit allowlist.

Only files in the allowlist below are staged. Anything else is refused,
even if it somehow appears in the working tree. Then scan-secrets.ps1 runs
against the staged content and the commit is aborted on any finding.

Examples:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1 -Message "fix: ping cache"
  powershell -NoProfile -ExecutionPolicy Bypass -File .\publish.ps1 -Message "release: 1.0.1" -Push
#>
param(
    [string]$Message,
    [switch]$Push,
    [switch]$SkipScan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootName = Split-Path -Leaf $root

function Stop-Publish([string]$text) {
    Write-Host ('publish: ' + $text) -ForegroundColor Red
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

Push-Location $root
try {
    if (!(Test-Path (Join-Path $root '.git'))) {
        Stop-Publish 'not a git repository - run "git init" first'
    }

    # --- allowlist: exact paths (relative, forward slashes) ---
    $allowedFiles = @(
        '.gitignore',
        '.gitattributes',
        'NOMINDConnect.ps1',
        'engine.ps1',
        'NOMINDGuard.ps1',
        'NOMINDStop.ps1',
        'NOMINDConnect.cmd',
        'NOMINDConnect.vbs',
        'NOMINDGuard.vbs',
        'build-installer.ps1',
        'publish.ps1',
        'scan-secrets.ps1',
        'release.ps1',
        'version.txt',
        'version.json',
        'README.md',
        'nomind.ico',
        'nomind.png',
        'installer/installer.nsi',
        'servers.sample.json',
        'settings.sample.json'
    )

    # --- allowlist: globs ---
    $allowedGlobs = @(
        'fonts/*',
        'tools/*',
        'tools/**/*',
        '.github/*',
        '.github/**/*',
        '.opencode/agents/*.md'
    )

    function Test-Allowed([string]$rel) {
        if ($allowedFiles -contains $rel) { return $true }
        foreach ($g in $allowedGlobs) {
            if ($rel -like $g) { return $true }
        }
        return $false
    }

    function Test-Forbidden([string]$rel) {
        if ($rel -match '(^|/)(servers|settings)\.json$') { return $true }
        if ($rel -match '(^|/)domains\.txt$') { return $true }
        if ($rel -match '^(runtime|dist|installer/stage)/') { return $true }
        if ($rel -match '\.(exe|zip|7z|rar|log|bak|tmp|pem|key|pfx)$') { return $true }
        if ($rel -match '(^|/)\.env(\.|$)') { return $true }
        return $false
    }

    # --- clear the index, never touch the working tree ---
    $hasHead = $false
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & git rev-parse --verify --quiet HEAD 2>$null | Out-Null
        $hasHead = ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if ($hasHead) { & git reset -q }

    # --- collect allowed files that actually exist ---
    $toAdd = New-Object System.Collections.ArrayList
    foreach ($f in $allowedFiles) {
        if (Test-Path -LiteralPath (Join-Path $root $f)) { [void]$toAdd.Add($f) }
    }
    foreach ($g in $allowedGlobs) {
        Get-ChildItem -Path (Join-Path $root $g) -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
            [void]$toAdd.Add($rel)
        }
    }
    $toAdd = @($toAdd | Sort-Object -Unique)

    if ($toAdd.Count -eq 0) { Stop-Publish 'nothing to publish' }

    & git add -- $toAdd
    if ($LASTEXITCODE -ne 0) { Stop-Publish 'git add failed' }

    # --- verify staged content against the allowlist ---
    $staged = @(& git diff --cached --name-only --diff-filter=ACMR | Where-Object { $_ })
    foreach ($rel in $staged) {
        $rel = $rel -replace '\\', '/'
        if ((Test-Forbidden $rel) -or !(Test-Allowed $rel)) {
            & git reset -q
            Stop-Publish ('refusing to publish forbidden file: ' + $rel)
        }
    }

    if ($staged.Count -eq 0) {
        Write-Host 'publish: no changes to commit'
        Pop-Location
        exit 0
    }

    # --- secrets ---
    if (!$SkipScan) {
        & (Join-Path $root 'scan-secrets.ps1') -Staged -Root $root
        if ($LASTEXITCODE -ne 0) {
            & git reset -q
            Stop-Publish 'secret scan failed - commit aborted'
        }
    }

    # --- identity (local to this repo only) ---
    $uname = (& git config user.name) 2>$null
    if (!$uname) { & git config user.name 'NOMIND Connect' }
    $umail = (& git config user.email) 2>$null
    if (!$umail) { & git config user.email 'nomind-connect@users.noreply.github.com' }

    if (!$Message) { $Message = 'update ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') }

    & git commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { Stop-Publish 'git commit failed' }
    Write-Host ('publish: committed ' + $staged.Count + ' file(s): ' + $Message) -ForegroundColor Green

    if ($Push) {
        $hasUpstream = $false
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
            $hasUpstream = ($LASTEXITCODE -eq 0)
        } finally {
            $ErrorActionPreference = 'Stop'
        }
        if (!$hasUpstream) {
            & git push -u origin HEAD
        } else {
            & git push
        }
        if ($LASTEXITCODE -ne 0) { Stop-Publish 'git push failed' }
        Write-Host 'publish: pushed' -ForegroundColor Green
    }
} finally {
    Pop-Location -ErrorAction SilentlyContinue
}
