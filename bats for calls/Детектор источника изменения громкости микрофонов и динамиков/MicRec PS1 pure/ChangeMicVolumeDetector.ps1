. "$PSScriptRoot\AudioUtils.ps1"

$logFile = "mic_forensics_log.txt"
$targetVolume = 100
$pollMs = 500
$lastSeen = @{}
$lastSeenMuted = @{}

$krispSettingRefreshSeconds = 2
$nextKrispSettingCheck = Get-Date
$lastKrispSettingChangeAt = $null

# Автоматически определяем настройку Krisp "Lock microphone volume at optimal level" из файла user.config
# Значение > 0 - галочка включена, скрипт только сообщает об изменении уровня USBC Headset
# Значение = 0 - галочка выключена, скрипт будет возвращать уровень USBC Headset на 100
# Если настройка не найдена или не читается, используется безопасное значение по умолчанию: $true
# Пример полного пути к файлу:
# C:\Users\Alex\AppData\Local\Krisp\Krisp.exe_Url_umx0atrp0vhkedazz45qlo3visl5aucc\1.40.7.0\user.config
function Get-KrispLockPhysicalMicVolumeSetting {
    param()

    $krispRoot = Join-Path $env:LOCALAPPDATA 'Krisp'

    if (-not (Test-Path $krispRoot)) {
        return $true
    }

    $configFiles = Get-ChildItem -Path $krispRoot -Filter 'user.config' -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($file in $configFiles) {
        try {
            [xml]$xml = Get-Content -Path $file.FullName -Raw -Encoding UTF8

            $settingNodes = $xml.SelectNodes("//setting[@name='LockUpVolumeForMic']")

            foreach ($node in $settingNodes) {
                $valueNode = $node.SelectSingleNode("value")

                if ($null -ne $valueNode) {
                    $rawValue = $valueNode.InnerText.Trim()

                    [int]$numericValue = 0

                    if ([int]::TryParse($rawValue, [ref]$numericValue)) {
                        return ($numericValue -gt 0)
                    }

                    return $true
                }
            }
        }
        catch {
        }
    }

    return $true
}

$KrispLockPhysicalMicVolume = Get-KrispLockPhysicalMicVolumeSetting

function Get-RunningSuspects {
    $suspects = Get-Process -Name `
        "Krisp", `
        "ms-teams", `
        "Teams", `
        "YandexTelemost", `
        "PhoneExperienceHost", `
        "audiodg", `
        "Voicemeeter", `
        "Voicemeeter64", `
        "voicemeeter8", `
        "Voicemeeter8x64", `
        "voicemeeterpro", `
        "Voicemeeterpro_x64", `
        "control", `
        "rundll32", `
        "SystemSettings", `
        "discord", `
        "zoom", `
        "chrome", `
        "firefox", `
		"browser", ` # Яндекс браузер
		"vivaldi",
		"opera",
        "msedge" `
        -ErrorAction SilentlyContinue

    return $suspects | Sort-Object ProcessName, Id -Unique
}

