param(
    [string]$Action = '',
    [string]$Server = '',
    [string]$OutFile = '',
    [string]$Url = '',
    [string]$Sha = '',
    [string]$Ver = '',
    [int]$Part = 0,
    [int]$Parts = 1
)

$ErrorActionPreference = 'Stop'

$script:Root = $PSScriptRoot

# Dannye: ryadom s programmoi (portativnyy rezhim). Esli papka tolko dlya chteniya
# (ustanovka v Program Files) - perenosim dannye v %APPDATA%\NOMIND Connect.
$script:Data = $script:Root
$canWrite = $false
try {
    $probe = Join-Path $script:Root ('.wt-' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($probe, 'ok')
    Remove-Item $probe -Force -ErrorAction Stop
    $canWrite = $true
} catch { $canWrite = $false }
if (!$canWrite) {
    $script:Data = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'NOMIND Connect'
}
if (!(Test-Path $script:Data)) { New-Item -ItemType Directory -Force -Path $script:Data | Out-Null }

$script:Bin  = Join-Path $script:Root 'bin'
$script:Run  = Join-Path $script:Data 'runtime'
$script:Exe  = Join-Path $script:Bin 'xray.exe'
# Polnyj put: inache curl ishetsya v PATH i tekushem kataloge, i podmenennyj
# curl.exe ryadom s programmoj mog by perehnvat vyzov.
$script:Curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$script:CfgF = Join-Path $script:Data 'servers.json'
$script:SetF = Join-Path $script:Data 'settings.json'
$script:DomF = Join-Path $script:Data 'domains.txt'

# pervyy zapusk posle ustanovki: podsevaem dannye iz papki programmy
foreach ($seed in @('servers.json', 'domains.txt', 'settings.json')) {
    $dstSeed = Join-Path $script:Data $seed
    $srcSeed = Join-Path $script:Root $seed
    if (!(Test-Path $dstSeed) -and (Test-Path $srcSeed)) {
        try { Copy-Item $srcSeed $dstSeed -Force } catch { }
    }
}

if (!(Test-Path $script:Run)) { New-Item -ItemType Directory -Force -Path $script:Run | Out-Null }

# ---------- files ----------

function Read-Utf8([string]$p) {
    if (!(Test-Path $p)) { return $null }
    return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
}

function Write-Utf8([string]$p, [string]$text) {
    [IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding($false)))
}

function Get-Servers {
    $raw = Read-Utf8 $script:CfgF
    if (!$raw) { return @() }
    $arr = $raw | ConvertFrom-Json
    return @($arr)
}

function Save-Servers($list) {
    $arr = @($list)
    $text = if ($arr.Count -eq 0) { '[]' } else { $arr | ConvertTo-Json -Depth 8 }
    Write-Utf8 $script:CfgF $text
}

function Get-Settings {
    $raw = Read-Utf8 $script:SetF
    if (!$raw) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Save-Settings($s) {
    Write-Utf8 $script:SetF ($s | ConvertTo-Json -Depth 8)
}

function Get-Domains {
    $raw = Read-Utf8 $script:DomF
    if (!$raw) { return @() }
    return @($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and !$_.Trim().StartsWith('#') } | ForEach-Object { $_.Trim() })
}

function Save-Domains([string[]]$d) {
    Write-Utf8 $script:DomF (($d -join "`r`n") + "`r`n")
}

function Get-ServerKey($n) { return ($n.host + ':' + $n.port) }

function Find-Server([string]$key, $list) {
    foreach ($n in $list) { if ((Get-ServerKey $n) -eq $key) { return $n } }
    return $null
}

# ---------- link parsing ----------

# flag emodzi (regionalnye indikatory) -> dve bukvy strany. Nuzhno tolko pervaa para.
function Get-FlagCode([string]$s) {
    if (!$s) { return '' }
    $code = ''
    $i = 0
    for ($k = 0; $k -lt 2; $k++) {
        if ($i + 1 -ge $s.Length) { break }
        $cp = [char]::ConvertToUtf32($s, $i)
        if ($cp -lt 0x1F1E6 -or $cp -gt 0x1F1FF) { break }
        $code += [char]($cp - 0x1F1E6 + 65)
        $i += 2
    }
    if ($code.Length -ne 2) { return '' }
    return $code
}

# Chistoe imya uzla: flagi ostavlyaem (po nim risuem ikonku strany), a prochie
# emodzi ubiraem - shrift ikh ne risuet, i oni prevrashchayutsya v kvadratiki.
function Clear-NodeName([string]$s) {
    if (!$s) { return '' }
    $t = $s.Trim()
    $sb = New-Object Text.StringBuilder
    $i = 0
    $atStart = $true
    while ($i -lt $t.Length) {
        $cp = [char]::ConvertToUtf32($t, $i)
        $len = if ($cp -gt 0xFFFF) { 2 } else { 1 }
        $isFlag = ($cp -ge 0x1F1E6 -and $cp -le 0x1F1FF)
        $drop = $false
        if ($isFlag) {
            if (!$atStart) { $drop = $true }
        } elseif (($cp -ge 0x1F000 -and $cp -le 0x1FAFF) -or ($cp -ge 0x2190 -and $cp -le 0x2BFF) -or $cp -eq 0xFE0F -or $cp -eq 0x200D) {
            $drop = $true
        } else {
            if ($cp -ne 0x20 -and $cp -ne 0x09) { $atStart = $false }
        }
        if (!$drop) { [void]$sb.Append($t.Substring($i, $len)) }
        $i += $len
    }
    $r = ($sb.ToString() -replace '\s+', ' ').Trim()
    $r = $r -replace '^[\-\u00B7\u2013\u2014\s]+', ''
    return $r
}

# ubiraem flagi iz nachala imeni - oni uzhe vyvedeny otdelnoy ikonkoy
function Strip-NodeFlags([string]$s) {
    if (!$s) { return '' }
    $i = 0
    while ($i -lt $s.Length) {
        $cp = [char]::ConvertToUtf32($s, $i)
        if ($cp -ge 0x1F1E6 -and $cp -le 0x1F1FF) { $i += 2; continue }
        break
    }
    return ($s.Substring($i) -replace '^[\s\uFE0F]+', '')
}

