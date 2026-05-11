#!/usr/bin/env bash
# dotfiles-timer.sh: Manage a systemd user timer that auto-commits dotfiles changes.

GIT_DIR="$HOME/.dotfiles"
WORK_TREE="$HOME"
SERVICE_NAME="dotfiles-git-commit"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.timer"
SCRIPT_FILE="$GIT_DIR/.auto-commit.sh"
TIMER_UNIT="${SERVICE_NAME}.timer"
SERVICE_UNIT="${SERVICE_NAME}.service"

print_usage() {
  cat <<EOF
Usage: $0 [install|reinstall|enable|disable|start|stop|status|logs|uninstall|remove]

  install    Write unit files, enable autostart, start now.
  reinstall  Uninstall + install.
  enable     Mark to autostart on next boot (don't necessarily run now).
  disable    Turn off autostart and stop now (keep unit files).
  start      Run now (idempotent — also enables if disabled).
  stop       Stop running now (transient — auto-resumes on reboot if enabled).
  status     Show timer and service status.
  logs       Show recent service logs.
  uninstall  Full removal (alias: remove).

Commits tracked dotfiles changes every minute using:
  git --git-dir=$GIT_DIR --work-tree=$WORK_TREE
EOF
}

install_timer() {
    mkdir -p "$HOME/.config/systemd/user"

    # Quoted heredoc: an unquoted EOF would run $((…)) and $(git …) while *installing*, corrupting the script.
    cat > "$SCRIPT_FILE" <<'AUTOSCRIPT'
#!/bin/bash
# Subject: chore(dotfiles): add/mod/del/ren with paths; body: grouped lists (names, not only counts).
GDIR='@DOTFILES_GIT_DIR@'
WTREE='@DOTFILES_WORK_TREE@'
git --git-dir="$GDIR" --work-tree="$WTREE" add -u
if ! git --git-dir="$GDIR" --work-tree="$WTREE" diff --quiet --cached; then
  ts=$(date --iso-8601=seconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

  paths_added=$(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --diff-filter=A --name-only)
  paths_modified=$(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --diff-filter=M --name-only)
  paths_deleted=$(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --diff-filter=D --name-only)

  sbj_parts=()
  while IFS= read -r f; do [ -z "$f" ] || sbj_parts+=("add ${f}"); done <<< "$paths_added"
  while IFS= read -r f; do [ -z "$f" ] || sbj_parts+=("mod ${f}"); done <<< "$paths_modified"
  while IFS= read -r f; do [ -z "$f" ] || sbj_parts+=("del ${f}"); done <<< "$paths_deleted"
  while IFS=$'\t' read -r _st oldp newp; do
    [ -n "$oldp" ] && [ -n "$newp" ] || continue
    sbj_parts+=("ren ${oldp} -> ${newp}")
  done < <(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --name-status --diff-filter=R)

  detail=""
  if [ ${#sbj_parts[@]} -gt 0 ]; then
    detail=$(IFS='; '; echo "${sbj_parts[*]}")
  else
    detail="changes"
  fi
  subject_core="chore(dotfiles): ${detail}"
  max_len=160
  if [ ${#subject_core} -gt $max_len ]; then
    name_lines=$(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --name-only)
    ntotal=$(printf '%s\n' "$name_lines" | sed '/^$/d' | wc -l | tr -d ' ')
    preview=$(printf '%s\n' "$name_lines" | sed '/^$/d' | head -n 3 | paste -sd ', ' -)
    subject_core="chore(dotfiles): ${ntotal} paths (${preview}, …)"
    if [ ${#subject_core} -gt $max_len ]; then
      subject_core="chore(dotfiles): ${ntotal} paths (see message body)"
    fi
  fi
  subject="${subject_core} at ${ts}"

  body=""
  append_section() {
    local title="$1"
    local lines="$2"
    local nonempty
    nonempty=$(printf '%s\n' "$lines" | sed '/^$/d')
    [ -z "$nonempty" ] && return 0
    body+="${title}"$'\n'
    body+=$(printf '%s\n' "$nonempty" | sed 's/^/  /')$'\n'$'\n'
  }
  append_section "Added:" "$paths_added"
  append_section "Modified:" "$paths_modified"
  append_section "Deleted:" "$paths_deleted"
  ren_body=""
  while IFS=$'\t' read -r _st oldp newp; do
    [ -n "$oldp" ] && [ -n "$newp" ] || continue
    ren_body+="  ${oldp} -> ${newp}"$'\n'
  done < <(git --git-dir="$GDIR" --work-tree="$WTREE" diff --cached --name-status --diff-filter=R)
  if [ -n "$ren_body" ]; then
    body+="Renamed:"$'\n'
    body+="$ren_body"$'\n'
  fi

  if [ -n "$(printf '%s' "$body" | sed '/^$/d')" ]; then
    msg=$(printf '%s\n\n%s' "$subject" "$body")
    git --git-dir="$GDIR" --work-tree="$WTREE" commit -m "$msg"
  else
    git --git-dir="$GDIR" --work-tree="$WTREE" commit -m "$subject"
  fi
fi
git --git-dir="$GDIR" --work-tree="$WTREE" push || {
  echo "auto-commit: push failed (check SSH agent / network)" >&2
  exit 1
}
AUTOSCRIPT
    sed -i "s|@DOTFILES_GIT_DIR@|$GIT_DIR|g;s|@DOTFILES_WORK_TREE@|$WORK_TREE|g" "$SCRIPT_FILE"
    chmod +x "$SCRIPT_FILE"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto-commit tracked dotfiles changes
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=SSH_AUTH_SOCK=%t/keyring/ssh
ExecStart=$SCRIPT_FILE
EOF

    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Timer for dotfiles auto-commit

[Timer]
OnBootSec=10s
OnUnitActiveSec=1min
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user disable --now "$TIMER_UNIT" "$SERVICE_UNIT" >/dev/null 2>&1 || true

    if ! systemctl --user enable "$TIMER_UNIT"; then
        echo "Error: failed to enable $TIMER_UNIT. Check: journalctl --user -xe"
        exit 1
    fi
    if ! systemctl --user start "$TIMER_UNIT"; then
        echo "Error: failed to start $TIMER_UNIT. Check: journalctl --user -xe"
        exit 1
    fi

    echo "Installed $TIMER_UNIT (commits every minute, git-dir: $GIT_DIR)"
}

disable_timer() {
    systemctl --user stop "$TIMER_UNIT" "$SERVICE_UNIT" 2>/dev/null || true
    systemctl --user disable "$TIMER_UNIT" "$SERVICE_UNIT" 2>/dev/null || true
    echo "Disabled $TIMER_UNIT."
}

remove_timer() {
    disable_timer
    rm -f "$SERVICE_FILE" "$TIMER_FILE" "$SCRIPT_FILE"
    systemctl --user daemon-reload
    echo "Removed $TIMER_UNIT unit files."
}

case "${1:-}" in
    install)          install_timer ;;
    reinstall)        remove_timer; install_timer ;;
    enable)           systemctl --user enable "$TIMER_UNIT" ;;
    disable)          systemctl --user disable --now "$TIMER_UNIT" 2>/dev/null || true ;;
    start)            systemctl --user enable --now "$TIMER_UNIT" ;;
    stop)             systemctl --user stop "$TIMER_UNIT" ;;
    uninstall|remove) remove_timer ;;
    status)
        systemctl --user status "$TIMER_UNIT"
        echo ""
        systemctl --user status "$SERVICE_UNIT"
        ;;
    logs)
        journalctl --user-unit "$SERVICE_UNIT" --no-pager -n 50
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
