# run_after_001_wsl2_symlink.sh — Windows → WSL symlink sync (after templates; WSL2)
#
# This is not a "config warning" script.  It mirrors Windows paths into WSL by symlink:
#   - %USERPROFILE%\.ssh → ~/.ssh, then chmod/chown on real targets behind symlinks (readlink -f);
#   - %USERPROFILE%\.wsl2\home → $HOME/…;
#   - %USERPROFILE%\.wsl2\etc → /etc/…;
#   - and chmod 644 on the real file if /etc/wsl.conf is a symlink (so a linked config keeps sane
#     permissions).
# Drive metadata for chmod to stick is validated in run_before_001_wsl2.sh, not here.

# Define WinWSL as the translated Windows %USERPROFILE% root in WSL
WinWSL="$(wslpath -u "$(cmd.exe /c "echo %USERPROFILE%" | tr -d '\r' | sed 's|\\|/|g')")"

ln -sf -- "$WinWSL" "$HOME/WinHome"

# Mirror USERPROFILE/.ssh into WSL ~/.ssh
WinDotSSH="$WinWSL/.ssh/"

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
      # Ensure the user running the script (root) owns the target
      chown "$(id -u):$(id -g)" -- "$real"
    fi
  done
fi

# Mirror USERPROFILE/.wsl2/home into WSL $HOME
WinHome="$WinWSL/.wsl2/home/"

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

# Mirror USERPROFILE/.wsl2/etc into WSL /etc (may require running chezmoi with sufficient privileges for /etc).
WinEtc="$WinWSL/.wsl2/etc/"

if [ -d "$WinEtc" ]; then
  find "$WinEtc" \( -type f -o -type l \) | while read -r file; do
    rel="${file#"$WinEtc"}"
    target="/etc/$rel"
    echo "etc: $rel"
    mkdir -p "$(dirname "$target")"
    if [ ! -L "$target" ]; then
      [ -e "$target" ] && mv -f "$target" "$target.bak"
      ln -sf "$file" "$target"
    fi
  done
else
  echo "Windows .wsl2/etc directory not found" >&2
fi

WslConf="$WinWSL/.wsl2/wsl.conf" 
if [ -f "$WslConf" ]; then
  echo "$WslConf"
  cp -f -- "$WslConf" /etc/wsl.conf
  chmod 644 -- /etc/wsl.conf
  chown root:root -- /etc/wsl.conf
else
  echo "Windows .wsl2/wsl.conf file not found" >&2
fi

# Ensure all files in ~/.local/bin are executable
if [ -d "$HOME/.local/bin" ]; then
  find "$HOME/.local/bin" -type f | while read -r f; do
    if [ ! -x "$f" ]; then
      chmod +x "$f"
    fi
  done
fi