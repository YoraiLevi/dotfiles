# ~/.config/zellij/launcher.ps1 — Zellij tab launcher
#
# ── Customize entries here ──────────────────────────────────────────────────
# @{ Name = "Display name"; Command = "command to run" }

# Zellij bug workaround: after a floating pane closes (close_on_exit), the tab's
# floating_panes_visible flag stays false. The next Run {floating true} creates
# the pane but it's hidden. A brief yield lets Zellij finish registering the
# floating state before we force-show it (otherwise show-floating-panes is a no-op).
Start-Sleep -Milliseconds 150
zellij action show-floating-panes 2>$null

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
