param()
if ($null -ne $ENV:CHEZMOI_SOURCE_FILE) {
    Write-Host "== $ENV:CHEZMOI_SOURCE_FILE ==" -ForegroundColor Green
}
Write-Host "args: $args" -ForegroundColor Cyan
$ENV:CHEZMOI_DATA = (chezmoi data --format json | Out-String | ConvertFrom-Json)
& $args