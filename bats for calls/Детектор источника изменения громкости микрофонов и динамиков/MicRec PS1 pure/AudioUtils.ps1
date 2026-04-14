Import-Module AudioDeviceCmdlets

$alarmWav = "$env:WINDIR\Media\Windows Notify System Generic.wav"

function Alarm {
    try {
        $player = New-Object System.Media.SoundPlayer $alarmWav
        $player.PlaySync()
    }
    catch {
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
        [System.Windows.Forms.SystemInformation]::Beep | Out-Null
    }
}

function Write-LogLine {
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)]
        [string]$Text
    )

    # $logFile должен быть определён в вызывающем скрипте
    Add-Content -Path $logFile -Value $Text -Encoding UTF8
}

function Get-EndpointVolumePct {
    param(
        [Parameter(Mandatory)]
        $AudioDevice
    )

    return [int][Math]::Round(
        $AudioDevice.Device.AudioEndpointVolume.MasterVolumeLevelScalar * 100
    )
}

function Set-EndpointVolumePct {
    param(
        [Parameter(Mandatory)]
        $AudioDevice,

        [Parameter(Mandatory)]
        [int]$Percent
    )

    $scalar = [Math]::Max(0.0, [Math]::Min(1.0, $Percent / 100.0))
    $AudioDevice.Device.AudioEndpointVolume.MasterVolumeLevelScalar = [float]$scalar
}

function Get-EndpointMuted {
    param(
        [Parameter(Mandatory)]
        $AudioDevice
    )

    return [bool]$AudioDevice.Device.AudioEndpointVolume.Mute
}

function Set-EndpointMuted {
    param(
        [Parameter(Mandatory)]
        $AudioDevice,

        [Parameter(Mandatory)]
        [bool]$Muted
    )

    $AudioDevice.Device.AudioEndpointVolume.Mute = $Muted
}

function Get-DeviceSessions {
    param(
        [Parameter(Mandatory)]
        $Device
    )

    $items = @()

    try {
        $sessions = $Device.Device.AudioSessionManager.Sessions
    }
    catch {
        return @()
    }

    for ($i = 0; $i -lt $sessions.Count; $i++) {
        try {
            $session = $sessions[$i]
            $pid = [int]$session.ProcessID
            $state = [string]$session.State
            $displayName = $session.DisplayName
            $sessionId = $session.SessionIdentifier

            $processName = $null
            $processPath = $null

            if ($pid -gt 0) {
                $p = Get-Process -Id $pid -ErrorAction SilentlyContinue

                if ($p) {
                    $processName = $p.ProcessName
                    try {
                        $processPath = $p.Path
                    }
                    catch {
                        $processPath = $null
                    }
                }
                else {
                    $processName = "pid:$pid"
                }
            }
            else {
                $processName = "system"
            }

            $items += [pscustomobject]@{
                Pid               = $pid
                ProcessName       = $processName
                State             = $state
                DisplayName       = $displayName
                SessionIdentifier = $sessionId
                Path              = $processPath
            }
        }
        catch {
        }
    }

    return $items | Sort-Object ProcessName, Pid -Unique
}

if (-not ([System.Management.Automation.PSTypeName]'ForegroundWindowHelper').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class ForegroundWindowHelper
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@
}

function Get-ForegroundProcessName {
    try {
        $hwnd = [ForegroundWindowHelper]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) {
            return $null
        }

        [uint32]$pid = 0
        [void][ForegroundWindowHelper]::GetWindowThreadProcessId($hwnd, [ref]$pid)

        if ($pid -le 0) {
            return $null
        }

        $p = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($p) {
            return $p.ProcessName
        }

        return $null
    }
    catch {
        return $null
    }
}

function Format-PidText {
    param(
        [AllowEmptyCollection()]
        [array]$PidValues = @(),

        [bool]$CompactPidList = $false
    )

    if ($PidValues.Count -eq 0) {
        return '-'
    }

    $sortedPids = @(
        $PidValues |
        ForEach-Object { [int]$_ } |
        Sort-Object -Unique
    )

    if ($CompactPidList -and $sortedPids.Count -gt 3) {
        return "$($sortedPids[0]),... $($sortedPids[-1])"
    }

    return ($sortedPids -join ', ')
}

