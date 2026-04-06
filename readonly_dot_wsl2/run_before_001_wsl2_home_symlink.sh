# windows -> wsl2:
WinHome="$(wslpath -u "$(cmd.exe /c "echo %USERPROFILE%" | tr -d '\r' | sed 's|\\|/|g')")/.wsl2/home/"

if [ -d "$WinHome" ]; then
  find "$WinHome" -mindepth 1 -maxdepth 1 -print | while read -r file; do
   echo "$file"
    target=~/"$(basename "$file")"
    if [ ! -L "$target" ]; then
        [ -e "$target" ] && mv -f "$target" "$target.bak"
        ln -sf "$file" "$target"
    fi
  done
fi
