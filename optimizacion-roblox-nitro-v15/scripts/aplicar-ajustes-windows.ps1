<#
  aplicar-ajustes-windows.ps1
  Aplica automaticamente los ajustes SEGUROS de Windows de la guia, con respaldo y confirmacion:
    1) Modo de juego: activado
    2) Grabacion en segundo plano ("Grabar lo que paso"): desactivada
    3) Roblox en la GPU de alto rendimiento (RTX 2050) en la configuracion de graficos de Windows
    4) "Optimizaciones para juegos en ventana": activado
    5) Solo si esta limitado: estado maximo del procesador con cargador al 100% (turbo de la CPU)

  Antes de cambiar nada: muestra el plan, pide confirmacion, ejecuta 1-respaldo.ps1 y guarda
  los valores anteriores en un .json para poder deshacer exactamente lo que se cambio.
  No hace falta administrador. NO toca NVIDIA, NitroSense, ajustes de Roblox, Defender,
  firewall, servicios ni actualizaciones.

  Uso:
    powershell -ExecutionPolicy Bypass -File .\aplicar-ajustes-windows.ps1               # aplicar
    powershell -ExecutionPolicy Bypass -File .\aplicar-ajustes-windows.ps1 -SoloMostrar  # solo ver el plan
    powershell -ExecutionPolicy Bypass -File .\aplicar-ajustes-windows.ps1 -Deshacer "<ruta del .json>"
#>
[CmdletBinding()]
param(
    [string]$Deshacer = '',
    [switch]$SoloMostrar,
    [switch]$SinRespaldo,
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt')
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destino -Force | Out-Null

# --- Ayudantes ----------------------------------------------------------------------
function Get-RegState([string]$key, [string]$name) {
    if (Test-Path -LiteralPath $key) {
        $item = Get-Item -LiteralPath $key
        if ($item.GetValueNames() -contains $name) {
            return [pscustomobject]@{ Existia = $true; Valor = $item.GetValue($name); Tipo = "$($item.GetValueKind($name))" }
        }
    }
    [pscustomobject]@{ Existia = $false; Valor = $null; Tipo = $null }
}
function Set-RegValue([string]$key, [string]$name, $value, [string]$type) {
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }   # solo si no existe
    New-ItemProperty -LiteralPath $key -Name $name -Value $value -PropertyType $type -Force | Out-Null
}
function Remove-RegValue([string]$key, [string]$name) {
    if (Test-Path -LiteralPath $key) { Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue }
}
# Cambia una clave dentro de un texto tipo "A=1;B=0;" sin tocar las demas.
function Merge-KvString([string]$s, [string]$k, [string]$v) {
    $pairs = [ordered]@{}
    foreach ($p in ("$s" -split ';')) { if ($p -match '^\s*([^=]+)=(.*)$') { $pairs[$Matches[1].Trim()] = $Matches[2].Trim() } }
    $pairs[$k] = $v
    (($pairs.Keys | ForEach-Object { "$_=$($pairs[$_])" }) -join ';') + ';'
}
function Get-PowerSettingAcDc([string]$scheme, [string]$sub, [string]$setting) {
    try { $out = & powercfg /query $scheme $sub $setting 2>$null } catch { return $null }
    $hex = @([regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject]@{ AC = [Convert]::ToInt32($hex[-2], 16); DC = [Convert]::ToInt32($hex[-1], 16) }
}

# --- Deshacer ------------------------------------------------------------------------
if ($Deshacer) {
    if (-not (Test-Path -LiteralPath $Deshacer)) { throw "No existe: $Deshacer" }
    $raw = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Deshacer -Raw)
    $items = @($raw | ForEach-Object { $_ })   # en PowerShell 5.1 un array JSON llega como un solo objeto
    Write-Host 'Se restaurara el valor anterior de:'
    foreach ($c in $items) { Write-Host "  - $($c.Descripcion)" }
    if ((Read-Host 'Escribe S para continuar') -notmatch '^[sS]$') { Write-Host 'Cancelado. No se cambio nada.'; return }
    foreach ($c in $items) {
        try {
            if ($c.Clase -eq 'registro') {
                if ($c.Existia) { Set-RegValue $c.Clave $c.Nombre $c.ValorAnterior $c.TipoAnterior }
                else { Remove-RegValue $c.Clave $c.Nombre }
            } elseif ($c.Clase -eq 'powercfg') {
                & powercfg /setacvalueindex $c.Esquema SUB_PROCESSOR PROCTHROTTLEMAX $c.ValorAnterior
                & powercfg /setactive $c.Esquema
            }
            Write-Host "[OK] Deshecho: $($c.Descripcion)"
        } catch { Write-Warning "No se pudo restaurar '$($c.Descripcion)': $($_.Exception.Message)" }
    }
    Write-Host 'Listo. Reinicia Roblox para que lo note.' -ForegroundColor Green
    return
}

