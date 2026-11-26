$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'engine.ps1')

# Ostanovka pered obnovleniem/udaleniem: zakryvaem GUI, gastim xray, snimaem proksi.

$appScript = Join-Path $PSScriptRoot 'NOMINDConnect.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and (Test-IsOurScript $_.CommandLine $appScript) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Milliseconds 800

Stop-Engine | Out-Null
Disable-SystemProxy | Out-Null
Write-Output 'stopped'