function ConvertFrom-VlessLink([string]$link) {
    $link = $link.Trim()
    if (!$link.StartsWith('vless://')) { throw 'Only vless:// links are supported for now' }
    $body = $link.Substring(8)
    $hash = ''
    $i = $body.IndexOf('#')
    if ($i -ge 0) { $hash = $body.Substring($i + 1); $body = $body.Substring(0, $i) }
    $q = ''
    $i = $body.IndexOf('?')
    if ($i -ge 0) { $q = $body.Substring($i + 1); $body = $body.Substring(0, $i) }
    $at = $body.LastIndexOf('@')
    if ($at -lt 0) { throw 'Bad link: no @' }
    $uuid = [Uri]::UnescapeDataString($body.Substring(0, $at).Trim('/'))
    $hp = $body.Substring($at + 1)
    $colon = $hp.LastIndexOf(':')
    if ($colon -lt 0) { throw 'Bad link: no port' }
    $h = $hp.Substring(0, $colon).Trim('[', ']')
    $p = [int]$hp.Substring($colon + 1)

    # sluzhebnye uzly (0.0.0.0:1) i nulevoy UUID - eto zaglushki panelej, a ne servery
    if (!$h -or $h -eq '0.0.0.0' -or $h -eq '127.0.0.1' -or $h -eq '::' -or $h -eq 'localhost') { throw 'служебный узел вместо сервера' }
    if ($p -le 1 -or $p -gt 65535) { throw 'неверный порт сервера' }
    # host uhodit v argumenty dochernih processov i v konfig: tolko imya/IP,
    # nikakih kavychek i probelov (inache mozhno podsunut lishnij argument)
    if ($h -notmatch '^[A-Za-z0-9._\-:\[\]]+$') { throw 'недопустимый адрес сервера' }
    $uhex = $uuid -replace '[^0-9a-fA-F]', ''
    if (!$uhex -or $uhex -match '^0+$') { throw 'нулевой UUID вместо сервера' }

    $par = @{}
    if ($q) {
        foreach ($pair in $q.Split('&')) {
            if (!$pair) { continue }
            $kv = $pair.Split('=', 2)
            $k = [Uri]::UnescapeDataString($kv[0])
            $v = ''
            if ($kv.Count -gt 1) { $v = [Uri]::UnescapeDataString($kv[1]) }
            $par[$k] = $v
        }
    }

    $name = if ($hash) { Clear-NodeName ([Uri]::UnescapeDataString($hash)) } else { Clear-NodeName $h }
    $net = if ($par['type']) { $par['type'] } else { 'tcp' }
    $node = [ordered]@{
        name     = $name
        host     = $h
        port     = $p
        uuid     = $uuid
        flow     = $par['flow']
        sni      = $par['sni']
        pbk      = $par['pbk']
        sid      = $par['sid']
        fp       = $par['fp']
        network  = $net
        path     = $par['path']
        hostHdr  = $par['host']
        mode     = $par['mode']
        serviceName = $par['serviceName']
        provider = 'manual'
        enabled  = $true
    }
    if (!$node.sni) { $node.sni = $par['host'] }
    if (!$node.fp) { $node.fp = 'chrome' }
    return [pscustomobject]$node
}

function ConvertTo-VlessLink($n) {
    $pairs = New-Object System.Collections.ArrayList
    $net = if ($n.network) { [string]$n.network } else { 'tcp' }
    [void]$pairs.Add('type=' + $net)
    if ($n.pbk) { [void]$pairs.Add('security=reality') }
    elseif ($n.security) { [void]$pairs.Add('security=' + $n.security) }
    else { [void]$pairs.Add('security=none') }
    [void]$pairs.Add('encryption=none')
    if ($n.flow) { [void]$pairs.Add('flow=' + $n.flow) }
    if ($n.sni) { [void]$pairs.Add('sni=' + $n.sni) }
    if ($n.fp) { [void]$pairs.Add('fp=' + $n.fp) }
    if ($n.pbk) { [void]$pairs.Add('pbk=' + $n.pbk) }
    if ($n.sid) { [void]$pairs.Add('sid=' + $n.sid) }
    if ($n.path) { [void]$pairs.Add('path=' + [Uri]::EscapeDataString([string]$n.path)) }
    if ($n.hostHdr) { [void]$pairs.Add('host=' + $n.hostHdr) }
    if ($n.mode) { [void]$pairs.Add('mode=' + $n.mode) }
    if ($n.serviceName) { [void]$pairs.Add('serviceName=' + $n.serviceName) }
    $frag = ''
    if ($n.name) { $frag = '#' + [Uri]::EscapeDataString([string]$n.name) }
    return ('vless://' + $n.uuid + '@' + $n.host + ':' + $n.port + '?' + ($pairs -join '&') + $frag)
}


# ---------- subscriptions ----------

function Get-MachineHwid {
    if ($script:MachineHwid) { return $script:MachineHwid }
    $src = ''
    try { $src = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid } catch { }
    if (!$src) { try { $src = [string]$env:COMPUTERNAME + '|' + [string]$env:USERNAME } catch { } }
    if (!$src) { $src = 'NOMIND' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('NOMIND Connect|' + $src))) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
    $script:MachineHwid = $hash.Substring(0, 8) + '-' + $hash.Substring(8, 4) + '-' + $hash.Substring(12, 4) + '-' + $hash.Substring(16, 4) + '-' + $hash.Substring(20, 12)
    return $script:MachineHwid
}

$script:MaxSubBytes = 4MB
$script:MaxSubNodes = 3000

function Test-HttpUrl([string]$url) {
    # Tolko https: po http podpisku mozhno podmenit (MITM), a file:// i
    # http://127.0.0.1 cherez HttpWebRequest chitayut lokalnye resursy.
    if ([string]$url -notmatch '^https://') { return $false }
    if ($url -match '["\s]') { return $false }
    $u = $null
    if (![Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$u)) { return $false }
    if ($u.Scheme -ne 'https') { return $false }
    if (!$u.Host) { return $false }
    return $true
}

