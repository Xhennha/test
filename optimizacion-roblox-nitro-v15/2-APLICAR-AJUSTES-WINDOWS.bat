@echo off
rem Aplica los ajustes seguros de Windows. Muestra el plan y pide confirmacion antes de cambiar nada.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\aplicar-ajustes-windows.ps1"
pause
