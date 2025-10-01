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
try {
    # & $ENV:CHEZMOI_EXECUTABLE init @params
}
catch {
    Write-Error "Failed to invoke chezmoi.exe for $dirPath. Error: $_"
}