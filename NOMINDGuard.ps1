$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms | Out-Null
. (Join-Path $PSScriptRoot 'engine.ps1')

# Guard runs at logon and keeps the Windows proxy consistent with reality.
# If our tunnel is dead, the proxy must be OFF, otherwise the browser sends
# traffic into a dead port and it looks like "the internet disappeared".

$log = Join-Path $script:Run 'guard.log'

function Note([string]$m) {
    try {
        Add-Content -Path $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) -Encoding UTF8
    } catch { }
}

$s = Get-Settings
$port = 10809
if ($s) { $port = [int]$s.httpPort }
$ours = '127.0.0.1:' + $port

# 1) The GUI is gone but xray survived (crash or forced kill during shutdown).
$gui = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*NOMINDConnect.ps1*' } |
    Select-Object -First 1
$engine = Get-EngineProcess
if (!$gui -and $engine) {
    Stop-Engine | Out-Null
    $engine = $null
    Note 'orphan xray stopped (gui is not running)'
}

# 2) Reconcile the system proxy, but only if it points at OUR tunnel port.
$proxy = Get-SystemProxy
$pointsToUs = ([string]$proxy.Server).Trim() -eq $ours
$tunnelUp = ([bool]$engine) -and (Test-LocalPort $port)

if ($proxy.Enable -eq 1 -and $pointsToUs -and !$tunnelUp) {
    Disable-SystemProxy | Out-Null
    Note 'system proxy OFF (tunnel is dead)'
}
elseif ($proxy.Enable -eq 0 -and $tunnelUp) {
    Enable-SystemProxy $port | Out-Null
    Note 'system proxy ON (tunnel is up)'
}
else {
    Note ('nothing to do (proxy=' + $proxy.Enable + ' ours=' + $pointsToUs + ' tunnel=' + $tunnelUp + ')')
}
