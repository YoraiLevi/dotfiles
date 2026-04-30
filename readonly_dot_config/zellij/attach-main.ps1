# ~/.config/zellij/attach-main.ps1
#
# Launches Zellij, naming the session after the current project context:
#   - Respects $_ZELLIJ_SESSION_NAME if already set (explicit override)
#   - Otherwise: git repo root basename if in a git repo, else cwd basename
#
# Session behaviour:
#   - Session exists  → open a new tab at $PWD inside it, then attach
#   - Session missing → create it in the background, then attach

function Get-ZellijAutoName {
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        # git returns unix-style paths on Windows; split on either separator
        return ($gitRoot.Trim() -split '[/\\]')[-1]
    }
    return Split-Path -Leaf $PWD.Path
}

$sessionName = if ($ENV:_ZELLIJ_SESSION_NAME) {
    $ENV:_ZELLIJ_SESSION_NAME
} else {
    Get-ZellijAutoName
}

$tabShell = if ($ENV:SHELL) { $ENV:SHELL } else { 'wsl' }

$existingSessions = zellij ls 2>&1 | Out-String
if ($existingSessions -match [regex]::Escape($sessionName)) {
    Write-Host "Session '$sessionName' exists — opening new tab"
    zellij --session $sessionName action new-tab --close-on-exit --cwd $PWD.Path -- $tabShell | Out-Null
} else {
    Write-Host "Session '$sessionName' not found — creating"
    zellij attach --create-background $sessionName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create session '$sessionName'"
    }
}

Write-Host "Attaching to '$sessionName'"
zellij attach $sessionName
