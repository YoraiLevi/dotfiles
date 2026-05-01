[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]
    $Shell,
    [Parameter(Mandatory = $false)]
    [string]
    $SessionName
    
)
# ~/.config/zellij/attach-main.ps1
#
# Launches Zellij, naming the session after the current project context:
#   - Respects $_ZELLIJ_SESSION_NAME if already set (explicit override)
#   - Otherwise: git repo root basename if in a git repo, else cwd basename
#
# Session behaviour:
#   - Session exists  → open a new tab at $PWD inside it, then attach
#   - Session missing → create it in the background, then attach
$ErrorActionPreference = 'Stop'

if (-not $ENV:TERM) {
    $env:TERM = 'xterm-256color'
}

# Define Custom Error Types
class ZellijException : System.Exception {
    ZellijException([string]$message) : base($message) {}
}
class ZellijSessionNotFoundException : ZellijException {
    [string]$SessionName
    ZellijSessionNotFoundException([string]$session) : 
    base("Zellij session '$session' not found.") {
        $this.SessionName = $session
    }
}
class ZellijSessionInUseException : ZellijException {
    [string]$SessionName
    ZellijSessionInUseException([string]$session) : 
    base("Zellij session '$session' is currently in use by other clients.") {
        $this.SessionName = $session
    }
}

class ZellijCommandException : ZellijException {
    [int]$ExitCode
    [string]$RawOutput
    ZellijCommandException([string]$message, [int]$code, [string]$output) : base($message) {
        $this.ExitCode = $code
        $this.RawOutput = $output
    }
}
function Get-ZellijClients {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    Write-Information "Listing clients for session '$SessionName' (zellij --session $SessionName action list-clients)"
    # Execute zellij command and capture both stdout and stderr
    $zellijOutput = & zellij --session $SessionName action list-clients 2>&1
    
    # Handle Errors
    if ($LASTEXITCODE -ne 0) {
        $errorString = $zellijOutput -join "`n"
        if ($errorString -like "*There is no active session*") {
            throw [ZellijSessionNotFoundException]::new($SessionName)
        }
        else {
            throw [ZellijCommandException]::new("Zellij command failed.", $LASTEXITCODE, $errorString)
        }
    }

    # Parse Output (Skip header, match columns via regex). Always return an array at the call site.
    $results = @(
        $zellijOutput | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^(?<ClientId>\d+)\s+(?<PaneId>\S+)\s+(?<Command>.+)$') {
                [PSCustomObject]@{
                    ClientId = [int]$Matches.ClientId
                    PaneId   = $Matches.PaneId
                    Command  = $Matches.Command.Trim()
                }
            }
        }
    )

    return $results
}
function Test-ZellijSessionListed {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )
    # Short, line-oriented output — safer to capture than attach/create commands.
    $lines = & zellij ls --no-formatting --short 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    foreach ($line in $lines) {
        if (([string]$line).Trim() -eq $SessionName) {
            return $true
        }
    }
    return $false
}
function Test-ZellijSessionExited {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )
    # Default `zellij ls` includes "(EXITED - attach to resurrect)" for dead sessions; those still
    # appear in `ls --short` but cannot serve `action new-tab` / stable attach until removed or resurrected.
    if ([string]::IsNullOrWhiteSpace($SessionName)) {
        return $false
    }
    $lines = & zellij ls 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    foreach ($raw in $lines) {
        $line = ([string]$raw).Trim()
        if (-not $line) {
            continue
        }
        if ($line -notmatch 'EXITED') {
            continue
        }
        $first = ($line -split '\s+', 2)[0]
        if ($first -eq $SessionName) {
            return $true
        }
    }
    return $false
}
function Start-ZellijSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [Parameter(Mandatory = $true)]
        [string]$ShellPath
    )

    $oldShell = $env:SHELL
    try {
        $env:SHELL = $ShellPath

        # Creates the session without attaching a client (avoids a second client when we `attach` below).
        Write-Information "Starting zellij session '$SessionName' (zellij attach --create-background $SessionName)"
        # Do not capture stdout/stderr here — redirection can block zellij indefinitely.
        & zellij attach --create-background $SessionName
        $createExit = $LASTEXITCODE

        # create-background exits non-zero when the session already exists (e.g. delete-session was
        # skipped because the session was still in use). If the session is listed, continue.
        if ($createExit -ne 0) {
            if (Test-ZellijSessionListed -SessionName $SessionName) {
                Write-Information "Zellij session '$SessionName' already exists; continuing."
            }
            else {
                throw [ZellijCommandException]::new(
                    "Session failed to start (zellij attach --create-background exited with code $createExit).",
                    $createExit,
                    "")
            }
        }
        elseif (-not (Test-ZellijSessionListed -SessionName $SessionName)) {
            throw [ZellijCommandException]::new(
                "Session failed to start after create-background (session not listed).",
                1,
                "")
        }
    }
    finally {
        if ($null -eq $oldShell) { 
            Remove-Item Env:SHELL -ErrorAction SilentlyContinue 
        }
        else { 
            $env:SHELL = $oldShell 
        }
    }
}
function New-ZellijTab {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,

        [Parameter(Mandatory = $true)]
        [string]$ShellPath,

        [string]$Cwd = $PWD.Path
    )

    Write-Information "Creating new tab in zellij session '$SessionName' with cwd '$Cwd' (zellij --session $SessionName action new-tab --close-on-exit --cwd $Cwd -- $ShellPath)"
    # Execute the action. We capture output to check for the "no active session" string 
    # since Zellij uses Exit Code 1 for both 'not found' and 'internal error'.
    $output = & zellij --session $SessionName action new-tab --close-on-exit --cwd $Cwd -- $ShellPath 2>&1

    if ($LASTEXITCODE -ne 0) {
        $errorString = $output -join "`n"
        if ($errorString -like "*There is no active session*") {
            throw [ZellijSessionNotFoundException]::new($SessionName)
        }
        else {
            throw [ZellijCommandException]::new("Failed to create new tab.", $LASTEXITCODE, $errorString)
        }
    }
    
    # Zellij usually returns the index of the new tab (e.g., "1") on success.
    return $output
}
function Remove-ZellijSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        
        [switch]$Force
    )

    $args = @("delete-session", $SessionName)
    if ($Force) { $args += "--force" }

    Write-Information "Deleting zellij session '$SessionName' (zellij $($args -join ' '))"
    $output = & zellij $args 2>&1

    if ($LASTEXITCODE -ne 0) {
        $errorString = $output -join "`n"
        
        if ($errorString -like "*not found*" -or $LASTEXITCODE -eq 2) {
            throw [ZellijSessionNotFoundException]::new($SessionName)
        }
        elseif ($errorString -like "*exists and is active*") {
            # Throw the more meaningful "InUse" exception
            throw [ZellijSessionInUseException]::new($SessionName)
        }
        else {
            throw [ZellijCommandException]::new("Failed to delete session.", $LASTEXITCODE, $errorString)
        }
    }
}

