param()
# re-add.pre runs before chezmoi runs the `re-add` command.
#
# Two responsibilities:
#
#   1. Always enforce the canonical chezmoi attribute-ordering guardrail. This is
#      cheap and catches the class of bug that previously produced phantom
#      ~/.readonly_powershell and doubled source directories.
#
#   2. For INTERACTIVE users only, run the re-add sweep (forget files that vanished
#      from the destination, add new files that appeared in marker directories).
#      The sweep shells out to chezmoi forget/add, which are top-level chezmoi
#      processes and therefore contend with the parent chezmoi re-add's BoltDB
#      persistent-state lock. chezmoi opens the lock lazily, so interactive
#      invocations happen to work, but the ChezmoiSync background service
#      consistently raced the parent and produced:
#        "chezmoi: timeout obtaining persistent state lock, is another instance of
#         chezmoi running?"
#      Because the service now runs the sweep itself BEFORE calling chezmoi re-add
#      (as top-level, non-nested chezmoi calls), it exports CHEZMOI_SYNC_SERVICE=1
#      before invoking chezmoi re-add and we skip the sweep here to avoid the
#      duplicate, lock-contending work.
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

# Guardrail (always runs): fail fast if the source tree contains a directory or
# file whose chezmoi attribute prefixes are in non-canonical order. See:
#   https://www.chezmoi.io/reference/source-state-attributes/
# Canonical order is:
#   encrypted_ / private_ / readonly_ / empty_ / executable_ / remove_ /
#   create_ / modify_ / run_ / symlink_ / dot_ / literal_
# Any entry that begins with `dot_<one of those other prefixes>_` has prefixes
# rearranged, and chezmoi would silently manage a bogus target. Kept here
# (duplicate with the sweep script) so interactive users get the check even
# when CHEZMOI_SYNC_SERVICE=1 suppresses the sweep.
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

if ($ENV:CHEZMOI_SYNC_SERVICE -eq '1') {
    Write-Host "re-add pre-hook: CHEZMOI_SYNC_SERVICE=1, sweep already performed by the service - skipping" -ForegroundColor DarkGray
    return
}

# Interactive path: run the shared sweep. It shells out to chezmoi forget/add,
# which nest inside this chezmoi re-add. Documented to be unreliable (see header)
# but observed to work in interactive shells because of lazy lock acquisition.
# The service path does not go through here.
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
