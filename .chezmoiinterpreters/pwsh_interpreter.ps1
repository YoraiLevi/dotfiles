param()
$ENV:CHEZMOI_DATA = (chezmoi data --format json | Out-String | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100)
