// Source - https://stackoverflow.com/a/73345651
// Posted by Poperton
// Retrieved 2026-04-21, License - CC BY-SA 4.0

# Make new environment variables available in the current PowerShell session:
function reload {
   foreach($level in "Machine","User") {
      [Environment]::GetEnvironmentVariables($level).GetEnumerator() | % {
         # For Path variables, append the new values, if they're not already in there
         if($_.Name -match 'Path$') { 
            $_.Value = ($((Get-Content "Env:$($_.Name)") + ";$($_.Value)") -split ';' | Select -unique) -join ';'
         }
         $_
      } | Set-Content -Path { "Env:$($_.Name)" }
   }
}
Write-Host "Installing Rust..." -ForegroundColor Cyan
$exePath = "$env:TEMP\rustup-init.exe"

Write-Host "Downloading..."
(New-Object Net.WebClient).DownloadFile('https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe', $exePath)

Write-Host "Installing..."
cmd /c start /wait $exePath -y
Remove-Item $exePath

$addPath = "$env:USERPROFILE\.cargo\bin"
[Environment]::SetEnvironmentVariable
     ($addPath, $env:Path, [System.EnvironmentVariableTarget]::Machine)

reload

cargo --version
rustup --version
rustc --version