function Format-GroupedProcessLines {
    param(
        [AllowEmptyCollection()]
        [array]$Items = @(),

        [Parameter(Mandatory)]
        [string]$PidPropertyName,

        [switch]$IncludePath,

        [bool]$CompactPidList = $false
    )

    $lines = New-Object System.Collections.Generic.List[string]

    $validItems = @(
        $Items | Where-Object { $_.ProcessName }
    )

    if ($validItems.Count -eq 0) {
        return @()
    }

    $groups = $validItems | Group-Object ProcessName | Sort-Object Name

    foreach ($group in $groups) {
        $first = $group.Group | Select-Object -First 1

        $pidValues = @(
            $group.Group |
            ForEach-Object { $_.$PidPropertyName } |
            Where-Object { $null -ne $_ -and "$_".Trim() -ne "" } |
            ForEach-Object { [int]$_ } |
            Sort-Object -Unique
        )

        $pidText = Format-PidText -PidValues $pidValues -CompactPidList $CompactPidList

        $lines.Add("  $($first.ProcessName).exe pid:$pidText")

        if ($IncludePath) {
            $pathValues = @(
                $group.Group |
                ForEach-Object { $_.Path } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
            )

            if ($pathValues.Count -gt 0) {
                foreach ($pathValue in $pathValues) {
                    $lines.Add("  path: $pathValue")
                }
            }
            else {
                $lines.Add("  path: -")
            }
        }
    }

    return $lines
}

