<#
  2-diagnostico.ps1
  Diagnostico de SOLO LECTURA para Roblox / Blade Ball en el Acer Nitro V15.
  No cambia ninguna configuracion. Genera un informe en Escritorio\RobloxOpt\diagnostico-<fecha>.txt

  Ejecutalo dos veces:
    a) con Roblox cerrado (estado general del sistema)
    b) con Blade Ball abierto (para comprobar que Roblox usa la RTX 2050)

  Uso (PowerShell normal, no hace falta administrador):
    powershell -ExecutionPolicy Bypass -File .\2-diagnostico.ps1
    powershell -ExecutionPolicy Bypass -File .\2-diagnostico.ps1 -SinInternet   # no consulta GitHub

  No mide FPS ni temperatura de CPU: para eso usa 3-monitor-carga.ps1, PresentMon y HWiNFO (ver la guia).
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt'),
    [switch]$SinInternet
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$reportPath = Join-Path $Destino ("diagnostico-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$lines = New-Object System.Collections.Generic.List[string]
$alerts = New-Object System.Collections.Generic.List[string]
$la = $env:LOCALAPPDATA

function W([string]$t = '') { $lines.Add($t); Write-Host $t }
function Section([string]$t) { W ''; W ('=' * 72); W "  $t"; W ('=' * 72) }
function Alert([string]$t) { $alerts.Add($t); W "  [!] $t" }
function Get-RegValue([string]$path, [string]$name) {
    try { (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { $null }
}
# Ultimos dos valores hexadecimales de "powercfg /query": indice actual con cargador (AC) y con bateria (DC).
# Se parsean los numeros, no el texto, porque el texto depende del idioma de Windows.
function Get-PowerSettingAcDc([string]$sub, [string]$setting) {
    $out = & powercfg /query SCHEME_CURRENT $sub $setting 2>$null
    $hex = @([regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject]@{ AC = [Convert]::ToInt32($hex[-2], 16); DC = [Convert]::ToInt32($hex[-1], 16) }
}

# FastFlags aceptadas por Roblox segun el anuncio del 29-09-2025 (lista de permitidos).
# Roblox puede cambiarla; si una flag que usas no aparece aqui, revisa el anuncio oficial.
$allowlist = @(
    'DFIntCSGLevelOfDetailSwitchingDistance', 'DFIntCSGLevelOfDetailSwitchingDistanceL12',
    'DFIntCSGLevelOfDetailSwitchingDistanceL23', 'DFIntCSGLevelOfDetailSwitchingDistanceL34',
    'FFlagHandleAltEnterFullscreenManually', 'DFFlagTextureQualityOverrideEnabled',
    'DFIntTextureQualityOverride', 'FIntDebugForceMSAASamples', 'DFFlagDisableDPIScale',
    'FFlagDebugGraphicsPreferD3D11', 'FFlagDebugSkyGray', 'DFFlagDebugPauseVoxelizer',
    'DFIntDebugFRMQualityLevelOverride', 'FIntFRMMaxGrassDistance', 'FIntFRMMinGrassDistance',
    'FFlagDebugGraphicsPreferVulkan', 'FFlagDebugGraphicsPreferOpenGL',
    'FIntGrassMovementReducedMotionFactor'
)

W "Diagnostico Roblox / Blade Ball - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W 'Solo lectura: este script no cambia nada.'

# ---------------------------------------------------------------------------
Section '1. Sistema'
$os = Get-CimInstance Win32_OperatingSystem
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
W ("Windows: {0} {1} (compilacion {2}.{3})" -f $os.Caption, (Get-RegValue $cv 'DisplayVersion'), $os.BuildNumber, (Get-RegValue $cv 'UBR'))
$uptime = (Get-Date) - $os.LastBootUpTime
W ("Encendido desde hace: {0:N1} dias" -f $uptime.TotalDays)
if ($uptime.TotalDays -gt 3) { Alert 'Mas de 3 dias sin reiniciar. Reinicia antes de medir para partir de un estado limpio.' }
$cs = Get-CimInstance Win32_ComputerSystem
W ("Equipo: {0} {1}" -f $cs.Manufacturer, $cs.Model)
$bios = Get-CimInstance Win32_BIOS
W ("BIOS: {0} ({1:yyyy-MM-dd})" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
W ("CPU: {0} - {1} nucleos / {2} hilos" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
$mods = @(Get-CimInstance Win32_PhysicalMemory)
W ("RAM: {0:N1} GB en {1} modulo(s); libre ahora {2:N1} GB" -f (($mods | Measure-Object Capacity -Sum).Sum / 1GB), $mods.Count, ($os.FreePhysicalMemory * 1KB / 1GB))
foreach ($m in $mods) { W ("  - {0:N0} GB a {1} MT/s ({2})" -f ($m.Capacity / 1GB), $m.ConfiguredClockSpeed, $m.DeviceLocator) }
if ($mods.Count -eq 1) { Alert 'Un solo modulo de RAM (canal simple). Es hardware, no se arregla por software; solo es informativo.' }

try {
    Add-Type -AssemblyName System.Windows.Forms
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    W ("Alimentacion: {0}; bateria al {1:P0}" -f $ps.PowerLineStatus, $ps.BatteryLifePercent)
    if ("$($ps.PowerLineStatus)" -ne 'Online') { Alert 'El portatil NO esta conectado al cargador en este momento.' }
} catch { W 'Alimentacion: no se pudo leer.' }

# ---------------------------------------------------------------------------
Section '2. GPU, drivers y pantalla'
$vcs = @(Get-CimInstance Win32_VideoController)
$maxHz = 0
foreach ($v in $vcs) {
    W $v.Name
    W ("  Driver {0} (fecha {1:yyyy-MM-dd})" -f $v.DriverVersion, $v.DriverDate)
    if ($v.CurrentRefreshRate) {
        W ("  Pantalla en este adaptador: {0}x{1} a {2} Hz" -f $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution, $v.CurrentRefreshRate)
        if ($v.CurrentRefreshRate -gt $maxHz) { $maxHz = $v.CurrentRefreshRate }
    } else {
        W '  (ninguna pantalla conectada directamente a este adaptador)'
    }
    if ($v.DriverDate -and ((Get-Date) - $v.DriverDate).TotalDays -gt 180) {
        Alert ("Driver de '{0}' con mas de 6 meses ({1:yyyy-MM-dd}). Ver seccion de drivers de la guia." -f $v.Name, $v.DriverDate)
    }
}
if ($maxHz -gt 0 -and $maxHz -lt 160) { Alert ("La pantalla esta a {0} Hz, no a 165 Hz. Cambialo en Configuracion > Sistema > Pantalla > Pantalla avanzada." -f $maxHz) }

$nv = $vcs | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
$intel = $vcs | Where-Object { $_.Name -match 'Intel' } | Select-Object -First 1
if ($nv -and $intel -and -not $nv.CurrentRefreshRate -and $intel.CurrentRefreshRate) {
    W ''
    W 'Indicio: la pantalla interna sale por la Intel UHD (modo hibrido / Optimus).'
    W 'La RTX 2050 renderiza y la Intel muestra la imagen. Es normal en portatiles sin MUX activo.'
}

$smi = $null
foreach ($c in @((Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source,
                 "$env:SystemRoot\System32\nvidia-smi.exe",
                 "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) {
    if ($c -and (Test-Path -LiteralPath $c)) { $smi = $c; break }
}
$robloxRunning = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue)
if ($smi) {
    W ''
    W 'nvidia-smi:'
    $q = 'name,driver_version,vbios_version,pstate,temperature.gpu,utilization.gpu,clocks.gr,clocks.max.gr,power.draw,memory.used,memory.total,display_active'
    & $smi "--query-gpu=$q" '--format=csv' 2>&1 | ForEach-Object { W "  $_" }
    $smiFull = @(& $smi 2>&1 | ForEach-Object { "$_" })
    $gpuProcs = $smiFull | Where-Object { $_ -match '\.exe' }
    W '  Procesos que usan la GPU NVIDIA:'
    if ($gpuProcs) { $gpuProcs | ForEach-Object { W "    $($_.Trim())" } } else { W '    (ninguno listado)' }
    if ($robloxRunning.Count -gt 0) {
        if ($smiFull -match 'RobloxPlayerBeta') { W '  OK: Roblox esta abierto y aparece usando la RTX 2050.' }
        else { Alert 'Roblox esta abierto pero NO aparece en la GPU NVIDIA. Comprueba la preferencia de GPU (guia, seccion Windows).' }
    } else {
        W '  (Roblox no esta abierto: vuelve a ejecutar con Blade Ball abierto para comprobar la GPU que usa.)'
    }
} else {
    Alert 'No se encontro nvidia-smi. Puede que el driver NVIDIA no este bien instalado.'
}

# ---------------------------------------------------------------------------
Section '3. Energia y limites de rendimiento'
W ("Plan activo: {0}" -f ((powercfg /getactivescheme) -join ' '))
if ((powercfg /getactivescheme) -match 'e9a42b02-d5df-448d-aa00-03f14749eb61') {
    W '  Plan "Rendimiento maximo/definitivo" activo. En portatiles suele subir temperatura sin ganancia clara; si ves throttling termico, vuelve a "Equilibrado".'
}
$pp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$modeNames = @{
    '00000000-0000-0000-0000-000000000000' = 'Equilibrado'
    'ded574b5-45a0-4f42-8737-46345c09c238' = 'Mejor rendimiento'
    '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Mejor eficiencia energetica'
    '3af9b8d9-7c97-431d-ad78-34a8bfea439f' = 'Mejor bateria'
}
$acMode = "$(Get-RegValue $pp 'ActiveOverlayAcPowerScheme')".ToLower()
$acName = if ($acMode -and $modeNames.ContainsKey($acMode)) { $modeNames[$acMode] } elseif ($acMode) { $acMode } else { 'no definido (normalmente Equilibrado)' }
W "Modo de energia con cargador (Windows 11): $acName"
if ($acName -ne 'Mejor rendimiento') { Alert 'Modo de energia con cargador distinto de "Mejor rendimiento". Ver guia, seccion Windows > Energia.' }

$maxState = Get-PowerSettingAcDc 'SUB_PROCESSOR' 'PROCTHROTTLEMAX'
if ($maxState) {
    W ("Estado maximo del procesador: {0}% con cargador / {1}% con bateria" -f $maxState.AC, $maxState.DC)
    if ($maxState.AC -lt 100) { Alert ("El estado maximo del procesador con cargador esta en {0}%: eso suele desactivar el turbo de la CPU." -f $maxState.AC) }
}
$boost = Get-PowerSettingAcDc 'SUB_PROCESSOR' 'PERFBOOSTMODE'
if ($boost) {
    W ("Modo de turbo del procesador (0 = desactivado): {0} con cargador" -f $boost.AC)
    if ($boost.AC -eq 0) { Alert 'El turbo de la CPU esta desactivado en el plan de energia (PERFBOOSTMODE = 0).' }
}

$acer = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Nitro|Predator|AcerAgent|PSAgent|QuickAccess' } | Select-Object -ExpandProperty Name -Unique)
W ("Software de Acer en ejecucion: {0}" -f $(if ($acer) { $acer -join ', ' } else { 'ninguno detectado' }))
W 'El modo de NitroSense (Silencioso/Equilibrado/Rendimiento/Turbo) no se puede leer desde aqui: revisalo en la app.'

# ---------------------------------------------------------------------------
Section '4. Funciones de juego de Windows'
$gm = Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
W ("Modo de juego: {0}" -f $(if ($gm -eq 0) { 'DESACTIVADO' } else { 'activado' }))
if ($gm -eq 0) { Alert 'Modo de juego desactivado. En Windows 11 se recomienda activado (ver guia).' }

$dvrKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$hist = Get-RegValue $dvrKey 'HistoricalCaptureEnabled'
W ("Grabacion en segundo plano ('Grabar lo que paso'): {0}" -f $(if ($hist -eq 1) { 'ACTIVADA' } else { 'desactivada' }))
if ($hist -eq 1) { Alert "Grabacion en segundo plano activada: graba continuamente y consume GPU. Desactivala en Configuracion > Juegos > Capturas." }

$hags = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
W ("Programacion de GPU acelerada por hardware (HAGS): {0}" -f $(switch ($hags) { 2 { 'activada' } 1 { 'desactivada' } default { 'valor por defecto de Windows' } }))

$gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$dxGlobal = Get-RegValue $gpuKey 'DirectXUserGlobalSettings'
W ("Ajustes DirectX globales: {0}" -f $(if ($dxGlobal) { $dxGlobal } else { 'no definidos (valores por defecto)' }))
if ($dxGlobal -match 'SwapEffectUpgradeEnable=0') { Alert '"Optimizaciones para juegos en ventana" desactivado. Suele convenir activarlo (ver guia).' }

$gpuPrefs = @{}
if (Test-Path -LiteralPath $gpuKey) {
    $skip = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider', 'DirectXUserGlobalSettings'
    foreach ($p in (Get-ItemProperty -LiteralPath $gpuKey).PSObject.Properties) {
        if ($skip -contains $p.Name) { continue }
        $gpuPrefs[$p.Name.ToLower()] = "$($p.Value)"
    }
}
W ("Preferencias de GPU por aplicacion registradas: {0}" -f $gpuPrefs.Count)
foreach ($k in $gpuPrefs.Keys) {
    if ($k -notmatch 'roblox|fishstrap|bloxstrap') { continue }
    $pref = if ($gpuPrefs[$k] -match 'GpuPreference=(\d)') {
        switch ($Matches[1]) { '0' { 'Windows decide' } '1' { 'Ahorro de energia (Intel)' } '2' { 'Alto rendimiento (NVIDIA)' } default { $gpuPrefs[$k] } }
    } else { $gpuPrefs[$k] }
    W "  $k -> $pref"
    if (-not (Test-Path -LiteralPath $k)) { W '    (esta ruta ya no existe: entrada obsoleta de una version anterior de Roblox)' }
    elseif ($pref -ne 'Alto rendimiento (NVIDIA)') { Alert "Roblox tiene preferencia de GPU '$pref' en: $k" }
}

foreach ($hive in 'HKCU:', 'HKLM:') {
    $lk = "$hive\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    if (-not (Test-Path -LiteralPath $lk)) { continue }
    foreach ($p in (Get-ItemProperty -LiteralPath $lk).PSObject.Properties) {
        if ($p.Name -match 'roblox|fishstrap|bloxstrap') {
            W "Bandera de compatibilidad ($hive): $($p.Name) = $($p.Value)"
            Alert 'Roblox tiene banderas de compatibilidad de Windows. Si no las pusiste a proposito, revisa la guia (seccion Windows).'
        }
    }
}

# ---------------------------------------------------------------------------
Section '5. Procesos en segundo plano y superposiciones'
$nCpu = [Environment]::ProcessorCount
function Get-ProcSample {
    $h = @{}
    foreach ($r in Get-CimInstance Win32_PerfRawData_PerfProc_Process) {
        if ($r.Name -eq '_Total' -or $r.Name -eq 'Idle') { continue }
        $h["$($r.IDProcess)"] = $r
    }
    $h
}
W 'Midiendo uso de CPU durante 3 segundos...'
$s1 = Get-ProcSample
Start-Sleep -Seconds 3
$s2 = Get-ProcSample
$rows = foreach ($k in $s2.Keys) {
    if (-not $s1.ContainsKey($k)) { continue }
    $a = $s1[$k]; $b = $s2[$k]
    $dt = [double]$b.Timestamp_Sys100NS - [double]$a.Timestamp_Sys100NS
    if ($dt -le 0) { continue }
    [pscustomobject]@{
        Nombre = $b.Name
        CPU    = ([double]$b.PercentProcessorTime - [double]$a.PercentProcessorTime) / $dt * 100 / $nCpu
        RamMB  = [double]$b.WorkingSetPrivate / 1MB
    }
}
W 'Top 12 por CPU (% del total del procesador):'
$rows | Sort-Object CPU -Descending | Select-Object -First 12 | ForEach-Object { W ("  {0,-34} {1,5:N1}%   {2,7:N0} MB" -f $_.Nombre, $_.CPU, $_.RamMB) }
W 'Top 8 por memoria privada:'
$rows | Sort-Object RamMB -Descending | Select-Object -First 8 | ForEach-Object { W ("  {0,-34} {1,7:N0} MB" -f $_.Nombre, $_.RamMB) }

$known = [ordered]@{
    'Discord'           = 'Discord: desactiva su superposicion del juego (guia, seccion superposiciones).'
    'GameBar'           = 'Xbox Game Bar abierta.'
    'XboxPcApp'         = 'App de Xbox abierta.'
    'NVIDIA Overlay'    = 'Superposicion de NVIDIA App (Alt+Z). Desactiva Repeticion instantanea si no la usas.'
    'obs64'             = 'OBS abierto (grabacion/streaming).'
    'Medal'             = 'Medal.tv (graba en segundo plano).'
    'Overwolf'          = 'Overwolf (superposicion).'
    'RTSS'              = 'RivaTuner (superposicion/limitador): no lo combines con otro limitador de FPS.'
    'MSIAfterburner'    = 'MSI Afterburner.'
    'rbxfpsunlocker'    = 'rbxfpsunlocker: OBSOLETO (Roblox ya tiene limite de FPS propio). Cierralo.'
    'wallpaper32'       = 'Wallpaper Engine (fondo animado consume GPU).'
    'wallpaper64'       = 'Wallpaper Engine (fondo animado consume GPU).'
    'OneDrive'          = 'OneDrive (si sincroniza durante la partida usa disco y red).'
    'chrome'            = 'Chrome: pestanas con video consumen CPU/GPU.'
    'msedge'            = 'Edge: pestanas con video consumen CPU/GPU.'
    'opera'             = 'Opera: pestanas con video consumen CPU/GPU.'
    'firefox'           = 'Firefox: pestanas con video consumen CPU/GPU.'
    'steam'             = 'Steam abierto (no afecta a Roblox salvo descargas).'
    'EpicGamesLauncher' = 'Epic Games Launcher (descargas en segundo plano).'
}
$running = @(Get-Process -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique)
W 'Programas conocidos que pueden influir (abiertos ahora):'
$anyKnown = $false
foreach ($k in $known.Keys) { if ($running -contains $k) { W "  - $($known[$k])"; $anyKnown = $true } }
if (-not $anyKnown) { W '  (ninguno de la lista)' }
if ($running -contains 'rbxfpsunlocker') { Alert 'rbxfpsunlocker esta abierto: es obsoleto y puede interferir con Roblox.' }

W 'Programas configurados para iniciar con Windows (pueden estar ya deshabilitados; confirma en Configuracion > Aplicaciones > Inicio):'
Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | ForEach-Object { W ("  - {0}  [{1}]" -f $_.Name, $_.Location) }

# ---------------------------------------------------------------------------
Section '6. Almacenamiento'
foreach ($d in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
    if (-not $d.Size) { continue }
    $freePct = 100 * $d.FreeSpace / $d.Size
    W ("{0} libre {1:N1} GB de {2:N1} GB ({3:N0}%)" -f $d.DeviceID, ($d.FreeSpace / 1GB), ($d.Size / 1GB), $freePct)
    if ($freePct -lt 15 -or $d.FreeSpace -lt 20GB) { Alert ("Poco espacio libre en {0}. Deja al menos ~15-20% libre (sin usar limpiadores agresivos)." -f $d.DeviceID) }
}
try {
    Get-PhysicalDisk -ErrorAction Stop | ForEach-Object { W ("Disco: {0} - {1} {2} - estado {3}" -f $_.FriendlyName, $_.MediaType, $_.BusType, $_.HealthStatus) }
} catch { W 'Disco fisico: no se pudo consultar.' }
foreach ($p in @("$la\Roblox\logs", "$env:TEMP\Roblox")) {
    if (Test-Path -LiteralPath $p) {
        $sz = (Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        W ("Tamano de {0}: {1:N0} MB (solo informativo, no se borra nada)" -f $p, ($sz / 1MB))
    }
}

# ---------------------------------------------------------------------------
Section '7. Red'
$up = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
foreach ($a in $up) {
    W ("Adaptador activo: {0} - {1} - {2}" -f $a.Name, $a.InterfaceDescription, $a.LinkSpeed)
    if ($a.InterfaceDescription -match 'VPN|TAP-|WireGuard|Tailscale|ZeroTier|Radmin|Hamachi|OpenVPN|Wintun') {
        Alert "Adaptador VPN/tunel activo ($($a.InterfaceDescription)). Si el trafico del juego pasa por el, puede subir el ping."
    }
}
$route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
if ($route) {
    $ad = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
    W ("Salida a Internet por: {0} ({1}); puerta de enlace {2}" -f $ad.Name, $ad.InterfaceDescription, $route.NextHop)
    if ("$($ad.PhysicalMediaType)" -match '802\.11') {
        Alert 'Conectado por Wi-Fi. Para Blade Ball, Ethernet suele dar ping mas estable. Mide con 4-prueba-red.ps1.'
        W 'Estado Wi-Fi (sin nombre de red ni direcciones):'
        & netsh wlan show interfaces 2>$null | Where-Object { $_ -match ':' -and $_ -notmatch 'SSID|BSSID|Perfil|Profile|sica|Physical|Name|Nombre|GUID' } |
            ForEach-Object { W "  $($_.Trim())" }
    }
}

# ---------------------------------------------------------------------------
Section '8. Roblox y launcher'
$latestTag = $null
if (-not $SinInternet) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/fishstrap/fishstrap/releases/latest' -TimeoutSec 15 -UseBasicParsing -Headers @{ 'User-Agent' = 'RobloxOpt-diagnostico' }
        $latestTag = "$($rel.tag_name)"
        W ("Ultima version de Fishstrap en su GitHub oficial: {0} (publicada {1:yyyy-MM-dd})" -f $latestTag, [datetime]$rel.published_at)
    } catch { W 'No se pudo consultar la ultima version de Fishstrap en GitHub (sin conexion o limite de la API).' }
}

foreach ($ln in 'Fishstrap', 'Bloxstrap') {
    $base = Join-Path $la $ln
    if (-not (Test-Path -LiteralPath $base)) { W "$ln no esta instalado en $base"; continue }
    $exe = Get-ChildItem -LiteralPath $base -Filter '*.exe' -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq $ln } | Select-Object -First 1
    $ver = if ($exe) { $exe.VersionInfo.ProductVersion } else { 'desconocida' }
    W "$ln instalado en $base (version $ver)"
    if ($ln -eq 'Fishstrap' -and $latestTag -and $exe) {
        try {
            $inst = [version](($ver -split '[^0-9.]')[0])
            $last = [version](($latestTag.TrimStart('v', 'V') -split '[^0-9.]')[0])
            $instN = New-Object Version $inst.Major, $inst.Minor, ([math]::Max($inst.Build, 0))
            $lastN = New-Object Version $last.Major, $last.Minor, ([math]::Max($last.Build, 0))
            if ($instN -lt $lastN) { Alert "Fishstrap $ver esta desactualizado (ultima: $latestTag). Actualiza solo desde github.com/fishstrap/fishstrap o fishstrap.app." }
            else { W '  Fishstrap esta al dia.' }
        } catch { W '  No se pudo comparar la version.' }
    }
    $sj = Join-Path $base 'Settings.json'
    if (Test-Path -LiteralPath $sj) {
        try {
            $s = Get-Content -LiteralPath $sj -Raw | ConvertFrom-Json
            W '  Ajustes relevantes de Settings.json:'
            foreach ($p in $s.PSObject.Properties) {
                if ($p.Name -notmatch 'Render|Fps|Frame|Fullscreen|Gpu|Static|Channel|Quality|Display|Optimi|Experiment|Matchmaking|Cookie|Multi|Update') { continue }
                $val = $p.Value
                if ($p.Name -match 'Cookie|Token|Auth' -and $val -is [string] -and $val.Length -gt 5) { $val = '(oculto)' }
                elseif ($null -ne $val -and -not ($val -is [string] -or $val -is [ValueType])) { $val = ConvertTo-Json -InputObject $val -Compress -Depth 3 }
                W ("    {0} = {1}" -f $p.Name, $val)
            }
        } catch { W "  No se pudo leer Settings.json: $($_.Exception.Message)" }
    }
}

W ''
W 'FastFlags encontradas (ClientAppSettings.json):'
$ffRoots = @("$la\Fishstrap\Modifications", "$la\Fishstrap\Versions", "$la\Bloxstrap\Modifications", "$la\Bloxstrap\Versions", "$la\Roblox\Versions")
$ffFiles = @(foreach ($r in $ffRoots) {
    if (Test-Path -LiteralPath $r) { Get-ChildItem -LiteralPath $r -Recurse -Depth 3 -Filter 'ClientAppSettings.json' -File -ErrorAction SilentlyContinue }
})
if ($ffFiles.Count -eq 0) { W '  Ningun ClientAppSettings.json: no hay FastFlags personalizadas (correcto para empezar).' }
foreach ($f in $ffFiles) {
    W "  Archivo: $($f.FullName)"
    try {
        $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $props = @($j.PSObject.Properties)
        if ($props.Count -eq 0) { W '    (vacio: sin FastFlags)'; continue }
        $ignored = 0
        foreach ($p in $props) {
            $ok = $allowlist -contains $p.Name
            if (-not $ok) { $ignored++ }
            W ("    [{0}] {1} = {2}" -f $(if ($ok) { 'PERMITIDA' } else { 'IGNORADA' }), $p.Name, $p.Value)
        }
        if ($ignored -gt 0) {
            Alert "$ignored FastFlag(s) fuera de la lista permitida en $($f.FullName). Roblox las ignora: quitalas desde el editor de Fishstrap para dejar la configuracion limpia."
        }
    } catch { W "    No se pudo leer: $($_.Exception.Message)" }
}

W ''
W 'Ejecutables de Roblox encontrados:'
$exeRoots = @("$la\Fishstrap\Versions", "$la\Bloxstrap\Versions", "$la\Roblox\Versions", "${env:ProgramFiles(x86)}\Roblox\Versions")
$exes = @(foreach ($r in $exeRoots) {
    if (Test-Path -LiteralPath $r) { Get-ChildItem -LiteralPath $r -Recurse -Depth 2 -Filter 'RobloxPlayerBeta.exe' -File -ErrorAction SilentlyContinue }
})
if ($exes.Count -eq 0) { W '  Ninguno encontrado en las rutas habituales.' }
foreach ($e in $exes) {
    W ("  {0}  (version {1}, {2:yyyy-MM-dd})" -f $e.FullName, $e.VersionInfo.FileVersion, $e.LastWriteTime)
    if ($gpuPrefs.ContainsKey($e.FullName.ToLower())) { W "    Preferencia de GPU en Windows: $($gpuPrefs[$e.FullName.ToLower()])" }
    else { W '    Sin preferencia de GPU en Windows para esta ruta exacta (ver guia si Roblox no usa la NVIDIA).' }
    if ($e.Directory.Name -match '^version-') {
        W '    Carpeta con hash de version: cambia con cada actualizacion de Roblox, y con ella la ruta que usa Windows.'
    }
}

W ''
W 'Ajustes guardados del juego (GlobalBasicSettings):'
$gbs = @(Get-ChildItem -LiteralPath "$la\Roblox" -Filter 'GlobalBasicSettings_*.xml' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'Studio' })
if ($gbs.Count -eq 0) { W '  No encontrado.' }
foreach ($f in $gbs) {
    W "  $($f.Name):"
    try {
        [xml]$x = Get-Content -LiteralPath $f.FullName -Raw
        foreach ($nd in $x.SelectNodes('//*[@name]')) {
            $name = $nd.GetAttribute('name')
            if ($name -match 'Frame|Fps|Quality|Fullscreen|Graphics|VSync|Performance') { W ("    {0} = {1}" -f $name, $nd.InnerText) }
        }
    } catch { W "    No se pudo leer: $($_.Exception.Message)" }
}

if ($robloxRunning.Count -gt 0) { W ''; W ("Roblox abierto ahora (PID {0})." -f (($robloxRunning | ForEach-Object { $_.Id }) -join ', ')) }

# ---------------------------------------------------------------------------
Section 'RESUMEN DE ALERTAS'
if ($alerts.Count -eq 0) { W 'Sin alertas automaticas. Revisa igualmente cada seccion.' }
else { for ($i = 0; $i -lt $alerts.Count; $i++) { W ("{0,2}. {1}" -f ($i + 1), $alerts[$i]) } }
W ''
W 'Este script no mide FPS, frametimes ni temperatura de CPU.'
W 'Siguiente paso: medicion base con PresentMon + 3-monitor-carga.ps1 + HWiNFO (ver guia).'

$lines | Out-File -LiteralPath $reportPath -Encoding UTF8
Write-Host ''
Write-Host "Informe guardado en: $reportPath" -ForegroundColor Green