# --- Plan ------------------------------------------------------------------------------
$changes = New-Object System.Collections.Generic.List[object]
function Add-RegChange([string]$desc, [string]$key, [string]$name, $value, [string]$type, [string]$ahora) {
    $cur = Get-RegState $key $name
    $changes.Add([pscustomobject]@{
        Clase = 'registro'; Descripcion = $desc; Clave = $key; Nombre = $name
        ValorNuevo = $value; TipoNuevo = $type
        Existia = $cur.Existia; ValorAnterior = $cur.Valor; TipoAnterior = $cur.Tipo
    })
    Write-Host ("  [CAMBIAR]  {0}   (ahora: {1})" -f $desc, $ahora)
}

Write-Host 'Revisando el estado actual...' -ForegroundColor Cyan

# 1) Modo de juego (si el valor no existe, Windows lo tiene activado por defecto)
$gmKey = 'HKCU:\Software\Microsoft\GameBar'
$gm = Get-RegState $gmKey 'AutoGameModeEnabled'
if ($gm.Existia -and $gm.Valor -eq 0) { Add-RegChange 'Modo de juego: activado' $gmKey 'AutoGameModeEnabled' 1 'DWord' 'desactivado' }
else { Write-Host '  [ya esta]  Modo de juego activado' }

# 2) Grabacion en segundo plano (si no existe, esta desactivada)
$dvrKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$hist = Get-RegState $dvrKey 'HistoricalCaptureEnabled'
if ($hist.Existia -and $hist.Valor -ne 0) { Add-RegChange "Grabacion en segundo plano ('Grabar lo que paso'): desactivada" $dvrKey 'HistoricalCaptureEnabled' 0 'DWord' 'activada' }
else { Write-Host "  [ya esta]  Grabacion en segundo plano desactivada" }

# 3) Roblox en la GPU de alto rendimiento
$gpuKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$la = $env:LOCALAPPDATA
$exeRoots = @("$la\Fishstrap\Versions", "$la\Bloxstrap\Versions", "$la\Roblox\Versions", "${env:ProgramFiles(x86)}\Roblox\Versions")
$exes = @(foreach ($r in $exeRoots) {
    if (Test-Path -LiteralPath $r) { Get-ChildItem -LiteralPath $r -Recurse -Depth 2 -Filter 'RobloxPlayerBeta.exe' -File -ErrorAction SilentlyContinue }
})
if ($exes.Count -eq 0) { Write-Host '  [omitido]  No se encontro RobloxPlayerBeta.exe (abre Roblox una vez con Fishstrap y vuelve a ejecutar).' }
$versionHash = $false
foreach ($e in $exes) {
    $cur = Get-RegState $gpuKey $e.FullName
    if ($cur.Existia -and "$($cur.Valor)" -match 'GpuPreference=2') { Write-Host "  [ya esta]  GPU de alto rendimiento para $($e.FullName)"; continue }
    $new = Merge-KvString $(if ($cur.Existia) { "$($cur.Valor)" } else { '' }) 'GpuPreference' '2'
    Add-RegChange "Roblox en GPU de alto rendimiento (NVIDIA): $($e.FullName)" $gpuKey $e.FullName $new 'String' $(if ($cur.Existia) { $cur.Valor } else { 'Windows decide' })
    if ($e.Directory.Name -match '^version-') { $versionHash = $true }
}

# 4) Optimizaciones para juegos en ventana
$dx = Get-RegState $gpuKey 'DirectXUserGlobalSettings'
if ($dx.Existia -and "$($dx.Valor)" -match 'SwapEffectUpgradeEnable=1') { Write-Host '  [ya esta]  Optimizaciones para juegos en ventana activadas' }
else {
    $new = Merge-KvString $(if ($dx.Existia) { "$($dx.Valor)" } else { '' }) 'SwapEffectUpgradeEnable' '1'
    Add-RegChange 'Optimizaciones para juegos en ventana: activado' $gpuKey 'DirectXUserGlobalSettings' $new 'String' $(if ($dx.Existia) { $dx.Valor } else { 'valor por defecto' })
}

