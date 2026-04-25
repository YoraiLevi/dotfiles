# windows -> wsl2:
WinHome="$(wslpath -u "$(cmd.exe /c "echo %USERPROFILE%" | tr -d '\r' | sed 's|\\|/|g')")/.wsl2/home/"

if [ -d "$WinHome" ]; then
  find "$WinHome" \( -type f -o -type l \) | while read -r file; do
    rel="${file#"$WinHome"}"
    target="$HOME/$rel"
    echo "$rel"
    mkdir -p "$(dirname "$target")"
    if [ ! -L "$target" ]; then
      [ -e "$target" ] && mv -f "$target" "$target.bak"
      ln -sf "$file" "$target"
    fi
  done
else
  echo "Windows home directory not found" >&2
fi
