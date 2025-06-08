# Script to install the Fort Knocks login task
$ErrorActionPreference = "Stop"

# Get the current script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScript = Join-Path $scriptDir "SSLVPNLoginTask.ps1"
$targetScript = Join-Path $env:USERPROFILE "SSLVPNLoginTask.ps1"
$userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Copy the script to the user's profile
Copy-Item -Path $sourceScript -Destination $targetScript -Force

# Create the scheduled task
$taskName = "Fort Knocks Login Task - $env:USERNAME"
$taskDescription = "Automatically authenticates to protected service endpoint."

# Create the task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetScript`""

# Create the task trigger (on logon)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userName

$principal = New-ScheduledTaskPrincipal -UserId $userName -LogonType Interactive

# Create the task settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Register the task
Register-ScheduledTask -TaskName $taskName `
    -Description $taskDescription `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Force

Write-Host "The Fort Knocks Login Task has been installed successfully!"
Write-Host "The script has been copied to: $targetScript"
Write-Host "A scheduled task has been created to run on user login." 
