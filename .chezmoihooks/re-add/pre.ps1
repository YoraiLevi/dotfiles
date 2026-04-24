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
#      forget/add.
#
#      The nested chezmoi calls contend with the parent chezmoi re-add's BoltDB
#      persistent-state lock. Two guards prevent contention in practice:
#        a) The service preserves chezmoistate.boltdb between runs (warm state),
#           so chezmoi skips DB writes during startup config evaluation.
#        b) The service passes --refresh-externals=never so chezmoi also skips
#           evaluating externals templates (another early lock-acquisition path).
#      With both guards active, the nested calls get the lock first, do their
#      work, and release before chezmoi re-add needs it for checksums. The retry
#      wrapper in Invoke-ChezmoiReAddSweep.ps1 is insurance for any remaining
#      transient contention (e.g. AV scanners or other tools touching the DB).
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

if (-not $ENV:CHEZMOI_SOURCE_DIR) {
    Write-Warning "re-add pre-hook: CHEZMOI_SOURCE_DIR is unset; resolving via 'chezmoi source-path'."
    if ($ENV:CHEZMOI_EXECUTABLE -and (Test-Path -LiteralPath $ENV:CHEZMOI_EXECUTABLE -PathType Leaf)) {
        $ENV:CHEZMOI_SOURCE_DIR = (& $ENV:CHEZMOI_EXECUTABLE source-path | Out-String).Trim()
    }
    if (-not $ENV:CHEZMOI_SOURCE_DIR) {
        Write-Warning "re-add pre-hook: cannot determine source dir; skipping guardrail and sweep."
        return
    }
}

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
