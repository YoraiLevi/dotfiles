param()
# re-add.pre runs before chezmoi runs the `re-add` command.
#
# Two responsibilities:
#
#   1. Enforce the canonical chezmoi attribute-ordering guardrail. This is cheap
#      and catches the class of bug that previously produced phantom
#      ~/.readonly_powershell and doubled source directories.
#
#   2. Run the re-add sweep (forget files that vanished from the destination and
#      add new files that appeared in marker directories). The sweep is in
#      .chezmoilib/Invoke-ChezmoiReAddSweep.ps1 and shells out to chezmoi
#      forget/add. Those nested chezmoi invocations contend with this parent
#      chezmoi re-add's BoltDB persistent-state lock, but the sweep wraps each
#      one in a retry loop that tolerates the transient
#        "chezmoi: timeout obtaining persistent state lock, is another instance
#         of chezmoi running?"
#      chezmoi opens the lock lazily so the nested calls normally succeed on
#      their first attempt; the retry is just insurance against AV scanners,
#      filesystem indexers, or a slower-than-usual first invocation.
#
#      This hook is the single place the sweep runs; the ChezmoiSync service
#      simply calls `chezmoi re-add` and lets this hook do the work, rather than
#      duplicating the sweep up-front.
#
# Do NOT move this work to re-add.post: chezmoi holds the state lock between pre
# and post hooks, and post-hook nested chezmoi calls always fail.
Write-Host $PSCommandPath -ForegroundColor Green
$ErrorActionPreference = 'Stop'

# $ENV:CHEZMOI_ARGS is a single space-joined string, not an array. Split and use
# -contains to reliably detect flags like --dry-run. A prior "-in $ENV:CHEZMOI_ARGS"
# check silently no-op'd because -in treats the string as a single element.
$chezmoiArgv = @()
if ($ENV:CHEZMOI_ARGS) {
    $chezmoiArgv = $ENV:CHEZMOI_ARGS -split '\s+' | Where-Object { $_ }
}
$IsDryRun = ($chezmoiArgv -contains '--dry-run') -or ($chezmoiArgv -contains '-n')

# Guardrail: fail fast if the source tree contains a directory or file whose
# chezmoi attribute prefixes are in non-canonical order. See
#   https://www.chezmoi.io/reference/source-state-attributes/
# Canonical order is:
#   encrypted_ / private_ / readonly_ / empty_ / executable_ / remove_ /
#   create_ / modify_ / run_ / symlink_ / dot_ / literal_
# Any entry that begins with `dot_<one of those other prefixes>_` has prefixes
# rearranged, and chezmoi would silently manage a bogus target.
$badOrderPattern = '^dot_(?:encrypted|private|readonly|empty|executable|remove|create|modify|run|symlink)_'
$badOrder = Get-ChildItem -Path $ENV:CHEZMOI_SOURCE_DIR -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $badOrderPattern }
if ($badOrder) {
    Write-Warning "Non-canonical chezmoi attribute ordering detected in source tree:"
    foreach ($bad in $badOrder) {
        Write-Warning "  $($bad.FullName)"
    }
    throw "Refusing to run re-add hook: rename the above entries so prefixes are in canonical order (e.g. readonly_dot_powershell, not dot_readonly_powershell)."
}

$sweepScript = Join-Path $ENV:CHEZMOI_SOURCE_DIR '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1'
if (-not (Test-Path -LiteralPath $sweepScript)) {
    Write-Warning "Sweep script not found at $sweepScript; skipping auto forget/add."
    return
}
try {
    & $sweepScript -ChezmoiPath $ENV:CHEZMOI_EXECUTABLE -SourceDir $ENV:CHEZMOI_SOURCE_DIR -DestDir $ENV:CHEZMOI_DEST_DIR -DryRun:$IsDryRun
}
catch {
    Write-Warning "re-add sweep failed from pre-hook (non-fatal, main re-add will continue): $_"
}
