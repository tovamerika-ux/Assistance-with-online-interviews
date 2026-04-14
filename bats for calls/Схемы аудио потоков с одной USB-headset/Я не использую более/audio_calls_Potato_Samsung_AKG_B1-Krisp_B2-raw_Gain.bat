@echo off
REM Гарнитура Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\
REM 1. На звук от микрофона своей гарнитуры накладываем шумодав от Krisp, с выхода которого берем очищенный звук и усиливаем его в Voicemeeter.
REM 2. Помимо этого raw-звук от микрофона своей гарнитуры подаём на отдельный канал и усиливаем (чтобы потом его можно было использовать для анализа речи ассистентом (нейронкой))
REM Батник написан для Voicemeeter 3.X.X.X, т.е. для Potato. Никакой надобности использовать Potato по сравнению с Banana нет, просто я купил именно Potato.

cd /d C:\SoundVolumeView

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Динамики гарнитуры Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\Render
set "SPK_NAME_Headset={0.0.0.00000000}.{f6ada981-1316-4cbe-a298-b39c3015fa01}"

REM Stereo Mix выключаем
SoundVolumeView.exe /Disable "%MIXER_NAME%"

REM заглушаем системные звуки
reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".None" /f >nul

REM Звонковый вывод. На случай если устройство было отключено вручную — включаем его
SoundVolumeView.exe /Enable "%SPK_NAME_Headset%"

REM Звонковый вывод - динамики гарнитуры
SoundVolumeView.exe /SetDefault "%SPK_NAME_Headset%" all

REM Звонковый ввод: микрофон из Voicemeeter (B1)
SoundVolumeView.exe /SetDefault "VB-Audio Voicemeeter VAIO\Device\Voicemeeter Out B1\Capture" all

REM Выставляем громкость микрофонов на максимум:
SoundVolumeView.exe /SetVolume "Voicemeeter Out B1" 100
SoundVolumeView.exe /SetVolume "Krisp Microphone" 100
REM выставлять громкость физического микрофона таким же образом не нужно, т.к. этим параметром управляет Krisp, который держит уровень громкости физического микрофона в районе 90-98% (при активной галочке "Lock microphone volume at optimal level" в настройках Krisp).

REM ============================================================
REM Запускаем Krisp (если не запущен)
REM ------------------------------------------------------------
tasklist /FI "IMAGENAME eq Krisp.exe" 2>NUL | find /I "Krisp.exe" >NUL
if errorlevel 1 (
    if exist "C:\Program Files\Krisp\Krisp.exe" (
        start "" "C:\Program Files\Krisp\Krisp.exe"
        timeout /t 4 >nul
    ) else (
        echo [WARN] Krisp exe not found
    )
)
REM ============================================================

REM важно: Voicemeeter должен быть полностью закрыт, чтобы загрузить в него XML-файл при следующем запуске
REM Stop Voicemeeter completely
taskkill /IM voicemeeter8x64.exe /F >nul 2>&1

REM Ожидаем пока процесс не пропадёт (max ~5 сек)
for /L %%i in (1,1,10) do (
  tasklist /FI "IMAGENAME eq voicemeeter8x64.exe" 2>NUL | find /I "voicemeeter8x64.exe" >NUL
  if errorlevel 1 goto VM_STOPPED
  timeout /t 1 /nobreak >nul
)
:VM_STOPPED

REM Запускаем Voicemeeter Potato с XML-профилем
REM важно: Voicemeeter должен быть полностью закрыт, иначе XML-файл не загрузится
start "" "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8x64.exe" -L"C:\Program Files (x86)\VB\VoicemeeterPotato_calls_mode_Samsung_AKG_headset_B1-Krisp_B2-raw_Gain.xml"
timeout /t 1 >nul

echo Calls + Voicemeeter Samsung_AKG audio profile applied. B1: 1)Krisp 2) Gain: Samsung AKG output. B2 - raw,Gain: Samsung AKG output
