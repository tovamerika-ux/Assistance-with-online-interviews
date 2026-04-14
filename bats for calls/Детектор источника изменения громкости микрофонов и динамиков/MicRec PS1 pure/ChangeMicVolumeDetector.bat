@echo off
REM %~dp0 — внутреннее значение CMD, которое PowerShell формирует сам, в результате путь берётся не из текста батника, а из метаданных запуска файла,
REM кириллица туда попадает уже корректно, без перекодировки
REM поэтому кирилица в пути файла вообще перестаёт быть проблемой.


set "PS1=%~dp0ChangeMicVolumeDetector.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