function Get-SubscriptionResponse([string]$url, [string]$hwid) {
    if (!(Test-HttpUrl $url)) { throw 'подписка должна быть по ссылке https://' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # paneli s privyazkoy k ustroystvu (Remnawave i t.p.) ozhidayut HWID: bez nego oni
    # otdayut zaglushki. Berem ustoychivyy id etogo kompyutera, esli polzovatel ne ukazal svoj.
    if (!$hwid) { $hwid = Get-MachineHwid }
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = 20000
    $req.ReadWriteTimeout = 20000
    $req.UserAgent = 'v2raytun/1.0'
    $req.Accept = '*/*'
    if ($hwid) { $req.Headers.Add('x-hwid', $hwid) }
    $resp = $req.GetResponse()
    try {
        # paneli (Marzban/x-ui i t.p.) peredayut srok i trafik v zagolovke
        $userinfo = ''
        try { $userinfo = [string]$resp.Headers['subscription-userinfo'] } catch { }
        # chitaem porciyami s limitom: sbitaya ili vrazhdebnaya panel ne dolzhna
        # vyest pamyat i podvesit GUI
        $len = [long]$resp.ContentLength
        if ($len -gt $script:MaxSubBytes) { throw ('подписка слишком большая: ' + $len + ' байт') }
        $ms = New-Object IO.MemoryStream
        $stream = $resp.GetResponseStream()
        $buf = New-Object byte[] 16384
        $total = 0
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $total += $n
            if ($total -gt $script:MaxSubBytes) { throw 'подписка слишком большая (больше 4 МБ)' }
            $ms.Write($buf, 0, $n)
        }
        $raw = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally { $resp.Close() }
    return [pscustomobject]@{ Text = $raw; UserInfo = $userinfo }
}

function Get-SubscriptionText([string]$url, [string]$hwid) {
    return (Get-SubscriptionResponse $url $hwid).Text
}

# 'upload=0; download=123; total=456; expire=1730000000' -> obekt
function ConvertFrom-UserInfo([string]$raw) {
    $expire = 0L; $total = 0L; $used = 0L
    if ($raw) {
        foreach ($part in ($raw -split ';')) {
            $kv = @($part.Trim() -split '=', 2)
            if ($kv.Count -ne 2) { continue }
            $v = 0L
            if (![long]::TryParse($kv[1].Trim(), [ref]$v)) { continue }
            switch ($kv[0].Trim().ToLower()) {
                'expire'   { $expire = $v }
                'total'    { $total = $v }
                'upload'   { $used += $v }
                'download' { $used += $v }
            }
        }
    }
    return [pscustomobject]@{ Expire = $expire; Total = $total; Used = $used }
}

function Save-SubscriptionInfo([string]$url, $info) {
    try {
        $s = Get-Settings
        if (!$s) { return }
        $map = [ordered]@{}
        if ($s.subInfo) {
            foreach ($p in $s.subInfo.PSObject.Properties) { $map[$p.Name] = $p.Value }
        }
        $map[$url] = [pscustomobject]@{
            expire  = [long]$info.Expire
            total   = [long]$info.Total
            used    = [long]$info.Used
            checked = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        $s | Add-Member -NotePropertyName subInfo -NotePropertyValue $map -Force
        Save-Settings $s
    } catch { }
}

function ConvertFrom-Subscription([string]$raw) {
    $text = $raw.Trim()
    if ($text -match '<html') { throw 'сервер вернул HTML вместо подписки (неверная ссылка или нужен HWID)' }

    # nekotorye paneli otdayut ne ssylki, a JSON-konfigi Xray (massiv obektov s outbounds)
    if ($text.StartsWith('[') -or $text.StartsWith('{')) {
        $cfgs = @()
        try {
            $parsed = ConvertFrom-Json $text
            $cfgs = @($parsed)
        } catch { throw 'не смог разобрать JSON-подписку' }
        if ($cfgs.Count -gt $script:MaxSubNodes) {
            throw ('в подписке слишком много конфигов: ' + $cfgs.Count + ' (лимит ' + $script:MaxSubNodes + ')')
        }
        $links = New-Object System.Collections.ArrayList
        foreach ($c in $cfgs) {
            $ob = $null
            foreach ($o in @($c.outbounds)) {
                if ($o -and $o.protocol -eq 'vless') { $ob = $o; break }
            }
            if (!$ob) { continue }
            $v = @($ob.settings.vnext)[0]
            if (!$v) { continue }
            $u = @($v.users)[0]
            if (!$u) { continue }
            $st = $ob.streamSettings
            $net = 'tcp'; $sec = 'none'; $sni = ''; $pbk = ''; $sid = ''; $fp = ''
            $path = ''; $hostHdr = ''; $mode = ''; $svc = ''
            if ($st) {
                if ($st.network) { $net = [string]$st.network }
                if ($st.security) { $sec = [string]$st.security }
                $rs = $st.realitySettings
                if ($rs) {
                    if ($rs.serverName) { $sni = [string]$rs.serverName }
                    if ($rs.publicKey) { $pbk = [string]$rs.publicKey }
                    if ($rs.shortId) { $sid = [string]$rs.shortId }
                    if ($rs.fingerprint) { $fp = [string]$rs.fingerprint }
                }
                $ts = $st.tlsSettings
                if ($ts) {
                    if ($ts.serverName) { $sni = [string]$ts.serverName }
                    if ($ts.fingerprint) { $fp = [string]$ts.fingerprint }
                }
                $ws = $st.wsSettings
                if ($ws) {
                    if ($ws.path) { $path = [string]$ws.path }
                    try { if ($ws.headers.Host) { $hostHdr = [string]$ws.headers.Host } } catch { }
                }
                $xh = $st.xhttpSettings
                if (!$xh) { $xh = $st.splithttpSettings }
                if ($xh) {
                    if ($xh.path) { $path = [string]$xh.path }
                    if ($xh.host) { $hostHdr = [string]$xh.host }
                    if ($xh.mode) { $mode = [string]$xh.mode }
                }
                $gs = $st.grpcSettings
                if ($gs -and $gs.serviceName) { $svc = [string]$gs.serviceName }
            }
            if ($net -eq 'splithttp') { $net = 'xhttp' }
            $nm = ''
            try { $nm = [string]$c.remarks } catch { }
            if (!$nm) { try { $nm = [string]$v.remark } catch { } }
            if (!$nm) { $nm = [string]$v.address }
            $nm = Clear-NodeName $nm
            if (!$nm) { $nm = [string]$v.address }
            $node = [pscustomobject]@{
                name = $nm; host = [string]$v.address; port = [int]$v.port
                uuid = [string]$u.id; flow = [string]$u.flow
                sni = $sni; pbk = $pbk; sid = $sid; fp = $fp
                network = $net; path = $path; hostHdr = $hostHdr; mode = $mode; serviceName = $svc
                security = $sec
            }
            [void]$links.Add((ConvertTo-VlessLink $node))
        }
        return @($links)
    }

    if ($text -notmatch '://') {
        try {
            $clean = $text -replace '\s', ''
            $bytes = [Convert]::FromBase64String($clean)
            $text = [Text.Encoding]::UTF8.GetString($bytes)
        } catch { throw 'не смог разобрать ответ подписки' }
    }
    $links = @($text -split "[\r\n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($links.Count -gt $script:MaxSubNodes) {
        throw ('в подписке слишком много серверов: ' + $links.Count + ' (лимит ' + $script:MaxSubNodes + ')')
    }
    return $links
}

function Import-Subscription([string]$url, [string]$hwid) {
    $resp = Get-SubscriptionResponse $url $hwid
    $links = ConvertFrom-Subscription $resp.Text
    $info = ConvertFrom-UserInfo $resp.UserInfo
    $nodes = @(Get-Servers)
    $set = @{}
    foreach ($n in $nodes) { $set[(Get-ServerKey $n)] = $true }
    $added = 0; $skip = 0; $bad = 0; $service = 0; $usable = 0; $tagged = $false
    foreach ($l in $links) {
        if ($l -notmatch '^vless://') { $bad++; continue }
        try { $node = ConvertFrom-VlessLink $l } catch {
            $bad++
            if ($_.Exception.Message -match 'служебный|нулевой') { $service++ }
            continue
        }
        $usable++
        $key = Get-ServerKey $node
        if ($set.ContainsKey($key)) {
            $skip++
            # server uzhe est - otmechaem, iz kakov on podpiski (dlya gruppirovki)
            for ($i = 0; $i -lt $nodes.Count; $i++) {
                if ((Get-ServerKey $nodes[$i]) -eq $key) {
                    if ([string]$nodes[$i].sub -ne $url) {
                        $nodes[$i] | Add-Member -NotePropertyName sub -NotePropertyValue $url -Force
                        $tagged = $true
                    }
                    break
                }
            }
            continue
        }
        $node.provider = 'sub'
        $node | Add-Member -NotePropertyName sub -NotePropertyValue $url -Force
        $nodes += $node
        $set[$key] = $true
        $added++
    }
    if ($usable -eq 0) {
        if ($service -gt 0) {
            throw ('панель вернула только заглушки (0.0.0.0:1) вместо серверов.' + "`r`n`r`n" +
                'Обычно так бывает, когда в тарифе занят лимит устройств: панель не отдаёт конфиг новому устройству.' + "`r`n" +
                'Что делать: откройте кабинет или бота сервиса, сбросьте список устройств (или увеличьте лимит), ' +
                'затем добавьте подписку снова. Если в кабинете есть номер устройства (HWID) — вставьте его в поле HWID выше.')
        }
        throw 'в подписке нет vless-серверов (возможно, формат подписки не поддерживается)'
    }
    if ($added -gt 0 -or $tagged) { Save-Servers $nodes }
    Save-SubscriptionInfo $url $info
    return [pscustomobject]@{
        Added = $added; Skipped = $skip; Bad = $bad; Total = $links.Count
        Expire = $info.Expire; TotalBytes = $info.Total; UsedBytes = $info.Used
    }
}

function Save-Subscription([string]$url, [string]$hwid) {
    $s = Get-Settings
    if (!$s) { return }
    $list = @()
    if ($s.subs) { $list = @($s.subs) }
    $out = @()
    $found = $false
    foreach ($x in $list) {
        if ($x.url -eq $url) { $found = $true; $out += [pscustomobject]@{ url = $url; hwid = $hwid } }
        else { $out += $x }
    }
    if (!$found) { $out += [pscustomobject]@{ url = $url; hwid = $hwid } }
    $s | Add-Member -NotePropertyName subs -NotePropertyValue @($out) -Force
    if ($hwid) { $s | Add-Member -NotePropertyName hwid -NotePropertyValue $hwid -Force }
    Save-Settings $s
}

function Remove-Subscription([string]$url) {
    $s = Get-Settings
    if (!$s) { return }
    $out = @()
    if ($s.subs) {
        foreach ($x in @($s.subs)) {
            if ([string]$x.url -ne $url) { $out += $x }
        }
    }
    $s | Add-Member -NotePropertyName subs -NotePropertyValue @($out) -Force
    # srok etoy podpiski bolshe ne nuzhen
    if ($s.subInfo) {
        $map = [ordered]@{}
        foreach ($p in $s.subInfo.PSObject.Properties) {
            if ($p.Name -ne $url) { $map[$p.Name] = $p.Value }
        }
        $s | Add-Member -NotePropertyName subInfo -NotePropertyValue $map -Force
    }
    Save-Settings $s
}
# ---------- config ----------

function New-Outbound($n) {
    $user = [ordered]@{ id = $n.uuid; encryption = 'none' }
    if ($n.flow) { $user.flow = $n.flow }

    # Bezopasnost uzla zavisit ot ego dannyh: REALITY est tolko tam, gde panel
    # vydala publicKey (pbk). Uzel s TLS/WS bez pbk nelzya opisyvat kak REALITY -
    # Xray otkazyvaetsya gruzit ves konfig, i odin takoj uzel lomaet ves poisk.
    $sec = ''
    if ($n.security) { $sec = ([string]$n.security).ToLower() }
    if ($n.pbk -and (!$sec -or $sec -eq 'reality')) { $sec = 'reality' }
    if ($sec -eq 'reality' -and !$n.pbk) { $sec = '' }
    if (!$sec) { if ($n.sni) { $sec = 'tls' } else { $sec = 'none' } }

    $ss = [ordered]@{ network = 'tcp'; security = $sec }
    if ($n.network -and $n.network -ne 'tcp') { $ss.network = $n.network }
    if ($n.network -eq 'ws') {
        $ss.wsSettings = [ordered]@{ path = (IfEmpty $n.path '/') }
        if ($n.hostHdr) { $ss.wsSettings.headers = [ordered]@{ Host = $n.hostHdr } }
    }
    if ($n.network -eq 'xhttp') {
        $x = [ordered]@{ mode = (IfEmpty $n.mode 'auto') }
        if ($n.path) { $x.path = $n.path } else { $x.path = '/' }
        if ($n.hostHdr) { $x.host = $n.hostHdr }
        $ss.xhttpSettings = $x
    }
    if ($n.network -eq 'grpc') {
        $ss.grpcSettings = [ordered]@{ serviceName = (IfEmpty $n.serviceName '') }
    }
    if ($sec -eq 'reality') {
        $ss.realitySettings = [ordered]@{
            serverName  = (IfEmpty $n.sni $n.host)
            fingerprint = (IfEmpty $n.fp 'chrome')
            publicKey   = $n.pbk
            shortId     = (IfEmpty $n.sid '')
            spiderX     = '/'
        }
    }
    elseif ($sec -eq 'tls') {
        $ss.tlsSettings = [ordered]@{
            serverName  = (IfEmpty $n.sni $n.host)
            fingerprint = (IfEmpty $n.fp 'chrome')
        }
    }
    return [ordered]@{
        tag            = 'proxy'
        protocol       = 'vless'
        settings       = [ordered]@{ vnext = @([ordered]@{ address = $n.host; port = [int]$n.port; users = @($user) }) }
        streamSettings = $ss
        mux            = [ordered]@{ enabled = $false }
    }
}

function IfEmpty($v, $def) { if ($v) { return $v } else { return $def } }

function New-RoutingRules($settings, [string[]]$domains) {
    $rules = New-Object System.Collections.ArrayList

    if ($settings.blockAds) {
        [void]$rules.Add([ordered]@{ type = 'field'; domain = @('geosite:category-ads'); outboundTag = 'block' })
    }
    [void]$rules.Add([ordered]@{ type = 'field'; ip = @('geoip:private'); outboundTag = 'direct' })

    $proxy = New-Object System.Collections.ArrayList
    if ($settings.mode -eq 'smart') {
        $seen = @{}
        foreach ($d in $domains) {
            $x = $d.Trim().ToLower()
            $x = $x -replace '^https?://', '' -replace '/.*$', '' -replace '^\*\.', ''
            if (!$x -or $x.Contains(' ')) { continue }
            if ($settings.ruDirect -and $x -match '\.(ru|su|xn--p1ai)$') { continue }
            if ($seen.ContainsKey($x)) { continue }
            $seen[$x] = 1
            [void]$proxy.Add('domain:' + $x)
        }
        if ($proxy.Count -gt 0) {
            [void]$rules.Add([ordered]@{ type = 'field'; domain = @($proxy); outboundTag = 'proxy' })
        }
    }

    if ($settings.ruDirect) {
        [void]$rules.Add([ordered]@{ type = 'field'; domain = @('domain:ru', 'domain:su', 'domain:xn--p1ai', 'geosite:category-ru'); outboundTag = 'direct' })
        [void]$rules.Add([ordered]@{ type = 'field'; ip = @('geoip:ru'); outboundTag = 'direct' })
    }

    if ($settings.mode -eq 'global') {
        [void]$rules.Add([ordered]@{ type = 'field'; network = 'tcp,udp'; outboundTag = 'proxy' })
    } else {
        [void]$rules.Add([ordered]@{ type = 'field'; network = 'tcp,udp'; outboundTag = 'direct' })
    }
    return @($rules)
}

function New-ConfigFile($node, $settings, [string[]]$domains, [int]$httpPort, [int]$socksPort, [string]$file) {
    $sniff = [ordered]@{ enabled = $true; destOverride = @('http', 'tls', 'quic'); routeOnly = $false }
    $cfg = [ordered]@{
        log      = [ordered]@{ loglevel = 'warning' }
        inbounds = @(
            [ordered]@{ tag = 'http'; listen = '127.0.0.1'; port = $httpPort; protocol = 'http'; settings = [ordered]@{}; sniffing = $sniff },
            [ordered]@{ tag = 'socks'; listen = '127.0.0.1'; port = $socksPort; protocol = 'socks'; settings = [ordered]@{ auth = 'noauth'; udp = $true }; sniffing = $sniff }
        )
        outbounds = @(
            (New-Outbound $node),
            [ordered]@{ tag = 'direct'; protocol = 'freedom'; settings = [ordered]@{ domainStrategy = 'AsIs' } },
            [ordered]@{ tag = 'block'; protocol = 'blackhole' }
        )
        routing  = [ordered]@{ domainStrategy = 'AsIs'; rules = (New-RoutingRules $settings $domains) }
    }
    Write-Utf8 $file ($cfg | ConvertTo-Json -Depth 20)
    return $file
}

# ---------- process ----------

function Test-LocalPort([int]$port) {
    $cli = New-Object Net.Sockets.TcpClient
    try {
        $t = $cli.ConnectAsync('127.0.0.1', $port)
        if ($t.Wait(400)) { return $cli.Connected }
        return $false
    } catch { return $false } finally { $cli.Close() }
}

function Test-IsOurScript([string]$commandLine, [string]$expectedPath) {
    # Sravnivaem imenno put iz -File, a ne podstroku v komandnoj stroke:
    # inache Get-Content NOMINDConnect.ps1 ili chuzhoj skript s tem zhe imenem
    # schitaetsya nashim prilozheniem i mozhet byt ubit.
    if (!$commandLine -or !$expectedPath) { return $false }
    $p = ''
    $m = [regex]::Match($commandLine, '(?i)-File\s+"([^"]+)"')
    if ($m.Success) { $p = $m.Groups[1].Value }
    else {
        $m = [regex]::Match($commandLine, '(?i)-File\s+([^\s"]+)')
        if ($m.Success) { $p = $m.Groups[1].Value }
    }
    if (!$p) { return $false }
    try {
        $a = [IO.Path]::GetFullPath($p.Trim())
        $b = [IO.Path]::GetFullPath($expectedPath)
        return ($a -ieq $b)
    } catch { return $false }
}

function Get-EngineProcess {
    $pidF = Join-Path $script:Run 'engine.pid'
    if (Test-Path $pidF) {
        $old = (Read-Utf8 $pidF).Trim()
        if ($old) {
            $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -match 'xray') { return $p }
        }
    }
    $p = Get-Process -Name 'xray' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $script:Exe } | Select-Object -First 1
    return $p
}

