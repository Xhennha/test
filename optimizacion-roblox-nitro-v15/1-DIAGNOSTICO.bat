@echo off
rem Diagnostico de solo lectura: no cambia nada.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\2-diagnostico.ps1"
pause
