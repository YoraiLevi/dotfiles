param()
Write-Warning "Fake Powershell interpreter executed for script: $args"
Write-Host (Get-Content $args | Out-String)
exit 0