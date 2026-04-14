@echo off
REM Гарнитура Samsung Galaxy Buds (SM-R175): Galaxy Buds+ (89AE)\Device\
REM 1. На звук от микрофона своей гарнитуры накладываем шумодав от Krisp, с выхода которого берем очищенный звук и усиливаем его в Voicemeeter.
REM 2. Помимо этого raw-звук от микрофона своей гарнитуры подаём на отдельный канал и усиливаем (чтобы потом его можно было использовать для анализа речи ассистентом (нейронкой))
REM 3. Усиливаем звук от собеседника (поэтому в имени кода конфигурации присутствует "Virtual_Input" по аналогии с названием канала Virtual Inputs\Voicemeeter Input в Voicemeeter, в котором происходит усиление звук от собеседника)
REM Вместе с голосом и звуками от собеседника в гарнитуру попадают все системные звуки и звуки приложений, поскольку устройство Voicemeeter Input выбрано в качестве дефолтного для воспроизведения. Способа отделения звуков системы от звуков собеседника нет по причине ограничений приложения Phone Link (нет управления аудиоустройствами, т.е. нельзя выбрать устройство ни для входа ни для выхода). 
REM Поэтому не используете приложения, которые могут издавать звуки и которые вам не нужны во время созвона по Phone Link, не открывайте в браузере сайты, где может появиться звук - для случая, когда дефолтное устройство воспроизведения (Voicemeeter Input) используется для распознавания голоса ассситентом(нейронкой).
REM Батник написан для Voicemeeter 3.X.X.X, т.е. для Potato. Никакой надобности использовать Potato по сравнению с Banana нет, просто я купил именно Potato.

cd /d C:\SoundVolumeView

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Stereo Mix выключаем
SoundVolumeView.exe /Disable "%MIXER_NAME%"

REM заглушаем системные звуки
reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".None" /f >nul

REM Звонковый вывод: системный звук в Voicemeeter
SoundVolumeView.exe /SetDefault "VB-Audio Voicemeeter VAIO\Device\Voicemeeter Input\Render" all

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
start "" "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter8x64.exe" -L"C:\Program Files (x86)\VB\VoicemeeterPotato_calls_mode_Galaxy_Buds_headset_B1-Krisp_B2-raw_Gain_and_Virtual_Input.xml"
timeout /t 1 >nul

echo Calls + Voicemeeter Samsung_AKG audio profile applied. B1: 1)Krisp 2) Gain: Samsung AKG output. B2 - raw,Gain: Samsung AKG output 3)Gain: sound from the cellphone interlocutor

