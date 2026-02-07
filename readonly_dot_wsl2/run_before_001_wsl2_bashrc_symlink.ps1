# wsl2 -> windows:
# $distro_network_path = ($(wsl -l -v | Select-String '\*' | ForEach-Object { $_.ToString().Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)[1] } | ForEach-Object { "\\wsl.localhost\$_" }) -replace "`0","")
# New-Item -ItemType SymbolicLink -Path "$ENV:USERPROFILE/.wsl2/.bashrc" -Target "$distro_network_path\home\$wsl_user\.bashrc"
# New-Item -ItemType SymbolicLink -Path "$ENV:USERPROFILE/.wsl2/.gitconfig" -Target "$distro_network_path\home\$wsl_user\.gitconfig"