# 5) Estado maximo del procesador con cargador (solo si esta por debajo de 100%)
$scheme = $null
$m = [regex]::Match(((powercfg /getactivescheme) -join ' '), '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
if ($m.Success) { $scheme = $m.Value }
$ms = if ($scheme) { Get-PowerSettingAcDc $scheme 'SUB_PROCESSOR' 'PROCTHROTTLEMAX' } else { $null }
if ($ms -and $ms.AC -lt 100) {
    $changes.Add([pscustomobject]@{ Clase = 'powercfg'; Descripcion = 'Estado maximo del procesador con cargador: 100%'; Esquema = $scheme; ValorAnterior = $ms.AC })
    Write-Host ("  [CAMBIAR]  Estado maximo del procesador con cargador: 100%   (ahora: {0}%)" -f $ms.AC)
} elseif ($ms) { Write-Host '  [ya esta]  Estado maximo del procesador con cargador al 100%' }

Write-Host ''
if ($changes.Count -eq 0) {
    Write-Host 'No hay nada que cambiar: estos ajustes ya estaban bien.' -ForegroundColor Green
} elseif ($SoloMostrar) {
    Write-Host '(-SoloMostrar: no se cambio nada)'
} else {
    if ((Read-Host ("Se aplicaran {0} cambio(s). Escribe S para continuar" -f $changes.Count)) -notmatch '^[sS]$') { Write-Host 'Cancelado. No se cambio nada.'; return }

    if (-not $SinRespaldo) {
        $bk = Join-Path $PSScriptRoot '1-respaldo.ps1'
        if (Test-Path -LiteralPath $bk) { Write-Host 'Haciendo respaldo...'; & $bk -Destino $Destino | Out-Null }
    }

    # Se guardan los valores anteriores ANTES de cambiar, para poder deshacer aunque algo falle a mitad.
    $undoPath = Join-Path $Destino ("deshacer-ajustes-windows-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    ConvertTo-Json -InputObject $changes.ToArray() -Depth 3 | Out-File -LiteralPath $undoPath -Encoding UTF8

    $ok = 0
    foreach ($c in $changes) {
        try {
            if ($c.Clase -eq 'registro') { Set-RegValue $c.Clave $c.Nombre $c.ValorNuevo $c.TipoNuevo }
            else {
                & powercfg /setacvalueindex $c.Esquema SUB_PROCESSOR PROCTHROTTLEMAX 100
                if ($LASTEXITCODE -ne 0) { throw "powercfg devolvio el codigo $LASTEXITCODE" }
                & powercfg /setactive $c.Esquema
            }
            Write-Host "[OK] $($c.Descripcion)" -ForegroundColor Green
            $ok++
        } catch { Write-Warning "No se pudo aplicar '$($c.Descripcion)': $($_.Exception.Message)" }
    }
    Write-Host ''
    Write-Host ("Aplicados {0} de {1}. Cierra y vuelve a abrir Roblox para que los note." -f $ok, $changes.Count)
    Write-Host 'Para deshacer exactamente estos cambios:'
    Write-Host ("  powershell -ExecutionPolicy Bypass -File `"{0}`" -Deshacer `"{1}`"" -f $PSCommandPath, $undoPath)
}

if ($versionHash) {
    Write-Host ''
    Write-Host 'Nota: Roblox esta en una carpeta "version-..." que cambia con cada actualizacion.' -ForegroundColor Yellow
    Write-Host 'Activa el directorio estatico en Fishstrap o vuelve a ejecutar este script tras cada actualizacion.'
}

Write-Host ''
Write-Host 'Esto NO se puede hacer de forma segura por script. Hazlo a mano (guia, secciones 5 a 7):' -ForegroundColor Cyan
Write-Host '  [ ] Pantalla a 165 Hz: Configuracion > Sistema > Pantalla > Pantalla avanzada'
Write-Host '  [ ] Modo de energia "Mejor rendimiento" (con cargador): Configuracion > Sistema > Energia y bateria'
Write-Host '  [ ] NitroSense en Rendimiento o Turbo'
Write-Host '  [ ] NVIDIA, perfil de Roblox: rendimiento maximo, baja latencia Activado, sincronizacion vertical Desactivado'
Write-Host '  [ ] Roblox: graficos Manual, calidad 1-3, pantalla completa (F11), limite de FPS 144 o 165'
Write-Host '  [ ] Discord: superposicion del juego desactivada'
Write-Host '  [ ] Fishstrap: borrar las FastFlags que el diagnostico marca como IGNORADA'
