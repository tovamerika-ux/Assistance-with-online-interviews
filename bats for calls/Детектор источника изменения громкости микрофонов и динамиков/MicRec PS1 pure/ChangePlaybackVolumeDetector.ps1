. "$PSScriptRoot\AudioUtils.ps1"

$logFile = "playback_forensics_log.txt"
$usbcTarget     = 100   # таргет для USBC Headset (динамики), меняется через промпт
$vmInputTarget  = 100   # таргет для Voicemeeter Input, всегда 100
$pollMs = 500
$lastSeen = @{}
$lastSeenMuted = @{}

# Периодически проверяем настройку Windows "Communications" (вкладка "Связь" в mmsys.cpl)
# Путь в реестре: HKCU:\Software\Microsoft\Multimedia\Audio, значение UserDuckingPreference
# 0 = отключить все остальные звуки
# 1 = уменьшать громкость других звуков на 80%
# 2 = уменьшать громкость других звуков на 50%
# 3 = действие не требуется
$windowsDuckingRefreshSeconds = 30
$nextWindowsDuckingCheck = Get-Date
$windowsDuckingSetting = 3 # безопасное значение по умолчанию

function Get-WindowsCommunicationsDuckingSetting {
    try {
        $value = Get-ItemPropertyValue `
            -Path 'HKCU:\Software\Microsoft\Multimedia\Audio' `
            -Name 'UserDuckingPreference' `
            -ErrorAction SilentlyContinue

        if ($null -eq $value) { return 3 }
        return [int]$value
    }
    catch {
        return 3
    }
}

function Get-WindowsDuckingDescription {
    param([int]$Value)

    switch ($Value) {
        0 { return "mute all other sounds" }
        1 { return "reduce by 80%" }
        2 { return "reduce by 50%" }
        3 { return "do nothing" }
        default { return "unknown ($Value)" }
    }
}

$windowsDuckingSetting = Get-WindowsCommunicationsDuckingSetting

function Get-RunningSuspects {
    $suspects = Get-Process -Name `
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

        # 0=mute all, 1=reduce 80%, 2=reduce 50%, 3=do nothing
        [int]$WindowsDuckingSetting = 3
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

    # Для background-проверки: SystemSettings.exe исключён, т.к. Windows 11 держит его
    # в памяти постоянно — его наличие не говорит об открытой панели звука.
    # rundll32 и control используются только явно для mmsys.cpl / панели управления.
    $backgroundUiNames = @('rundll32', 'control')
    $manualUiPresent = @($suspectNames | Where-Object { $_ -in $backgroundUiNames }).Count -gt 0

    $voicemeeterRunning = @($suspectNames | Where-Object { $_ -like 'voicemeeter*' }).Count -gt 0
    $teamsRunning = ($suspectNames -contains 'ms-teams' -or $suspectNames -contains 'teams')
    $telemostRunning = $suspectNames -contains 'yandextelemost'
    $phoneLinkRunning = $suspectNames -contains 'phoneexperiencehost'
    $discordRunning = $suspectNames -contains 'discord'
    $zoomRunning = $suspectNames -contains 'zoom'

    # Discord attenuation: Discord снижает сессионный объём ДРУГИХ приложений во время звонка.
    # Если Discord запущен, но не имеет сессии на данном endpoint, он мог снизить его мастер-уровень
    # через IAudioEndpointVolume вместо ISimpleAudioVolume (поведение зависит от версии Discord).
    $discordAttenuationSuspected = $discordRunning -and ($sessionNames -notcontains 'discord')

    # Windows Communications ducking активен, если выставлено любое действие кроме "do nothing".
    # Ducking технически работает на уровне сессий (ISimpleAudioVolume), а не endpoint master volume,
    # однако некоторые драйверы и приложения реагируют на события ducking изменением мастер-уровня.
    $windowsDuckingActive = $WindowsDuckingSetting -ne 3
    $commAppRunning = $teamsRunning -or $discordRunning -or $zoomRunning -or $telemostRunning -or $phoneLinkRunning

    $source = 'unknown'
    $confidence = 'low'
    $primaryNames = @()

    if ($sessionNames.Count -gt 0) {
        if ($sessionNames -contains 'ms-teams' -or $sessionNames -contains 'teams') {
            $source = 'Teams audio session'
            $confidence = 'high'
            $primaryNames = @('ms-teams', 'teams')
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
        elseif ($sessionNames -contains 'discord') {
            $source = 'Discord audio session'
            $confidence = 'high'
            $primaryNames = @('discord')
        }
        elseif ($sessionNames -contains 'zoom') {
            $source = 'Zoom audio session'
            $confidence = 'high'
            $primaryNames = @('zoom')
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
    elseif ($manualUiForeground) {
        $source = 'manual change via Windows sound settings'
        $confidence = 'medium'
        $primaryNames = $uiNames
    }
    elseif ($manualUiPresent) {
        # rundll32/control запущены в фоне (не foreground).
        # Возможны два сценария: пользователь изменил уровень в mmsys.cpl и быстро
        # переключился на другое приложение до того, как скрипт обнаружил изменение,
        # либо уровень был изменён физическими кнопками гарнитуры пока mmsys.cpl был открыт.
        $source = 'manual change via Windows sound settings or physical device button (heuristic)'
        $confidence = 'low'
        $primaryNames = $backgroundUiNames
    }
    elseif ($windowsDuckingActive -and $commAppRunning) {
        # Windows Communications ducking включён + коммуникационное приложение запущено.
        # Ducking может косвенно спровоцировать изменение мастер-уровня через драйвер или само приложение.
        $duckingDesc = Get-WindowsDuckingDescription -Value $WindowsDuckingSetting
        $source = "Windows Communications ducking ($duckingDesc) + comm app running (heuristic)"
        $confidence = 'medium'
        $primaryNames = @()
        if ($teamsRunning) { $primaryNames += @('ms-teams', 'teams') }
        if ($discordRunning) { $primaryNames += 'discord' }
        if ($zoomRunning) { $primaryNames += 'zoom' }
        if ($telemostRunning) { $primaryNames += 'yandextelemost' }
        if ($phoneLinkRunning) { $primaryNames += 'phoneexperiencehost' }
    }
    elseif ($Label -eq 'Voicemeeter Input' -and $voicemeeterRunning) {
        $source = 'Voicemeeter (heuristic)'
        $confidence = 'low'
        $primaryNames = @($suspectNames | Where-Object { $_ -like 'voicemeeter*' })
    }
    elseif ($discordAttenuationSuspected) {
        # Discord запущен, но не имеет сессии на данном endpoint.
        # Discord Attenuation (Settings → Voice & Video → Attenuation) может менять уровни устройств.
        $source = 'Discord attenuation (heuristic)'
        $confidence = 'low'
        $primaryNames = @('discord')
    }
    elseif ($teamsRunning) {
        # Teams документально меняет endpoint-уровень гарнитуры во время звонков
        # (связано с опцией "Sync device buttons").
        $source = 'Teams (heuristic)'
        $confidence = 'low'
        $primaryNames = @('ms-teams', 'teams')
    }
    elseif ($zoomRunning) {
        $source = 'Zoom (heuristic)'
        $confidence = 'low'
        $primaryNames = @('zoom')
    }
    elseif ($telemostRunning) {
        $source = 'Yandex Telemost (heuristic)'
        $confidence = 'low'
        $primaryNames = @('yandextelemost')
    }
    elseif ($Label -eq 'USBC Headset' -and $sessionNames.Count -eq 0) {
        # Нет сессий на endpoint, нет UI настроек звука, нет активных comm-app.
        # Наиболее вероятная причина — физические кнопки гарнитуры (HID → audiodg)
        # или ручное перемещение ползунка в mmsys.cpl без открытого окна UI.
        # Phone Link намеренно исключён из heuristics: он почти всегда запущен,
        # что делает его непригодным как сигнал — остаётся в running suspects.
        $source = 'physical device button or manual volume slider (heuristic)'
        $confidence = 'low'
        $primaryNames = @()
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

    $lines = New-Object System.Collections.Generic.List[string]
    $sessions = @(Get-DeviceSessions -Device $Device)
    $suspects = @(Get-RunningSuspects)
    $foregroundProcessName = Get-ForegroundProcessName

    $sourceInfo = Get-LikelySourceInfo `
        -Sessions @($sessions) `
        -Suspects @($suspects) `
        -Label $Label `
        -ForegroundProcessName $foregroundProcessName `
        -WindowsDuckingSetting $windowsDuckingSetting

    $duckingDesc = Get-WindowsDuckingDescription -Value $windowsDuckingSetting
    $lines.Add("Windows Communications ducking: $duckingDesc")
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

function Invoke-TargetAdjustPrompt {
    param([int]$TimeoutSeconds = 8)

    Write-Host ""
    Write-Host "  Current target: $($script:usbcTarget)%. Press Y to change target, or wait..." -ForegroundColor Cyan

    # Сбросить буфер клавиатуры (могло скопиться от предыдущих нажатий)
    while ([Console]::KeyAvailable) {
        [void][Console]::ReadKey($true)
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastDisplayed = $TimeoutSeconds + 1
    $pressed = $false

    Write-Host "  " -NoNewline -ForegroundColor DarkGray

    while ((Get-Date) -lt $deadline) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Y) {
                $pressed = $true
            }
            break
        }
        $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($remaining -ne $lastDisplayed) {
            Write-Host "$remaining...  " -NoNewline -ForegroundColor DarkGray
            $lastDisplayed = $remaining
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ""

    if ($pressed) {
        Write-Host "  Enter new target (1-100): " -NoNewline -ForegroundColor Cyan
        $newTargetStr = Read-Host
        if ($newTargetStr -match '^\d+$') {
            $newTarget = [int]$newTargetStr
            if ($newTarget -ge 1 -and $newTarget -le 100) {
                $oldTarget = $script:usbcTarget
                $script:usbcTarget = $newTarget
                $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logLine = "$time  Target volume changed by user: $oldTarget -> $newTarget"
                Write-Host "  Target updated: $oldTarget% -> $newTarget%" -ForegroundColor Green
                Write-LogLine $logLine
                Write-LogLine ""
            }
            else {
                Write-Host "  Value out of range (1-100). Target unchanged: $($script:usbcTarget)%" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  Invalid input. Target unchanged: $($script:usbcTarget)%" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  Target unchanged: $($script:usbcTarget)%" -ForegroundColor DarkGray
    }
    Write-Host ""
}

while ($true) {
    $now = Get-Date

    if ($now -ge $nextWindowsDuckingCheck) {
        $previousWindowsDuckingSetting = $windowsDuckingSetting
        $currentWindowsDuckingSetting = Get-WindowsCommunicationsDuckingSetting
        $nextWindowsDuckingCheck = $now.AddSeconds($windowsDuckingRefreshSeconds)

        if ($currentWindowsDuckingSetting -ne $previousWindowsDuckingSetting) {
            $windowsDuckingSetting = $currentWindowsDuckingSetting
            $duckingDesc = Get-WindowsDuckingDescription -Value $windowsDuckingSetting
            $duckingLine = "$($now.ToString('yyyy-MM-dd HH:mm:ss'))  Windows Communications ducking setting changed: `"$duckingDesc`""

            Write-Host $duckingLine -ForegroundColor Cyan
            Write-LogLine $duckingLine
            Write-LogLine ""
        }
        else {
            $windowsDuckingSetting = $currentWindowsDuckingSetting
        }
    }

    $devices = Get-AudioDevice -List | Where-Object { $_.Type -eq "Playback" }

    $usbc    = $devices | Where-Object { $_.Name -like "*USBC Headset*" }      | Select-Object -First 1
    $vmInput = $devices | Where-Object { $_.Name -like "*Voicemeeter Input*" } | Select-Object -First 1

    if ($usbc) {
        $usbcResult = Protect-Volume -Device $usbc -Label "USBC Headset" -RestoreToTarget $true -TargetVolume $usbcTarget -DeviceKind "Playback device"
        if ($usbcResult -and $usbcResult.ShouldOffer) {
            Invoke-TargetAdjustPrompt
        }
    }

    if ($vmInput) {
        [void](Protect-Volume -Device $vmInput -Label "Voicemeeter Input" -RestoreToTarget $true -TargetVolume $vmInputTarget -DeviceKind "Playback device")
    }

    Start-Sleep -Milliseconds $pollMs
}