function Connect-ZellijSession {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SessionName)

    Write-Information "Attaching to zellij session '$SessionName' (zellij attach $SessionName)"
    # Run directly so the TUI can render. Do not capture output in a variable.
    if ($InformationPreference -eq "Continue") {
        Write-Information "Press Enter to continue..."
        Read-Host
    }
    & zellij attach $SessionName
    if ($InformationPreference -eq "Continue") {
        Write-Information "Press Enter to continue..."
        Read-Host
    }

    if ($LASTEXITCODE -ne 0) {
        # Based on your trace, Exit Code 1 = Not Found / Failure
        throw [ZellijSessionNotFoundException]::new($SessionName)
    }
}
function Get-ZellijAutoName {
    $MaxLen = 36
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Information "Failed to get git repository root. Using folder name."
    }
    
    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        $name = ($gitRoot.Trim() -split '[/\\]')[-1]
    }
    else {
        # Get path parts (ignoring empty strings from root slashes)
        $parts = ($PWD.Path.replace($HOME, '~') -replace '[^a-zA-Z0-9/\\~\-_\.]', '') -split '[/\\]' | Where-Object { $_ }
        
        # Try 3 leaves, then 2, then 1
        $name = ""
        foreach ($count in 4, 3, 2, 1) {
            if ($parts.Count -ge $count) {
                $candidate = ($parts | Select-Object -Last $count) -join '-'
                if ($candidate.Length -le $MaxLen) {
                    $name = $candidate
                    break
                }
            }
        }
        
        # Fallback: If even 1 leaf is > 36, take the leaf and trim it
        if (-not $name) {
            $name = $parts[-1]
        }
    }

    # Final hard-trim safety check
    if ($name.Length -gt $MaxLen) {
        return $name.Substring(0, $MaxLen)
    }
    return $name
}

