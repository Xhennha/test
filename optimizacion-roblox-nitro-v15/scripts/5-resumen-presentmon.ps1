<#
  5-resumen-presentmon.ps1
  Analiza una captura CSV de PresentMon y calcula FPS promedio, 1% low, 0.1% low,
  estabilidad de frametimes y si el limite es la GPU o la CPU. Anade la fila a
  resultados.csv para comparar antes/despues de cada grupo de ajustes.

  Captura (PowerShell como administrador, abierto en la carpeta Escritorio\RobloxOpt,
  con el .exe de PresentMon copiado ahi y Blade Ball abierto):
    .\PresentMon-2.x.x-x64.exe --process_name RobloxPlayerBeta.exe --output_file .\base-1.csv --delay 5 --timed 60 --terminate_after_timed
  (si tu version no acepta esas opciones, ejecuta PresentMon con --help)

  Analisis (no necesita administrador):
    powershell -ExecutionPolicy Bypass -File .\5-resumen-presentmon.ps1 -Csv "$HOME\Desktop\RobloxOpt\base-1.csv" -Etiqueta "base lobby" -LimiteFps 240
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Csv,
    [string]$Etiqueta = '',
    [string]$Proceso = 'RobloxPlayerBeta',
    [double]$LimiteFps = 0,          # el limite de FPS que tenias puesto (0 = sin limite / no lo se)
    [string]$ColumnaFrametime = '',  # solo si el script no encuentra la columna por si solo
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Csv)) { throw "No existe el archivo: $Csv" }
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
if (-not $Etiqueta) { $Etiqueta = [IO.Path]::GetFileNameWithoutExtension($Csv) }

$data = @(Import-Csv -LiteralPath $Csv)
if ($data.Count -eq 0) { throw 'El CSV esta vacio.' }
$cols = @($data[0].PSObject.Properties | ForEach-Object { $_.Name })

