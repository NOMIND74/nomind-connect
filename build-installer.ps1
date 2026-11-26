param(
    [string]$Makensis = (Join-Path $env:TEMP 'opencode\nsis\nsis-3.11\makensis.exe')
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist\NOMIND Connect'
$inst = Join-Path $root 'installer'
$stage = Join-Path $inst 'stage'

if (!(Test-Path $Makensis)) { throw "Не найден makensis.exe: $Makensis" }

# 1. Свежие скрипты в дистрибутив
Copy-Item (Join-Path $root 'NOMINDConnect.ps1') $dist -Force
Copy-Item (Join-Path $root 'engine.ps1')       $dist -Force
Copy-Item (Join-Path $root 'NOMINDGuard.ps1')  $dist -Force
Copy-Item (Join-Path $root 'NOMINDStop.ps1')   $dist -Force
Copy-Item (Join-Path $root 'NOMINDConnect.vbs') $dist -Force
Copy-Item (Join-Path $root 'NOMINDGuard.vbs')  $dist -Force
Copy-Item (Join-Path $root 'nomind.png')       $dist -Force
Copy-Item (Join-Path $root 'nomind.ico')       $dist -Force

# 2. Staging без логов и рантайма
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item (Join-Path $dist '*') $stage -Recurse -Force
Get-ChildItem (Join-Path $stage 'runtime') -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $stage 'runtime') -Force | Out-Null
Get-ChildItem (Join-Path $stage '*.bak') -Force -ErrorAction SilentlyContinue | Remove-Item -Force

# 2b. Chistye dannye v ustanovke: lichnye podpiski i serverov polzovatelya
# v sborniku byt ne dolzhno - ustanovshik dolzhen stat s pustym spiskom.
[IO.File]::WriteAllText((Join-Path $stage 'servers.json'), '[]', (New-Object Text.UTF8Encoding($false)))
$srcSet = Join-Path $stage 'settings.json'
if (Test-Path $srcSet) {
    $old = Get-Content $srcSet -Raw -Encoding UTF8 | ConvertFrom-Json
    $clean = [ordered]@{
        mode           = $(if ($null -ne $old.mode) { $old.mode } else { 'global' })
        httpPort       = $(if ($old.httpPort) { [int]$old.httpPort } else { 10809 })
        socksPort      = $(if ($old.socksPort) { [int]$old.socksPort } else { 10808 })
        ruDirect       = $(if ($null -ne $old.ruDirect) { [bool]$old.ruDirect } else { $true })
        guardAutostart = $(if ($null -ne $old.guardAutostart) { [bool]$old.guardAutostart } else { $true })
        blockAds       = $(if ($null -ne $old.blockAds) { [bool]$old.blockAds } else { $false })
        closeToTray    = $(if ($null -ne $old.closeToTray) { [bool]$old.closeToTray } else { $true })
        server         = ''
        subs           = @()
    }
    [IO.File]::WriteAllText($srcSet, ($clean | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# 3. Скрипт установщика в UTF-8 с BOM (иначе NSIS не поймёт русский текст)
$nsi = Join-Path $inst 'installer.nsi'
$text = [IO.File]::ReadAllText($nsi, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($nsi, $text, (New-Object Text.UTF8Encoding($true)))

# 4. Компиляция
Push-Location $inst
try {
    & $Makensis '/V2' 'installer.nsi'
    if ($LASTEXITCODE -ne 0) { throw "makensis вернул код $LASTEXITCODE" }
} finally {
    Pop-Location
}

$setup = Join-Path $root 'NOMIND-Connect-Setup.exe'
if (!(Test-Path $setup)) { throw 'Установщик не создан' }

# 5. Портативный архив (та же чистая начинка, без runtime-логов и .bak)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $root 'NOMIND-Connect-portable.zip'
$zipRoot = Join-Path $inst 'ziproot'
if (Test-Path $zipRoot) { Remove-Item $zipRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $zipRoot 'NOMIND Connect') -Force | Out-Null
Copy-Item (Join-Path $stage '*') (Join-Path $zipRoot 'NOMIND Connect') -Recurse -Force
if (Test-Path $zip) { Remove-Item $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($zipRoot, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $zipRoot -Recurse -Force

Get-Item $setup, $zip | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }, LastWriteTime | Format-Table -AutoSize
