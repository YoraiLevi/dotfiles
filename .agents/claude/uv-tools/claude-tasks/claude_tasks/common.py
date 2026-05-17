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
from typing import Iterator

import psutil

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


def _ancestor_pids(max_depth: int = 32) -> Iterator[int]:
    """Yield PIDs walking up the process tree from our parent.

    Stops when no further ancestor exists, on access errors, on cycles, or
    when ``max_depth`` is reached. Never raises — callers can iterate freely.
    """
    try:
        proc = psutil.Process().parent()
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.Error):
        return
    seen: set[int] = set()
    depth = 0
    while proc is not None and depth < max_depth:
        try:
            pid = proc.pid
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            return
        if pid in seen:
            return  # cycle guard — shouldn't happen but cheap insurance
        seen.add(pid)
        yield pid
        depth += 1
        try:
            proc = proc.parent()
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.Error):
            return


def _read_pid_session_file(path: Path, expected_session_id: str) -> str | None:
    """Open a ``<pid>.json`` file. Return its ``name`` iff ``sessionId`` matches."""
    try:
        with path.open("r", encoding="utf-8") as f:
            obj = json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return None
    if not isinstance(obj, dict):
        return None
    if str(obj.get("sessionId", "")) != expected_session_id:
        return None
    name = obj.get("name")
    if isinstance(name, str) and name:
        return name
    return None


def get_session_name(session_id: str) -> str | None:
    """The human-readable name for ``session_id`` (e.g. ``add-task-progress-statusline``).

    Claude Code writes one ``<pid>.json`` per running session under
    ``~/.claude/sessions/``. Two-strategy lookup:

    1. **Fast path** — walk our parent processes and check
       ``~/.claude/sessions/<ancestor_pid>.json``. Returns on first match.
       Typically finds Claude within 1–5 levels.
    2. **Fallback** — scan every ``*.json`` in the directory. Handles cases
       where Claude isn't a direct ancestor (e.g., the env var was set by
       hand, or this tool was invoked from a detached process).

    Returns ``None`` if no matching file is found or no name is recorded.
    """
    if not SESSIONS_DIR.is_dir():
        return None

    # Fast path: walk parent PIDs.
    for pid in _ancestor_pids():
        candidate = SESSIONS_DIR / f"{pid}.json"
        if candidate.is_file():
            name = _read_pid_session_file(candidate, session_id)
            if name is not None:
                return name

    # Fallback: full directory scan.
    try:
        entries = list(SESSIONS_DIR.glob("*.json"))
    except OSError:
        return None
    for path in entries:
        name = _read_pid_session_file(path, session_id)
        if name is not None:
            return name
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
