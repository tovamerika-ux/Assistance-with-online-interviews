@echo off
cd /d C:\SoundVolumeView
REM Батник для ноута YOGA. Режим просмотра фильмов на ноуте

REM Встроенные динамики ноута: Realtek(R) Audio\Device\Динамики\Render
set "SPK_NAME={0.0.0.00000000}.{f4fbe252-29ed-414d-bcf6-c460dff5eed5}"

REM Встроенный микрофон ноута: Realtek(R) Audio\Device\Набор микрофонов\Capture
set "MIC_NAME={0.0.1.00000000}.{14673e6c-d339-4a90-bc3a-d9d1cb3303be}" 

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Обычный вывод/ввод. На случай если устройства были отключены вручную — включаем их
SoundVolumeView.exe /Enable "%SPK_NAME%"
SoundVolumeView.exe /Enable "%MIC_NAME%"
timeout /t 1 >nul

REM Выбираем по умолчанию обычный вывод/ввод
SoundVolumeView.exe /SetDefault "%SPK_NAME%" all
SoundVolumeView.exe /SetDefault "%MIC_NAME%" all

REM Включаем системные звуки
reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".Default" /f >nul

REM Stereo Mix включаем. Хотя зачем он нужен? Можно и не включать никогда
SoundVolumeView.exe /Enable "%MIXER_NAME%"

REM Завершение с /F нужно для случая, когда в настройках стоит галочка "System Tray"
taskkill /IM voicemeeter_x64.exe /F
taskkill /IM voicemeeterpro_x64.exe /F
taskkill /IM voicemeeter8x64.exe /F

REM ============================================================
REM Надежно останавливаем Krisp
REM ------------------------------------------------------------
taskkill /IM Krisp.exe /F /T >nul 2>&1

REM ============================================================

echo Normal audio profile applied.
