#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$taskName = "Atmos Automation"
$installDir = "C:\Programs\AtmosAutomation"

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Stop-ScheduledTask `
        -TaskName $taskName `
        -ErrorAction SilentlyContinue

    Unregister-ScheduledTask `
        -TaskName $taskName `
        -Confirm:$false

    Write-Host "Scheduled Task removed."
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item `
        -LiteralPath $installDir `
        -Recurse `
        -Force

    Write-Host "Program files removed."
}

Write-Host ""
Write-Host "Atmos Automation has been uninstalled." -ForegroundColor Green
Write-Host "Saved audio format and log files were kept in:"
Write-Host (Join-Path $env:LOCALAPPDATA "AtmosAutomation")