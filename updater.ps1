#requires -Version 5.1
<#
Signed update channel for NOMIND Connect.

Manifest: version.json published as a GitHub release asset.
Integrity: ECDSA P-256 signature over a fixed text payload, SHA-256 of the
installer inside the signed payload. The private key never ships with the app.

Public key is embedded below. Private key lives in
%USERPROFILE%\.config\nomind\update-signing-key.bin (DPAPI, see tools\update-keygen.ps1).
#>

# Set after the repository exists, e.g. 'someuser/nomind-connect'.
$script:UpdateRepo = 'OWNER/nomind-connect'

# base64(X || Y) of the ECDSA P-256 public key.
$script:UpdatePubKey = '1OzVC4Qr6WO08Pp00fwSgqdODUiRxXgybN5nhPEYsbqNK8ZEe3wHR22sZge77zIMOtuPtfwxYbHVV9+RflnAsA=='

$script:UpdateMaxManifest = 64KB
$script:UpdateMaxInstaller = 256MB

function Get-AppVersion {
    $root = if ($script:Root) { $script:Root } else { $PSScriptRoot }
    $f = Join-Path $root 'version.txt'
    try {
        if (Test-Path -LiteralPath $f) {
            $v = ([IO.File]::ReadAllText($f)).Trim()
            if ($v -match '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $v }
        }
    } catch { }
    return '0.0.0'
}

function Compare-AppVersion([string]$a, [string]$b) {
    $va = $null; $vb = $null
    if (![version]::TryParse(([string]$a).Trim(), [ref]$va)) { $va = [version]'0.0.0' }
    if (![version]::TryParse(([string]$b).Trim(), [ref]$vb)) { $vb = [version]'0.0.0' }
    return $va.CompareTo($vb)
}

# The signature covers exactly this text. Keep it identical in release.ps1.
function Get-UpdatePayload($m) {
    return ([string]$m.version + "`n" + [string]$m.sha256 + "`n" + [string]$m.url + "`n" + [string]$m.published)
}

function Test-ManifestFields($m) {
    if (!$m) { return $false }
    if ([string]$m.version -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }
    if ([string]$m.sha256 -notmatch '^[0-9a-fA-F]{64}$') { return $false }
    if ([string]$m.url -notmatch '^https://') { return $false }
    if ([string]$m.url -notmatch '^https://[A-Za-z0-9._~:/?#\[\]@!$&''()*+,;=%-]+$') { return $false }
    if (([string]$m.url).Length -gt 512) { return $false }
    if ([string]$m.published -notmatch '^\d{4}-\d{2}-\d{2}$') { return $false }
    if ([string]$m.signature -notmatch '^[A-Za-z0-9+/=]{40,200}$') { return $false }
    return $true
}

function Test-UpdateSignature($m) {
    try {
        $sig = [Convert]::FromBase64String([string]$m.signature)
        $pub = [Convert]::FromBase64String($script:UpdatePubKey)
        if ($sig.Length -ne 64 -or $pub.Length -ne 64) { return $false }

        $cp = New-Object System.Security.Cryptography.ECParameters
        $cp.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
        $pt = New-Object System.Security.Cryptography.ECPoint
        $pt.X = [byte[]]$pub[0..31]
        $pt.Y = [byte[]]$pub[32..63]
        $cp.Q = $pt

        $ec = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $ec.ImportParameters($cp)
            $data = [Text.Encoding]::UTF8.GetBytes((Get-UpdatePayload $m))
            return $ec.VerifyData($data, $sig, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        } finally { $ec.Dispose() }
    } catch { return $false }
}

function New-UpdateResult($current) {
    return [pscustomobject]@{
        Ok        = $false
        Available = $false
        Current   = $current
        Version   = ''
        Url       = ''
        Sha256    = ''
        Notes     = ''
        Error     = ''
    }
}

function Get-UpdateResponse([string]$url, [int]$timeoutMs, [long]$maxBytes) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = $timeoutMs
    $req.ReadWriteTimeout = $timeoutMs
    $req.UserAgent = 'NOMIND-Connect-Updater'
    $req.Accept = 'application/json, application/octet-stream'
    $resp = $req.GetResponse()
    try {
        $len = [long]$resp.ContentLength
        if ($len -gt $maxBytes) { throw ('response is too large: ' + $len + ' bytes') }
        $ms = New-Object IO.MemoryStream
        $stream = $resp.GetResponseStream()
        $buf = New-Object byte[] 16384
        $total = 0
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $n
            if ($total -gt $maxBytes) { throw 'response is too large' }
            $ms.Write($buf, 0, $n)
        }
        return $ms.ToArray()
    } finally { $resp.Close() }
}

function Invoke-UpdateCheck {
    $current = Get-AppVersion
    $res = New-UpdateResult $current
    if (!$script:UpdateRepo -or $script:UpdateRepo -match '^OWNER/') {
        $res.Error = 'update channel is not configured'
        return $res
    }
    $res.Ok = $true

    $url = 'https://github.com/' + $script:UpdateRepo + '/releases/latest/download/version.json'
    try {
        $bytes = Get-UpdateResponse $url 12000 $script:UpdateMaxManifest
    } catch {
        $res.Ok = $false
        $res.Error = 'cannot download update manifest: ' + $_.Exception.Message
        return $res
    }

    try {
        $m = ([Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
    } catch {
        $res.Ok = $false
        $res.Error = 'update manifest is not valid JSON'
        return $res
    }

    if (!(Test-ManifestFields $m)) {
        $res.Ok = $false
        $res.Error = 'update manifest has invalid fields'
        return $res
    }
    if (!(Test-UpdateSignature $m)) {
        $res.Ok = $false
        $res.Error = 'update manifest signature is not valid'
        return $res
    }

    $res.Version = [string]$m.version
    $res.Sha256 = ([string]$m.sha256).ToLower()
    $res.Url = [string]$m.url
    $notes = ([string]$m.notes) -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    if ($notes.Length -gt 1500) { $notes = $notes.Substring(0, 1500) + '...' }
    $res.Notes = $notes

    if ((Compare-AppVersion $current $res.Version) -ge 0) {
        $res.Available = $false
        return $res
    }
    $res.Available = $true
    return $res
}

function Save-UpdateInstaller($u) {
    if (!$u -or !$u.Url -or !$u.Sha256) { throw 'no update to download' }
    if ([string]$u.Url -notmatch '^https://') { throw 'refusing non-https update url' }
    if ([string]$u.Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'invalid installer hash' }

    $ver = ([string]$u.Version) -replace '[^0-9.]', ''
    $dst = Join-Path $env:TEMP ('NOMIND-Connect-Setup-' + $ver + '.exe')
    Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create([string]$u.Url)
    $req.Timeout = 60000
    $req.ReadWriteTimeout = 60000
    $req.UserAgent = 'NOMIND-Connect-Updater'
    $resp = $req.GetResponse()
    try {
        $len = [long]$resp.ContentLength
        if ($len -gt $script:UpdateMaxInstaller) { throw 'installer is too large' }
        $fs = [IO.File]::Create($dst)
        try {
            $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            $total = 0
            while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                $total += $n
                if ($total -gt $script:UpdateMaxInstaller) { throw 'installer is too large' }
                $fs.Write($buf, 0, $n)
            }
        } finally { $fs.Dispose() }
    } finally { $resp.Close() }

    $hash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne ([string]$u.Sha256).ToLower()) {
        Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        throw 'installer SHA-256 mismatch - download rejected'
    }
    return $dst
}
