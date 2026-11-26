$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'engine.ps1')

# Ostanovka pered obnovleniem/udaleniem: zakryvaem GUI, gastim xray, snimaem proksi.

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*NOMINDConnect.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Sleep -Milliseconds 800

Stop-Engine | Out-Null
Disable-SystemProxy | Out-Null
Write-Output 'stopped'
