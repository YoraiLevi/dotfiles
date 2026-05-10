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

    cat > "$SCRIPT_FILE" <<EOF
#!/bin/bash
# Message pattern: counts from --diff-filter (like git-magic / git-alias porcelain summaries) + path list in body.
git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" add -u
if ! git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --quiet --cached; then
  \$n_added=\$(( \$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --cached --diff-filter=A --name-only | wc -l) ))
  \$n_updated=\$(( \$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --cached --diff-filter=M --name-only | wc -l) ))
  \$n_deleted=\$(( \$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --cached --diff-filter=D --name-only | wc -l) ))
  \$n_renamed=\$(( \$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --cached --diff-filter=R --name-only | wc -l) ))
  parts=()
  [ "\$n_added" -gt 0 ] && parts+=(\"\${n_added} added\")
  [ "\$n_updated" -gt 0 ] && parts+=(\"\${n_updated} updated\")
  [ "\$n_deleted" -gt 0 ] && parts+=(\"\${n_deleted} deleted\")
  [ "\$n_renamed" -gt 0 ] && parts+=(\"\${n_renamed} renamed\")
  \$summary=\$(IFS=', '; echo \"\${parts[*]}\")
  \$ts=\$(date --iso-8601=seconds 2>/dev/null || date -u +\"%Y-%m-%dT%H:%M:%SZ\")
  \$subject=\"chore\(dotfiles\): dotfiles sync \(\${summary}\) at \${ts}\"
  \$file_list=\$(git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" diff --cached --name-only | head -n 40)
  if [ -n \"\$file_list\" ]; then
    \$msg=\$(printf '%s\\n\\n%s\\n%s' \"\$subject\" \"Changed paths:\" \"\$file_list\")
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" commit -m \"\$msg\"
  else
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" commit -m \"\$subject\"
  fi
fi
git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" push || {
  echo "auto-commit: push failed (check SSH agent / network)" >&2
  exit 1
}
EOF
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
