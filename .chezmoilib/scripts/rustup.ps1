#  Source - https://stackoverflow.com/a/73345651
#  Posted by Poperton
#  Retrieved 2026-04-21, License - CC BY-SA 4.0

# Make new environment variables available in the current PowerShell session:

# https://rustup.rs/
# https://rust-lang.github.io/rustup/installation/windows-msvc.html
# winget install --id Microsoft.VisualStudio.2022.Community --source winget --force --override "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --addProductLang En-us"
# winget install --source winget --id Microsoft.WindowsSDK.10.0.28000
# winget install StrawberryPerl
# winget install zellij.zellij

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
& $exePath -y
Remove-Item $exePath

$addPath = "$env:USERPROFILE\.cargo\bin"
[Environment]::SetEnvironmentVariable
     ($addPath, $env:Path, [System.EnvironmentVariableTarget]::Machine)

reload

cargo --version
rustup --version
rustc --version
# rustup toolchain install stable-x86_64-pc-windows-gnu
# rustup default stable-x86_64-pc-windows-gnu
# cargo install --locked zellij
# cargo install --git https://github.com/zellij-org/zellij.git --locked zellij 2>&1
# cargo install --git https://github.com --locked zellij --target-dir ./zellij_build