function Start-Engine($node, $settings, [string[]]$domains) {
    Stop-Engine | Out-Null
    $cfg = Join-Path $script:Run 'config.json'
    New-ConfigFile -node $node -settings $settings -domains $domains -httpPort ([int]$settings.httpPort) -socksPort ([int]$settings.socksPort) -file $cfg | Out-Null
    $errLog = Join-Path $script:Run 'xray.err.log'
    $outLog = Join-Path $script:Run 'xray.out.log'
    $p = Start-Process -FilePath $script:Exe -ArgumentList @('-c', ('"' + $cfg + '"')) -WorkingDirectory $script:Bin -WindowStyle Hidden -RedirectStandardError $errLog -RedirectStandardOutput $outLog -PassThru
    Write-Utf8 (Join-Path $script:Run 'engine.pid') ([string]$p.Id)

    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
        if ($p.HasExited) {
            $err = ''
            if (Test-Path $errLog) { $err = (Read-Utf8 $errLog).Trim() }
            throw ('xray exited with code ' + $p.ExitCode + ': ' + $err)
        }
        if ((Test-LocalPort ([int]$settings.httpPort)) -and (Test-LocalPort ([int]$settings.socksPort))) {
            return $p
        }
        Start-Sleep -Milliseconds 150
    }
    Stop-Engine | Out-Null
    throw 'xray did not open its ports in 12 seconds'
}

