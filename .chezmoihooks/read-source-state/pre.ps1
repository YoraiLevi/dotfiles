param()
Write-Host $PSCommandPath -ForegroundColor Green
Write-Host "Before loop"; for ($i = 1; $i -le 10000000; $i++) { }; Write-Host "After loop"
