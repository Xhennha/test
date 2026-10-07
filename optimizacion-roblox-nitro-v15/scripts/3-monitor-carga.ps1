<#
  3-monitor-carga.ps1
  Registra, mientras juegas, la carga de CPU y GPU para encontrar el cuello de botella.
  SOLO LECTURA: usa contadores de rendimiento de Windows y nvidia-smi. No toca el proceso de Roblox.

  Registra cada segundo:
    - CPU total, nucleo mas cargado, frecuencia estimada
    - CPU que usa Roblox y su hilo mas ocupado (si un hilo esta cerca del 100% de un nucleo,
      el limite es la CPU / el motor, no la grafica)
    - GPU NVIDIA: uso, temperatura, relojes, consumo, VRAM, motivos de bajada de reloj

  No mide FPS (usa PresentMon a la vez) ni temperatura de CPU (usa HWiNFO a la vez).

  Uso:
    1) Abre Blade Ball y espera en el lobby o entra a una partida.
    2) En una ventana de PowerShell:
         powershell -ExecutionPolicy Bypass -File .\3-monitor-carga.ps1 -Segundos 180 -Etiqueta base
    3) Vuelve al juego (Alt+Tab) y juega normal hasta que termine.
#>
[CmdletBinding()]
param(
    [int]$Segundos = 180,
    [string]$Etiqueta = 'prueba',
    [int]$CadaHilos = 5,      # cada cuantos segundos se mide el hilo mas ocupado de Roblox
    [switch]$SinHilos,        # no medir hilos (aun mas ligero)
    [string]$Destino = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'RobloxOpt')
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$tag = ($Etiqueta -replace '[^\w\-]', '_')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$cpuCsv = Join-Path $Destino "carga-cpu-$tag-$stamp.csv"
$gpuCsv = Join-Path $Destino "carga-gpu-$tag-$stamp.csv"
$sumTxt = Join-Path $Destino "carga-resumen-$tag-$stamp.txt"