# Invoked from finally and from PowerShell.Exiting; must be global so the engine event action can call it.
function global:ZellijAttachMain_ExitCleanup {
    param([string]$SessionName)
    if ([string]::IsNullOrWhiteSpace($SessionName)) {
        return
    }
    try {
        $zellijOutput = & zellij --session $SessionName action list-clients 2>&1
        if ($LASTEXITCODE -ne 0) {
            return
        }
        $parsed = $zellijOutput | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^(?<ClientId>\d+)\s+(?<PaneId>\S+)\s+(?<Command>.+)$') {
                $_
            }
        }
        if ($null -eq $parsed -or @($parsed).Count -eq 0) {
            & zellij kill-session $SessionName 2>&1 | Out-Null
        }
    }
    catch {
        # Session gone or zellij unavailable — ignore
    }
}

# Closing the console with X sends CTRL_CLOSE_EVENT; PowerShell often never reaches finally / PowerShell.Exiting.
# Run cleanup from the Win32 handler (short-lived thread; keep work to Process-only, no PowerShell pipeline).
if (-not $script:ZellijAttachMain_ConsoleCloseTypeLoaded) {
    Add-Type -Namespace ZellijAttachMain -Name ConsoleCloseCleanup -ErrorAction Stop -MemberDefinition @'
private delegate bool HandlerRoutine(uint dwCtrlType);

private static HandlerRoutine _handler;
private static readonly System.Text.RegularExpressions.Regex ClientLine =
    new System.Text.RegularExpressions.Regex(
        @"^(?<ClientId>\d+)\s+(?<PaneId>\S+)\s+(?<Command>.+)$",
        System.Text.RegularExpressions.RegexOptions.Compiled);

[System.Runtime.InteropServices.DllImport("Kernel32", SetLastError = true)]
private static extern bool SetConsoleCtrlHandler(HandlerRoutine handler, bool add);

private const uint CTRL_CLOSE_EVENT = 2;
private const uint CTRL_LOGOFF_EVENT = 5;
private const uint CTRL_SHUTDOWN_EVENT = 6;

public static bool Register() {
    _handler = OnNativeCtrl;
    return SetConsoleCtrlHandler(_handler, true);
}

public static void Unregister() {
    if (_handler != null) {
        SetConsoleCtrlHandler(_handler, false);
        _handler = null;
    }
}

private static bool OnNativeCtrl(uint sig) {
    if (sig != CTRL_CLOSE_EVENT && sig != CTRL_LOGOFF_EVENT && sig != CTRL_SHUTDOWN_EVENT) {
        return false;
    }
    try {
        RunCleanup();
    }
    catch {
    }
    return false;
}

private static void RunCleanup() {
    string session = System.Environment.GetEnvironmentVariable(
        "ZELLIJ_ATTACH_MAIN_CLEANUP_SESSION",
        System.EnvironmentVariableTarget.Process);
    if (string.IsNullOrWhiteSpace(session)) {
        return;
    }

    var listPsi = new System.Diagnostics.ProcessStartInfo {
        FileName = "zellij",
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true,
    };
    listPsi.ArgumentList.Add("--session");
    listPsi.ArgumentList.Add(session);
    listPsi.ArgumentList.Add("action");
    listPsi.ArgumentList.Add("list-clients");

    string combined;
    using (var p = System.Diagnostics.Process.Start(listPsi)) {
        if (p == null) {
            return;
        }
        combined = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit();
        if (p.ExitCode != 0) {
            return;
        }
    }

    int clients = 0;
    bool skipHeader = true;
    foreach (var raw in combined.Split(new[] { '\r', '\n' }, System.StringSplitOptions.RemoveEmptyEntries)) {
        var line = raw.TrimEnd();
        if (skipHeader) {
            skipHeader = false;
            continue;
        }
        if (ClientLine.IsMatch(line)) {
            clients++;
        }
    }
    if (clients > 0) {
        return;
    }

    var killPsi = new System.Diagnostics.ProcessStartInfo {
        FileName = "zellij",
        UseShellExecute = false,
        CreateNoWindow = true,
    };
    killPsi.ArgumentList.Add("kill-session");
    killPsi.ArgumentList.Add(session);
    using (var p = System.Diagnostics.Process.Start(killPsi)) {
        if (p != null) {
            p.WaitForExit();
        }
    }
}
'@
    $script:ZellijAttachMain_ConsoleCloseTypeLoaded = $true
}

# Covers host/process exit paths where try/finally may not run (e.g. closing the terminal).
$script:ZellijAttachMain_ExitingJob = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $sn = [Environment]::GetEnvironmentVariable('ZELLIJ_ATTACH_MAIN_CLEANUP_SESSION', 'Process')
    if ([string]::IsNullOrWhiteSpace($sn)) {
        return
    }
    ZellijAttachMain_ExitCleanup -SessionName $sn
}
$script:ZellijAttachMain_ExitingSubscriptionId = @(
    Get-EventSubscriber -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
) | Sort-Object SubscriptionId -Descending | Select-Object -First 1 -ExpandProperty SubscriptionId

try {
    try {
        $sessionName = if ($SessionName) { $SessionName } else { Get-ZellijAutoName }

        if (Test-ZellijSessionExited -SessionName $sessionName) {
            Write-Information "Zellij session '$sessionName' is EXITED; forcing delete before attach."
            try {
                Remove-ZellijSession -SessionName $sessionName -Force
            }
            catch [ZellijSessionNotFoundException] { }
            catch [ZellijSessionInUseException] { }
        }

        Write-Information "Getting zellij clients for session '$sessionName'"
        $clients = try {
            Get-ZellijClients -SessionName $sessionName
        }
        catch [ZellijSessionNotFoundException] {
            $null
        }

        $sessionListed = Test-ZellijSessionListed -SessionName $sessionName

        if (-not $sessionListed) {
            Write-Information "Removing zellij session '$sessionName' if it exists"
            try { Remove-ZellijSession -SessionName $sessionName } catch [ZellijSessionNotFoundException] { } catch [ZellijSessionInUseException] { }
            Write-Information "Starting zellij session '$sessionName'"
            Start-ZellijSession -SessionName $sessionName -ShellPath $SHELL
        }
        elseif (@($clients).Count -gt 0) {
            Write-Information "Session already exists with clients; creating a new tab in session '$sessionName'"
            New-ZellijTab -SessionName $sessionName -ShellPath $SHELL -Cwd $PWD.Path
        }

        [Environment]::SetEnvironmentVariable('ZELLIJ_ATTACH_MAIN_CLEANUP_SESSION', $sessionName, 'Process')
        $null = [ZellijAttachMain.ConsoleCloseCleanup]::Register()
        Write-Information "Connecting to zellij session '$sessionName'"
        Connect-ZellijSession -SessionName $sessionName
    }
    catch [ZellijCommandException] {
        throw "Zellij Error (Code $($_.Exception.ExitCode)): $($_.Exception.RawOutput)"
    }
    catch {
        Write-Error "Unexpected Error: $_"
        Start-Sleep -Seconds 600
    }
}
finally {
    $sn = [Environment]::GetEnvironmentVariable('ZELLIJ_ATTACH_MAIN_CLEANUP_SESSION', 'Process')
    if (-not [string]::IsNullOrWhiteSpace($sn)) {
        ZellijAttachMain_ExitCleanup -SessionName $sn
    }
    [Environment]::SetEnvironmentVariable('ZELLIJ_ATTACH_MAIN_CLEANUP_SESSION', $null, 'Process')
    try {
        [ZellijAttachMain.ConsoleCloseCleanup]::Unregister()
    }
    catch {
        # Type not loaded (e.g. Add-Type failed) — ignore
    }
    if ($null -ne $script:ZellijAttachMain_ExitingSubscriptionId) {
        Unregister-Event -SubscriptionId $script:ZellijAttachMain_ExitingSubscriptionId -ErrorAction SilentlyContinue
        $script:ZellijAttachMain_ExitingSubscriptionId = $null
    }
    $job = $script:ZellijAttachMain_ExitingJob
    if ($null -ne $job) {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $script:ZellijAttachMain_ExitingJob = $null
    }
    Remove-Item Function:\ZellijAttachMain_ExitCleanup -ErrorAction SilentlyContinue
}
