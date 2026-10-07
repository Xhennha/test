<#
  revertir-archivos.ps1
  Restaura los archivos guardados por 1-respaldo.ps1:
    - Fishstrap/Bloxstrap: Settings.json y Modifications\ClientSettings (FastFlags)
    - Roblox: GlobalBasicSettings_*.xml (ajustes del juego)

  No borra nada: antes de sobrescribir, mueve los archivos actuales a
  <respaldo>\antes-de-revertir-<fecha>. Si un archivo no existia en el respaldo
  y ahora si, tambien se mueve ahi (asi queda como estaba originalmente).

  NO revierte el registro, NVIDIA ni las opciones de Windows: esos se vuelven
  atras desde sus pantallas (ver la seccion "Como revertir" de la guia).

  Uso (cierra Roblox y Fishstrap antes):
    powershell -ExecutionPolicy Bypass -File .\revertir-archivos.ps1 -Respaldo "$HOME\Desktop\RobloxOpt\respaldo-20261007-120000"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Respaldo
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $Respaldo 'manifiesto.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "No encuentro manifiesto.json en $Respaldo" }

$busy = @(Get-Process -Name 'RobloxPlayerBeta', 'Fishstrap', 'Bloxstrap' -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) { throw ("Cierra primero: {0}" -f (($busy | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')) }

$raw = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw)
$items = @($raw | ForEach-Object { $_ })   # en PowerShell 5.1 un array JSON llega como un solo objeto
$safety = Join-Path $Respaldo ("antes-de-revertir-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

Write-Host 'Se va a hacer lo siguiente:'
$plan = foreach ($it in $items) {
    $nowExists = Test-Path -LiteralPath $it.Origen
    if ($it.Existia) {
        Write-Host "  RESTAURAR  $($it.Origen)"
        [pscustomobject]@{ Item = $it; Accion = 'restaurar'; Existe = $nowExists }
    } elseif ($nowExists) {
        Write-Host "  APARTAR    $($it.Origen)  (no existia en el respaldo)"
        [pscustomobject]@{ Item = $it; Accion = 'apartar'; Existe = $true }
    }
}
if (-not $plan) { Write-Host '  Nada que hacer.'; return }
Write-Host "Copia de seguridad de lo actual en: $safety"
$ans = Read-Host 'Escribe S para continuar'
if ($ans -notmatch '^[sS]$') { Write-Host 'Cancelado. No se cambio nada.'; return }

New-Item -ItemType Directory -Path $safety -Force | Out-Null
foreach ($p in $plan) {
    $src = $p.Item.Origen
    if ($p.Existe) {
        $keep = Join-Path $safety $p.Item.Copia
        New-Item -ItemType Directory -Path (Split-Path $keep -Parent) -Force | Out-Null
        Move-Item -LiteralPath $src -Destination $keep -Force
    }
    if ($p.Accion -eq 'restaurar') {
        $from = Join-Path $Respaldo $p.Item.Copia
        New-Item -ItemType Directory -Path (Split-Path $src -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $from -Destination $src -Recurse -Force
        Write-Host "[OK] Restaurado: $src"
    } else {
        Write-Host "[OK] Apartado: $src"
    }
}
Write-Host ''
Write-Host 'Listo. Abre Fishstrap/Roblox para que lean la configuracion restaurada.' -ForegroundColor Green
Write-Host "Lo que habia antes de revertir quedo en: $safety"
