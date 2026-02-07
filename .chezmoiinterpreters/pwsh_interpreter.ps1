param()
if ($null -ne $ENV:CHEZMOI_SOURCE_FILE) {
    Write-Host "=== $ENV:CHEZMOI_SOURCE_FILE ==="
}

$ENV:CHEZMOI_DATA = (chezmoi data --format json | Out-String | ConvertFrom-Json)
& $args