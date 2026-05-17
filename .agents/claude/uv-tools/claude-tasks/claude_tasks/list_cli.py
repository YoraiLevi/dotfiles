"""``list-tasks`` — print the current Claude Code session's task list to stdout.

Designed for in-conversation use via Claude Code's ``!`` prefix:

    !list-tasks

Colors mirror the statusline's vocabulary (green check, yellow play, dim
circle) for consistency. ``NO_COLOR=1`` or a non-TTY stdout disables ANSI.
"""

from __future__ import annotations

import os
import sys

from .common import (
    Task,
    get_session_id,
    load_session_tasks,
    partition_by_status,
)


def _use_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    # When piped (e.g., into less), still emit color if forced; otherwise auto.
    if os.environ.get("FORCE_COLOR"):
        return True
    return sys.stdout.isatty()


def main() -> int:
    color = _use_color()
    green = "\033[32m" if color else ""
    yellow = "\033[33m" if color else ""
    dim = "\033[2m" if color else ""
    reset = "\033[0m" if color else ""

    sid = get_session_id()
    if not sid:
        print(
            "list-tasks: CLAUDE_CODE_SESSION_ID is not set.\n"
            "Run this from inside a Claude Code session (e.g. via the ! prefix).",
            file=sys.stderr,
        )
        return 1

    tasks = load_session_tasks(sid)
    if not tasks:
        print(f"{dim}Session {sid[:8]}:{reset} no tasks.")
        return 0

    parts = partition_by_status(tasks)
    done = len(parts["completed"])
    active = len(parts["in_progress"])
    pending = len(parts["pending"])
    other = len(parts["other"])
    total = len(tasks)

    # Header
    header = f"{dim}Session{reset} {sid[:8]}  —  {green}{done}/{total} ✓{reset}"
    if active:
        header += f"  {yellow}{active} ▶{reset}"
    if pending:
        header += f"  {dim}{pending} ○{reset}"
    if other:
        header += f"  {dim}{other} ?{reset}"
    print(header)
    print()

    # In progress
    if parts["in_progress"]:
        print(f"{yellow}In progress{reset}")
        for t in parts["in_progress"]:
            label = t.active_form or t.subject
            blocked = f"  {dim}(blocked by {len(t.blocked_by)}){reset}" if t.blocked_by else ""
            print(f"  {yellow}▶{reset} {label}  {dim}(id {t.id}){reset}{blocked}")
        print()

    # Pending
    if parts["pending"]:
        print(f"{dim}Pending{reset}")
        for t in parts["pending"]:
            blocked = f"  {dim}(blocked by {len(t.blocked_by)}){reset}" if t.blocked_by else ""
            print(f"  {dim}○{reset} {t.subject}  {dim}(id {t.id}){reset}{blocked}")
        print()

    # Completed (dimmed; less prominent)
    if parts["completed"]:
        print(f"{green}Completed{reset}")
        for t in parts["completed"]:
            print(f"  {green}✓{reset} {dim}{t.subject}{reset}  {dim}(id {t.id}){reset}")
        print()

    # Other / unknown statuses
    if parts["other"]:
        print(f"{dim}Other{reset}")
        for t in parts["other"]:
            print(f"  {dim}[{t.status}]{reset} {t.subject}  {dim}(id {t.id}){reset}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
