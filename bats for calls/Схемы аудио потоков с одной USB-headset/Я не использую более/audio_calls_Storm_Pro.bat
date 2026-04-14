@echo off
REM Гарнитура Storm Pro: Storm Pro\Device\Динамики\
REM Усиливаем только звук от микрофона своей гарнитуры
REM Батник написан для Voicemeeter 1.X.X.X, т.е. для обычной версии

cd /d C:\SoundVolumeView

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Динамики гарнитуры Storm Pro: Storm Pro\Device\Динамики\Render
set "SPK_NAME_Headset={0.0.0.00000000}.{28091505-8d38-4b96-b30c-1ffb3ba9f892}"

REM Микрофон гарнитуры Storm Pro: Storm Pro\Device\Микрофон\Capture
set "MIC_NAME_Headset={0.0.1.00000000}.{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}"

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
SoundVolumeView.exe /SetVolume "%MIC_NAME_Headset%" 100

REM важно: Voicemeeter должен быть полностью закрыт, чтобы загрузить в него XML-файл при следующем запуске
REM Проверка: запущен ли процесс
tasklist /FI "IMAGENAME eq voicemeeter_x64.exe" 2>NUL | find /I "voicemeeter_x64.exe" >NUL
if %errorlevel%==0 (
  echo Voicemeeter is running - terminating it...
  taskkill /IM voicemeeter_x64.exe /F
  timeout /t 1 /nobreak >nul
)

REM Запускаем Voicemeeter с XML-профилем
REM важно: Voicemeeter должен быть полностью закрыт, иначе XML-файл не загрузится
start "" "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe" -L"C:\Program Files (x86)\VB\Voicemeeter_calls_mode_Storm_Pro_headset.xml"
timeout /t 1 >nul

echo Calls + Voicemeeter Storm_Pro audio profile applied. Gain: Storm Pro output.
