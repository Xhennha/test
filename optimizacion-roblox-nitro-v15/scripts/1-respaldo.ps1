<#
  1-respaldo.ps1
  Copia de seguridad de las configuraciones que la guia puede llegar a cambiar.
  NO modifica nada: solo lee y copia a una carpeta nueva en el Escritorio.

  Que guarda:
    - Fishstrap/Bloxstrap: Settings.json y Modifications\ClientSettings (FastFlags)
    - Roblox: GlobalBasicSettings_*.xml (ajustes del juego: calidad, limite de FPS...)
    - Registro (solo exportar, HKCU): preferencias de GPU por aplicacion, Game Bar,
      grabacion en segundo plano, banderas de compatibilidad
    - Estado actual de energia, pantalla, modo juego y HAGS en un .txt
    - manifiesto.json, que usa revertir-archivos.ps1

  Uso (PowerShell normal, no hace falta administrador):
    powershell -ExecutionPolicy Bypass -File .\1-respaldo.ps1
#>
[CmdletBinding()]
param(
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt')
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $Destino "respaldo-$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

$log = New-Object System.Collections.Generic.List[string]
$manifest = New-Object System.Collections.Generic.List[object]

function Add-Log([string]$msg) { $log.Add($msg); Write-Host $msg }

function Get-RegValue([string]$path, [string]$name) {
    try { (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name } catch { $null }
}

# Copia un archivo o carpeta si existe y lo anota en el manifiesto (exista o no).
function Backup-Item([string]$src, [string]$rel) {
    $exists = Test-Path -LiteralPath $src
    if ($exists) {
        $dst = Join-Path $out $rel
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        Add-Log "[OK] $src"
    } else {
        Add-Log "[--] No existe (se anota igual): $src"
    }
    $manifest.Add([pscustomobject]@{ Origen = $src; Copia = $rel; Existia = $exists })
}

Add-Log "Respaldo en: $out"
Add-Log ''

# --- Launchers -------------------------------------------------------------
$la = $env:LOCALAPPDATA
foreach ($ln in 'Fishstrap', 'Bloxstrap') {
    $base = Join-Path $la $ln
    if (-not (Test-Path -LiteralPath $base)) { Add-Log "[--] $ln no esta instalado en $base"; continue }
    Backup-Item (Join-Path $base 'Settings.json') "$ln\Settings.json"
    Backup-Item (Join-Path $base 'Modifications\ClientSettings') "$ln\Modifications\ClientSettings"
}

# --- Ajustes del juego de Roblox -------------------------------------------
$rbx = Join-Path $la 'Roblox'
$gbs = @(Get-ChildItem -LiteralPath $rbx -Filter 'GlobalBasicSettings_*.xml' -File -ErrorAction SilentlyContinue)
if ($gbs.Count -eq 0) { Add-Log "[--] No se encontro GlobalBasicSettings_*.xml en $rbx" }
foreach ($f in $gbs) { Backup-Item $f.FullName "Roblox\$($f.Name)" }

# --- Registro (solo exportar) ----------------------------------------------
$regDir = Join-Path $out 'registro'
New-Item -ItemType Directory -Path $regDir -Force | Out-Null
$regKeys = [ordered]@{
    'gpu-preferencias.reg'  = 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
    'gamebar.reg'           = 'HKCU\Software\Microsoft\GameBar'
    'gamedvr.reg'           = 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    'gameconfigstore.reg'   = 'HKCU\System\GameConfigStore'
    'compatibilidad.reg'    = 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
}
foreach ($file in $regKeys.Keys) {
    $key = $regKeys[$file]
    $null = & reg.exe export $key (Join-Path $regDir $file) /y 2>&1
    if ($LASTEXITCODE -eq 0) { Add-Log "[OK] Registro exportado: $key" }
    else { Add-Log "[--] Clave no encontrada (normal si nunca se uso): $key" }
}

# --- Estado actual (texto) --------------------------------------------------
$st = New-Object System.Collections.Generic.List[string]
$st.Add("Estado original - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$st.Add('')
$st.Add('Plan de energia activo:')
$st.Add(((powercfg /getactivescheme) -join ' '))
$pp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$st.Add("Modo de energia Windows 11 (enchufado, GUID): $(Get-RegValue $pp 'ActiveOverlayAcPowerScheme')")
$st.Add("Modo de energia Windows 11 (bateria, GUID):  $(Get-RegValue $pp 'ActiveOverlayDcPowerScheme')")
$st.Add('  ded574b5-... = Mejor rendimiento | 00000000-... o vacio = Equilibrado | 961cc777-... = Mejor eficiencia')
$st.Add('')
$st.Add('Pantallas:')
foreach ($v in Get-CimInstance Win32_VideoController) {
    $st.Add(("  {0}: {1}x{2} @ {3} Hz, driver {4}" -f $v.Name, $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution, $v.CurrentRefreshRate, $v.DriverVersion))
}
$st.Add('')
$st.Add("Modo de juego (AutoGameModeEnabled; vacio = activado por defecto): $(Get-RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled')")
$st.Add("Grabacion en segundo plano (HistoricalCaptureEnabled): $(Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled')")
$st.Add("Capturas (AppCaptureEnabled): $(Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled')")
$st.Add("HAGS (HwSchMode: 2 = activado, 1 = desactivado, vacio = por defecto): $(Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode')")
$st.Add("Ajustes DirectX globales (juegos en ventana / VRR): $(Get-RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')")
$st | Out-File -LiteralPath (Join-Path $out 'estado-original.txt') -Encoding UTF8
Add-Log '[OK] estado-original.txt'

# --- NVIDIA: no hay exportacion oficial del perfil ---------------------------
@(
    'El perfil de Roblox del Panel de control de NVIDIA no se puede exportar sin herramientas de terceros.',
    'Antes de cambiar nada, haz capturas de pantalla de:',
    '  Panel de control de NVIDIA > Administrar la configuracion 3D > Configuracion de programa > Roblox',
    'y guardalas en esta carpeta. Para volver a los valores del driver: boton "Restaurar" en ese perfil.'
) | Out-File -LiteralPath (Join-Path $out 'nvidia-LEEME.txt') -Encoding UTF8

ConvertTo-Json -InputObject $manifest.ToArray() -Depth 3 | Out-File -LiteralPath (Join-Path $out 'manifiesto.json') -Encoding UTF8
$log | Out-File -LiteralPath (Join-Path $out 'respaldo-log.txt') -Encoding UTF8

Write-Host ''
Write-Host "Listo. Respaldo guardado en: $out" -ForegroundColor Green
Write-Host 'Falta a mano: capturas del perfil de Roblox en el Panel de control de NVIDIA (ver nvidia-LEEME.txt).'
