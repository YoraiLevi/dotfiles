"""``open-plan`` — open the current Claude Code session's plan file in Obsidian.

Resolution order (first hit wins):

1. **Session-aware**: read ``$CLAUDE_CODE_SESSION_ID`` (set by Claude Code in
   every shell it spawns), locate the matching transcript JSONL under
   ``~/.claude/projects/``, and extract the canonical plan path by matching
   the unique discriminator phrases the harness injects in plan-mode system
   reminders.
2. **Fallback**: the most-recently-modified ``*.md`` under ``~/.claude/plans/``.

The chosen method is printed as ``Resolution:`` so the caller always knows
which logic answered.

Originally a standalone uv-tool at ``~/.agents/claude/uv-tools/open-plan/``;
folded into ``claude-tasks`` so all three Claude-related uv-tools share one
package (common session/transcript/Obsidian helpers in ``common.py``).
"""

from __future__ import annotations

import re
import sys
from datetime import datetime

from .common import (
    PLANS_DIR,
    build_obsidian_uri,
    find_session_transcript,
    get_session_id,
    launch_uri,
    setup_utf8_stdout,
)

# This tool's files live under ``plans/`` relative to the ``.claude`` vault.
OBSIDIAN_PATH_PREFIX = "plans"

# Match phrases that ONLY appear in plan-mode system reminders injected by
# the Claude Code harness:
#   "You should create your plan at C:\\Users\\...\\plans\\<file>.md ..."
#   "Your plan has been saved to: C:\\Users\\...\\plans\\<file>.md"
# ``[^"]*`` confines the match to a single JSON string field (transcript is
# JSON-per-line). ``[\\/]+`` handles both forward slashes and JSON-escaped
# backslash pairs that appear in stringified Windows paths.
_DISCRIMINATOR_RE = re.compile(
    r'(?:You should create your plan at|Your plan has been saved to)'
    r'[^"]*plans[\\/]+([a-zA-Z0-9_.-]+\.md)'
)


def _resolve_via_session() -> tuple[str | None, str | None]:
    """Return ``(basename, resolution_label)`` using the session-aware path."""
    sid = get_session_id()
    if not sid:
        return None, None
    transcript = find_session_transcript(sid)
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
    """Return ``(basename, resolution_label)`` using the latest-modified fallback."""
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


def main() -> int:
    setup_utf8_stdout()

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

    uri = build_obsidian_uri(OBSIDIAN_PATH_PREFIX, plan_path.stem)

    print(f"Plan:       {basename}")
    print(f"Resolution: {resolution}")
    if mtime is not None:
        print(f"Modified:   {mtime}")
    print(f"Opening:    {uri}")

    launch_uri(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
