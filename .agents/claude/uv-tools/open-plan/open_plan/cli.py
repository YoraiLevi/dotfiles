"""Open the current Claude Code session's plan file in Obsidian.

Resolution order (first hit wins):
  1. Session-aware: read ``$CLAUDE_CODE_SESSION_ID`` (set by Claude Code in
     every shell it spawns), locate the matching transcript JSONL under
     ``~/.claude/projects/``, and extract the canonical plan path by matching
     the unique discriminator phrases the harness injects in plan-mode system
     reminders.
  2. Fallback: most-recently-modified ``*.md`` under ``~/.claude/plans/``.

The chosen method is printed as ``Resolution:`` so the caller always knows
which logic answered.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import urllib.parse
from datetime import datetime
from pathlib import Path

PLANS_DIR = Path.home() / ".claude" / "plans"
PROJECTS_DIR = Path.home() / ".claude" / "projects"

# Hardcoded: every Claude-related uv-tool on this machine opens files inside
# the `.claude` Obsidian vault (covers ~/.claude/ — plans, tasks, projects,
# everything). Files are addressed relative to ~/.claude/ in the URI.
OBSIDIAN_VAULT = ".claude"
OBSIDIAN_PATH_PREFIX = "plans"

# Match phrases that ONLY appear in plan-mode system reminders injected by the
# Claude Code harness:
#   "You should create your plan at C:\\Users\\...\\plans\\<file>.md ..."
#   "Your plan has been saved to: C:\\Users\\...\\plans\\<file>.md"
# [^"]* confines the match to a single JSON string field (the JSONL is JSON-per-line).
# [\\/]+ handles both forward slashes and JSON-escaped backslash pairs.
_DISCRIMINATOR_RE = re.compile(
    r'(?:You should create your plan at|Your plan has been saved to)'
    r'[^"]*plans[\\/]+([a-zA-Z0-9_.-]+\.md)'
)


def _find_session_transcript(session_id: str) -> Path | None:
    """Locate ``~/.claude/projects/*/<session_id>.jsonl``."""
    if not PROJECTS_DIR.is_dir():
        return None
    needle = f"{session_id}.jsonl"
    for path in PROJECTS_DIR.rglob(needle):
        if path.is_file():
            return path
    return None


def _resolve_via_session() -> tuple[str | None, str | None]:
    """Return (basename, resolution_label) using the session-aware path."""
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if not sid:
        return None, None
    transcript = _find_session_transcript(sid)
    if not transcript:
        return None, None
    try:
        content = transcript.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None, None
    matches = _DISCRIMINATOR_RE.findall(content)
    if not matches:
        return None, None
    # Last match wins: handles plan-mode re-entry within a single session.
    basename = matches[-1]
    if not (PLANS_DIR / basename).is_file():
        return None, None
    return basename, f"session {sid[:8]} (transcript discriminator)"


def _resolve_latest() -> tuple[str | None, str | None]:
    """Return (basename, resolution_label) using the latest-modified fallback."""
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


def _open_uri(uri: str) -> None:
    """Hand off ``uri`` to the OS's registered protocol handler."""
    if sys.platform == "win32":
        # os.startfile handles protocol URIs natively on Windows.
        os.startfile(uri)  # type: ignore[attr-defined]  # noqa: S606
    elif sys.platform == "darwin":
        subprocess.run(["open", uri], check=False)
    else:
        subprocess.run(["xdg-open", uri], check=False)


def main() -> int:
    basename, resolution = _resolve_via_session()
    if not basename:
        basename, resolution = _resolve_latest()

    if not basename:
        print(f"No plans found in {PLANS_DIR}", file=sys.stderr)
        return 1

    plan_path = PLANS_DIR / basename
    try:
        mtime = datetime.fromtimestamp(plan_path.stat().st_mtime)
    except OSError:
        mtime = None

    # File parameter is path relative to vault root, e.g. ``plans/<stem>``.
    # safe='/' preserves the path separator inside the URI's file= value.
    vault_relative = f"{OBSIDIAN_PATH_PREFIX}/{plan_path.stem}"
    encoded_file = urllib.parse.quote(vault_relative, safe="/")
    encoded_vault = urllib.parse.quote(OBSIDIAN_VAULT, safe="")
    uri = f"obsidian://open?vault={encoded_vault}&file={encoded_file}"

    print(f"Plan:       {basename}")
    print(f"Resolution: {resolution}")
    if mtime is not None:
        print(f"Modified:   {mtime}")
    print(f"Opening:    {uri}")

    _open_uri(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
