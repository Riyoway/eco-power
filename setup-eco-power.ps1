#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# ---- Tune these for your own schedule / hardware ----
$WeekdayEcoStart = '02:30'
$WeekdayEcoEnd   = '08:00'
$WeekendEcoStart = '03:30'
$WeekendEcoEnd   = '10:30'
$CpuMaxPercent   = 30   # max processor state while in Eco
$DisplayOffSec   = 60   # turn off display after N seconds idle
$DiskOffSec      = 60   # spin down disk after N seconds idle
# -------------------------------------------------------

function Get-Guid($text) {
    [regex]::Match($text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
}

# Capture the plan currently in daily use (switched back to at the end of Eco hours)
$normalGuid = Get-Guid (powercfg /getactivescheme)

# Duplicate "Power saver" into a dedicated Eco scheme we can tune freely
$dupOut   = powercfg /duplicatescheme a1841308-3541-4fab-bc81-f71556f20b4a
$ecoGuid  = Get-Guid ($dupOut | Select-Object -First 1)
powercfg /changename $ecoGuid "Eco (Unused Hours)" "Max power saving, stays awake for SSH/RustDesk/Parsec/RDP"

function Set-Both($sub, $setting, $value) {
    powercfg /setacvalueindex $ecoGuid $sub $setting $value
    powercfg /setdcvalueindex $ecoGuid $sub $setting $value
}

# Never sleep/hibernate -- staying reachable was the explicit priority
Set-Both SUB_SLEEP STANDBYIDLE 0
Set-Both SUB_SLEEP HIBERNATEIDLE 0

# Aggressive but harmless: screen/disk off fast
Set-Both SUB_VIDEO VIDEOIDLE $DisplayOffSec
Set-Both SUB_DISK DISKIDLE $DiskOffSec

# Hard CPU cap + no boost clocks
Set-Both SUB_PROCESSOR PROCTHROTTLEMAX $CpuMaxPercent
Set-Both SUB_PROCESSOR PROCTHROTTLEMIN 0
Set-Both SUB_PROCESSOR PERFBOOSTMODE 0

powercfg /setactive $normalGuid  # leave current plan active; Eco only engages on schedule

# Keep every network adapter powered -- otherwise Windows can silently drop
# the link and SSH/RustDesk/Parsec/RDP access breaks during the eco window.
# Note: Set-NetAdapterPowerManagement has no writable "AllowComputerToTurnOffDevice"
# parameter on most drivers -- disable it per-adapter in Device Manager > Power
# Management tab instead (Windows won't reliably apply it via script here).
Get-NetAdapter | ForEach-Object {
    try { Set-NetAdapterPowerManagement -Name $_.Name -ErrorAction Stop | Out-Null }
    catch { }
}

# Clock-based switch: unused hours -> Eco, rest of day -> back to normal plan
$actionEco    = New-ScheduledTaskAction -Execute 'powercfg.exe' -Argument "/setactive $ecoGuid"
$actionNormal = New-ScheduledTaskAction -Execute 'powercfg.exe' -Argument "/setactive $normalGuid"
$settings     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName "EcoPower-Start-Weekday" -Force -Settings $settings -Action $actionEco `
  -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At $WeekdayEcoStart) | Out-Null
Register-ScheduledTask -TaskName "EcoPower-End-Weekday" -Force -Settings $settings -Action $actionNormal `
  -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At $WeekdayEcoEnd) | Out-Null
Register-ScheduledTask -TaskName "EcoPower-Start-Weekend" -Force -Settings $settings -Action $actionEco `
  -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday,Sunday -At $WeekendEcoStart) | Out-Null
Register-ScheduledTask -TaskName "EcoPower-End-Weekend" -Force -Settings $settings -Action $actionNormal `
  -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday,Sunday -At $WeekendEcoEnd) | Out-Null

# One-click manual override (e.g. woke up early on a day off)
"@echo off`r`npowercfg /setactive $ecoGuid`r`necho Eco mode ON" | Set-Content "$env:USERPROFILE\Desktop\switch-to-eco.bat" -Encoding ASCII
"@echo off`r`npowercfg /setactive $normalGuid`r`necho Back to normal" | Set-Content "$env:USERPROFILE\Desktop\switch-to-normal.bat" -Encoding ASCII

Write-Host "`nDone."
Write-Host "Eco scheme guid:    $ecoGuid"
Write-Host "Normal scheme guid: $normalGuid"
Write-Host "Tasks: EcoPower-Start/End-Weekday, EcoPower-Start/End-Weekend (schtasks /query /tn EcoPower-* to inspect)"
