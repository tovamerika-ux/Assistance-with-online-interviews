@echo off
REM Гарнитура Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\
REM Усиливаем только звук от микрофона своей гарнитуры
REM Батник написан для Voicemeeter 1.X.X.X, т.е. для обычной версии

cd /d C:\SoundVolumeView

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Динамики гарнитуры Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\Render
set "SPK_NAME_Headset={0.0.0.00000000}.{f6ada981-1316-4cbe-a298-b39c3015fa01}"

REM Микрофон гарнитуры Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\Capture
set "MIC_NAME_Headset={0.0.1.00000000}.{3136ddda-2336-43ab-ac93-8451214ccb99}"

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

REM Запускаем Voicemeeter (если уже запущен — просто откроется/сфокусится)
start "" "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
timeout /t 1 >nul

cd /d C:\vmrcli\
REM грузим XML-профиль через Remote API
vmrcli.exe -k basic -e -l INFO -c "Voicemeeter_calls_mode_Samsung_AKG_headset.xml"

echo Calls + Voicemeeter Samsung_AKG audio profile applied. Gain: Samsung AKG output.