function Get-Stats([double[]]$v) {
    if (-not $v -or $v.Count -eq 0) { return $null }
    $s = [double[]]$v.Clone(); [Array]::Sort($s)
    $avg = ($s | Measure-Object -Average).Average
    [pscustomobject]@{
        Prom = $avg; Min = $s[0]; Max = $s[$s.Count - 1]
        P5   = $s[[int][math]::Floor(0.05 * ($s.Count - 1))]
        P95  = $s[[int][math]::Ceiling(0.95 * ($s.Count - 1))]
    }
}
function ConvertTo-Num([string]$x) {
    $d = 0.0
    if ([double]::TryParse($x.Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return $null
}

# --- nvidia-smi en segundo plano ---------------------------------------------
$smi = $null
foreach ($c in @((Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source,
                 "$env:SystemRoot\System32\nvidia-smi.exe",
                 "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) {
    if ($c -and (Test-Path -LiteralPath $c)) { $smi = $c; break }
}
$gpuFields = @('timestamp', 'utilization.gpu', 'temperature.gpu', 'clocks.gr', 'clocks.mem', 'power.draw', 'memory.used', 'memory.total', 'pstate')
$gpuProc = $null
if ($smi) {
    # El nombre del campo de "motivos de bajada de reloj" cambio entre versiones del driver.
    foreach ($f in 'clocks_event_reasons.active', 'clocks_throttle_reasons.active') {
        $null = & $smi "--query-gpu=$f" '--format=csv,noheader' 2>&1
        if ($LASTEXITCODE -eq 0) { $gpuFields += $f; break }
    }
    $smiArgs = @("--query-gpu=$($gpuFields -join ',')", '--format=csv,noheader,nounits', '-lms', '1000', '-f', "`"$gpuCsv`"")
    $gpuProc = Start-Process -FilePath $smi -ArgumentList $smiArgs -WindowStyle Hidden -PassThru
} else {
    Write-Warning 'No se encontro nvidia-smi: solo se registrara la CPU.'
}

# Los contadores de rendimiento de WMI pueden faltar en algunos equipos ("Clase no valida").
# Sin ellos se registra solo el uso total de CPU (Win32_Processor) y la GPU.
$perfCpu = $true; $perfProc = $true
try { $null = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction Stop } catch { $perfCpu = $false }
try { $null = Get-CimInstance Win32_PerfRawData_PerfProc_Process -Filter "Name = 'Idle'" -ErrorAction Stop } catch { $perfProc = $false }
if (-not ($perfCpu -and $perfProc)) {
    Write-Warning 'Los contadores de rendimiento de Windows (WMI) no estan disponibles: solo se medira el uso total de CPU y la GPU.'
    Write-Warning 'Para repararlos (opcional): PowerShell como administrador -> winmgmt /resyncperf  y reinicia.'
}

# Si Roblox no aparece en la GPU NVIDIA, los datos de GPU no son de Roblox.
$robloxOnNvidia = $null
if ($smi -and @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0) {
    $robloxOnNvidia = [bool](@(& $smi 2>&1 | ForEach-Object { "$_" }) -match 'RobloxPlayerBeta')
    if (-not $robloxOnNvidia) { Write-Warning 'Roblox esta abierto pero NO usa la RTX 2050. Arregla eso primero (guia, seccion 5.2).' }
}

# --- Bucle de CPU -------------------------------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$prevProc = $null
$prevThreads = $null
$end = (Get-Date).AddSeconds($Segundos)
$i = 0
if ($perfCpu) { $null = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation }   # primera lectura descartada

Write-Host "Registrando $Segundos s. Vuelve al juego. (Ctrl+C para cortar antes; los datos ya registrados se pierden)" -ForegroundColor Cyan
try {
    while ((Get-Date) -lt $end) {
        $t0 = Get-Date
        $cpuTotal = $null; $maxCore = $null; $mhzMax = $null
        if ($perfCpu) {
            $pi = @(Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation)
            $tot = $pi | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
            $cores = @($pi | Where-Object { $_.Name -match '^\d+,\d+$' })
            if ($tot) { $cpuTotal = [math]::Round($tot.PercentProcessorTime, 1) }
            if ($cores.Count -gt 0) {
                $maxCore = [math]::Round(($cores | Measure-Object PercentProcessorTime -Maximum).Maximum, 1)
                $maxPerf = ($cores | Measure-Object PercentProcessorPerformance -Maximum).Maximum
                if ($tot) { $mhzMax = [math]::Round($tot.ProcessorFrequency * $maxPerf / 100) }
            }
        } else {
            $cpuTotal = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average, 1)
        }

        $rbxOpen = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0
        $rbxCpu = $null; $rbxRam = $null; $thrMax = $null
        $rp = if ($perfProc) { @(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Filter "Name LIKE 'RobloxPlayerBeta%'") } else { @() }
        if ($rp.Count -gt 0) {
            $cur = $rp[0]
            if ($prevProc -and $prevProc.IDProcess -eq $cur.IDProcess) {
                $dt = [double]$cur.Timestamp_Sys100NS - [double]$prevProc.Timestamp_Sys100NS
                if ($dt -gt 0) { $rbxCpu = [math]::Round(([double]$cur.PercentProcessorTime - [double]$prevProc.PercentProcessorTime) / $dt * 100, 1) }
            }
            $prevProc = $cur
            $rbxRam = [math]::Round([double]$cur.WorkingSetPrivate / 1MB)

            if (-not $SinHilos -and ($i % [math]::Max($CadaHilos, 1)) -eq 0) {
                $map = @{}
                foreach ($t in Get-CimInstance Win32_PerfRawData_PerfProc_Thread -Filter "Name LIKE 'RobloxPlayerBeta/%'") {
                    if ($t.IDProcess -eq $cur.IDProcess) { $map["$($t.IDThread)"] = $t }
                }
                if ($prevThreads) {
                    $best = 0.0
                    foreach ($k in $map.Keys) {
                        if (-not $prevThreads.ContainsKey($k)) { continue }
                        $a = $prevThreads[$k]; $b = $map[$k]
                        $dt = [double]$b.Timestamp_Sys100NS - [double]$a.Timestamp_Sys100NS
                        if ($dt -le 0) { continue }
                        $v = ([double]$b.PercentProcessorTime - [double]$a.PercentProcessorTime) / $dt * 100
                        if ($v -gt $best) { $best = $v }
                    }
                    $thrMax = [math]::Round([math]::Min($best, 100), 1)
                }
                $prevThreads = $map
            }
        }

        if ($i -gt 0) {
            $rows.Add([pscustomobject]@{
                Hora                  = $t0.ToString('HH:mm:ss')
                CPU_Total_pct         = $cpuTotal
                CPU_NucleoMax_pct     = $maxCore
                CPU_MHz_NucleoRapido  = $mhzMax
                Roblox_Abierto        = $rbxOpen
                Roblox_CPU_pct1Nucleo = $rbxCpu
                Roblox_HiloMax_pct    = $thrMax
                Roblox_RAM_MB         = $rbxRam
            })
        }
        $i++
        $wait = 1000 - ((Get-Date) - $t0).TotalMilliseconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    }
} finally {
    if ($gpuProc -and -not $gpuProc.HasExited) { Stop-Process -Id $gpuProc.Id -Force -ErrorAction SilentlyContinue }
}

$rows | Export-Csv -LiteralPath $cpuCsv -NoTypeInformation -Encoding UTF8 -UseCulture

# --- Resumen ---------------------------------------------------------------------
$out = New-Object System.Collections.Generic.List[string]
function S([string]$t = '') { $out.Add($t); Write-Host $t }

S "Resumen de carga - etiqueta '$Etiqueta' - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
S ("Muestras de CPU: {0}" -f $rows.Count)
$robloxSeen = @($rows | Where-Object { $_.Roblox_Abierto }).Count -gt 0
if (-not $robloxSeen) { S '[!] Roblox no estuvo abierto durante la medicion.' }
if ($robloxOnNvidia -eq $false) { S '[!] Roblox NO estaba usando la RTX 2050: los datos de GPU de abajo no son de Roblox. Arregla eso primero (guia, seccion 5.2).' }
if (-not ($perfCpu -and $perfProc)) { S '[!] Sin contadores de rendimiento de WMI: no se pudo medir la CPU de Roblox ni su hilo principal.' }

function Show([string]$label, $vals, [string]$unit) {
    $st = Get-Stats ([double[]]@($vals | Where-Object { $null -ne $_ }))
    if ($st) { S ("{0,-34} prom {1,7:N1}{5}  p5 {2,7:N1}  p95 {3,7:N1}  max {4,7:N1}" -f $label, $st.Prom, $st.P5, $st.P95, $st.Max, $unit) }
    return $st
}
S ''
S 'CPU'
$null = Show 'Uso total' ($rows | ForEach-Object { $_.CPU_Total_pct }) '%'
$null = Show 'Nucleo mas cargado' ($rows | ForEach-Object { $_.CPU_NucleoMax_pct }) '%'
$mhz = Show 'Frecuencia nucleo mas rapido (est.)' ($rows | ForEach-Object { $_.CPU_MHz_NucleoRapido }) ' MHz'
$null = Show 'Roblox (% de UN nucleo)' ($rows | ForEach-Object { $_.Roblox_CPU_pct1Nucleo }) '%'
$thr = Show 'Hilo mas ocupado de Roblox' ($rows | ForEach-Object { $_.Roblox_HiloMax_pct }) '%'

$gpuUtil = $null; $gpuTemp = $null; $reasonSummary = @()
if ($smi -and (Test-Path -LiteralPath $gpuCsv)) {
    $g = @(Import-Csv -LiteralPath $gpuCsv -Header $gpuFields)
    S ''
    S ("GPU NVIDIA ({0} muestras)" -f $g.Count)
    $gpuUtil = Show 'Uso' ($g | ForEach-Object { ConvertTo-Num $_.'utilization.gpu' }) '%'
    $gpuTemp = Show 'Temperatura' ($g | ForEach-Object { ConvertTo-Num $_.'temperature.gpu' }) ' C'
    $null = Show 'Reloj grafico' ($g | ForEach-Object { ConvertTo-Num $_.'clocks.gr' }) ' MHz'
    $null = Show 'Consumo' ($g | ForEach-Object { ConvertTo-Num $_.'power.draw' }) ' W'
    $vram = Show 'VRAM usada' ($g | ForEach-Object { ConvertTo-Num $_.'memory.used' }) ' MB'
    $vramTotal = ($g | ForEach-Object { ConvertTo-Num $_.'memory.total' } | Where-Object { $_ } | Select-Object -First 1)

    $rf = $gpuFields | Where-Object { $_ -like 'clocks_*reasons.active' } | Select-Object -First 1
    if ($rf) {
        $bits = @(
            [pscustomobject]@{ Bit = 4;   Termico = $false; Texto = 'Limite de potencia (normal en portatiles cuando la GPU va al maximo)' }
            [pscustomobject]@{ Bit = 8;   Termico = $false; Texto = 'Ralentizacion por hardware' }
            [pscustomobject]@{ Bit = 32;  Termico = $true;  Texto = 'Ralentizacion TERMICA (software)' }
            [pscustomobject]@{ Bit = 64;  Termico = $true;  Texto = 'Ralentizacion TERMICA (hardware)' }
            [pscustomobject]@{ Bit = 128; Termico = $false; Texto = 'Freno de potencia (hardware)' }
        )
        $counts = @{}; foreach ($b in $bits) { $counts[$b.Bit] = 0 }
        $valid = 0
        foreach ($r in $g) {
            $hex = "$($r.$rf)".Trim()
            if ($hex -notmatch '^0x[0-9a-fA-F]+$') { continue }
            $valid++
            $val = [Convert]::ToInt64($hex.Substring(2), 16)
            foreach ($b in $bits) { if (($val -band [int64]$b.Bit) -ne 0) { $counts[$b.Bit]++ } }
        }
        if ($valid -gt 0) {
            S 'Motivos de bajada de reloj de la GPU (% del tiempo):'
            foreach ($b in $bits) {
                $pct = 100 * $counts[$b.Bit] / $valid
                S ("  {0,-70} {1,5:N1}%" -f $b.Texto, $pct)
                if ($b.Termico -and $pct -gt 0) { $reasonSummary += $b.Texto }
            }
        }
    }
}

# --- Interpretacion (heuristica, no un veredicto) ----------------------------------
S ''
S 'Lectura orientativa (combinala con PresentMon y HWiNFO):'
$said = $false
if ($robloxOnNvidia -ne $false -and $gpuUtil -and $gpuUtil.Prom -ge 95) {
    S '- La GPU trabaja al maximo casi todo el tiempo: probable limite por GPU.'
    S '  Prueba: bajar la calidad grafica de Roblox, quitar MSAA, o fijar un limite de FPS que la GPU sostenga con margen.'
    $said = $true
}
if ($robloxOnNvidia -ne $false -and $gpuUtil -and $gpuUtil.Prom -ge 85 -and $gpuUtil.Prom -lt 95) {
    S '- La GPU va alta (85-95%) sin saturarse del todo: CPU y GPU estan cerca de su limite a la vez.'
    S '  Bajar un poco la calidad grafica suele aliviar a ambas.'
    $said = $true
}
if ($robloxOnNvidia -ne $false -and $gpuUtil -and $gpuUtil.Prom -lt 85 -and $thr -and $thr.P95 -ge 85) {
    S '- La GPU tiene margen y un hilo de Roblox llega a ~100% de un nucleo: probable limite por CPU / motor de Roblox.'
    S '  Prueba: modo de energia y NitroSense en rendimiento, cerrar procesos pesados, calidad grafica mas baja (tambien alivia la CPU).'
    $said = $true
}
if ($robloxOnNvidia -ne $false -and $gpuUtil -and $gpuUtil.Prom -lt 85 -and $thr -and $thr.P95 -lt 85) {
    S '- Ni la GPU ni el hilo principal estan saturados. Si los FPS estaban en tu limite, es lo esperado (el limitador manda).'
    S '  Para ver el techo real, repite la medicion con el limite de Roblox en 240.'
    $said = $true
}
if ($robloxOnNvidia -ne $false -and $gpuUtil -and $gpuUtil.Prom -lt 85 -and -not $thr) {
    S '- La GPU tiene margen: el limite esta en la CPU / motor de Roblox o en tu limitador de FPS (sin datos del hilo principal para distinguirlo).'
    $said = $true
}
if ($reasonSummary.Count -gt 0) {
    S ("- Hubo ralentizacion termica de la GPU ({0}). Mejora la ventilacion antes de tocar ajustes graficos." -f ($reasonSummary -join '; '))
    $said = $true
}
if ($gpuTemp -and $gpuTemp.Max -ge 85) { S '- La GPU llego a 85 C o mas: revisa ventilacion (superficie dura, rejillas libres, base elevada).'; $said = $true }
if ($vram -and $vramTotal -and $vram.Max -ge 0.9 * $vramTotal) { S '- La VRAM llego a mas del 90%: baja la calidad de texturas (ver guia).'; $said = $true }
if ($mhz -and $mhz.P5 -gt 0 -and $mhz.P5 -lt 2500 -and $robloxSeen) {
    S '- El nucleo mas rapido bajo de ~2,5 GHz en parte de la prueba: posible limite de energia o temperatura de la CPU. Confirma en HWiNFO.'
    $said = $true
}
if (-not $said) { S '- Sin senales claras. Compara con la medicion de FPS/frametimes de PresentMon.' }

$out | Out-File -LiteralPath $sumTxt -Encoding UTF8
Write-Host ''
Write-Host "CSV de CPU:  $cpuCsv"
if ($smi) { Write-Host "CSV de GPU:  $gpuCsv" }
Write-Host "Resumen:     $sumTxt" -ForegroundColor Green
