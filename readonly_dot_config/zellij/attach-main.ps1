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
    if (-not $SHELL) {
        throw "FAILED TO DETERMINE SHELL"
    }
    $sessionName = if ($SessionName) { $SessionName } else { Get-ZellijAutoName }
    Write-Information "sessionName: $sessionName"
    $zellijLsOutput = @()
    $zellijLsOutput = & zellij ls --no-formatting --short 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (-not ($zellijLsOutput -like "*No active zellij sessions found.*")) {
            throw "zellij ls failed with code $LASTEXITCODE. Output:`n$zellijLsOutput"
        }
    }
    $zellijLsOutput = $zellijLsOutput | ForEach-Object { ($_ | Out-String).Trim() }
    Write-Information "zellijLsOutput: $zellijLsOutput"
    if ($zellijLsOutput | Where-Object { $_ -eq $sessionName }) {
        & zellij --session $sessionName action new-tab --close-on-exit --cwd $PWD.Path -- $SHELL | Write-Information
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to open new tab in existing session '$sessionName' (exit $LASTEXITCODE)"
        }
    }
    else {
        $ENV:SHELL = $SHELL
        & zellij attach --create-background $sessionName
        Remove-Item Env:SHELL -ErrorAction SilentlyContinue
   
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create session '$sessionName' (exit $LASTEXITCODE)"
        }
    }

    Write-Information "Attaching to '$sessionName'"
    $null = zellij da -y # delete dead sessions
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete dead sessions (exit $LASTEXITCODE)"
    }
    if ($InformationPreference -eq "Continue") {
        Pause
    }
    & zellij attach $sessionName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to attach to session '$sessionName' (exit $LASTEXITCODE)"
    }
    if ($InformationPreference -eq "Continue") {
        Pause
    }
}
catch {
    Write-Error "Error: $_"
    Pause
}