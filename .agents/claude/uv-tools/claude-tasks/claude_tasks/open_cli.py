"""``open-tasks`` — render a markdown dashboard for this session and open it.

Writes the dashboard to ``~/.claude/tasks/<session_id>/dashboard.md`` (next to
the JSON task files Claude Code maintains) and launches it in Obsidian via
the ``obsidian://open?vault=.claude&file=tasks/<session_id>/dashboard`` URI.
The ``.claude`` vault — registered on this machine at ``~/.claude/`` — covers
the dashboard location natively, so no file relocation is needed.

Designed to be invoked manually (via Claude Code's ``!`` prefix or any shell).
The dashboard is a snapshot at the moment of invocation; re-run to refresh.
"""

from __future__ import annotations

import sys
from datetime import datetime

from .common import (
    Task,
    build_obsidian_uri,
    get_session_id,
    launch_uri,
    load_session_tasks,
    partition_by_status,
    pretty_session,
    session_tasks_dir,
    setup_utf8_stdout,
)

# This tool's files live under ``tasks/`` relative to the ``.claude`` vault.
OBSIDIAN_PATH_PREFIX = "tasks"


def _render_task_line(t: Task, marker: str, *, strike: bool = False) -> str:
    label = t.subject if not strike else f"~~{t.subject}~~"
    return f"- {marker} {label}  _(id {t.id})_"


def render_dashboard(session_id: str, tasks: list[Task]) -> str:
    parts = partition_by_status(tasks)
    done = len(parts["completed"])
    active = len(parts["in_progress"])
    pending = len(parts["pending"])
    other = len(parts["other"])
    total = len(tasks)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    label = pretty_session(session_id)

    out: list[str] = [
        f"# Session {label} — Task List",
        "",
        f"*Generated {now}*",
        "",
        f"**{done} done / {active} active / {pending} pending  ({total} total)**",
        "",
    ]

    if parts["in_progress"]:
        out.append("## In progress")
        for t in parts["in_progress"]:
            label = t.active_form or t.subject
            out.append(f"- [▶] **{label}**  _(id {t.id})_")
            desc = t.description.strip()
            if desc and desc != t.subject:
                out.append(f"  {desc}")
            if t.blocked_by:
                out.append(f"  _Blocked by: {', '.join(t.blocked_by)}_")
        out.append("")

    if parts["pending"]:
        out.append("## Pending")
        for t in parts["pending"]:
            out.append(f"- [ ] {t.subject}  _(id {t.id})_")
            desc = t.description.strip()
            if desc and desc != t.subject:
                out.append(f"  _{desc}_")
            if t.blocked_by:
                out.append(f"  _Blocked by: {', '.join(t.blocked_by)}_")
        out.append("")

    if parts["completed"]:
        out.append("## Completed")
        for t in parts["completed"]:
            out.append(f"- [x] ~~{t.subject}~~  _(id {t.id})_")
        out.append("")

    if parts["other"]:
        out.append("## Other / unknown status")
        for t in parts["other"]:
            out.append(f"- [{t.status}] {t.subject}  _(id {t.id})_")
        out.append("")

    return "\n".join(out)


def main() -> int:
    setup_utf8_stdout()
    sid = get_session_id()
    if not sid:
        print(
            "open-tasks: CLAUDE_CODE_SESSION_ID is not set.\n"
            "Run this from inside a Claude Code session (e.g. via the ! prefix).",
            file=sys.stderr,
        )
        return 1

    sdir = session_tasks_dir(sid)
    # Even an empty task dir gets a placeholder dashboard so the file always exists.
    sdir.mkdir(parents=True, exist_ok=True)

    tasks = load_session_tasks(sid)
    label = pretty_session(sid)
    if not tasks:
        body = (
            f"# Session {label} — Task List\n\n"
            f"*Generated {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n\n"
            f"*No tasks for this session yet.*\n"
        )
    else:
        body = render_dashboard(sid, tasks)

    out_path = sdir / "dashboard.md"
    out_path.write_text(body, encoding="utf-8")

    uri = build_obsidian_uri(OBSIDIAN_PATH_PREFIX, f"{sid}/dashboard")

    print(f"Session:    {label}")
    print(f"Dashboard:  {out_path}")
    print(f"Opening:    {uri}")
    launch_uri(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
