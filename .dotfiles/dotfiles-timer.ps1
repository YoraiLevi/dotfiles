#!/usr/bin/env pwsh
# dotfiles-timer.ps1: Manage auto-commit for tracked dotfiles changes.
# Auto-detects privilege at install time:
#   Admin     -> Windows Task Scheduler (survives logoff)
#   Non-admin -> Startup-folder VBS launcher + hidden pwsh while-loop

param(
    [Parameter(Position=0, Mandatory=$false)]
    [ValidateSet('install','reinstall','enable','disable','start','stop','uninstall','remove','status','logs')]
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
# In user mode the install state is encoded by file presence:
#   $LoopPath exists, $LauncherPath exists  -> installed + enabled
#   $LoopPath exists, $LauncherPath missing -> installed + disabled
#   $LoopPath missing                       -> not installed

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Action) {
    $mode = if (Test-IsAdmin) { 'admin (Task Scheduler)' } else { 'user (startup folder + VBS)' }
    Write-Host @"
Usage: pwsh dotfiles-timer.ps1 [install|reinstall|enable|disable|start|stop|status|logs|uninstall|remove]

Detected privilege: $mode

  install    Write files, enable autostart, start now.
  reinstall  Uninstall + install.
  enable     Mark to autostart on next boot/logon (don't necessarily run now).
  disable    Turn off autostart and stop now (keep files).
  start      Run now (idempotent — also enables if disabled).
  stop       Stop running now (transient — auto-resumes on reboot if enabled).
  status     Show install + autostart + running state.
  logs       Show recent activity.
  uninstall  Full removal (alias: remove).
"@
    exit 1
}

function Write-CommitScript {
    @"
`$gitArgs = @('--git-dir', '$($GitDir)', '--work-tree', '$($WorkTree)')
& git @gitArgs add -u
& git @gitArgs diff --cached --quiet
if (`$LASTEXITCODE -ne 0) {
    function Get-DiffPathCount([string]`$filter) {
        `$out = & git @gitArgs diff --cached --diff-filter=`$filter --name-only 2>`$null
        if (-not `$out) { return 0 }
        if (`$out -is [array]) { return `$out.Count }
        return 1
    }
    `$nAdded    = Get-DiffPathCount 'A'
    `$nUpdated  = Get-DiffPathCount 'M'
    `$nDeleted  = Get-DiffPathCount 'D'
    `$nRenamed  = Get-DiffPathCount 'R'
    `$parts = [System.Collections.Generic.List[string]]::new()
    if (`$nAdded   -gt 0) { `$parts.Add("{0} added"   -f `$nAdded) }
    if (`$nUpdated -gt 0) { `$parts.Add("{0} updated" -f `$nUpdated) }
    if (`$nDeleted -gt 0) { `$parts.Add("{0} deleted" -f `$nDeleted) }
    if (`$nRenamed -gt 0) { `$parts.Add("{0} renamed" -f `$nRenamed) }
    `$summary = (`$parts -join ', ')
    `$ts = Get-Date -Format 'o'
    `$subject = "chore(dotfiles): dotfiles sync (`$summary) at `$ts"
    `$fileList = @(& git @gitArgs diff --cached --name-only | Select-Object -First 40)
    if (`$fileList.Count -gt 0) {
        `$bodyText = (`$fileList | ForEach-Object { `$_ }) -join "`n"
        `$msg = "`$subject`n`nChanged paths:`n`$bodyText"
        & git @gitArgs commit -m `$msg
    } else {
        & git @gitArgs commit -m `$subject
    }
}
& git @gitArgs push
"@ | Set-Content -Path $ScriptPath -Encoding UTF8
}

function Write-LoopScript {
    @"
# .auto-commit-loop.ps1 — invoked by the VBS launcher at logon
`$logPath   = '$LogPath'
`$maxBytes  = 524288     # 0.5 MB threshold for log rotation
`$keepCount = 5          # archives to keep before pruning oldest

function Invoke-LogRotation([string]`$path) {
    if (-not (Test-Path `$path)) { return }
    if ((Get-Item `$path).Length -le `$maxBytes) { return }
    `$archive = "`$path.`$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item `$path `$archive -Force
    `$dir  = Split-Path `$path -Parent
    `$name = Split-Path `$path -Leaf
    Get-ChildItem -Path `$dir -Filter "`$name.*" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip `$keepCount |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

while (`$true) {
    `$ts = Get-Date -Format 'o'
    try {
        # Capture all stdout+stderr from the commit script (git output, etc.)
        `$output = & '$ScriptPath' 2>&1 | Out-String
        if (`$output.Trim()) {
            Invoke-LogRotation `$logPath
            Add-Content -Path `$logPath -Value "[`$ts] `$(`$output.TrimEnd())"
        }
    } catch {
        Invoke-LogRotation `$logPath
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
    Remove-Item $LoopPath     -Force -ErrorAction SilentlyContinue
    Remove-Item $ScriptPath   -Force -ErrorAction SilentlyContinue
    Write-Host "[user] Removed startup launcher and stopped running loop."
}

function Enable-Timer {
    if (Test-IsAdmin) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) { Write-Host "Not installed."; return }
        Enable-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null
        Write-Host "[admin] Task enabled (will autostart per its triggers)."
    } else {
        if (-not (Test-Path $LoopPath)) { Write-Host "Not installed."; return }
        if (-not (Test-Path $LauncherPath)) { Write-VbsLauncher }
        Write-Host "[user] VBS launcher re-created in startup folder (runs at next logon)."
    }
}

function Disable-Timer {
    if (Test-IsAdmin) {
        Stop-ScheduledTask    -TaskName $TaskName -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
        Write-Host "[admin] Task disabled and stopped (files preserved; 'start' or 'enable' to resume)."
    } else {
        Stop-LoopProcesses
        Remove-Item $LauncherPath -Force -ErrorAction SilentlyContinue
        Write-Host "[user] Loop stopped and VBS launcher removed from startup folder (loop+commit scripts kept)."
    }
}

function Start-Timer {
    if (Test-IsAdmin) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) { Write-Host "Not installed. Run 'install' first."; return }
        Enable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
        Start-ScheduledTask  -TaskName $TaskName
        Write-Host "[admin] Task enabled and started."
    } else {
        if (-not (Test-Path $LoopPath)) { Write-Host "Not installed. Run 'install' first."; return }
        if (-not (Test-Path $LauncherPath)) { Write-VbsLauncher }
        $running = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*$LoopPath*" }
        if ($running) { Write-Host "[user] Loop already running."; return }
        Start-Process wscript.exe -ArgumentList "`"$LauncherPath`"" -WindowStyle Hidden
        Write-Host "[user] Loop started."
    }
}

function Stop-Timer {
    if (Test-IsAdmin) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host "[admin] Stopped current run (autostart still on; use 'disable' to fully halt)."
    } else {
        Stop-LoopProcesses
        Write-Host "[user] Loop stopped (will resume on next logon if VBS launcher still in startup folder)."
    }
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

    if (Test-Path $LoopPath) {
        $found = $true
        if (Test-Path $LauncherPath) {
            Write-Host "[user mode] Installed; autostart: ENABLED ($LauncherPath)"
        } else {
            Write-Host "[user mode] Installed; autostart: DISABLED (no VBS in startup folder)"
            Write-Host "Run 'enable' or 'start' to recreate the launcher."
        }
        $procs = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*$LoopPath*" }
        if ($procs) {
            Write-Host "Loop running (PIDs: $(($procs.ProcessId) -join ', '))"
        } else {
            Write-Host "Loop NOT running."
        }
    }

    if (-not $found) {
        Write-Host "Not installed."
    }
}

function Get-Logs {
    $emitted = $false

    if (Test-Path $LogPath) {
        Write-Host "User-mode log ( $LogPath ):"
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
    'enable'    { Enable-Timer }
    'disable'   { Disable-Timer }
    'start'     { Start-Timer }
    'stop'      { Stop-Timer }
    'uninstall' { if ($isAdmin) { Uninstall-Admin } else { Uninstall-User } }
    'remove'    { if ($isAdmin) { Uninstall-Admin } else { Uninstall-User } }
    'status'    { Get-Status }
    'logs'      { Get-Logs }
}
