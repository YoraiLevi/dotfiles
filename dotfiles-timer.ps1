#!/usr/bin/env pwsh
# dotfiles-timer.ps1: Manage a Windows Task Scheduler task that auto-commits dotfiles changes.

param(
    [Parameter(Position=0, Mandatory=$false)]
    [ValidateSet('install','reinstall','uninstall','status','logs')]
    [string]$Action
)

$TaskName   = "dotfiles-git-commit"
$GitDir     = "$HOME\.dotfiles"
$WorkTree   = "$HOME"
$ScriptPath = "$GitDir\.auto-commit.ps1"

if (-not $Action) {
    Write-Host @"
Usage: pwsh dotfiles-timer.ps1 [install|reinstall|uninstall|status|logs]

  install    Register and enable the auto-commit scheduled task.
  reinstall  Remove then reinstall.
  uninstall  Remove the task and commit script.
  status     Show task status and last run info.
  logs       Show recent Task Scheduler events for this task.

Commits tracked dotfiles changes every minute using:
  git --git-dir=$GitDir --work-tree=$WorkTree
"@
    exit 1
}

function Install-Timer {
    # Write the commit script with paths expanded now, runtime vars escaped
    @"
`$gitArgs = @('--git-dir', '$GitDir', '--work-tree', '$WorkTree')
& git @gitArgs add -u
& git @gitArgs diff --cached --quiet
if (`$LASTEXITCODE -ne 0) {
    `$ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
    & git @gitArgs commit -m "chore: auto-commit at `$ts"
}
& git @gitArgs push
"@ | Set-Content -Path $ScriptPath -Encoding UTF8

    $action   = New-ScheduledTaskAction -Execute 'pwsh' `
                    -Argument "-NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""
    $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                    -RepetitionInterval ([TimeSpan]::FromMinutes(1))
    $settings = New-ScheduledTaskSettingsSet `
                    -ExecutionTimeLimit ([TimeSpan]::FromMinutes(5)) `
                    -StartWhenAvailable $true

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger $trigger -Settings $settings `
        -RunLevel Limited -Force | Out-Null

    Write-Host "Installed task '$TaskName' (commits every minute, git-dir: $GitDir)"
}

function Uninstall-Timer {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removed task '$TaskName'."
}

function Get-TimerStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { Write-Host "Task '$TaskName' not found."; return }
    $task | Format-List TaskName, State, Description
    Get-ScheduledTaskInfo -TaskName $TaskName |
        Format-List LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
}

function Get-TimerLogs {
    Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match [regex]::Escape($TaskName) } |
        Select-Object -First 50 |
        Format-List TimeCreated, Id, Message
}

switch ($Action) {
    'install'   { Install-Timer }
    'reinstall' { Uninstall-Timer; Install-Timer }
    'uninstall' { Uninstall-Timer }
    'status'    { Get-TimerStatus }
    'logs'      { Get-TimerLogs }
}
