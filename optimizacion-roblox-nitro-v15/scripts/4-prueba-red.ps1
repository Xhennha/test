<#
  4-prueba-red.ps1
  Mide latencia, variacion (jitter) y perdida de paquetes. SOLO LECTURA.

  Hace ping a:
    1) tu router (puerta de enlace)   -> calidad de tu Wi-Fi / cable
    2) 1.1.1.1 y 8.8.8.8              -> calidad de tu conexion a Internet
    3) el ultimo servidor de Roblox al que te conectaste (si aparece en los logs de Roblox).
       Muchos servidores de Roblox no responden a ping: si da 100% de perdida, no significa nada.

  El ping que importa en Blade Ball es el que muestra Roblox en partida
  (Ajustes de Roblox > Estadisticas de rendimiento). Esta prueba sirve para saber
  si el problema esta en tu red local, en tu proveedor o en la distancia al servidor.

  Uso:
    powershell -ExecutionPolicy Bypass -File .\4-prueba-red.ps1
    powershell -ExecutionPolicy Bypass -File .\4-prueba-red.ps1 -Cantidad 300 -Etiqueta wifi-5ghz
  Consejo: repitela mientras otra persona ve video o descarga algo (prueba de "bufferbloat").
#>
[CmdletBinding()]
param(
    [int]$Cantidad = 100,
    [int]$IntervaloMs = 200,
    [string]$Etiqueta = 'red',
    [string[]]$Extra = @(),
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt')
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$tag = ($Etiqueta -replace '[^\w\-]', '_')
$sumTxt = Join-Path $Destino ("red-{0}-{1}.txt" -f $tag, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$out = New-Object System.Collections.Generic.List[string]
function S([string]$t = '') { $out.Add($t); Write-Host $t }

function Test-Latency([string]$ip, [int]$count, [int]$interval) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $rtts = New-Object System.Collections.Generic.List[double]
    $lost = 0
    for ($i = 0; $i -lt $count; $i++) {
        try {
            $r = $ping.Send($ip, 1000)
            if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $rtts.Add([double]$r.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds $interval
    }
    $ping.Dispose()
    if ($rtts.Count -eq 0) { return [pscustomobject]@{ Destino = $ip; Prom = $null; Min = $null; P95 = $null; Max = $null; Jitter = $null; Perdida = 100.0 } }
    $s = $rtts.ToArray(); [Array]::Sort($s)
    $jit = 0.0
    for ($i = 1; $i -lt $rtts.Count; $i++) { $jit += [math]::Abs($rtts[$i] - $rtts[$i - 1]) }
    if ($rtts.Count -gt 1) { $jit = $jit / ($rtts.Count - 1) }
    [pscustomobject]@{
        Destino = $ip
        Prom    = ($s | Measure-Object -Average).Average
        Min     = $s[0]
        P95     = $s[[int][math]::Ceiling(0.95 * ($s.Count - 1))]
        Max     = $s[$s.Count - 1]
        Jitter  = $jit
        Perdida = 100.0 * $lost / $count
    }
}

function Test-PrivateIp([string]$ip) { $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.)' }

S "Prueba de red - '$Etiqueta' - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

# Conexion usada
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
$gateway = $null
if ($route) {
    $gateway = $route.NextHop
    $ad = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
    $isWifi = "$($ad.PhysicalMediaType)" -match '802\.11'
    S ("Conexion: {0} ({1}) - {2} - {3}" -f $ad.Name, $ad.InterfaceDescription, $ad.LinkSpeed, $(if ($isWifi) { 'Wi-Fi' } else { 'cable/otro' }))
    if ($isWifi) {
        & netsh wlan show interfaces 2>$null | Where-Object { $_ -match ':' -and $_ -notmatch 'SSID|BSSID|Perfil|Profile|sica|Physical|Name|Nombre|GUID' } |
            ForEach-Object { S "  $($_.Trim())" }
    }
}

# Ultimo servidor de Roblox en los logs (solo lectura)
$robloxIp = $null
$logDir = Join-Path $env:LOCALAPPDATA 'Roblox\logs'
if (Test-Path -LiteralPath $logDir) {
    $logs = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5
    foreach ($l in $logs) {
        try {
            $m = Select-String -LiteralPath $l.FullName -Pattern 'UDMUX Address = ([0-9.]+)', 'serverId: ([0-9.]+)\|' -ErrorAction Stop | Select-Object -Last 1
            if ($m) {
                $cand = $m.Matches[0].Groups[1].Value
                if (-not (Test-PrivateIp $cand)) { $robloxIp = $cand; break }
            }
        } catch { }
    }
}

$targets = New-Object System.Collections.Generic.List[object]
if ($gateway -and $gateway -ne '0.0.0.0') { $targets.Add([pscustomobject]@{ Ip = $gateway; Nombre = 'Router (red local)' }) }
$targets.Add([pscustomobject]@{ Ip = '1.1.1.1'; Nombre = 'Internet (Cloudflare)' })
$targets.Add([pscustomobject]@{ Ip = '8.8.8.8'; Nombre = 'Internet (Google)' })
if ($robloxIp) { $targets.Add([pscustomobject]@{ Ip = $robloxIp; Nombre = 'Ultimo servidor Roblox (puede no responder)' }) }
foreach ($e in $Extra) { $targets.Add([pscustomobject]@{ Ip = $e; Nombre = 'Extra' }) }

$secs = [math]::Round($targets.Count * $Cantidad * ($IntervaloMs + 20) / 1000)
S ("Enviando {0} pings a cada destino (unos {1} s en total)..." -f $Cantidad, $secs)
S ''
S ("{0,-44} {1,8} {2,8} {3,8} {4,8} {5,8} {6,9}" -f 'Destino', 'Prom', 'Min', 'P95', 'Max', 'Jitter', 'Perdida')
$results = @{}
foreach ($t in $targets) {
    $r = Test-Latency $t.Ip $Cantidad $IntervaloMs
    $results[$t.Nombre] = $r
    $label = "{0} [{1}]" -f $t.Nombre, $t.Ip
    if ($null -eq $r.Prom) { S ("{0,-44} {1,8} {2,8} {3,8} {4,8} {5,8} {6,8:N1}%" -f $label, '-', '-', '-', '-', '-', $r.Perdida) }
    else { S ("{0,-44} {1,6:N1}ms {2,6:N0}ms {3,6:N0}ms {4,6:N0}ms {5,6:N1}ms {6,8:N1}%" -f $label, $r.Prom, $r.Min, $r.P95, $r.Max, $r.Jitter, $r.Perdida) }
}

# Lectura orientativa
S ''
S 'Lectura orientativa:'
$lan = $results['Router (red local)']
$net = @($results['Internet (Cloudflare)'], $results['Internet (Google)']) | Where-Object { $_ -and $null -ne $_.Prom }
if ($lan -and $null -eq $lan.Prom) { S '- El router no respondio al ping (algunos routers lo bloquean): no se puede evaluar la red local con este metodo.' }
if (@($net).Count -eq 0) { S '- Ningun destino de Internet respondio: sin conexion, o un firewall/antivirus bloquea el ping. Repite la prueba.' }
if ($lan -and $null -ne $lan.Prom) {
    if ($lan.Perdida -gt 0 -or $lan.Jitter -gt 5 -or $lan.P95 -gt 15) {
        S '- La conexion con TU ROUTER ya es inestable: el problema esta en el Wi-Fi/cable de casa.'
        S '  Prueba: cable Ethernet, banda de 5 GHz, acercarte al router, menos dispositivos descargando.'
    } else { S '- Red local estable.' }
}
if (@($net).Count -gt 0) {
    $worstLoss = ($net | Measure-Object Perdida -Maximum).Maximum
    $worstJit = ($net | Measure-Object Jitter -Maximum).Maximum
    if ($worstLoss -ge 1) { S ("- Perdida de paquetes hacia Internet ({0:N1}%): en Blade Ball se nota como bola que 'salta' o parrys que no registran." -f $worstLoss) }
    if ($worstJit -gt 10) { S ("- Jitter alto hacia Internet ({0:N1} ms): ping irregular. Si la red local esta bien, suele ser saturacion de la conexion o del proveedor." -f $worstJit) }
    if ($worstLoss -lt 1 -and $worstJit -le 10) { S '- Conexion a Internet estable. Si el ping en Roblox es alto, lo mas probable es la distancia al servidor.' }
}
S '- Compara siempre con el ping que muestra Roblox en partida; ese es el que afecta al parry.'

$out | Out-File -LiteralPath $sumTxt -Encoding UTF8
Write-Host ''
Write-Host "Resultado guardado en: $sumTxt" -ForegroundColor Green
