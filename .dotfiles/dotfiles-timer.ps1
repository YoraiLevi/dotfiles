#!/usr/bin/env pwsh
# dotfiles-timer.ps1: Manage auto-commit for tracked dotfiles changes.
# Auto-detects privilege at install time:
#   Admin     -> Windows Task Scheduler (survives logoff)
#   Non-admin -> Startup-folder VBS launcher + hidden pwsh while-loop

param(
    [Parameter(Position=0, Mandatory=$false)]
    [ValidateSet('install','reinstall','uninstall','status','logs')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

$TaskName     = "dotfiles-git-commit"
$GitDir       = "$HOME\.dotfiles"
$WorkTree     = "$HOME"
$ScriptPath   = "$GitDir\.auto-commit.ps1"
$LoopPath     = "$GitDir\.auto-commit-loop.ps1"
$LauncherPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\DotfilesAutoCommit.vbs"
$LogPath      = "$env:TEMP\dotfiles-auto-commit.log"

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Action) {
    $mode = if (Test-IsAdmin) { 'admin (Task Scheduler)' } else { 'user (startup folder + VBS)' }
    Write-Host @"
Usage: pwsh dotfiles-timer.ps1 [install|reinstall|uninstall|status|logs]

Detected privilege: $mode

  install    Install the auto-commit timer.
  reinstall  Remove then reinstall.
  uninstall  Remove the timer (and stop running loop if in user mode).
  status     Show installation status (checks both modes).
  logs       Show recent activity.
"@
    exit 1
}

function Write-CommitScript {
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
}

function Write-LoopScript {
    @"
# .auto-commit-loop.ps1 — invoked by the VBS launcher at logon
`$logPath = '$LogPath'
while (`$true) {
    `$ts = Get-Date -Format 'o'
    try {
        # Capture all stdout+stderr from the commit script (git output, etc.)
        `$output = & '$ScriptPath' 2>&1 | Out-String
        if (`$output.Trim()) {
            Add-Content -Path `$logPath -Value "[`$ts] `$(`$output.TrimEnd())"
        }
    } catch {
        Add-Content -Path `$logPath -Value "[`$ts] ERROR: `$(`$_.Exception.Message)"
    }
    Start-Sleep -Seconds 60
}
"@ | Set-Content -Path $LoopPath -Encoding UTF8
}

function Write-VbsLauncher {
    $pwshExe = (Get-Command pwsh).Source
    # VBS literal-quote rule: doubled "" inside a "..." string yields one " in the output.
    @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$pwshExe"" -NonInteractive -ExecutionPolicy Bypass -File ""$LoopPath""", 0, False
"@ | Set-Content -Path $LauncherPath -Encoding ASCII
}

function Stop-LoopProcesses {
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$LoopPath*" } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
        }
}

function Install-Admin {
    Write-CommitScript

    $action        = New-ScheduledTaskAction -Execute 'pwsh' `
                         -Argument "-NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""
    $triggerLogon  = New-ScheduledTaskTrigger -AtLogOn
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) `
                         -RepetitionInterval ([TimeSpan]::FromMinutes(1)) `
                         -RepetitionDuration ([TimeSpan]::FromDays(365 * 10))
    $settings      = New-ScheduledTaskSettingsSet `
                         -ExecutionTimeLimit ([TimeSpan]::FromMinutes(5)) `
                         -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action -Trigger @($triggerLogon, $triggerRepeat) -Settings $settings `
        -RunLevel Limited -Force | Out-Null

    Write-Host "[admin] Installed Task Scheduler task '$TaskName' (commits every minute)."
}

function Install-User {
    Write-CommitScript
    Write-LoopScript
    Write-VbsLauncher

    # Stop any old loops, then start one immediately so the user doesn't have to log out/in
    Stop-LoopProcesses
    Start-Process wscript.exe -ArgumentList "`"$LauncherPath`"" -WindowStyle Hidden

    Write-Host "[user] Installed startup launcher: $LauncherPath"
    Write-Host "       Loop script: $LoopPath"
    Write-Host "       Log file:    $LogPath"
    Write-Host "       Loop started; will resume automatically on each logon."
}

function Uninstall-Admin {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
    Write-Host "[admin] Removed task '$TaskName'."
}

function Uninstall-User {
    Stop-LoopProcesses
    Remove-Item $LauncherPath -Force -ErrorAction SilentlyContinue
    Remove-Item $LoopPath -Force -ErrorAction SilentlyContinue
    Remove-Item $ScriptPath -Force -ErrorAction SilentlyContinue
    Write-Host "[user] Removed startup launcher and stopped running loop."
}

function Get-Status {
    $found = $false

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $found = $true
        Write-Host "[admin mode] Task Scheduler task '$TaskName':"
        $task | Format-List TaskName, State
        Get-ScheduledTaskInfo -TaskName $TaskName |
            Format-List LastRunTime, LastTaskResult, NextRunTime, NumberOfMissedRuns
    }

    if (Test-Path $LauncherPath) {
        $found = $true
        Write-Host "[user mode] Startup launcher: $LauncherPath"
        $procs = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*$LoopPath*" }
        if ($procs) {
            Write-Host "Loop running (PIDs: $(($procs.ProcessId) -join ', '))"
        } else {
            Write-Host "Loop NOT running (will start on next logon)."
        }
    }

    if (-not $found) {
        Write-Host "Not installed."
    }
}

function Get-Logs {
    $emitted = $false

    if (Test-Path $LogPath) {
        Write-Host "User-mode log ($LogPath):"
        Get-Content $LogPath -Tail 50
        $emitted = $true
    }

    if (Test-IsAdmin) {
        Write-Host ""
        Write-Host "Task Scheduler events for '$TaskName':"
        Get-WinEvent -LogName 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match [regex]::Escape($TaskName) } |
            Select-Object -First 50 | Format-List TimeCreated, Id, Message
        $emitted = $true
    }

    if (-not $emitted) {
        Write-Host "No log file at $LogPath."
        Write-Host ""
        Write-Host "The log captures git output (commits, pushes) and errors — silent no-op runs"
        Write-Host "(when nothing has changed) leave no entry. To verify the loop is alive, use:"
        Write-Host "  dotfiles-timer status     # shows running PIDs"
        Write-Host "  config log --oneline      # shows commits the timer has actually made"
    }
}

$isAdmin = Test-IsAdmin

switch ($Action) {
    'install'   { if ($isAdmin) { Install-Admin } else { Install-User } }
    'reinstall' { if ($isAdmin) { Uninstall-Admin; Install-Admin } else { Uninstall-User; Install-User } }
    'uninstall' { if ($isAdmin) { Uninstall-Admin } else { Uninstall-User } }
    'status'    { Get-Status }
    'logs'      { Get-Logs }
}
