# ~/.config/zellij/launcher.ps1 — Zellij tab launcher
#
# ── Customize entries here ──────────────────────────────────────────────────
# @{ Name = "Display name"; Command = "command to run" }
$Entries = @(
    @{ Name = "WSL";        Command = "wsl"  }
    @{ Name = "PowerShell"; Command = "pwsh" }
)
# ────────────────────────────────────────────────────────────────────────────

$fzfArgs = @(
    '--prompt= > '
    '--border=rounded'
    '--no-info'
    '--bind=esc:abort'
    '--bind=ctrl-c:abort'
)

$selected = $Entries | ForEach-Object { $_.Name } | fzf @fzfArgs

if (-not $selected) { exit 0 }

$entry = $Entries | Where-Object { $_.Name -eq $selected } | Select-Object -First 1
if ($entry) {
    zellij --session $ENV:ZELLIJ_SESSION_NAME action new-tab --close-on-exit --cwd $PWD.Path -- $entry.Command > $null
}
