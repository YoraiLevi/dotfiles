"""``claude-tasks`` — open a unified session dashboard in Obsidian.

The dashboard at ``~/.claude/tasks/<session_id>/dashboard.md`` is rendered
fresh each invocation. It has two halves, separated by a horizontal rule:

1. **Tasks** — the current session's tasks, grouped by status with the
   summary counts and the active ``activeForm`` highlighted.
2. **Plan** — the verbatim body of the session's plan markdown file
   (resolved via the transcript discriminator, with a latest-modified
   fallback). Its header levels are demoted by one so they nest cleanly
   under the dashboard's existing structure.

The dashboard is then launched in the ``.claude`` Obsidian vault via
``obsidian://open?vault=.claude&file=tasks/<session_id>/dashboard``.

This module replaces the separate ``open-tasks`` and ``open-plan`` commands
that previously existed. They produced two parallel views; this single view
shows everything relevant to the active session in one place.
"""

from __future__ import annotations

import re
import sys
from datetime import datetime

from .common import (
    PLANS_DIR,
    Task,
    build_obsidian_uri,
    find_session_transcript,
    get_session_id,
    launch_uri,
    load_session_tasks,
    partition_by_status,
    pretty_session,
    session_tasks_dir,
    setup_utf8_stdout,
)

OBSIDIAN_PATH_PREFIX = "tasks"

# Phrases injected ONLY by the Claude Code harness into plan-mode system
# reminders. ``[^"]*`` confines the match to a single JSON string field in
# the transcript JSONL; ``[\\/]+`` handles both forward slashes and the
# JSON-escaped backslash pairs that appear in stringified Windows paths.
_PLAN_DISCRIMINATOR_RE = re.compile(
    r'(?:You should create your plan at|Your plan has been saved to)'
    r'[^"]*plans[\\/]+([a-zA-Z0-9_.-]+\.md)'
)

# Promote every ATX header up to H5 by one level — so the plan's `# Title`
# becomes `## Title` when nested under the dashboard's H1.
_HEADER_DEMOTE_RE = re.compile(r'^(#{1,5})(?= )', flags=re.MULTILINE)


def _render_tasks_section(session_id: str, tasks: list[Task]) -> str:
    parts = partition_by_status(tasks)
    done = len(parts["completed"])
    active = len(parts["in_progress"])
    pending = len(parts["pending"])
    total = len(tasks)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    label = pretty_session(session_id)

    out: list[str] = [
        f"# Session {label}",
        "",
        f"*Generated {now}*",
        "",
    ]
    if not tasks:
        out.append("## Tasks")
        out.append("")
        out.append("*No tasks for this session yet.*")
        out.append("")
        return "\n".join(out)

    out.append(f"## Tasks — {done} done / {active} active / {pending} pending  ({total} total)")
    out.append("")

    if parts["in_progress"]:
        out.append("### In progress")
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
        out.append("### Pending")
        for t in parts["pending"]:
            out.append(f"- [ ] {t.subject}  _(id {t.id})_")
            desc = t.description.strip()
            if desc and desc != t.subject:
                out.append(f"  _{desc}_")
            if t.blocked_by:
                out.append(f"  _Blocked by: {', '.join(t.blocked_by)}_")
        out.append("")

    if parts["completed"]:
        out.append("### Completed")
        for t in parts["completed"]:
            out.append(f"- [x] ~~{t.subject}~~  _(id {t.id})_")
        out.append("")

    if parts["other"]:
        out.append("### Other / unknown status")
        for t in parts["other"]:
            out.append(f"- [{t.status}] {t.subject}  _(id {t.id})_")
        out.append("")

    return "\n".join(out)


def _resolve_plan_via_session(session_id: str) -> tuple[str | None, str | None]:
    transcript = find_session_transcript(session_id)
    if not transcript:
        return None, None
    try:
        content = transcript.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None, None
    matches = _PLAN_DISCRIMINATOR_RE.findall(content)
    if not matches:
        return None, None
    basename = matches[-1]
    if not (PLANS_DIR / basename).is_file():
        return None, None
    return basename, f"session {session_id[:8]} (transcript discriminator)"


def _resolve_plan_latest() -> tuple[str | None, str | None]:
    if not PLANS_DIR.is_dir():
        return None, None
    try:
        plans = sorted(
            PLANS_DIR.glob("*.md"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return None, None
    if not plans:
        return None, None
    return plans[0].name, "latest-modified (no session match)"


def _render_plan_section(session_id: str) -> str:
    basename, resolution = _resolve_plan_via_session(session_id)
    if not basename:
        basename, resolution = _resolve_plan_latest()

    out: list[str] = ["---", ""]

    if not basename:
        out.append("## Plan")
        out.append("")
        out.append("_No plan file found._")
        out.append("")
        return "\n".join(out)

    plan_path = PLANS_DIR / basename
    try:
        plan_body = plan_path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        out.append(f"## Plan — {basename}")
        out.append("")
        out.append(f"_Failed to read plan: {e}_")
        out.append("")
        return "\n".join(out)

    try:
        mtime = datetime.fromtimestamp(plan_path.stat().st_mtime)
    except OSError:
        mtime = None

    out.append(f"## Plan — {basename}")
    out.append("")
    out.append(f"_{resolution}_")
    if mtime is not None:
        out.append(f"_Modified {mtime}_")
    out.append("")
    out.append(_HEADER_DEMOTE_RE.sub(r"#\1", plan_body))
    return "\n".join(out)


def main() -> int:
    setup_utf8_stdout()
    sid = get_session_id()
    if not sid:
        print(
            "claude-tasks: CLAUDE_CODE_SESSION_ID is not set.\n"
            "Run this from inside a Claude Code session (e.g. via the ! prefix).",
            file=sys.stderr,
        )
        return 1

    sdir = session_tasks_dir(sid)
    sdir.mkdir(parents=True, exist_ok=True)

    tasks = load_session_tasks(sid)
    body_tasks = _render_tasks_section(sid, tasks)
    body_plan = _render_plan_section(sid)
    body = body_tasks + "\n" + body_plan + "\n"

    out_path = sdir / "dashboard.md"
    out_path.write_text(body, encoding="utf-8")

    uri = build_obsidian_uri(OBSIDIAN_PATH_PREFIX, f"{sid}/dashboard")
    label = pretty_session(sid)

    print(f"Session:    {label}")
    print(f"Dashboard:  {out_path}")
    print(f"Opening:    {uri}")
    launch_uri(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