function Stop-Engine {
    $p = Get-EngineProcess
    if ($p) {
        try { $p.Kill(); $p.WaitForExit(3000) | Out-Null } catch { }
    }
    $pidF = Join-Path $script:Run 'engine.pid'
    if (Test-Path $pidF) { Remove-Item $pidF -Force -ErrorAction SilentlyContinue }
    return $true
}

# ---------- system proxy ----------

$script:WinInet = @'
using System;
using System.Runtime.InteropServices;
public class WinInet {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
    public static void Refresh() {
        InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
    }
}
'@

function Ensure-WinInet {
    if (-not ('WinInet' -as [type])) {
        Add-Type -TypeDefinition $script:WinInet
    }
}

$script:Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Get-SystemProxy {
    $p = Get-ItemProperty $script:Key -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Enable = [int]$p.ProxyEnable; Server = $p.ProxyServer; Override = $p.ProxyOverride }
}

function Enable-SystemProxy([int]$port) {
    $bak = Join-Path $script:Run 'proxy-backup.json'
    if (!(Test-Path $bak)) {
        $cur = Get-SystemProxy
        Write-Utf8 $bak (($cur | ConvertTo-Json) )
    }
    Set-ItemProperty $script:Key -Name 'ProxyEnable' -Value 1 -Type DWord
    Set-ItemProperty $script:Key -Name 'ProxyServer' -Value ('127.0.0.1:' + $port) -Type String
    Set-ItemProperty $script:Key -Name 'ProxyOverride' -Value ('<local>;192.168.*;10.*;172.16.*;127.*') -Type String
    Ensure-WinInet
    [WinInet]::Refresh()
    return $true
}

