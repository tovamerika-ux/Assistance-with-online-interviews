@echo off
REM Мастер-лаунчер: запускает оба детектора в отдельных окнах консоли.
REM Закрытие этого окна НЕ останавливает уже запущенные детекторы.

start "ChangeMicVolumeDetector"        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChangeMicVolumeDetector.ps1"
start "ChangePlaybackVolumeDetector"   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChangePlaybackVolumeDetector.ps1"
