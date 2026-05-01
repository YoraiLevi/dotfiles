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

    # Parse Output (Skip header, match columns via regex). Always return an array so
    # "zero clients" is not confused with "session missing" ($null) at the call site.
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

try {
    $sessionName = if ($SessionName) { $SessionName } else { Get-ZellijAutoName }
    Write-Information "Getting zellij clients for session '$sessionName'"
    $clients = try { Get-ZellijClients -SessionName $sessionName } catch [ZellijSessionNotFoundException] { $null }
    if ($null -eq $clients) {
        Write-Information "Removing zellij session '$sessionName' if it exists"
        try { Remove-ZellijSession -SessionName $sessionName } catch [ZellijSessionNotFoundException] { } catch [ZellijSessionInUseException] { }
        Write-Information "Starting zellij session '$sessionName'"
        Start-ZellijSession -sessionName $sessionName -SHELL $SHELL
    }
    elseif ($clients.Count -gt 0) {
        Write-Information "Session previously existed, creating a new tab in session '$sessionName'"
        New-ZellijTab -SessionName $sessionName -ShellPath $SHELL -Cwd $PWD.Path | Write-Information
    }
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