function Get-OurProxyServers {
    # Nashi adresa proksi: 127.0.0.1:<httpPort> i :<socksPort> iz nastroyek.
    $ports = @(10809, 10808)
    try {
        $s = Get-Settings
        if ($s) {
            if ($s.httpPort) { $ports = @([int]$s.httpPort) }
            if ($s.socksPort) { $ports += [int]$s.socksPort }
        }
    } catch { }
    return @($ports | ForEach-Object { '127.0.0.1:' + $_ })
}

function Disable-SystemProxy {
    $bak = Join-Path $script:Run 'proxy-backup.json'
    if (Test-Path $bak) {
        $b = Read-Utf8 $bak | ConvertFrom-Json
        Set-ItemProperty $script:Key -Name 'ProxyEnable' -Value ([int]$b.Enable) -Type DWord
        Set-ItemProperty $script:Key -Name 'ProxyServer' -Value ([string]$b.Server) -Type String
        Set-ItemProperty $script:Key -Name 'ProxyOverride' -Value ([string]$b.Override) -Type String
        Remove-Item $bak -Force -ErrorAction SilentlyContinue
    } else {
        # Bekapa net - znachit my proksi ne vklyuchali (ili on uzhe sbroshen).
        # Chuzhoj proksi (korotativnyj, ruchnoj) gasit nelzya: inache chelovek
        # ostaetsya bez interneta i bez ponimaniya pochemu.
        $cur = Get-SystemProxy
        $isOurs = ((Get-OurProxyServers) -contains ([string]$cur.Server))
        if ([int]$cur.Enable -eq 1 -and !$isOurs) {
            return $false
        }
        Set-ItemProperty $script:Key -Name 'ProxyEnable' -Value 0 -Type DWord
    }
    Ensure-WinInet
    [WinInet]::Refresh()
    return $true
}

# ---------- tests ----------

function Test-ServerTcp($n, [int]$timeout = 4000) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cli = New-Object Net.Sockets.TcpClient
    try {
        $t = $cli.ConnectAsync($n.host, [int]$n.port)
        if ($t.Wait($timeout) -and $cli.Connected) { return [int]$sw.ElapsedMilliseconds }
        return -1
    } catch { return -1 } finally { $cli.Close() }
}

function Get-Trace([int]$port, [string]$url) {
    $out = & $script:Curl -s -m 15 --proxy ('http://127.0.0.1:' + $port) $url 2>&1
    $txt = ($out | Out-String)
    $ip = ''
    $loc = ''
    foreach ($line in $txt -split "`r?`n") {
        if ($line -match '^ip=(.*)$') { $ip = $Matches[1] }
        if ($line -match '^loc=(.*)$') { $loc = $Matches[1] }
    }
    return [pscustomobject]@{ Ip = $ip; Loc = $loc; Raw = $txt }
}

function Test-ServerReal($n, $settings, [string[]]$domains) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $tmpCfg = Join-Path $script:Run 'test-config.json'
    New-ConfigFile -node $n -settings $settings -domains $domains -httpPort 11809 -socksPort 11808 -file $tmpCfg | Out-Null
    $errLog = Join-Path $script:Run 'test.err.log'
    $outLog = Join-Path $script:Run 'test.out.log'
    $p = Start-Process -FilePath $script:Exe -ArgumentList @('-c', ('"' + $tmpCfg + '"')) -WorkingDirectory $script:Bin -WindowStyle Hidden -RedirectStandardError $errLog -RedirectStandardOutput $outLog -PassThru
    $ms = -1; $ip = ''; $loc = ''
    try {
        $deadline = (Get-Date).AddSeconds(10)
        $up = $false
        while ((Get-Date) -lt $deadline) {
            if ($p.HasExited) { break }
            if (Test-LocalPort 11809) { $up = $true; break }
            Start-Sleep -Milliseconds 150
        }
        if ($up) {
            $tr = Get-Trace 11809 'https://chatgpt.com/cdn-cgi/trace'
            $ip = $tr.Ip
            $loc = $tr.Loc
            if ($ip) { $ms = [int]$sw.ElapsedMilliseconds }
        }
    } catch { } finally {
        try { if (!$p.HasExited) { $p.Kill() } } catch { }
        Remove-Item $tmpCfg -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{ Ms = $ms; Ip = $ip; Loc = $loc }
}

function Test-RealPing($n, $settings, [int]$timeoutMs = 12000, [int]$port = 11829, [string]$tag = 'ping') {
    $tmpCfg = Join-Path $script:Run ($tag + '-config.json')
    $socks = $port - 1
    $s2 = $settings.PSObject.Copy()
    $s2.mode = 'global'
    $s2 | Add-Member -NotePropertyName blockAds -NotePropertyValue $false -Force
    New-ConfigFile -node $n -settings $s2 -domains @() -httpPort $port -socksPort $socks -file $tmpCfg | Out-Null
    $errLog = Join-Path $script:Run ($tag + '.err.log')
    $outLog = Join-Path $script:Run ($tag + '.out.log')
    $p = $null
    try {
        $p = Start-Process -FilePath $script:Exe -ArgumentList @('-c', ('"' + $tmpCfg + '"')) -WorkingDirectory $script:Bin -WindowStyle Hidden -RedirectStandardError $errLog -RedirectStandardOutput $outLog -PassThru
        $deadline = (Get-Date).AddMilliseconds($timeoutMs)
        $up = $false
        while ((Get-Date) -lt $deadline) {
            if ($p.HasExited) { break }
            if (Test-LocalPort $port) { $up = $true; break }
            Start-Sleep -Milliseconds 60
        }
        if (!$up) { return -1 }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $code = (& $script:Curl -s -o NUL -m 3 -w '%{http_code}' --proxy ('http://127.0.0.1:' + $port) 'https://cp.cloudflare.com/generate_204' 2>$null | Out-String).Trim()
        $ms = [int]$sw.ElapsedMilliseconds
        if ($code -match '^(204|200)$') { return $ms }
        return -1
    } catch { return -1 } finally {
        try { if ($p -and !$p.HasExited) { $p.Kill() } } catch { }
        Remove-Item $tmpCfg -Force -ErrorAction SilentlyContinue
    }
}

# ---------- fast batch ping ----------
# One xray process serves every node: an HTTP inbound per node, a vless
# outbound per node, and an inboundTag -> outboundTag routing rule. Then one
# curl per node runs in parallel. This replaces N xray process startups with
# a single one, so a full scan takes seconds instead of tens of seconds.