function Get-LikelySourceInfo {
    param(
        [AllowEmptyCollection()]
        [array]$Sessions = @(),

        [AllowEmptyCollection()]
        [array]$Suspects = @(),

        [Parameter(Mandatory)]
        [string]$Label,

        [string]$ForegroundProcessName = $null,

        [Nullable[datetime]]$LastKrispSettingChangeAt = $null,

        [bool]$KrispLockEnabled = $false
    )

    $sessionNames = @(
        $Sessions |
        ForEach-Object {
            if ($_.ProcessName) {
                $_.ProcessName.ToString().ToLowerInvariant()
            }
        }
    ) | Sort-Object -Unique

    $suspectNames = @(
        $Suspects |
        ForEach-Object {
            if ($_.ProcessName) {
                $_.ProcessName.ToString().ToLowerInvariant()
            }
        }
    ) | Sort-Object -Unique

    $foregroundName = $null
    if ($ForegroundProcessName) {
        $foregroundName = $ForegroundProcessName.ToLowerInvariant()
    }

    # Для foreground-проверки: все три процесса надёжно указывают на открытое окно настройки звука
    $uiNames = @('rundll32', 'control', 'systemsettings') # mmsys.cpl - это rundll32
    $manualUiForeground = $foregroundName -in $uiNames

    # Для background-проверки: SystemSettings.exe исключён — Windows 11 держит его
    # в памяти постоянно, что делает его непригодным как сигнал ручного изменения.
    $backgroundUiNames = @('rundll32', 'control')
    $manualUiPresent = @($suspectNames | Where-Object { $_ -in $backgroundUiNames }).Count -gt 0

    $krispRunning = $suspectNames -contains 'krisp'
    $teamsRunning = ($suspectNames -contains 'ms-teams' -or $suspectNames -contains 'teams')
    $telemostRunning = $suspectNames -contains 'yandextelemost'
    $phoneLinkRunning = $suspectNames -contains 'phoneexperiencehost'

    $recentKrispSettingChange = $false
    if ($null -ne $LastKrispSettingChangeAt) {
        $recentKrispSettingChange = ((Get-Date) - $LastKrispSettingChangeAt).TotalSeconds -le 15
    }

    $source = 'unknown'
    $confidence = 'low'
    $primaryNames = @()

    if ($sessionNames.Count -gt 0) {
        if ($sessionNames -contains 'ms-teams' -or $sessionNames -contains 'teams') {
            $source = 'Teams audio session'
            $confidence = 'high'
            $primaryNames = @('ms-teams','teams')
        }
        elseif ($sessionNames -contains 'krisp') {
            $source = 'Krisp audio session'
            $confidence = 'high'
            $primaryNames = @('krisp')
        }
        elseif ($sessionNames -contains 'yandextelemost') {
            $source = 'Yandex Telemost audio session'
            $confidence = 'high'
            $primaryNames = @('yandextelemost')
        }
        elseif ($sessionNames -contains 'phoneexperiencehost') {
            $source = 'Phone Link audio session'
            $confidence = 'high'
            $primaryNames = @('phoneexperiencehost')
        }
        elseif ($sessionNames -contains 'browser') {
            $source = 'Yandex Browser audio session'
            $confidence = 'high'
            $primaryNames = @('browser')
        }
        elseif ($sessionNames -contains 'vivaldi') {
            $source = 'Vivaldi audio session'
            $confidence = 'high'
            $primaryNames = @('vivaldi')
        }
        elseif ($sessionNames -contains 'opera') {
            $source = 'Opera audio session'
            $confidence = 'high'
            $primaryNames = @('opera')
        }
        elseif ($sessionNames -contains 'chrome') {
            $source = 'Chrome audio session'
            $confidence = 'high'
            $primaryNames = @('chrome')
        }
        elseif ($sessionNames -contains 'firefox') {
            $source = 'Firefox audio session'
            $confidence = 'high'
            $primaryNames = @('firefox')
        }
        elseif ($sessionNames -contains 'msedge') {
            $source = 'Microsoft Edge audio session'
            $confidence = 'high'
            $primaryNames = @('msedge')
        }
        else {
            $source = 'audio session on endpoint'
            $confidence = 'high'
            $primaryNames = $sessionNames
        }
    }
    elseif ($Label -eq 'USBC Headset' -and $krispRunning -and ($KrispLockEnabled -or $recentKrispSettingChange) -and (-not $manualUiForeground)) {
        # Krisp является кандидатом в двух случаях:
        # 1. "Lock microphone volume at optimal level" включён — Krisp удерживает уровень.
        # 2. Настройка была изменена недавно (15 сек) — Krisp мог отпустить или захватить уровень
        #    при включении/выключении флага.
        $source = 'Krisp sync or AGC (heuristic)'
        $confidence = if ($recentKrispSettingChange) { 'medium' } else { 'low' }
        $primaryNames = @('krisp')
    }
    elseif ($manualUiForeground) {
        $source = 'manual change via Windows sound settings'
        $confidence = 'medium'
        $primaryNames = $uiNames
    }
    elseif ($manualUiPresent) {
        # rundll32/control запущены в фоне — вероятно mmsys.cpl был открыт.
        # Стоит ДО comm-app эвристик: наличие процесса mmsys.cpl является
        # более прямым признаком ручного изменения, чем просто запущенное приложение.
        $source = 'manual change via Windows sound settings'
        $confidence = 'low'
        $primaryNames = $backgroundUiNames
    }
    elseif ($Label -eq 'B1' -and $teamsRunning) {
        $source = 'Teams (heuristic)'
        $confidence = 'low'
        $primaryNames = @('ms-teams','teams')
    }
    elseif ($telemostRunning) {
        $source = 'Yandex Telemost (heuristic)'
        $confidence = 'low'
        $primaryNames = @('yandextelemost')
    }

    $otherCandidates = @()

    if ($Sessions.Count -gt 0) {
        $otherCandidates += $Sessions |
            Where-Object {
                $_.ProcessName -and
                ($_.ProcessName.ToString().ToLowerInvariant() -notin $primaryNames)
            } |
            ForEach-Object {
                [pscustomobject]@{
                    ProcessName = $_.ProcessName
                    Pid         = $_.Pid
                    Path        = $_.Path
                }
            }
    }

    $otherCandidates += $Suspects |
        Where-Object {
            $_.ProcessName -and
            ($_.ProcessName.ToString().ToLowerInvariant() -notin $primaryNames)
        } |
        Sort-Object ProcessName, Id -Unique |
        ForEach-Object {
            [pscustomobject]@{
                ProcessName = $_.ProcessName
                Pid         = $_.Id
                Path        = $($_.Path)
            }
        }

    return [pscustomobject]@{
        LikelySource    = $source
        Confidence      = $confidence
        OtherCandidates = @($otherCandidates)
    }
}

