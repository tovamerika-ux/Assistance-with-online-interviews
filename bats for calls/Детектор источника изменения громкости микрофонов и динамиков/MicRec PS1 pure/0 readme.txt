Структура файлов и зависимости
Скрипт состоит из трёх файлов:
   ChangeMicVolumeDetector.ps1  — логика мониторинга микрофонов (Krisp, Voicemeeter Out B1, USBC Headset)
   ChangePlaybackVolumeDetector.ps1  — логика мониторинга устройств воспроизведения
   AudioUtils.ps1                    — общая библиотека функций, подключается через . "$PSScriptRoot\AudioUtils.ps1"

AudioUtils.ps1 должен находиться в той же папке, что и ChangePlaybackVolumeDetector.ps1 и ChangeMicVolumeDetector.ps1.

Запуск обоих детекторов одновременно:
   ChangeRecordPlaybackVolumeDetector.bat — запускает ChangeMicVolumeDetector и ChangePlaybackVolumeDetector
   в отдельных окнах консоли.