function New-PingBatchConfig($nodes, [int]$basePort, [string]$file) {
    $inbounds = New-Object System.Collections.ArrayList
    $outbounds = New-Object System.Collections.ArrayList
    $rules = New-Object System.Collections.ArrayList
    $sniff = [ordered]@{ enabled = $true; destOverride = @('http', 'tls', 'quic'); routeOnly = $false }
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $inTag = 'pin' + $i
        $outTag = 'pout' + $i
        [void]$inbounds.Add([ordered]@{
            tag = $inTag; listen = '127.0.0.1'; port = ($basePort + $i)
            protocol = 'http'; settings = [ordered]@{}; sniffing = $sniff
        })
        $ob = New-Outbound $nodes[$i]
        $ob.tag = $outTag
        [void]$outbounds.Add($ob)
        [void]$rules.Add([ordered]@{ type = 'field'; inboundTag = @($inTag); outboundTag = $outTag })
    }
    [void]$outbounds.Add([ordered]@{ tag = 'direct'; protocol = 'freedom'; settings = [ordered]@{ domainStrategy = 'AsIs' } })
    [void]$outbounds.Add([ordered]@{ tag = 'block'; protocol = 'blackhole' })
    $cfg = [ordered]@{
        log       = [ordered]@{ loglevel = 'warning' }
        inbounds  = @($inbounds)
        outbounds = @($outbounds)
        routing   = [ordered]@{ domainStrategy = 'AsIs'; rules = @($rules) }
    }
    Write-Utf8 $file ($cfg | ConvertTo-Json -Depth 20)
    return $file
}

