# Mini PC BRIX 8550 and Haier 55" HD TV, movie-watching mode from the PC (audio output to the TV).
# The BRIX 8550 mini PC does not have an Stereo Mixer device, unlike the Lenovo YOGA laptop.

$ErrorActionPreference = "Stop"
Set-Location "C:\SoundVolumeView"

$MIC_NAME   = "{0.0.1.00000000}.{929602a7-26cc-4958-b975-ee3495fe0872}"

$TV_MATCH = "Haier 55 TV"

$csvPath = Join-Path $env:TEMP "svv_devices.csv"
& .\SoundVolumeView.exe /scomma $csvPath | Out-Null
$rows = Import-Csv -Path $csvPath

# Find TV Render device by name match
$tvRow = $rows |
  Where-Object {
    (($_.Direction -eq "Render") -or ($_.Type -eq "Render") -or ($_.'Data Flow' -eq "Render")) -and
    (($_.'Device Name' -like "*$TV_MATCH*") -or ($_.Name -like "*$TV_MATCH*"))
  } |
  Select-Object -First 1

if (-not $tvRow) { throw "TV Render device not found: $TV_MATCH" }

$SPK_NAME = $tvRow.'Command-Line Friendly ID'
$SPK_ITEM = $tvRow.'Item ID'
if ([string]::IsNullOrWhiteSpace($SPK_NAME)) { throw "No Command-Line Friendly ID in /scomma output." }

# Enable TV (try Friendly ID, then Item ID)
& .\SoundVolumeView.exe /Enable "$SPK_NAME" | Out-Null
Start-Sleep -Milliseconds 200
if ($SPK_ITEM) { & .\SoundVolumeView.exe /Enable "$SPK_ITEM" | Out-Null }

Start-Sleep -Seconds 1

# Set defaults (TV output + your stable mic input)
& .\SoundVolumeView.exe /SetDefault "$SPK_NAME" all | Out-Null
if ($SPK_ITEM) { & .\SoundVolumeView.exe /SetDefault "$SPK_ITEM" all | Out-Null }
& .\SoundVolumeView.exe /SetDefault "$MIC_NAME" all | Out-Null

# Enable Windows sounds
# reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".Default" /f | Out-Null

# Disable Windows sounds
reg add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".None" /f | Out-Null

# Kill Voicemeeter variants (silently if not running)
$vm = "voicemeeter_x64","voicemeeterpro_x64","voicemeeter8x64"
Get-Process -Name $vm -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Kill Krisp
Get-Process -Name "Krisp" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Normal audio profile applied."
