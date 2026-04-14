@echo off
REM Гарнитура Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\
REM Усиливаем микрофон своей гарнитуры и звук от собеседника 
REM Усиливаем звук от собеседника (поэтому в имени кода конфигурации присутствует "Virtual_Input" по аналогии с названием канала Virtual Inputs\Voicemeeter Input в Voicemeeter, в котором происходит усиление звук от собеседника)
REM Вместе с голосом и звуками от собеседника в гарнитуру попадают все системные звуки и звуки приложений, поскольку устройство Voicemeeter Input выбрано в качестве дефолтного для воспроизведения. Способа отделения звуков системы от звуков собеседника нет по причине ограничений приложения Phone Link (нет управления аудиоустройствами, т.е. нельзя выбрать устройство ни для входа ни для выхода). 
REM Поэтому не используете приложения, которые могут издавать звуки и которые вам не нужны во время созвона по Phone Link, не открывайте в браузере сайты, где может появиться звук - для случая, когда дефолтное устройство воспроизведения (Voicemeeter Input) используется для распознавания голоса ассситентом(нейронкой).
REM Батник написан для Voicemeeter 1.X.X.X, т.е. для обычной версии

cd /d C:\SoundVolumeView

set MIXER_NAME="Realtek(R) Audio\Device\Стерео микшер\Capture"

REM Микрофон гарнитуры Samsung EO-IC100BWEGRU: USBC Headset\Device\Головной телефон\Capture
set "MIC_NAME_Headset={0.0.1.00000000}.{3136ddda-2336-43ab-ac93-8451214ccb99}"

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
start "" "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe" -L"C:\Program Files (x86)\VB\Voicemeeter_calls_mode_Samsung_AKG_headset_with_Virtual_Input.xml"
timeout /t 1 >nul

echo Calls + Voicemeeter Samsung_AKG audio profile applied. Gain: 1)sound from the cellphone interlocutor, 2)Samsung AKG output.