function Format-GroupedSessionLines {
    param(
        [AllowEmptyCollection()]
        [array]$Sessions = @(),

        [bool]$IncludePath = $true,

        [bool]$CompactPidList = $false
    )

    $lines = New-Object System.Collections.Generic.List[string]

    if ($Sessions.Count -eq 0) {
        return @()
    }

    $groups = $Sessions | Where-Object { $_.ProcessName } | Group-Object ProcessName | Sort-Object Name

    foreach ($group in $groups) {
        $first = $group.Group | Select-Object -First 1

        $pidValues = @(
            $group.Group |
            ForEach-Object { $_.Pid } |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [int]$_ } |
            Sort-Object -Unique
        )

        $stateValues = @(
            $group.Group |
            ForEach-Object { $_.State } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )

        $displayValues = @(
            $group.Group |
            ForEach-Object { $_.DisplayName } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )

        $pathValues = @(
            $group.Group |
            ForEach-Object { $_.Path } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )

        $pidText = Format-PidText -PidValues $pidValues -CompactPidList $CompactPidList
        $stateText = if ($stateValues.Count -gt 0) { $stateValues -join ', ' } else { '-' }
        $displayText = if ($displayValues.Count -gt 0) { $displayValues -join '; ' } else { '-' }

        $lines.Add("  $($first.ProcessName).exe pid:$pidText state:$stateText display:`"$displayText`"")

        if ($IncludePath) {
            if ($pathValues.Count -gt 0) {
                foreach ($pathValue in $pathValues) {
                    $lines.Add("  path: $pathValue")
                }
            }
            else {
                $lines.Add("  path: -")
            }
        }
    }

    return $lines
}

function Protect-Volume {
    param(
        [Parameter(Mandatory)]
        $Device,

        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [object]$RestoreToTarget,

        [Parameter(Mandatory)]
        [int]$TargetVolume,

        # Префикс типа устройства в лог-сообщениях.
        # Вызывающий скрипт передаёт "Microphone device" или "Playback device".
        [string]$DeviceKind = "Device"
    )

    # $RestoreToTarget может быть bool или scriptblock.
    # Scriptblock вычисляется в точке принятия решения (после Get-SourceEvidence),
    # что позволяет вызывающему скрипту принять решение на основе свежих данных.
    function Invoke-RestoreDecision {
        if ($RestoreToTarget -is [scriptblock]) { [bool](& $RestoreToTarget) }
        else                                    { [bool]$RestoreToTarget }
    }

    $key = $Device.ID
    $deviceName = $Device.Name
    $currentVol = Get-EndpointVolumePct -AudioDevice $Device

    if (-not $lastSeen.ContainsKey($key)) {
        $currentMuted = Get-EndpointMuted -AudioDevice $Device
        $lastSeen[$key] = $currentVol
        $lastSeenMuted[$key] = $currentMuted

        $needVolumeRestore = $currentVol -ne $TargetVolume
        $needUnmute = $currentMuted

        if ($needVolumeRestore -or $needUnmute) {
            # Get-SourceEvidence вызывается до Invoke-RestoreDecision, чтобы
            # обновить $KrispLockPhysicalMicVolume перед принятием решения о восстановлении.
            $evidenceForConsole = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $false
            $evidenceForLog     = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $true

            if ((Invoke-RestoreDecision)) {
                $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

                $mutedSuffix = if ($currentMuted) { ", muted" } else { "" }
                $startupLine = "$time  ${DeviceKind}: $deviceName. State at script startup: volume=$currentVol$mutedSuffix"
                Write-Host $startupLine -ForegroundColor Yellow
                Write-LogLine $startupLine

                Write-Host $evidenceForConsole -ForegroundColor DarkGray
                Write-LogLine $evidenceForLog

                Alarm

                if ($needVolumeRestore) {
                    Set-EndpointVolumePct -AudioDevice $Device -Percent $TargetVolume
                }
                if ($needUnmute) {
                    Set-EndpointMuted -AudioDevice $Device -Muted $false
                }
                Start-Sleep -Milliseconds 50

                $restoredVol = Get-EndpointVolumePct -AudioDevice $Device
                $restoredMuted = Get-EndpointMuted -AudioDevice $Device

                $actions = @()
                if ($needVolumeRestore) {
                    if ($restoredVol -ne $currentVol) {
                        $actions += "volume: $currentVol -> $restoredVol"
                    }
                    else {
                        $actions += "volume restore failed: remained $currentVol"
                    }
                }
                if ($needUnmute) {
                    if (-not $restoredMuted) {
                        $actions += "unmuted"
                    }
                    else {
                        $actions += "unmute failed"
                    }
                }
                $actionText = $actions -join ', '
                $restoreLine = "$time  ${DeviceKind}: $deviceName. Script has corrected at startup: $actionText"

                Write-Host $restoreLine -ForegroundColor Red
                Write-LogLine $restoreLine
                Write-LogLine ""

                $lastSeen[$key] = $restoredVol
                $lastSeenMuted[$key] = $restoredMuted
            }
        }

        return [pscustomobject]@{ ChangeDetected=$false; Restored=$false }
    }

    $previousVol = [int]$lastSeen[$key]

    if ($currentVol -ne $previousVol) {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $evidenceForConsole = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $false
        $evidenceForLog     = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $true

        $changeLine = "$time  ${DeviceKind}: $deviceName. Sound volume level has been changed: $previousVol -> $currentVol"
        Write-Host $changeLine -ForegroundColor Yellow
        Write-Host $evidenceForConsole -ForegroundColor DarkGray

        Write-LogLine $changeLine
        Write-LogLine $evidenceForLog

        Alarm

        $wasRestored = $false

        if ((Invoke-RestoreDecision) -and $currentVol -ne $TargetVolume) {
            Set-EndpointVolumePct -AudioDevice $Device -Percent $TargetVolume
            Start-Sleep -Milliseconds 50

            $restoredVol = Get-EndpointVolumePct -AudioDevice $Device

            if ($restoredVol -ne $currentVol) {
                $restoreLine = "$time  ${DeviceKind}: $deviceName. Script has restored the level: $currentVol -> $restoredVol"
            }
            else {
                $restoreLine = "$time  ${DeviceKind}: $deviceName. Script attempted to restore the level, but it remained unchanged: $currentVol"
            }

            Write-Host $restoreLine -ForegroundColor Red
            Write-LogLine $restoreLine
            $lastSeen[$key] = $restoredVol
            $wasRestored = $true
        }
        else {
            $monitorLine = "$time  ${DeviceKind}: $deviceName. Script action: monitor-only. Level remains: $currentVol"

            Write-Host $monitorLine -ForegroundColor Cyan
            Write-LogLine $monitorLine
            $lastSeen[$key] = $currentVol
        }

        Write-LogLine ""
        return [pscustomobject]@{ ChangeDetected=$true; Restored=$wasRestored; ShouldOffer=$wasRestored }
    }

    if ((Invoke-RestoreDecision) -and $currentVol -ne $TargetVolume) {
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $evidenceForConsole = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $false
        $evidenceForLog     = Get-SourceEvidence -Device $Device -Label $Label -IncludePaths $true

        $enforceLine = "$time  ${DeviceKind}: $deviceName. Script has enforced the level: $currentVol -> $TargetVolume"
        Write-Host $enforceLine -ForegroundColor Red
        Write-Host $evidenceForConsole -ForegroundColor DarkGray
        Write-LogLine $enforceLine
        Write-LogLine $evidenceForLog

        Set-EndpointVolumePct -AudioDevice $Device -Percent $TargetVolume
        Start-Sleep -Milliseconds 50

        $lastSeen[$key] = Get-EndpointVolumePct -AudioDevice $Device
        Write-LogLine ""
        return [pscustomobject]@{ ChangeDetected=$false; Restored=$false; ShouldOffer=$true }
    }

    $lastSeen[$key] = $currentVol
    return [pscustomobject]@{ ChangeDetected=$false; Restored=$false; ShouldOffer=$false }
}