function Get-SourceEvidence {
    param(
        [Parameter(Mandatory)]
        $Device,

        [Parameter(Mandatory)]
        [string]$Label,

        [bool]$IncludePaths = $true
    )

    # При событии изменения громкости на USBC Headset — перечитываем настройку Krisp,
    # чтобы эвристика не использовала устаревшее значение из 2-секундного кэша.
    # Чтение выполняется только при факте изменения, не в каждой итерации цикла.
    if ($Label -eq 'USBC Headset') {
        $freshKrispLock = Get-KrispLockPhysicalMicVolumeSetting
        if ($freshKrispLock -ne $script:KrispLockPhysicalMicVolume) {
            $script:KrispLockPhysicalMicVolume = $freshKrispLock
            $script:lastKrispSettingChangeAt = Get-Date
            $stateText = if ($script:KrispLockPhysicalMicVolume) { "enabled" } else { "disabled" }
            $settingLine = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Krisp setting changed: `"Lock microphone volume at optimal level`" $stateText"
            Write-Host $settingLine -ForegroundColor Cyan
            Write-LogLine $settingLine
            Write-LogLine ""
        }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $sessions = @(Get-DeviceSessions -Device $Device)
    $suspects = @(Get-RunningSuspects)
    $foregroundProcessName = Get-ForegroundProcessName

    $sourceInfo = Get-LikelySourceInfo `
        -Sessions @($sessions) `
        -Suspects @($suspects) `
        -Label $Label `
        -ForegroundProcessName $foregroundProcessName `
        -LastKrispSettingChangeAt $lastKrispSettingChangeAt `
        -KrispLockEnabled $KrispLockPhysicalMicVolume

    $lines.Add("likely source: $($sourceInfo.LikelySource)")
    $lines.Add("confidence: $($sourceInfo.Confidence)")

    if ($foregroundProcessName) {
        $lines.Add("foreground process: $foregroundProcessName")
    }
    else {
        $lines.Add("foreground process: unknown")
    }

    if ($IncludePaths) {
        $groupedCandidates = @(Format-GroupedProcessLines -Items $sourceInfo.OtherCandidates -PidPropertyName 'Pid' -CompactPidList $false)

        if ($groupedCandidates.Count -gt 0) {
            $lines.Add("other candidates:")
            foreach ($line in $groupedCandidates) {
                $lines.Add($line)
            }
        }
        else {
            $lines.Add("other candidates: none")
        }
    }

    $groupedSessions = @(Format-GroupedSessionLines -Sessions $sessions -IncludePath:$IncludePaths -CompactPidList:(-not $IncludePaths))

    if ($groupedSessions.Count -gt 0) {
        $lines.Add("sessions on endpoint:")
        foreach ($line in $groupedSessions) {
            $lines.Add($line)
        }
    }
    else {
        $lines.Add("sessions on endpoint: none")
    }

    $groupedSuspects = @(Format-GroupedProcessLines -Items $suspects -PidPropertyName 'Id' -IncludePath:$IncludePaths -CompactPidList:(-not $IncludePaths))

    if ($groupedSuspects.Count -gt 0) {
        $lines.Add("running suspects:")
        foreach ($line in $groupedSuspects) {
            $lines.Add($line)
        }
    }
    else {
        $lines.Add("running suspects: none")
    }

    return ($lines -join "`r`n")
}

while ($true) {
    $now = Get-Date

    if ($now -ge $nextKrispSettingCheck) {
        $previousKrispLockPhysicalMicVolume = $KrispLockPhysicalMicVolume
        $currentKrispLockPhysicalMicVolume = Get-KrispLockPhysicalMicVolumeSetting
        $nextKrispSettingCheck = $now.AddSeconds($krispSettingRefreshSeconds)

        if ($currentKrispLockPhysicalMicVolume -ne $previousKrispLockPhysicalMicVolume) {
            $KrispLockPhysicalMicVolume = $currentKrispLockPhysicalMicVolume
            $lastKrispSettingChangeAt = $now
            $stateText = if ($KrispLockPhysicalMicVolume) { "enabled" } else { "disabled" }

            $settingLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss'))  Krisp setting changed: `"Lock microphone volume at optimal level`" $stateText"

            Write-Host $settingLine -ForegroundColor Cyan
            Write-LogLine $settingLine
            Write-LogLine ""
        }
        else {
            $KrispLockPhysicalMicVolume = $currentKrispLockPhysicalMicVolume
        }
    }

    $devices = Get-AudioDevice -List | Where-Object { $_.Type -eq "Recording" }

    $krisp = $devices | Where-Object { $_.Name -like "*Krisp*" }            | Select-Object -First 1
    $b1    = $devices | Where-Object { $_.Name -like "*Voicemeeter Out B1*" } | Select-Object -First 1
    $usbc  = $devices | Where-Object { $_.Name -like "*USBC Headset*" }      | Select-Object -First 1

    if ($krisp) {
        [void](Protect-Volume -Device $krisp -Label "Krisp" -RestoreToTarget $true -TargetVolume $targetVolume -DeviceKind "Microphone device")
    }

    if ($b1) {
        [void](Protect-Volume -Device $b1 -Label "B1" -RestoreToTarget $true -TargetVolume $targetVolume -DeviceKind "Microphone device")
    }

    if ($usbc) {
        # Решение о восстановлении принимается как scriptblock — внутри Protect-Volume,
        # после того как Get-SourceEvidence обновит $KrispLockPhysicalMicVolume.
        # Это исключает гонку состояний, когда Krisp меняет уровень и настройку одновременно.
        [void](Protect-Volume -Device $usbc -Label "USBC Headset" `
            -RestoreToTarget { -not $script:KrispLockPhysicalMicVolume } `
            -TargetVolume $targetVolume -DeviceKind "Microphone device")
    }

    Start-Sleep -Milliseconds $pollMs
}
