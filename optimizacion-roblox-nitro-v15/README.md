# Optimización de Roblox (Blade Ball) en Acer Nitro V15 ANV15-51-53W1

**i5-13420H · RTX 2050 4 GB + Intel UHD · 24 GB DDR5 · 1080p 165 Hz · Windows 11 · Fishstrap**

> **Antes de empezar.** Esta guía y sus scripts se prepararon **sin acceso a tu notebook**.
> No se aplicó ningún ajuste ni se midió nada en tu equipo. Por eso, la tabla de resultados
> (sección 10) está vacía: solo deben ir ahí **tus** mediciones. Los scripts se probaron con datos
> simulados, no en un Windows real; si alguno falla, el informe mostrará el error. Solo dos scripts
> cambian algo (`aplicar-ajustes-windows.ps1` y `revertir-archivos.ps1`), y únicamente si escribes **S** para confirmar.

---

## Contenido

| Archivo | Qué hace | ¿Cambia algo? |
|---|---|---|
| `scripts/1-respaldo.ps1` | Copia Fishstrap, FastFlags, ajustes del juego, claves de registro relevantes y el estado de energía y pantalla | No (solo copia) |
| `scripts/2-diagnostico.ps1` | Revisa Windows, drivers, GPU usada, pantalla, energía, superposiciones, disco, red, Fishstrap y FastFlags | No |
| `scripts/3-monitor-carga.ps1` | Registra la CPU, el hilo más ocupado de Roblox y la GPU (uso, temperatura y bajadas de reloj) mientras juegas | No |
| `scripts/4-prueba-red.ps1` | Mide ping, jitter y pérdida de paquetes hacia el router, Internet y el último servidor de Roblox | No |
| `scripts/5-resumen-presentmon.ps1` | Calcula FPS promedio, 1% low, 0.1% low, estabilidad y cuello de botella a partir de una captura de PresentMon, y arma una tabla comparativa | No |
| `scripts/aplicar-ajustes-windows.ps1` | Aplica solo los ajustes seguros de Windows: modo de juego, grabación en segundo plano desactivada, Roblox en la RTX 2050, optimizaciones para juegos en ventana y, si estaba limitado, el turbo de la CPU | Sí, muestra el plan, pide confirmación, hace respaldo y permite deshacer |
| `scripts/revertir-archivos.ps1` | Restaura los archivos del respaldo | Sí, pide confirmación y guarda copia de lo actual |
| `1-DIAGNOSTICO.bat` / `2-APLICAR-AJUSTES-WINDOWS.bat` | Ejecutan esos dos scripts con doble clic | Igual que el script que ejecutan |

Todos los resultados se guardan en **Escritorio\RobloxOpt**.

### Modo rápido (si no quieres medir todo)

1. Doble clic en **`1-DIAGNOSTICO.bat`** → lee el «RESUMEN DE ALERTAS» del final: es la lista de lo que está mal en tu equipo.
2. Doble clic en **`2-APLICAR-AJUSTES-WINDOWS.bat`** → revisa el plan y escribe **S**. Hace respaldo antes y, al terminar,
   te muestra el comando exacto para deshacer.
3. Haz a mano la lista que muestra al final: pantalla a 165 Hz, modo de energía, NitroSense, perfil de NVIDIA, gráficos de
   Roblox, Discord y FastFlags (secciones 5 a 7). Eso no se puede cambiar de forma segura con un script.

Si Windows muestra un aviso al abrir el `.bat` (porque viene de Internet), elige «Más información → Ejecutar de todas formas»
solo si lo descargaste de tu propio repositorio.

### Cómo ejecutar un script