function Invoke-BatchPing($nodes, $settings, [int]$basePort = 12200, [int]$requestMs = 6000) {
    if (!$nodes -or @($nodes).Count -eq 0) { return @() }
    $cfg = Join-Path $script:Run 'pingbatch-config.json'
    New-PingBatchConfig $nodes $basePort $cfg | Out-Null
    $err = Join-Path $script:Run 'pingbatch.err.log'
    $out = Join-Path $script:Run 'pingbatch.out.log'
    $p = $null
    $reqs = New-Object System.Collections.ArrayList
    $result = @{}
    try {
        $p = Start-Process -FilePath $script:Exe -ArgumentList @('-c', ('"' + $cfg + '"')) -WorkingDirectory $script:Bin -WindowStyle Hidden -RedirectStandardError $err -RedirectStandardOutput $out -PassThru

        # all inbounds are bound together: wait for the first one only
        $ready = $false
        $deadline = (Get-Date).AddMilliseconds(2500)
        while ((Get-Date) -lt $deadline) {
            if ($p.HasExited) { break }
            if (Test-LocalPort $basePort) { $ready = $true; break }
            Start-Sleep -Milliseconds 40
        }
        if (!$ready) { return $null }   # caller falls back to the old per-node path

        $sec = [string]([Math]::Round(($requestMs / 1000.0), 2))
        for ($i = 0; $i -lt $nodes.Count; $i++) {
            $key = Get-ServerKey $nodes[$i]
            $of = Join-Path $script:Run ('pingbatch.' + $i + '.txt')
            try { Remove-Item $of -Force -ErrorAction SilentlyContinue } catch { }
            $cargs = @(
                '-s', '-o', 'NUL', '-m', $sec,
                # bez probela: Start-Process skleivaet argumenty cherez probel i
                # inache -w razvalivaetsya na dva argumenta, a otvet ne parsitsya
                '-w', '%{http_code},%{time_total}',
                '-x', ('http://127.0.0.1:' + ($basePort + $i)),
                'https://cp.cloudflare.com/generate_204'
            )
            $cp = Start-Process -FilePath $script:Curl -ArgumentList $cargs -WindowStyle Hidden -RedirectStandardOutput $of -PassThru
            [void]$reqs.Add([pscustomobject]@{ Key = $key; Proc = $cp; File = $of })
        }

        $deadline = (Get-Date).AddMilliseconds($requestMs + 1200)
        foreach ($r in $reqs) {
            $left = [int]($deadline - (Get-Date)).TotalMilliseconds
            if ($left -lt 1) { $left = 1 }
            try { if (!$r.Proc.HasExited) { $r.Proc.WaitForExit($left) | Out-Null } } catch { }
        }

        foreach ($r in $reqs) {
            $ms = -1
            try {
                $txt = ''
                if (Test-Path $r.File) { $txt = [string](Get-Content $r.File -Raw -ErrorAction SilentlyContinue) }
                $txt = $txt.Trim()
                if ($txt -match '^(204|200),([0-9]+(?:[\.,][0-9]+)?)') {
                    $t = [double](($Matches[2]) -replace ',', '.')
                    if ($t -gt 0) { $ms = [int][Math]::Round($t * 1000) }
                }
            } catch { }
            $result[$r.Key] = [pscustomobject]@{ Key = $r.Key; Tcp = 0; Real = $ms }
        }
    } finally {
        try { if ($p -and !$p.HasExited) { $p.Kill() } } catch { }
        foreach ($r in @($reqs)) {
            try { if ($r.Proc -and !$r.Proc.HasExited) { $r.Proc.Kill() } } catch { }
        }
        Remove-Item $cfg -Force -ErrorAction SilentlyContinue
        Get-ChildItem $script:Run -Filter 'pingbatch.*.txt' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    return @($nodes | ForEach-Object { $result[(Get-ServerKey $_)] })
}

# ---------- status ----------

function Get-State {
    $s = Get-Settings
    $p = Get-EngineProcess
    $running = [bool]$p
    $proxy = Get-SystemProxy
    $server = $null
    if ($s) {
        $list = Get-Servers
        $server = Find-Server $s.server $list
    }
    return [pscustomobject]@{
        Running = $running
        Pid     = if ($p) { $p.Id } else { 0 }
        ProxyOn = ($proxy.Enable -eq 1)
        Proxy   = $proxy.Server
        Mode    = if ($s) { $s.mode } else { '' }
        Server  = $server
        ServerKey = if ($s) { $s.server } else { '' }
    }
}

# ---------- CLI ----------

if ($Action) {
    switch ($Action) {
        'list' {
            $i = 0
            foreach ($n in Get-Servers) {
                $i++
                '{0,2}. {1,-30} {2}' -f $i, $n.name, (Get-ServerKey $n)
            }
        }
        'start' {
            $s = Get-Settings
            $list = Get-Servers
            $node = $null
            if ($Server) { $node = Find-Server $Server $list }
            if (!$node) { $node = Find-Server $s.server $list }
            if (!$node) { throw 'Server not found' }
            $dom = Get-Domains
            try {
                $p = Start-Engine $node $s $dom
                Enable-SystemProxy ([int]$s.httpPort) | Out-Null
                $tr = Get-Trace ([int]$s.httpPort) 'https://chatgpt.com/cdn-cgi/trace'
                'engine pid  : ' + $p.Id
                'server      : ' + $node.name + '  ' + (Get-ServerKey $node)
                'mode        : ' + $s.mode
                'exit ip     : ' + $tr.Ip + '  loc=' + $tr.Loc
            } catch {
                # Ne ostavlyaem sistemnyj proksi vklyuchennym na mertvyj tunnel:
                # inache posle neudachi "propadaet internet".
                try { Stop-Engine | Out-Null } catch { }
                try { Disable-SystemProxy | Out-Null } catch { }
                throw
            }
        }
        'stop' {
            Stop-Engine | Out-Null
            Disable-SystemProxy | Out-Null
            'stopped'
        }
        'reset' {
            Stop-Engine | Out-Null
            Disable-SystemProxy | Out-Null
            'reset: xray stopped, system proxy off'
        }
        'status' {
            $st = Get-State
            'running : ' + $st.Running + ' (pid ' + $st.Pid + ')'
            'proxy   : ' + $st.ProxyOn + ' ' + $st.Proxy
            'mode    : ' + $st.Mode
            'server  : ' + $st.ServerKey
            if ($st.Running) {
                $s = Get-Settings
                $tr = Get-Trace ([int]$s.httpPort) 'https://chatgpt.com/cdn-cgi/trace'
                'exit    : ' + $tr.Ip + ' loc=' + $tr.Loc
            }
        }
        'test' {
            $s = Get-Settings
            $dom = Get-Domains
            foreach ($n in Get-Servers) {
                $tcp = Test-ServerTcp $n
                if ($tcp -lt 0) {
                    '{0,-32} tcp=FAIL' -f $n.name
                    continue
                }
                $r = Test-ServerReal $n $s $dom
                '{0,-32} tcp={1,5} ms  chatgpt={2,5} ms  ip={3} loc={4}' -f $n.name, $tcp, $r.Ms, $r.Ip, $r.Loc
            }
        }
        'pingall' {
            $s = Get-Settings
            $list = @(Get-Servers)
            if ($Server) {
                $one = Find-Server $Server $list
                if (!$one) { throw 'Server not found' }
                $list = @($one)
            } elseif ($Parts -gt 1) {
                # proverka idet neskolkimi processami parallelno: kazhdyy beret svoyu chast spiska
                $all = $list
                $list = @()
                for ($i = 0; $i -lt $all.Count; $i++) {
                    if (($i % $Parts) -eq $Part) { $list += $all[$i] }
                }
            }
            $write = {
                param($data)
                if (!$OutFile) { return }
                for ($i = 0; $i -lt 6; $i++) {
                    try { Write-Utf8 $OutFile ($data | ConvertTo-Json -Depth 4); return } catch { Start-Sleep -Milliseconds 80 }
                }
            }
            $pingPort = 11829 + (10 * $Part)
            $pingTag = if ($Parts -gt 1) { 'ping' + $Part } else { 'ping' }
            $res = New-Object System.Collections.ArrayList
            foreach ($n in $list) {
                $key = Get-ServerKey $n
                $tcp = Test-ServerTcp $n 1200
                $real = -1
                if ($tcp -ge 0) { $real = Test-RealPing $n $s 3500 $pingPort $pingTag }
                [void]$res.Add([pscustomobject]@{ Key = $key; Tcp = [int]$tcp; Real = [int]$real })
                if ($OutFile) { & $write $res } else { '{0,-32} tcp={1,5}  real={2,5}' -f $n.name, $tcp, $real }
            }
            if ($OutFile) { & $write $res }
        }
        'pingfast' {
            $s = Get-Settings
            $list = @(Get-Servers)
            if ($Server) {
                $one = Find-Server $Server $list
                if (!$one) { throw 'Server not found' }
                $list = @($one)
            }
            $write = {
                param($data)
                if (!$OutFile) { return }
                for ($i = 0; $i -lt 6; $i++) {
                    try { Write-Utf8 $OutFile ($data | ConvertTo-Json -Depth 4); return } catch { Start-Sleep -Milliseconds 80 }
                }
            }
            $res = Invoke-BatchPing $list $s
            if ($null -eq $res) {
                # batch config failed to start - fall back to the per-node path
                $acc = New-Object System.Collections.ArrayList
                foreach ($n in $list) {
                    $key = Get-ServerKey $n
                    $tcp = Test-ServerTcp $n 1200
                    $real = -1
                    if ($tcp -ge 0) { $real = Test-RealPing $n $s 3500 11829 'pingfb' }
                    [void]$acc.Add([pscustomobject]@{ Key = $key; Tcp = [int]$tcp; Real = [int]$real })
                    if ($OutFile) { & $write $acc }
                }
                $res = @($acc)
            }
            if ($OutFile) { & $write $res }
            else { foreach ($r in @($res)) { '{0,-40} real={1,5}' -f $r.Key, $r.Real } }
        }
        'updatecheck' {
            . (Join-Path $script:Root 'updater.ps1')
            $u = Invoke-UpdateCheck
            $json = $u | ConvertTo-Json -Depth 4
            if ($OutFile) { Write-Utf8 $OutFile $json } else { $json }
        }
        'updatefetch' {
            . (Join-Path $script:Root 'updater.ps1')
            $res = [pscustomobject]@{ Ok = $false; Path = ''; Error = '' }
            try {
                $u = [pscustomobject]@{ Version = $Ver; Url = $Url; Sha256 = $Sha }
                $res.Path = Save-UpdateInstaller $u
                $res.Ok = $true
            } catch {
                $res.Error = $_.Exception.Message
            }
            $json = $res | ConvertTo-Json -Depth 4
            if ($OutFile) { Write-Utf8 $OutFile $json } else { $json }
        }
        'subs' {            $s = Get-Settings
            $list = @()
            if ($s -and $s.subs) { $list = @($s.subs) }
            $write = {
                param($data)
                if (!$OutFile) { return }
                for ($i = 0; $i -lt 6; $i++) {
                    try { Write-Utf8 $OutFile ($data | ConvertTo-Json -Depth 4); return } catch { Start-Sleep -Milliseconds 80 }
                }
            }
            $res = New-Object System.Collections.ArrayList
            foreach ($sub in $list) {
                $url = [string]$sub.url
                $hw = [string]$sub.hwid
                try {
                    $r = Import-Subscription $url $hw
                    [void]$res.Add([pscustomobject]@{
                        Url = $url; Added = $r.Added; Skipped = $r.Skipped; Bad = $r.Bad
                        Expire = $r.Expire; Total = $r.TotalBytes; Used = $r.UsedBytes
                        Checked = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Error = ''
                    })
                    if (!$OutFile) { '{0,-42} added={1} skipped={2} expire={3}' -f $url, $r.Added, $r.Skipped, $r.Expire }
                } catch {
                    $msg = $_.Exception.Message
                    [void]$res.Add([pscustomobject]@{
                        Url = $url; Added = 0; Skipped = 0; Bad = 0
                        Expire = 0; Total = 0; Used = 0; Checked = 0; Error = $msg
                    })
                    if (!$OutFile) { '{0,-42} ERROR {1}' -f $url, $msg }
                }
                if ($OutFile) { & $write $res }
            }
            if ($OutFile) {
                if ($res.Count -eq 0) { Write-Utf8 $OutFile '[]' } else { & $write $res }
            }
        }
    }
}
