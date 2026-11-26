param(
    [string]$Makensis = (Join-Path $env:TEMP 'opencode\nsis2\nsis-3.11\makensis.exe')
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist\NOMIND Connect'
$inst = Join-Path $root 'installer'
$stage = Join-Path $inst 'stage'

if (!(Test-Path $Makensis)) { throw "Не найден makensis.exe: $Makensis" }
# makensis.exe в корне — это лаунчер, ему нужен Bin\makensis.exe
$mkBin = Join-Path (Split-Path -Parent $Makensis) 'Bin\makensis.exe'
if (!(Test-Path $mkBin)) { throw "NSIS распакован не полностью (нет $mkBin). Перекачайте nsis-3.11.zip." }

# 0. Версия из version.txt — единый источник для установщика и приложения
$version = ([IO.File]::ReadAllText((Join-Path $root 'version.txt'))).Trim()
if ($version -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { throw "Плохая версия в version.txt: $version" }
$version4 = $version + '.0'

# 1. Свежие скрипты в дистрибутив
Copy-Item (Join-Path $root 'NOMINDConnect.ps1') $dist -Force
Copy-Item (Join-Path $root 'engine.ps1')       $dist -Force
Copy-Item (Join-Path $root 'updater.ps1')      $dist -Force
Copy-Item (Join-Path $root 'NOMINDGuard.ps1')  $dist -Force
Copy-Item (Join-Path $root 'NOMINDStop.ps1')   $dist -Force
Copy-Item (Join-Path $root 'NOMINDConnect.vbs') $dist -Force
Copy-Item (Join-Path $root 'NOMINDGuard.vbs')  $dist -Force
Copy-Item (Join-Path $root 'version.txt')      $dist -Force
Copy-Item (Join-Path $root 'nomind.png')       $dist -Force
Copy-Item (Join-Path $root 'nomind.ico')       $dist -Force

# 2. Staging без логов и рантайма
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item (Join-Path $dist '*') $stage -Recurse -Force
Get-ChildItem (Join-Path $stage 'runtime') -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $stage 'runtime') -Force | Out-Null
Get-ChildItem (Join-Path $stage '*.bak') -Force -ErrorAction SilentlyContinue | Remove-Item -Force

# 2a. Личные данные не входят в payload установщика вообще. Иначе обновление
# поверх установленной версии затёрло бы серверы, настройки и список сайтов.
foreach ($dataFile in @('servers.json', 'settings.json', 'domains.txt')) {
    Remove-Item (Join-Path $stage $dataFile) -Force -ErrorAction SilentlyContinue
}

# 2b. Значения по умолчанию для чистой установки. Лежат отдельно от payload:
# установщик кладёт их только если файла ещё нет.
$defaults = Join-Path $inst 'defaults'
if (Test-Path $defaults) { Remove-Item $defaults -Recurse -Force }
New-Item -ItemType Directory -Path $defaults | Out-Null

[IO.File]::WriteAllText((Join-Path $defaults 'servers.json'), '[]', (New-Object Text.UTF8Encoding($false)))
$sampleDom = Join-Path $root 'domains.sample.txt'
if (Test-Path -LiteralPath $sampleDom) {
    Copy-Item -LiteralPath $sampleDom -Destination (Join-Path $defaults 'domains.txt') -Force
} else {
    [IO.File]::WriteAllText((Join-Path $defaults 'domains.txt'), '', (New-Object Text.UTF8Encoding($false)))
}

# настройки по умолчанию: режим и порты берём из текущих, но без личных полей
$srcSet = Join-Path $dist 'settings.json'
$clean = [ordered]@{
    mode           = 'global'
    httpPort       = 10809
    socksPort      = 10808
    ruDirect       = $true
    guardAutostart = $true
    blockAds       = $false
    closeToTray    = $true
    checkUpdates   = $true
    server         = ''
    subs           = @()
}
if (Test-Path -LiteralPath $srcSet) {
    try {
        $old = Get-Content $srcSet -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($old.mode -eq 'smart') { $clean.mode = 'smart' }
        if ($old.httpPort) { $clean.httpPort = [int]$old.httpPort }
        if ($old.socksPort) { $clean.socksPort = [int]$old.socksPort }
        if ($null -ne $old.ruDirect) { $clean.ruDirect = [bool]$old.ruDirect }
        if ($null -ne $old.guardAutostart) { $clean.guardAutostart = [bool]$old.guardAutostart }
        if ($null -ne $old.blockAds) { $clean.blockAds = [bool]$old.blockAds }
        if ($null -ne $old.closeToTray) { $clean.closeToTray = [bool]$old.closeToTray }
        if ($null -ne $old.checkUpdates) { $clean.checkUpdates = [bool]$old.checkUpdates }
    } catch { }
}
[IO.File]::WriteAllText((Join-Path $defaults 'settings.json'), ($clean | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

# 3. Скрипт установщика в UTF-8 с BOM (иначе NSIS не поймёт русский текст)
$nsi = Join-Path $inst 'installer.nsi'
$text = [IO.File]::ReadAllText($nsi, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($nsi, $text, (New-Object Text.UTF8Encoding($true)))

# 4. Компиляция
Push-Location $inst
try {
    & $Makensis '/V2' ('/DAPPVERSION=' + $version) ('/DAPPVERSION4=' + $version4) 'installer.nsi'
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
# портативная сборка — как чистая установка: кладём данные по умолчанию
Copy-Item (Join-Path $defaults '*') (Join-Path $zipRoot 'NOMIND Connect') -Force
if (Test-Path $zip) { Remove-Item $zip -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($zipRoot, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $zipRoot -Recurse -Force

Get-Item $setup, $zip | Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }, LastWriteTime | Format-Table -AutoSize
