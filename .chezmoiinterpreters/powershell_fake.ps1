param()
Write-Warning "Fake interpreter executed for script: $args"
Write-Host (Get-Content $args | Out-String)
exit 0