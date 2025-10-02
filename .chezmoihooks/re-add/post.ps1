param()
Write-Host $PSCommandPath -ForegroundColor Green
$ErrorActionPreference = 'Stop'
Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' } | ForEach-Object { Write-Debug $_.Name, $_.Value -ForegroundColor Yellow }
