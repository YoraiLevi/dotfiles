# windows -> wsl2:
WinDotSSH="$(wslpath -u "$(cmd.exe /c "echo %USERPROFILE%" | tr -d '\r' | sed 's|\\|/|g')")/.ssh/"

if [ -d "$WinDotSSH" ]; then
  find "$WinDotSSH" \( -type f -o -type l \) -print0 | while IFS= read -r -d '' file; do
    rel="${file#"$WinDotSSH"}"
    target="$HOME/.ssh/$rel"
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

# Set modes on the canonical file/dir behind each path (readlink -f) so deep symlinks
# to Windows files get the right perms. On /mnt/c, modes persist only with drvfs metadata
# in /etc/wsl.conf (e.g. [automount] options) after restart.
if [ -d "$HOME/.ssh" ]; then
  find "$HOME/.ssh" -print0 | while IFS= read -r -d '' entry; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    real=$(readlink -f -- "$entry" 2>/dev/null) || continue
    [ -n "$real" ] && [ -e "$real" ] || continue
    if [ -d "$real" ]; then
      chmod 700 -- "$real"
    else
      base=$(basename -- "$entry")
      case "$base" in
        known_hosts)
          chmod 644 -- "$real"
          ;;
        *.pub)
          chmod 644 -- "$real"
          ;;
        config|authorized_keys)
          chmod 600 -- "$real"
          ;;
        *)
          chmod 600 -- "$real"
          ;;
      esac
    fi
  done
fi
