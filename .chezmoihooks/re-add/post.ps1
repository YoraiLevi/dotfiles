param()
Write-Host $PSCommandPath -ForegroundColor Green
$ErrorActionPreference = 'Stop'
try{
    chezmoi init
}
catch {
    Write-Error "Failed to invoke chezmoi.exe for $dirPath. Error: $_"
}