param()
Write-Host $PSCommandPath -ForegroundColor Green
$ErrorActionPreference = 'Stop'
$params = @()
if ("--debug" -in $ENV:CHEZMOI_ARGS) {
    $params += "--debug"
    $DebugPreference = 'Continue'
}
if ("--verbose" -in $ENV:CHEZMOI_ARGS) {
    $params += "--verbose"
}
if (("--dry-run" -in $ENV:CHEZMOI_ARGS) -or ("-n" -in $ENV:CHEZMOI_ARGS)) {
    $params += "--dry-run"
}
try {
    & $ENV:CHEZMOI_EXECUTABLE init @params
}
catch {
    Write-Error "Failed to chezmoi init with $params. Error: $_"
}