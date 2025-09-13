@echo off
echo pwsh.exe -NoProfile -Command "$path = %1; $path = $path.Replace('\', '/'); $path = (wsl wslpath $path); echo $path"