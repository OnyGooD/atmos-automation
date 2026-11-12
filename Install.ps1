#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = "C:\Programs\AtmosAutomation"
$taskName = "Atmos Automation"

$requiredFiles = @(
    "AtmosWatcher.ps1",
    "Config.ps1",
    "LaunchWatcher.vbs",
    "config.txt"
)

foreach ($file in $requiredFiles) {
    $sourcePath = Join-Path $sourceDir $file

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required file not found: $sourcePath"
    }
}

. (Join-Path $sourceDir "Config.ps1")

$config = Get-AtmosConfig -Path (Join-Path $sourceDir "config.txt")

New-Item -ItemType Directory -Path $installDir -Force | Out-Null

foreach ($file in $requiredFiles) {
    Copy-Item `
        -LiteralPath (Join-Path $sourceDir $file) `
        -Destination (Join-Path $installDir $file) `
        -Force
}

$launcherPath = Join-Path $installDir "LaunchWatcher.vbs"

$action = New-ScheduledTaskAction `
    -Execute "C:\Windows\System32\wscript.exe" `
    -Argument "`"$launcherPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings

Register-ScheduledTask `
    -TaskName $taskName `
    -InputObject $task `
    -Force |
    Out-Null

Write-Host ""
Write-Host "Atmos Automation was installed successfully." -ForegroundColor Green
Write-Host "Installation directory: $installDir"
Write-Host "Scheduled Task: $taskName"
Write-Host ""
Write-Host "The watcher will start automatically at your next login."
Write-Host "You can also start it manually using LaunchWatcher.vbs."