1. Descarga esta carpeta (botón *Code → Download ZIP* en GitHub) y descomprímela.
2. Abre la carpeta `scripts`, haz clic en la barra de direcciones, escribe `powershell` y pulsa Enter.
3. Ejecuta, por ejemplo:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\2-diagnostico.ps1
   ```
   `-ExecutionPolicy Bypass` vale solo para esa ejecución y **no** cambia la política de Windows.
   Los scripts son texto plano: puedes abrirlos con el Bloc de notas y revisarlos antes de ejecutarlos.

### Herramientas externas (opcionales, de fuentes oficiales; tú decides si las instalas)

| Herramienta | Para qué | Dónde |
|---|---|---|
| **PresentMon** (Intel, código abierto) | FPS, frametimes, 1% low, «GPU busy», modo de presentación | github.com/GameTechDev/PresentMon → *Releases* (versión de consola, no requiere instalación) |
| **HWiNFO64** | Temperaturas de CPU y avisos de *throttling* térmico o de potencia | hwinfo.com (modo *Sensors-only*) |
| CapFrameX (alternativa gráfica a PresentMon) | Captura y comparación con gráficos | github.com/CXWorld/CapFrameX |

No hace falta ningún «optimizador», limpiador ni pack de registro.

---

## 1. Plan de trabajo

```
Fase 0  Respaldo                         1-respaldo.ps1 + capturas del perfil de NVIDIA
Fase 1  Diagnóstico + medición base      2-diagnostico.ps1, PresentMon, 3-monitor-carga.ps1, HWiNFO
Fase 2  Windows y energía                sección 5   → medir
Fase 3  NVIDIA (solo perfil de Roblox)   sección 6   → medir
Fase 4  Roblox y Fishstrap               sección 7   → medir
Fase 5  Límite 120 / 144 / 165           sección 8   → medir y elegir
Fase 6  Red                              sección 9   (independiente de los FPS)
```

Regla: **un grupo de cambios → medir → conservar o revertir**. Si un cambio no mejora el 1% low,
los picos o la latencia más allá del ruido normal entre pruebas, vuelve al valor anterior.

---

## 2. Protocolo de medición (para que las pruebas sean comparables)

**Preparación (siempre igual):**
- Cargador conectado, mismo modo de NitroSense, mismas apps abiertas.
- Reinicia el equipo antes de la sesión de pruebas y juega 10 minutos para que alcance su temperatura de funcionamiento.
- Gráficos de Roblox en **Manual** (en «Automático», Roblox cambia la calidad durante la partida y las pruebas dejan de ser comparables).

**Dos escenas:**
- **A — Lobby (repetible):** en el lobby de Blade Ball, quieto en el mismo sitio y con la cámara apuntando al mismo lugar, 60 s.
  Sirve para comparar ajustes con poco ruido.
- **B — Partida real:** 3 rondas completas. Anota cuántos jugadores había. Sirve para ver los tirones reales (efectos, habilidades).

Haz **cada escena 2 veces** en la medición base. La diferencia entre esas dos repeticiones es el
ruido normal: un cambio menor que esa diferencia no demuestra nada.

**Captura con PresentMon** (PowerShell como administrador, en la carpeta `Escritorio\RobloxOpt`,
con el `.exe` de PresentMon copiado ahí):

```powershell
.\PresentMon-2.x.x-x64.exe --process_name RobloxPlayerBeta.exe --output_file .\base-lobby-1.csv --delay 5 --timed 60 --terminate_after_timed
```

Al mismo tiempo, en otra ventana (sin administrador):

```powershell
powershell -ExecutionPolicy Bypass -File .\3-monitor-carga.ps1 -Segundos 70 -Etiqueta base-lobby-1
```

Y con HWiNFO abierto (*Sensors-only*), anota el máximo de: **CPU Package** (°C), **Core Thermal
Throttling**, **Package/Ring Power Limit Exceeded** y **GPU Temperature**.

**Análisis:**

```powershell
powershell -ExecutionPolicy Bypass -File .\5-resumen-presentmon.ps1 -Csv "$HOME\Desktop\RobloxOpt\base-lobby-1.csv" -Etiqueta "base lobby 1" -LimiteFps 240
```

(Si tu Escritorio está en OneDrive, usa la ruta que muestran los scripts al terminar).
Cada análisis añade una fila a `resultados.csv` y muestra la comparativa con todas las anteriores.
Rellena en Excel las columnas de temperatura, ping y observaciones.

Para una comprobación rápida dentro del juego, **Shift+F5** muestra los FPS de Roblox.

---

## 3. Diagnóstico: qué buscar y cómo interpretarlo

No se presupone que el problema sea la GPU. Estas son las hipótesis, de más a menos probable para
este equipo, y la medición que confirma o descarta cada una:

| # | Hipótesis | Cómo se confirma | Qué hacer si se confirma |
|---|---|---|---|
| 1 | **Límite por CPU / hilo principal de Roblox** (habitual en Roblox) | PresentMon: `GPU ocupada / frametime` ≤ 0,75 sin estar en el límite de FPS. Monitor: hilo de Roblox ≥ 85 % de un núcleo y GPU < 85 % | Energía al máximo (sección 5.3), cerrar procesos pesados, bajar calidad gráfica (también reduce el trabajo de la CPU) |
| 2 | **Límite por GPU** | `GPU ocupada / frametime` ≥ 0,9; monitor: GPU ≥ 95 % | Bajar calidad gráfica, MSAA o texturas; fijar un límite de FPS que la GPU sostenga con margen |
| 3 | **Límite térmico o de potencia** (CPU y GPU comparten el presupuesto de energía y refrigeración) | HWiNFO: *Thermal Throttling = Yes*; monitor: «Ralentización TÉRMICA» > 0 %; la frecuencia baja durante la partida | Ventilación (superficie dura, rejillas libres, parte trasera elevada, limpieza), modo Rendimiento/Turbo en NitroSense |
| 4 | **Pantalla a menos de 165 Hz** o con frecuencia dinámica | Diagnóstico, sección 2 | Sección 5.1 |
| 5 | **Gráficos híbridos (Optimus):** la RTX 2050 renderiza y la Intel UHD muestra la imagen | Diagnóstico: «la pantalla interna sale por la Intel UHD» | Normal si no hay MUX. Revisa si NitroSense ofrece «solo GPU dedicada» (sección 5.4) |
| 6 | **Procesos o superposiciones** que causan picos periódicos | Picos en PresentMon que se repiten cada cierto tiempo; diagnóstico, sección 5 | Sección 5.6 |
| 7 | **FastFlags obsoletas o «FPS unlockers»** antiguos | Diagnóstico: `[IGNORADA]` o `rbxfpsunlocker` | Sección 7.2 |
| 8 | **VRAM llena** (4 GB) | Monitor: VRAM > 90 % | Bajar la calidad de texturas (sección 7.2) |
| 9 | **La red, no los FPS** (parries que no entran, la bola «salta») | FPS estables en PresentMon, pero ping irregular o con pérdida | Sección 9 |

**Medición de techo:** pon temporalmente el límite de Roblox en **240** y captura la escena A.
Así ves cuántos FPS puede dar realmente el equipo y cuál es el cuello de botella sin que el limitador lo oculte.

**Cómo leer `5-resumen-presentmon.ps1`:**
- **1% low / promedio** ≥ 0,8 = estable; entre 0,6 y 0,8 = tirones apreciables; < 0,6 = mala estabilidad.
- **Picos por minuto** (frames que duran más del doble de lo normal): son los microtirones que notas.
- **Modo de presentación:** `Hardware: Independent Flip` o `Hardware Composed: Independent Flip` = ruta de baja latencia.
  `Composed: Flip` o `Composed: Copy…` = Windows compone la imagen, lo que suele añadir latencia (revisa pantalla completa y la sección 5.5).

---

## 4. Fase 0 — Respaldo

```powershell
powershell -ExecutionPolicy Bypass -File .\1-respaldo.ps1
```

Además, **haz capturas** del perfil de Roblox en el Panel de control de NVIDIA (sección 6) y de
los ajustes gráficos de Roblox antes de tocar nada. El panel de NVIDIA no se puede exportar sin
herramientas de terceros.

---

## 5. Windows 11

Los nombres de los menús pueden variar un poco según la versión de Windows.

### 5.1 Frecuencia de actualización
*Configuración → Sistema → Pantalla → Pantalla avanzada → Elegir una frecuencia de actualización* → **165 Hz**.
Si aparece «165 Hz (dinámica)», elige la opción fija de 165 Hz para evitar cambios de frecuencia durante el juego.

### 5.2 Roblox en la GPU de alto rendimiento
Dices que Roblox ya usa la RTX 2050. Comprobarlo cuesta poco:
- `2-diagnostico.ps1` con Blade Ball abierto debe mostrar `RobloxPlayerBeta.exe` en la GPU NVIDIA.
- O bien: *Administrador de tareas → Detalles* → clic derecho en las columnas → *Seleccionar columnas* → **Motor de GPU**: Roblox debe usar la GPU de NVIDIA (normalmente *GPU 1 – 3D*).

Si no la usa, en este orden:
1. **Fishstrap → activa el directorio estático** (*Static Directory*), para que la ruta de Roblox deje de cambiar. Abre Roblox una vez para que se instale en la carpeta nueva.
2. **`2-APLICAR-AJUSTES-WINDOWS.bat`**: añade la preferencia de alto rendimiento para la ruta actual de Roblox.
   A mano: *Configuración → Sistema → Pantalla → Gráficos* → *Agregar aplicación* → el `RobloxPlayerBeta.exe`
   que indica el diagnóstico → *Opciones* → **Alto rendimiento (NVIDIA)**.
3. **Panel de NVIDIA**, perfil de Roblox → *Procesador de gráficos preferido* → **Procesador NVIDIA de alto rendimiento** (sección 6). Va por nombre de ejecutable y sobrevive a las actualizaciones.
4. **Comprueba** con una partida en pantalla (no minimizado) en el Administrador de tareas (columna *Motor de GPU*) o repitiendo el diagnóstico.

Ojo: si el ejecutable está en una carpeta `version-xxxxxxxx`, esa ruta cambia con cada actualización
de Roblox y la preferencia de Windows se pierde. Fishstrap 3.0.3 añadió un **directorio estático**
(carpeta fija, p. ej. `WindowsPlayer`) precisamente para que el panel de NVIDIA y Windows reconozcan
siempre a Roblox. El diagnóstico muestra qué ruta usas. El perfil de NVIDIA (sección 6) va por nombre
de ejecutable, así que no se pierde al actualizar.

### 5.3 Energía y rendimiento
- *Configuración → Sistema → Energía y batería → Modo de energía* (con cargador) → **Mejor rendimiento**.
- **NitroSense** (tecla Nitro): modo **Rendimiento**, o **Turbo** si lo tienes y las temperaturas lo permiten. Ventiladores en automático o al máximo mientras juegas.
- El diagnóstico avisa si el plan de energía limita la CPU (estado máximo del procesador < 100 % o turbo desactivado). Si lo hace, la forma limpia de arreglarlo es *Panel de control → Opciones de energía → Restaurar la configuración predeterminada del plan*.
- No uses el plan «Rendimiento máximo» (Ultimate Performance) en un portátil: impide que la CPU baje a estados de reposo, sube la temperatura y puede provocar *throttling*.
  Algunos programas (por ejemplo ExitLag) crean su propia copia de ese plan. Además, con un plan distinto de **Equilibrado**, el «Modo de energía» de Windows 11 deja de aplicarse.
  Prueba *Panel de control → Opciones de energía →* **Equilibrado** + modo **Mejor rendimiento**, y compara con tus mediciones.
- En el *Administrador de tareas → Procesos*, comprueba que Roblox **no** esté en **Modo de eficiencia** (icono de hoja).

### 5.4 Gráficos híbridos y MUX
No pude confirmar si el ANV15-51 tiene conmutador MUX. Abre NitroSense → icono de engranaje: si
existe una opción del tipo **«Solo GPU dedicada» / «Discrete GPU»**, puedes probarla (requiere
reiniciar). Puede subir los FPS y bajar la latencia, a cambio de más consumo con batería. Mide antes
y después. Si la opción no existe, el equipo funciona siempre en modo híbrido y no hay nada que cambiar.

### 5.5 Modo Juego, captura y opciones gráficas
- *Configuración → Juegos → Modo de juego* → **Activado**.
- *Configuración → Juegos → Capturas* → **«Grabar lo que pasó»: Desactivado** (graba continuamente en segundo plano).
- *Configuración → Sistema → Notificaciones* → activar «No molestar» automáticamente **al jugar**.
- *Configuración → Sistema → Pantalla → Gráficos → Configuración de gráficos predeterminada*:
  - **Optimizaciones para juegos en ventana: Activado** (permite la presentación de baja latencia en modo ventana sin bordes).
  - **Programación de GPU acelerada por hardware (HAGS):** déjala como está. Solo si hay microtirones persistentes, prueba a cambiarla (requiere reiniciar) y compara con PresentMon.

### 5.6 Programas en segundo plano y superposiciones
- **Discord:** *Configuración de usuario → Superposición del juego* → desactivada, o desactivada para Roblox.
- **Xbox Game Bar:** con la grabación en segundo plano desactivada no consume recursos de forma apreciable; no hace falta desinstalarla.
- **NVIDIA App:** desactiva la **Repetición instantánea** y la superposición si no las usas. Desactiva también la optimización automática de juegos para Roblox, para que no cambie tus ajustes.
- **Navegador:** cierra las pestañas con vídeo o streams mientras juegas.
- **OneDrive y launchers** (Steam, Epic): pausa sincronizaciones y descargas mientras juegas.
- **Inicio de Windows:** *Configuración → Aplicaciones → Inicio* → desactiva lo que no necesites al arrancar (decisión tuya; el diagnóstico lista los programas).
- **RivaTuner / MSI Afterburner:** si limitan los FPS, no los combines con otro limitador.
- **Limpiadores de RAM (Mem Reduct y similares):** ciérralos y quítalos del inicio. Vaciar la memoria a la fuerza obliga a recargarla y puede causar tirones; con 24 GB no hacen falta.
- **Wallpaper Engine:** en sus ajustes de rendimiento, pon «Otra aplicación en pantalla completa/maximizada» en **Pausar** o **Detener**, o ciérralo mientras juegas.

### 5.7 Almacenamiento
Deja al menos un 15-20 % libre en C:. Para liberar espacio, usa *Configuración → Sistema →
Almacenamiento → Recomendaciones de limpieza* (herramienta de Windows) y nada de limpiadores de terceros.

### 5.8 Drivers (te pido autorización antes; los instalas tú)
- **NVIDIA:** el último Game Ready desde la NVIDIA App o nvidia.com. Una instalación normal basta; DDU solo si hay problemas.
- **Intel UHD:** importa en modo híbrido, porque es la que muestra la imagen. Primero, la página de soporte de Acer para tu modelo; si el driver es muy antiguo, el de Intel.
- **BIOS:** solo desde el soporte de Acer, con el cargador conectado y únicamente si la nota de la versión corrige algo relevante.
- **Windows Update:** al día.

### 5.9 Lo que NO se toca (y por qué)
- Windows Defender, Firewall, aislamiento del núcleo e integridad de memoria (VBS/HVCI), actualizaciones de seguridad, servicios críticos.
- Packs de «tweaks» de registro, desactivadores de servicios, «optimizadores» y limpiadores de RAM.
- Prioridad «Alta» o «Tiempo real» forzada para Roblox, o tocar su proceso con herramientas externas: no hay evidencia de mejora, y Roblox tiene un sistema antitrampas.
- Ajustes TCP (Nagle, TCPAckFrequency…): Roblox usa UDP para el juego, así que esos ajustes no le afectan. Cambiar el DNS tampoco cambia el ping en partida.

---

## 6. NVIDIA: solo el perfil de Roblox

*Panel de control de NVIDIA → Configuración 3D → Administrar la configuración 3D → **Configuración de programa*** →
selecciona **Roblox** / `RobloxPlayerBeta.exe` (si no aparece: *Agregar* → busca el `.exe` que indica el
diagnóstico). **No cambies la Configuración global.** Haz capturas antes.

| Opción (nombres aproximados en español) | Valor | Motivo |
|---|---|---|
| Procesador de gráficos preferido | **Procesador NVIDIA de alto rendimiento** | Asegura que Roblox use la RTX 2050 |
| Modo de control de energía *(también «de administración de energía»)* | **Preferir rendimiento máximo** | Evita bajadas de reloj entre picos de carga. Solo afecta a Roblox |
| Modo de baja latencia | **Activado**. Prueba **Ultra** solo si las mediciones muestran límite por GPU | Reduce la cola de frames en DirectX 11 cuando la GPU va al límite. Si el límite es la CPU, no aporta nada |
| Sincronización vertical | **Desactivado** | Menor latencia. A cambio puede aparecer *tearing* (líneas de corte) |
| Velocidad de fotogramas máxima | **Desactivado** si limitas los FPS en Roblox. Si necesitas exactamente 165 y Roblox no lo ofrece: **165** aquí y Roblox en 240 | Usa un solo limitador |
| Filtrado de textura – Calidad | **Alto rendimiento** | Ganancia pequeña en la GPU |
| Filtrado de textura – Optimización trilineal / de muestra anisotrópica | **Activado** | Ídem |
| Antialiasing y filtrado anisotrópico | **Controlado por la aplicación** | Que decida Roblox |
| Optimización de subprocesos | **Automático** (predeterminado) | Sin evidencia para cambiarlo |
| G-SYNC | Solo si aparece *Configurar G-SYNC* | En modo híbrido normalmente no está disponible |

**Revertir:** botón **Restaurar** en el perfil de Roblox (vuelve a los valores del driver).

---

## 7. Roblox y Fishstrap

### 7.1 Fishstrap
- Última versión que pude confirmar: **v3.1.2** (GitHub y WinGet, agosto de 2026). `2-diagnostico.ps1` compara tu versión con la última publicada en GitHub.
- Descárgalo **solo** de **github.com/fishstrap/fishstrap** o **fishstrap.app**. El propio proyecto advierte que otros sitios no son suyos.
- Mantén **desactivadas** las funciones experimentales que piden acceso a la cookie de Roblox (*BetterMatchmaking*, *Roblox Cookie Access*): dan a un programa de terceros acceso a tu sesión y no mejoran los FPS.
- Activa el **directorio estático** si tu versión lo ofrece (sección 5.2).

### 7.2 FastFlags: qué ha cambiado
Desde el **29 de septiembre de 2025**, Roblox solo aplica las FastFlags de una **lista de permitidas**;
las demás se **ignoran sin ningún aviso**. Fishstrap 3.0 eliminó la mayoría de sus presets por ese
motivo y advierte que intentar saltarse la restricción puede acabar en baneo.

Lista conocida (puede haber cambiado; el diagnóstico la usa para marcar cada flag como `PERMITIDA` o `IGNORADA`):

| Grupo | Flags |
|---|---|
| Geometría | `DFIntCSGLevelOfDetailSwitchingDistance`, `…L12`, `…L23`, `…L34` |
| Render | `FFlagHandleAltEnterFullscreenManually`, `DFFlagTextureQualityOverrideEnabled`, `DFIntTextureQualityOverride`, `FIntDebugForceMSAASamples`, `DFFlagDisableDPIScale`, `FFlagDebugGraphicsPreferD3D11`, `FFlagDebugGraphicsPreferVulkan`, `FFlagDebugGraphicsPreferOpenGL`, `FFlagDebugSkyGray`, `DFFlagDebugPauseVoxelizer`, `DFIntDebugFRMQualityLevelOverride`, `FIntFRMMaxGrassDistance`, `FIntFRMMinGrassDistance` |
| Interfaz | `FIntGrassMovementReducedMotionFactor` |

Consecuencias prácticas:
- `DFIntTaskSchedulerTargetFps` (el antiguo «desbloqueo de FPS») **ya no funciona**. Usa el límite de FPS de Roblox (sección 8).
- Flags de red como `DFIntConnectionMTUSize` y otras «para el ping» **no se aplican**.
- **Recomendación:** empieza **sin ninguna FastFlag** y mide. Quita las `IGNORADA` desde el editor de Fishstrap.
- Pruebas opcionales, de una en una y con medición:
  - `FIntDebugForceMSAASamples = 1` (sin MSAA) → solo si estás limitado por la GPU con una calidad que activa MSAA.
  - `DFFlagTextureQualityOverrideEnabled = True` + `DFIntTextureQualityOverride = 0` o `1` → solo si la VRAM pasa del 90 %.
- **API gráfica:** deja DirectX 11 (la predeterminada). Vulkan u OpenGL solo como prueba A/B: Fishstrap 3.1 tuvo que simular el modo «sin bordes» en Vulkan, así que la pantalla completa se comporta distinto.

### 7.3 Ajustes de Roblox para Blade Ball
- **Modo de gráficos: Manual.** El automático cambia la calidad sobre la marcha y provoca variaciones de FPS.
- **Calidad gráfica:** empieza en **1-3 barras**. Súbela solo mientras el 1% low se mantenga ≥ 90 % de tu límite en la escena B.
  En niveles bajos, Roblox reduce sombras, distancia de dibujado y efectos, que es justo lo que más carga en rondas caóticas.
  La bola y el indicador de objetivo siguen viéndose igual.
- **Pantalla completa:** activada (F11).
- **Velocidad de fotogramas máxima:** según la sección 8.
- **Ajustes propios de Blade Ball** (engranaje dentro del juego): si ofrece opciones para reducir efectos o partículas, actívalas. No pude verificar qué opciones tiene ahora mismo.
- **Estadísticas de rendimiento:** actívalas solo para medir el ping (sección 9).

### 7.4 ¿Fishstrap, Bloxstrap o el cliente oficial?

| | Fishstrap | Bloxstrap | Cliente oficial |
|---|---|---|---|
| Mantenimiento confirmado | v3.1.2, agosto de 2026 | v2.11.3, abril de 2026 (no encontré versiones más recientes) | Roblox |
| FastFlags | Misma lista permitida | Misma lista permitida | Misma lista permitida |
| Extras útiles | Directorio estático, editor de ajustes globales (límite de FPS y calidad), integración con Discord | Integración con Discord, mods | — |
| FPS esperados | Iguales: los tres ejecutan el mismo `RobloxPlayerBeta.exe` | Iguales | Iguales |

Con la lista de permitidas, ningún launcher da FPS extra. La diferencia está en la comodidad y la
compatibilidad. **Recomendación: conserva Fishstrap** si está actualizado y descargado de su fuente
oficial (el directorio estático y el editor del límite de FPS te sirven). Si alguna vez tienes
cierres o errores al iniciar, prueba con el cliente oficial para descartar el launcher. Si quieres
comprobarlo, haz una captura A/B de la escena A con cada uno.

---

## 8. Límite de FPS: 120 vs 144 vs 165

Datos de partida: VSync desactivado y, salvo que NitroSense ofrezca MUX, sin G-SYNC.

| Límite | Tiempo por frame | Qué esperar |
|---|---|---|
| 120 | 8,33 ms | Más margen: la GPU y la CPU van más holgadas, frametimes más estables y menos calor |
| 144 | 6,94 ms | Punto intermedio |
| 165 | 6,06 ms | Coincide con la pantalla. Solo compensa si el equipo lo **sostiene**: pasar de 144 a 165 ahorra unos 0,9 ms por frame, menos de lo que pierdes con un solo tirón |

**Cómo poner el límite** (usa **solo uno**):
1. Roblox → *Ajustes → Velocidad de fotogramas máxima*. La lista original es 60/120/144/240. No pude confirmar si ya incluye 165.
2. Si no aparece 165: el editor de ajustes globales de Fishstrap (permite subir el límite) o el panel de NVIDIA → *Velocidad de fotogramas máxima = 165* con Roblox en 240.
3. Comprueba que funciona: con `-LimiteFps 165`, el análisis indicará si los FPS quedan «pegados» al límite.

**Prueba:** para cada límite, escena A ×2 y escena B ×1, analizadas con `-LimiteFps`.

**Cómo elegir:** el límite **más alto** que cumpla las tres condiciones:
- 1% low ≥ ~90 % del límite en la escena B;
- `GPU ocupada / frametime` ≤ ~0,85 (deja margen y evita que se acumulen frames, que añade latencia);
- sin *throttling* térmico en HWiNFO ni en el monitor.

Si 165 no cumple, elige 144; si 144 tampoco, 120. **Un 144 estable es mejor para el parry que un 165 que oscila.**

---

## 9. Red y latencia (Blade Ball depende mucho del ping)

1. `powershell -ExecutionPolicy Bypass -File .\4-prueba-red.ps1` en reposo.
2. Repítelo mientras alguien de tu casa ve vídeo o descarga algo (prueba de *bufferbloat*).
   Como alternativa: el test de bufferbloat de waveform.com en el navegador.
3. En partida: *Ajustes de Roblox → Estadísticas de rendimiento* muestra el **ping real al servidor**. Anótalo en `resultados.csv`.

| Síntoma | Probable causa | Acción |
|---|---|---|
| FPS estables (PresentMon), pero la bola «salta» o el parry no entra | Red | Sección 9 |
| Jitter o pérdida ya hacia **tu router** | Wi-Fi o cable de casa | Ethernet; si no puedes, Wi-Fi de 5 GHz y cerca del router |
| Red local bien, pero jitter o pérdida hacia Internet | Saturación de la línea o del proveedor | Pausar descargas y streams; si el ping se dispara con carga, revisa la calidad de servicio (QoS) del router |
| Todo estable, pero ping alto en Roblox | Distancia al servidor | No se puede elegir región de forma oficial. Evita las funciones experimentales con cookie |
| Picos en PresentMon y tirones que ves en pantalla | Rendimiento local, no red | Secciones 3 a 8 |

No uses «reductores de ping», VPN «gaming» ni ajustes TCP sin una medición que demuestre la mejora.
Si ya usas uno (por ejemplo ExitLag), compara el ping y su estabilidad en Roblox con él y sin él en la misma partida o servidor.

---

## 10. Resultados (para rellenar con TUS mediciones)

`resultados.csv` se genera solo. Resumen para copiar aquí, o para enviármelo junto con
`diagnostico-*.txt` y `carga-resumen-*.txt` y analizarlo:

| Fase | Escena | Límite | FPS prom. | 1% low | 0.1% low | p99 frametime | Picos/min | GPU ocupada | T. CPU máx. | T. GPU máx. | Ping | Notas |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Base | A | | *pendiente* | | | | | | | | | |
| Base | B | | *pendiente* | | | | | | | | | |
| + Windows/energía | A/B | | | | | | | | | | | |
| + NVIDIA | A/B | | | | | | | | | | | |
| + Roblox/Fishstrap | A/B | | | | | | | | | | | |
| Límite 120 | B | 120 | | | | | | | | | | |
| Límite 144 | B | 144 | | | | | | | | | | |
| Límite 165 | B | 165 | | | | | | | | | | |

---

## 11. Configuración final recomendada (punto de partida; tus mediciones mandan)

**Roblox:** gráficos en Manual, calidad 1-3 (o la más alta que mantenga el 1% low ≥ 90 % del límite);
pantalla completa; límite según la sección 8; sin FastFlags `IGNORADA`; DirectX 11.

**NVIDIA (solo perfil de Roblox):** GPU NVIDIA de alto rendimiento · Preferir rendimiento máximo ·
baja latencia Activado (Ultra solo si el límite es la GPU) · VSync desactivado · filtrado de textura
en Alto rendimiento · un único limitador de FPS.

**Windows:** 165 Hz fijos · Mejor rendimiento con cargador · NitroSense en Rendimiento o Turbo ·
Modo de juego activado · «Grabar lo que pasó» desactivado · Optimizaciones para juegos en ventana
activado · HAGS sin cambios · superposición de Discord y Repetición instantánea de NVIDIA desactivadas ·
drivers de NVIDIA e Intel al día · Defender, Firewall y actualizaciones intactos.

**Launcher:** Fishstrap actualizado desde github.com/fishstrap/fishstrap o fishstrap.app, sin funciones
experimentales con cookie y con directorio estático si está disponible.

---

## 12. Cómo revertir cada cambio

| Cambio | Cómo volver atrás |
|---|---|
| Lo aplicado por `aplicar-ajustes-windows.ps1` | `powershell -ExecutionPolicy Bypass -File .\aplicar-ajustes-windows.ps1 -Deshacer "<deshacer-ajustes-windows-….json>"` (el comando exacto aparece al terminar de aplicar) |
| FastFlags, ajustes de Fishstrap y ajustes del juego | Cierra Roblox y Fishstrap → `powershell -ExecutionPolicy Bypass -File .\revertir-archivos.ps1 -Respaldo "<carpeta respaldo-...>"` |
| Perfil de NVIDIA | Panel de NVIDIA → perfil de Roblox → **Restaurar** (o vuelve a los valores de tus capturas) |
| Frecuencia de pantalla | *Pantalla avanzada* → el valor que figura en `estado-original.txt` |
| Modo de energía | *Energía y batería → Modo de energía* → el de `estado-original.txt` (vacío o `00000000-…` = Equilibrado) |
| NitroSense / MUX | El modo anterior en NitroSense (el MUX requiere reiniciar) |
| Preferencia de GPU de Windows | *Pantalla → Gráficos* → Roblox → *Quitar* o *Dejar que Windows decida* |
| Modo de juego, capturas, HAGS, juegos en ventana | Mismo interruptor, con el valor de `estado-original.txt` (HAGS requiere reiniciar) |
| Discord, NVIDIA App, inicio de Windows | Mismo interruptor en cada app |
| Registro (último recurso) | Doble clic en el `.reg` de `respaldo-…\registro`. Ojo: restaura los valores guardados, pero no borra los que se crearon después; para eso usa los menús de arriba |
| Drivers | *Administrador de dispositivos → adaptador → Propiedades → Controlador → Revertir al controlador anterior* |

---

## Fuentes

- Lista de FastFlags permitidas (29-09-2025): [anuncio en el DevForum de Roblox](https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569) · [copia de la lista](https://github.com/LeventGameing/allowlist)
- Fishstrap: [repositorio oficial](https://github.com/fishstrap/fishstrap) · [versiones](https://github.com/fishstrap/fishstrap/releases) (v3.0.0.0: restricción de FastFlags; v3.0.3: directorio estático; v3.1.2: última confirmada)
- Bloxstrap: [notas de la v2.11.3](https://bloxstraplabs.com/versions/2.11.3)
- Límite de FPS de Roblox: [Introducing the Maximum Framerate setting](https://devforum.roblox.com/t/introducing-the-maximum-framerate-setting/2995965) · [Dexerto](https://www.dexerto.com/roblox/how-to-change-your-fps-in-roblox-2751173/)
- MUX en portátiles Acer: [blog de Acer](https://blog.acer.com/en/discussion/4510/what-is-a-mux-switch-how-to-turn-it-on-and-off-on-your-gaming-laptop) · análisis del ANV15-51: [LaptopMedia](https://laptopmedia.com/review/acer-nitro-v-15-anv15-51-review-successful-symbiosis-between-the-aspire-and-the-nitro-series/)
- PresentMon (opciones y columnas): [README de la aplicación de consola](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
