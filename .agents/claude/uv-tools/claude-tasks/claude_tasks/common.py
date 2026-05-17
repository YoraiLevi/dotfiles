"""Shared task-loading helpers for ``list-tasks`` and ``open-tasks``.

Reads the same on-disk format as the statusline's ``seg_tasks``:
``~/.claude/tasks/<session_id>/<task_id>.json``, one JSON object per task with
``id``, ``subject``, ``description``, ``activeForm``, ``status``, ``blocks``,
and ``blockedBy`` fields. Files written mid-tick or otherwise malformed are
skipped silently — these CLIs must never crash on a partially-written file.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path

TASKS_DIR = Path.home() / ".claude" / "tasks"
SESSIONS_DIR = Path.home() / ".claude" / "sessions"

KNOWN_STATUSES = ("in_progress", "pending", "completed")


@dataclass(frozen=True)
class Task:
    id: int
    subject: str
    description: str
    active_form: str
    status: str
    blocks: tuple[str, ...]
    blocked_by: tuple[str, ...]


def get_session_id() -> str | None:
    """The current Claude Code session UUID, or None when invoked outside Claude Code."""
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    return sid if sid else None


def get_session_name(session_id: str) -> str | None:
    """The human-readable name for ``session_id`` (e.g. ``add-task-progress-statusline``).

    Claude Code writes one ``<pid>.json`` per running session under
    ``~/.claude/sessions/``. Each file has ``sessionId`` and ``name`` fields;
    scan them to find the entry matching our session. Returns ``None`` if no
    matching file exists or no name is recorded — callers should fall back to
    the bare session id for display.
    """
    if not SESSIONS_DIR.is_dir():
        return None
    try:
        entries = list(SESSIONS_DIR.glob("*.json"))
    except OSError:
        return None
    for path in entries:
        try:
            with path.open("r", encoding="utf-8") as f:
                obj = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(obj, dict):
            continue
        if str(obj.get("sessionId", "")) != session_id:
            continue
        name = obj.get("name")
        if isinstance(name, str) and name:
            return name
        return None
    return None


def pretty_session(session_id: str) -> str:
    """``<short_id> | <name>`` if a name is registered; otherwise just ``<short_id>``."""
    short = session_id[:8]
    name = get_session_name(session_id)
    return f"{short} | {name}" if name else short


def setup_utf8_stdout() -> None:
    """Reconfigure stdout/stderr to UTF-8 so Unicode glyphs like ``✓ ▶ ○`` work
    on Windows, whose default cp1252 codec raises ``UnicodeEncodeError`` on them.

    Safe to call from any entry point; no-op if reconfigure isn't supported."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, OSError):
            pass


def session_tasks_dir(session_id: str) -> Path:
    return TASKS_DIR / session_id


def load_session_tasks(session_id: str) -> list[Task]:
    """All tasks for ``session_id``, sorted by numeric id. Empty list on any failure."""
    sdir = session_tasks_dir(session_id)
    if not sdir.is_dir():
        return []
    try:
        entries = list(sdir.glob("*.json"))
    except OSError:
        return []

    def sort_key(p: Path) -> tuple[int, int, str]:
        try:
            return (0, int(p.stem), "")
        except ValueError:
            return (1, 0, p.stem)

    tasks: list[Task] = []
    for path in sorted(entries, key=sort_key):
        try:
            with path.open("r", encoding="utf-8") as f:
                obj = json.load(f)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if not isinstance(obj, dict):
            continue
        try:
            tid = int(obj.get("id", 0))
        except (TypeError, ValueError):
            continue
        tasks.append(
            Task(
                id=tid,
                subject=str(obj.get("subject", "")),
                description=str(obj.get("description", "")),
                active_form=str(obj.get("activeForm", "")),
                status=str(obj.get("status", "pending")),
                blocks=tuple(str(x) for x in (obj.get("blocks") or [])),
                blocked_by=tuple(str(x) for x in (obj.get("blockedBy") or [])),
            )
        )
    return tasks


def partition_by_status(tasks: list[Task]) -> dict[str, list[Task]]:
    """Group tasks: ``in_progress``, ``pending``, ``completed``, ``other`` (unknown statuses)."""
    buckets: dict[str, list[Task]] = {s: [] for s in KNOWN_STATUSES}
    buckets["other"] = []
    for t in tasks:
        bucket = t.status if t.status in KNOWN_STATUSES else "other"
        buckets[bucket].append(t)
    return buckets