function Find-Column([string[]]$candidates) {
    foreach ($c in $candidates) { if ($cols -contains $c) { return $c } }
    return $null
}
function ConvertTo-Num($x) {
    $d = 0.0
    if ([double]::TryParse("$x", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

$appCol  = Find-Column @('Application', 'ProcessName')
$ftCol   = if ($ColumnaFrametime) { $ColumnaFrametime } else { Find-Column @('MsBetweenPresents', 'MsBetweenAppStart', 'FrameTime') }
$cpuBusyCol = Find-Column @('MsCPUBusy')
$cpuWaitCol = Find-Column @('MsCPUWait')
$gpuCol  = Find-Column @('MsGPUBusy', 'MsGPUActive', 'GPUBusy')
$latCol  = Find-Column @('MsPCLatency', 'MsClickToPhotonLatency')
$dispCol = Find-Column @('DisplayLatency', 'MsUntilDisplayed')
$modeCol = Find-Column @('PresentMode')

if (-not $ftCol -and -not ($cpuBusyCol -and $cpuWaitCol)) {
    Write-Host 'No encuentro la columna de frametime. Columnas del CSV:'
    $cols | ForEach-Object { Write-Host "  $_" }
    throw 'Indica la columna con -ColumnaFrametime <nombre>.'
}

$rows = if ($appCol) { @($data | Where-Object { $_.$appCol -like "$Proceso*" }) } else { $data }
if ($rows.Count -eq 0) {
    $apps = $data | ForEach-Object { $_.$appCol } | Sort-Object -Unique
    throw ("No hay frames de '{0}'. Aplicaciones en el CSV: {1}" -f $Proceso, ($apps -join ', '))
}

$ft = New-Object System.Collections.Generic.List[double]
$gpuRatioNum = 0.0; $gpuRatioDen = 0.0
$lat = New-Object System.Collections.Generic.List[double]
$modes = @{}
foreach ($r in $rows) {
    $f = if ($ftCol) { ConvertTo-Num $r.$ftCol } else {
        $b = ConvertTo-Num $r.$cpuBusyCol; $w = ConvertTo-Num $r.$cpuWaitCol
        if ($null -ne $b -and $null -ne $w) { $b + $w } else { $null }
    }
    if ($null -eq $f -or $f -le 0 -or $f -gt 1000) { continue }   # descarta pausas de mas de 1 s (Alt+Tab, pantallas de carga)
    $ft.Add($f)
    if ($gpuCol) {
        $g = ConvertTo-Num $r.$gpuCol
        if ($null -ne $g) { $gpuRatioNum += $g; $gpuRatioDen += $f }
    }
    foreach ($lc in @($latCol, $dispCol)) {
        if (-not $lc) { continue }
        $l = ConvertTo-Num $r.$lc
        if ($null -ne $l -and $l -gt 0) { $lat.Add($l); break }
    }
    if ($modeCol) { $m = "$($r.$modeCol)"; if ($modes.ContainsKey($m)) { $modes[$m]++ } else { $modes[$m] = 1 } }
}

$n = $ft.Count
if ($n -lt 2) { throw 'Muy pocos frames validos para analizar.' }
$arr = $ft.ToArray()
$sorted = [double[]]$arr.Clone(); [Array]::Sort($sorted)
$sum = 0.0; foreach ($x in $arr) { $sum += $x }
$mean = $sum / $n
$var = 0.0; foreach ($x in $arr) { $var += ($x - $mean) * ($x - $mean) }
$std = [math]::Sqrt($var / $n)
function Get-Pct([double[]]$s, [double]$p) {
    $idx = [int][math]::Ceiling($p / 100 * $s.Count) - 1
    if ($idx -lt 0) { $idx = 0 }; if ($idx -ge $s.Count) { $idx = $s.Count - 1 }
    $s[$idx]
}
function Get-LowAvgFps([double[]]$s, [double]$fraction) {
    $k = [math]::Max(1, [int][math]::Ceiling($s.Count * $fraction))
    $acc = 0.0
    for ($i = $s.Count - $k; $i -lt $s.Count; $i++) { $acc += $s[$i] }
    1000 / ($acc / $k)
}
$median = Get-Pct $sorted 50
$p99 = Get-Pct $sorted 99
$p999 = Get-Pct $sorted 99.9
$avgFps = 1000 * $n / $sum
$low1 = Get-LowAvgFps $sorted 0.01
$low01 = Get-LowAvgFps $sorted 0.001
$spikes = 0; foreach ($x in $arr) { if ($x -gt 2 * $median) { $spikes++ } }
$minutes = $sum / 60000
$spikesPerMin = if ($minutes -gt 0) { $spikes / $minutes } else { 0 }
$f2f = 0.0; for ($i = 1; $i -lt $n; $i++) { $f2f += [math]::Abs($arr[$i] - $arr[$i - 1]) }; $f2f = $f2f / ($n - 1)
$gpuRatio = if ($gpuRatioDen -gt 0) { $gpuRatioNum / $gpuRatioDen } else { $null }
$latAvg = if ($lat.Count -gt 0) { ($lat | Measure-Object -Average).Average } else { $null }
$topMode = if ($modes.Count -gt 0) { ($modes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key } else { '' }

# --- Informe -----------------------------------------------------------------------
Write-Host ''
Write-Host "Captura: $Csv  (etiqueta: $Etiqueta)" -ForegroundColor Cyan
Write-Host ("Frames analizados: {0}   Duracion: {1:N1} s" -f $n, ($sum / 1000))
Write-Host ''
Write-Host ("FPS promedio ............................ {0,7:N1}" -f $avgFps)
Write-Host ("1% low (promedio del 1% mas lento) ....... {0,7:N1}" -f $low1)
Write-Host ("1% low (percentil 99 del frametime) ...... {0,7:N1}" -f (1000 / $p99))
Write-Host ("0.1% low (promedio del 0.1% mas lento) ... {0,7:N1}" -f $low01)
Write-Host ("Frametime: mediana {0:N2} ms | p99 {1:N2} ms | p99.9 {2:N2} ms | desv. {3:N2} ms" -f $median, $p99, $p999, $std)
Write-Host ("Variacion entre frames consecutivos ...... {0,7:N2} ms" -f $f2f)
Write-Host ("Picos (> 2x la mediana) .................. {0} ({1:N1} por minuto)" -f $spikes, $spikesPerMin)
if ($null -ne $gpuRatio) { Write-Host ("GPU ocupada / frametime ................... {0,7:N2}" -f $gpuRatio) }
if ($null -ne $latAvg) { Write-Host ("Latencia media ({0}) ... {1,7:N1} ms" -f $(if ($latCol) { $latCol } else { $dispCol }), $latAvg) }
if ($modes.Count -gt 0) {
    Write-Host 'Modo de presentacion:'
    $modes.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Host ("  {0,-40} {1,5:N1}%" -f $_.Key, (100 * $_.Value / ($rows.Count))) }
}

Write-Host ''
Write-Host 'Lectura orientativa:'
$capped = $LimiteFps -gt 0 -and [math]::Abs($avgFps - $LimiteFps) / $LimiteFps -lt 0.03
if ($capped) { Write-Host ("- Los FPS estan pegados a tu limite de {0}: el limitador manda (eso es bueno si los 1% low tambien estan cerca)." -f $LimiteFps) }
if ($null -ne $gpuRatio) {
    if ($gpuRatio -ge 0.9) { Write-Host '- La GPU esta ocupada casi todo el frame: limite por GPU. Bajar calidad grafica o MSAA deberia subir FPS.' }
    elseif ($gpuRatio -le 0.75 -and -not $capped) { Write-Host '- La GPU espera a la CPU buena parte del frame: limite por CPU / motor de Roblox.' }
    elseif ($gpuRatio -le 0.75) { Write-Host '- La GPU tiene margen de sobra con este limite.' }
    else { Write-Host '- Carga equilibrada entre CPU y GPU.' }
}
$stab = $low1 / $avgFps
if ($stab -ge 0.8) { Write-Host ("- Estabilidad buena: el 1% low es el {0:P0} del promedio." -f $stab) }
elseif ($stab -ge 0.6) { Write-Host ("- Estabilidad regular: 1% low al {0:P0} del promedio. Hay tirones apreciables." -f $stab) }
else { Write-Host ("- Estabilidad mala: 1% low al {0:P0} del promedio. Prioriza eliminar tirones antes que subir FPS." -f $stab) }
if ($topMode -match '^Composed') { Write-Host "- Modo '$topMode': Windows compone la imagen (suele anadir latencia). Usa pantalla completa (F11) y revisa 'Optimizaciones para juegos en ventana'." }

# --- Guardar en resultados.csv -----------------------------------------------------
$resPath = Join-Path $Destino 'resultados.csv'
$row = [pscustomobject]@{
    Fecha                  = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    Etiqueta               = $Etiqueta
    Archivo                = [IO.Path]::GetFileName($Csv)
    Limite_FPS             = $LimiteFps
    Frames                 = $n
    Duracion_s             = [math]::Round($sum / 1000, 1)
    FPS_prom               = [math]::Round($avgFps, 1)
    FPS_1pct_low           = [math]::Round($low1, 1)
    FPS_01pct_low          = [math]::Round($low01, 1)
    Frametime_mediana_ms   = [math]::Round($median, 2)
    Frametime_p99_ms       = [math]::Round($p99, 2)
    Frametime_desv_ms      = [math]::Round($std, 2)
    Picos_por_min          = [math]::Round($spikesPerMin, 1)
    GPU_ocupada_ratio      = if ($null -ne $gpuRatio) { [math]::Round($gpuRatio, 2) } else { '' }
    Latencia_ms            = if ($null -ne $latAvg) { [math]::Round($latAvg, 1) } else { '' }
    Modo_presentacion      = $topMode
    CPU_temp_max_C_HWiNFO  = ''
    GPU_temp_max_C         = ''
    Ping_Roblox_ms         = ''
    Observaciones          = ''
}
$row | Export-Csv -LiteralPath $resPath -NoTypeInformation -Encoding UTF8 -UseCulture -Append
Write-Host ''
Write-Host "Anadido a: $resPath (completa a mano temperaturas, ping y observaciones)" -ForegroundColor Green

$all = @(Import-Csv -LiteralPath $resPath -UseCulture)
if ($all.Count -gt 1) {
    Write-Host ''
    Write-Host 'Comparativa de todas tus capturas:'
    $all | Format-Table Etiqueta, Limite_FPS, FPS_prom, FPS_1pct_low, FPS_01pct_low, Frametime_p99_ms, Picos_por_min, GPU_ocupada_ratio -AutoSize | Out-String -Width 220 | Write-Host
}
