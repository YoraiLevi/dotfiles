#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Claude Code statusLine command: stdin JSON → ANSI status rows.

Segment types (DEFAULT_LAYOUT): version, session_id, session_name, cost, billing_wall,
billing_api, cost_session_lines, rate_limits, transcript_path (optional segment;
default layout uses ``transcript_below`` on the billing line instead),
model, agent, effort, thinking (includes ``fast_mode`` when on), tokens, context_pct
(``used/total (pct%)`` with ``K``/``M``-suffixed counts when size is present),
exceeds_200k, added_dirs, project_dir (``[branch ↑n↓m +a/−r] path``), cwd_or_worktree
(``[cwd branch ↑n↓m | +a/−r] path``; optional ``[worktree]``), output_style.

EOL: STATUSLINE_EOL=lf|crlf (env overrides DEFAULT_LINE_ENDING constant below).
Colors: enabled by default (Claude Code uses a pipe, not a TTY). Set NO_COLOR=1 to disable.

Invoke with uv as a standalone script (ignores adjacent pyproject): uv run --script statusline.py

Each run appends to ``statusline.log`` in this script's directory (stdin + stdout, plain text).
Valid stdin JSON is also written under ``statusline_stdin/`` as a timestamped ``.json`` file
(invalid JSON is stored as a matching ``*_invalid.txt``).

**Maintainers:** Add a ``seg_*`` function, register it in ``_bind()``, and reference it from
``DEFAULT_LAYOUT`` (or a custom layout dict). Git subprocess results for a resolved repo path
are cached for the duration of one ``render()`` call — see ``_repo_git_snap``. All ``git`` subprocesses go through ``_git_run`` (shared kwargs and error handling). Nested payload slices use ``_workspace`` / ``_cost`` / ``_context_window`` / ``_rate_limits`` / ``_thinking``.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

# Env overrides this when set: lf | crlf (case-insensitive)
DEFAULT_LINE_ENDING = "lf"

SCRIPT_DIR = Path(__file__).resolve().parent
EXECUTION_LOG_PATH = SCRIPT_DIR / "statusline.log"
STDIN_ARCHIVE_DIR = SCRIPT_DIR / "statusline_stdin"
WRITE_LOG = False

# Workspace row: if visible width exceeds this, +dirs / project / cwd use folder leaf names only.
WORKSPACE_LINE_MAX_VISIBLE = 80

WORKSPACE_COMPACT_TYPES = frozenset({"added_dirs", "project_dir", "cwd_or_worktree"})

# rate_limits payload keys → compact label for the status row
_RATE_LIMIT_WINDOWS: tuple[tuple[str, str], ...] = (
    ("five_hour", "5h"),
    ("seven_day", "7d"),
)

_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;:]*m")

RESET = "\033[0m"
DIM = "\033[2m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
CYAN = "\033[36m"


def use_color() -> bool:
    # Claude Code statusLine subprocess: stdout is piped, not a TTY — isatty() is false.
    return not os.environ.get("NO_COLOR")


def line_terminator() -> str:
    raw = os.environ.get("STATUSLINE_EOL", DEFAULT_LINE_ENDING).strip().lower()
    if raw in ("crlf", "dos", "windows"):
        return "\r\n"
    return "\n"


def _strip_ansi(s: str) -> str:
    return _ANSI_ESCAPE_RE.sub("", s)


def _visible_width(s: str) -> int:
    """Character cells for the rendered line (ANSI stripped)."""
    return len(_strip_ansi(s))


def _fit_path_suffix(path: str, width: int) -> str:
    """Trim path to ``width`` cells, keeping the right-hand end; pad left if shorter."""
    if width <= 0:
        return ""
    raw = path.replace("\n", " ").replace("\r", "")
    if len(raw) <= width:
        return raw.rjust(width)
    return raw[-width:]


def _stdin_archive_stem(ts: datetime) -> str:
    """Filesystem-safe UTC timestamp (aligned with log ``run`` line)."""
    return ts.strftime("%Y%m%dT%H%M%S_%f") + "Z"


def _write_stdin_archive(stdin_text: str, ts: datetime) -> None:
    """Save stdin next to the script: pretty ``.json`` if parseable, else ``*_invalid.txt``."""
    if not WRITE_LOG:
        return
    if not stdin_text.strip():
        return
    stem = _stdin_archive_stem(ts)
    try:
        STDIN_ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        data = json.loads(stdin_text)
        path = STDIN_ARCHIVE_DIR / f"{stem}.json"
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except json.JSONDecodeError:
        try:
            (STDIN_ARCHIVE_DIR / f"{stem}_invalid.txt").write_text(stdin_text, encoding="utf-8")
        except OSError:
            pass
    except OSError:
        pass


def _append_execution_log(
    stdin_text: str,
    stdout_text: str | None,
    *,
    error: str | None = None,
    exit_code: int = 0,
    run_at: datetime | None = None,
) -> None:
    """Append one run to EXECUTION_LOG_PATH; failures to write must not break the statusline."""
    at = run_at or datetime.now(timezone.utc)
    _write_stdin_archive(stdin_text, at)
    ts = at.isoformat()
    block: list[str] = [
        "=" * 80,
        f"--- run {ts} exit={exit_code} ---",
        "--- stdin ---",
        stdin_text if stdin_text else "(empty)",
        "",
    ]
    if error is not None:
        block.extend(["--- error ---", error, ""])
    if stdout_text is not None:
        block.extend(["--- stdout ---", _strip_ansi(stdout_text), ""])
    else:
        block.extend(["--- stdout ---", "(none)", ""])
    block.append("=" * 80)
    try:
        with EXECUTION_LOG_PATH.open("a", encoding="utf-8") as f:
            f.write("\n".join(block) + "\n\n")
    except OSError:
        pass


def stylize(enabled: bool, code: str, text: str) -> str:
    if not enabled or not text:
        return text
    return f"{code}{text}{RESET}"


def dim(enabled: bool, s: str) -> str:
    return stylize(enabled, DIM, s)


def green(enabled: bool, s: str) -> str:
    return stylize(enabled, GREEN, s)


def yellow(enabled: bool, s: str) -> str:
    return stylize(enabled, YELLOW, s)


def red(enabled: bool, s: str) -> str:
    return stylize(enabled, RED, s)


def cyan(enabled: bool, s: str) -> str:
    return stylize(enabled, CYAN, s)


def pct_colored(enabled: bool, pct: float | int | None, s: str) -> str:
    if pct is None or not enabled:
        return s
    p = float(pct)
    if p < 40:
        return green(enabled, s)
    if p < 75:
        return yellow(enabled, s)
    return red(enabled, s)


def _nested_str_field(d: dict[str, Any], section: str, *keys: str) -> str | None:
    """First truthy value among ``d[section][k]`` for each ``k`` (skips non-dict section)."""
    obj = d.get(section)
    if not isinstance(obj, dict):
        return None
    for k in keys:
        v = obj.get(k)
        if v:
            return str(v)
    return None


def _workspace(d: dict[str, Any]) -> dict[str, Any]:
    return d.get("workspace") or {}


def _cost(d: dict[str, Any]) -> dict[str, Any]:
    return d.get("cost") or {}


def _context_window(d: dict[str, Any]) -> dict[str, Any]:
    return d.get("context_window") or {}


def _rate_limits(d: dict[str, Any]) -> dict[str, Any]:
    rl = d.get("rate_limits")
    return rl if isinstance(rl, dict) else {}


def _thinking(d: dict[str, Any]) -> dict[str, Any]:
    t = d.get("thinking")
    return t if isinstance(t, dict) else {}


def fmt_time_until_reset(ts: Any) -> str:
    """Human-readable time remaining until resets_at (UTC).

    More than 24 hours left: compact days, e.g. ``3d`` or ``3d 4h``.
    Otherwise: ``hours:minutes`` until reset (same calendar day style, not clock time).
    """
    if ts is None:
        return "—"
    try:
        reset = datetime.fromtimestamp(float(ts), tz=timezone.utc)
    except (ValueError, TypeError, OSError):
        return str(ts)
    now = datetime.now(timezone.utc)
    sec = (reset - now).total_seconds()
    if sec <= 0:
        return "now"
    day_s = 86400.0
    if sec > 24 * 3600:
        days = int(sec // day_s)
        rem = sec - days * day_s
        rh = int(rem // 3600)
        if rh >= 1:
            return f"{days}d {rh}h"
        return f"{days}d"
    total_minutes = int(sec // 60)
    hours = total_minutes // 60
    minutes = total_minutes % 60
    return f"{hours}:{minutes:02d}"


def seg_session_id(d: dict[str, Any], uc: bool) -> str | None:
    raw = d.get("session_id")
    if not raw:
        return None
    sid = str(raw).split("-")[0][:8]
    if not sid:
        return None
    return dim(uc, sid)


def seg_session_name(d: dict[str, Any], uc: bool) -> str | None:
    name = d.get("session_name")
    if not name:
        return None
    return str(name)


def seg_transcript_path(d: dict[str, Any], uc: bool) -> str | None:
    path = d.get("transcript_path")
    if not path:
        return None
    return dim(uc, str(path))


def _resolve_git_path(raw: str) -> str:
    """Expand env/user and resolve existing dirs so ``git`` runs with a stable cwd."""
    p = Path(os.path.expandvars(os.path.expanduser(raw.strip())))
    try:
        if p.exists():
            return str(p.resolve())
    except OSError:
        pass
    return os.path.normpath(raw)


def _path_inside_or_same(child: str, parent: str) -> bool:
    """True if ``child`` resolves under ``parent`` (same directory allowed)."""
    try:
        c = Path(child).resolve()
        b = Path(parent).resolve()
        c.relative_to(b)
        return True
    except (ValueError, OSError):
        return False


def _parse_numstat(stdout: str) -> tuple[int, int]:
    added = removed = 0
    for line in stdout.splitlines():
        cols = line.split("\t")
        if len(cols) < 2:
            continue
        a, b = cols[0], cols[1]
        if a == "-" or b == "-":
            continue
        try:
            added += int(a)
            removed += int(b)
        except ValueError:
            continue
    return added, removed


# Shared by all ``git`` subprocess calls (avoid per-call dict allocation on hot path).
_GIT_SUBPROCESS_KW: dict[str, Any] = {
    "capture_output": True,
    "text": True,
    "encoding": "utf-8",
    "errors": "replace",
}
if sys.platform == "win32":
    _GIT_SUBPROCESS_KW["creationflags"] = subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]


def _git_run(
    args: list[str], *, cwd: str, timeout: float
) -> subprocess.CompletedProcess[str] | None:
    """Run ``git`` with shared kwargs; ``None`` on missing binary / OS errors / timeout."""
    try:
        return subprocess.run(
            ["git", *args],
            cwd=cwd,
            timeout=timeout,
            **_GIT_SUBPROCESS_KW,
        )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return None


@dataclass(frozen=True)
class _RepoGitSnap:
    """One-shot git subprocess bundle for a resolved working tree (used by segment formatters)."""

    accessible: bool
    label: str | None
    upstream_ab: tuple[int, int] | None
    numstat: tuple[int, int] | None


# Populated for the lifetime of one ``render()``; ``None`` when segments run outside ``render`` (rare).
_GIT_SNAP_CACHE: dict[str, _RepoGitSnap] | None = None


def _git_numstat_vs_head(repo_r: str) -> tuple[int, int] | None:
    """Insertions/deletions vs ``HEAD``, then unstaged + staged if ``HEAD`` diff fails."""
    diff = _git_run(["diff", "--numstat", "HEAD"], cwd=repo_r, timeout=12)
    if diff is None:
        return None

    if diff.returncode == 0:
        return _parse_numstat(diff.stdout or "")

    unst = _git_run(["diff", "--numstat"], cwd=repo_r, timeout=12)
    if unst is None:
        return None
    staged = _git_run(["diff", "--numstat", "--cached"], cwd=repo_r, timeout=12)
    if staged is None:
        return None
    if unst.returncode != 0 and staged.returncode != 0:
        return None
    ua, ur = _parse_numstat(unst.stdout or "") if unst.returncode == 0 else (0, 0)
    sa, sr = _parse_numstat(staged.stdout or "") if staged.returncode == 0 else (0, 0)
    return (ua + sa, ur + sr)


def _compute_repo_snap(repo_r: str) -> _RepoGitSnap:
    chk = _git_run(["rev-parse", "--git-dir"], cwd=repo_r, timeout=3)
    accessible = chk is not None and chk.returncode == 0

    if not accessible:
        return _RepoGitSnap(False, None, None, None)

    label: str | None = None
    b = _git_run(["rev-parse", "--abbrev-ref", "HEAD"], cwd=repo_r, timeout=3)
    if b is not None and b.returncode == 0:
        ref = (b.stdout or "").strip()
        if ref == "HEAD":
            sh = _git_run(["rev-parse", "--short", "HEAD"], cwd=repo_r, timeout=3)
            if sh is None:
                label = None
            elif sh.returncode == 0:
                label = (sh.stdout or "").strip()
            else:
                label = "(detached)"
        else:
            label = ref

    upstream_ab: tuple[int, int] | None = None
    u = _git_run(["rev-parse", "-q", "--verify", "@{upstream}"], cwd=repo_r, timeout=3)
    if u is not None and u.returncode == 0:
        ah = _git_run(["rev-list", "--count", "@{upstream}..HEAD"], cwd=repo_r, timeout=8)
        if ah is None:
            upstream_ab = None
        else:
            bh = _git_run(["rev-list", "--count", "HEAD..@{upstream}"], cwd=repo_r, timeout=8)
            if bh is None:
                upstream_ab = None
            else:
                try:
                    ahead = int((ah.stdout or "").strip() or "0") if ah.returncode == 0 else 0
                    behind = int((bh.stdout or "").strip() or "0") if bh.returncode == 0 else 0
                    upstream_ab = (ahead, behind)
                except ValueError:
                    upstream_ab = None

    numstat = _git_numstat_vs_head(repo_r)
    return _RepoGitSnap(True, label, upstream_ab, numstat)


def _repo_git_snap(repo_r: str) -> _RepoGitSnap:
    """Return git facts for ``repo_r`` (already resolved). Uses per-``render()`` cache when active."""
    if _GIT_SNAP_CACHE is not None and repo_r in _GIT_SNAP_CACHE:
        return _GIT_SNAP_CACHE[repo_r]
    snap = _compute_repo_snap(repo_r)
    if _GIT_SNAP_CACHE is not None:
        _GIT_SNAP_CACHE[repo_r] = snap
    return snap


def _snap_label_arrow_parts(snap: _RepoGitSnap) -> list[str]:
    """Branch label and upstream arrow fragment strings from a resolved git snap."""
    parts: list[str] = []
    if snap.label:
        parts.append(snap.label)
    if snap.upstream_ab is not None:
        ahead, behind = snap.upstream_ab
        arr = _fmt_track_arrows(ahead, behind)
        if arr:
            parts.append(arr)
    return parts


def _fmt_project_git_line(
    uc: bool, repo_r: str, path_tail_parts: int | None, base: str
) -> str:
    """``[branch ↑n … +a/−r] <path>`` when repo is a git checkout; else path tail only."""
    snap = _repo_git_snap(repo_r)
    if not snap.accessible:
        return _path_tail_display(base, path_tail_parts)

    left = _snap_label_arrow_parts(snap)
    stats = snap.numstat
    path_show = _path_tail_display(base, path_tail_parts)

    inner = [*left]
    if stats is not None:
        a, r_ = stats
        inner.append(_fmt_git_diff_pair(uc, a, r_))
    if not inner:
        return path_show
    return f"[{' '.join(inner)}] {path_show}"


def _fmt_cwd_git_line(
    uc: bool,
    path_tail_parts: int | None,
    cwd_raw: str,
    stats: tuple[int, int] | None,
    snap: _RepoGitSnap,
) -> str:
    """``[cwd branch … | +a/−r] <path>`` for an accessible git cwd (``stats`` may be ``None`` → ``0/0``)."""
    left = _snap_label_arrow_parts(snap)
    left_bits = ["cwd", *left]
    left_s = " ".join(left_bits)
    if stats is not None:
        da, dr = stats
        diff_s = _fmt_git_diff_pair(uc, da, dr)
    else:
        diff_s = _fmt_git_diff_pair(uc, 0, 0)
    path_show = _path_tail_display(str(cwd_raw), path_tail_parts)
    return f"[{left_s} | {diff_s}] {path_show}"


def _git_repo_accessible(repo_cwd: str) -> bool:
    """True if ``git rev-parse --git-dir`` succeeds in ``repo_cwd``."""
    key = _resolve_git_path(repo_cwd)
    return _repo_git_snap(key).accessible


def _git_diff_numstat_head(repo: str) -> tuple[int, int] | None:
    """Sum insertions/deletions vs ``HEAD``; cached per resolved repo for one ``render()``."""
    key = _resolve_git_path(repo)
    return _repo_git_snap(key).numstat


def _fmt_git_diff_pair(uc: bool, a: int, r: int) -> str:
    """Compact ``+a/−r`` for git diff vs ``HEAD`` (no ``[git]`` label)."""
    if not uc:
        return f"+{a}/−{r}"
    return green(uc, f"+{a}") + "/" + red(uc, f"−{r}")


def _path_tail_display(base: str, tail_parts: int | None) -> str:
    """Show the last ``tail_parts`` path components (``None`` = full path)."""
    norm = os.path.normpath(str(base))
    parts = Path(norm).parts
    if not parts:
        return str(base)
    if tail_parts is None:
        k = len(parts)
    else:
        k = min(max(int(tail_parts), 1), len(parts))
    seg = parts[-k:]
    return os.path.join(*seg) if len(seg) > 1 else seg[0]


def _path_part_count(path_str: str) -> int:
    norm = os.path.normpath(str(path_str))
    parts = Path(norm).parts
    return max(1, len(parts))


def _git_head_label(repo_r: str) -> str | None:
    return _repo_git_snap(_resolve_git_path(repo_r)).label


def _git_upstream_ahead_behind(repo_r: str) -> tuple[int, int] | None:
    """``(ahead, behind)`` vs ``@{upstream}``, or ``None`` if no upstream."""
    return _repo_git_snap(_resolve_git_path(repo_r)).upstream_ab


def _fmt_track_arrows(ahead: int, behind: int) -> str:
    if ahead <= 0 and behind <= 0:
        return ""
    parts: list[str] = []
    if ahead > 0:
        parts.append(f"↑{ahead}")
    if behind > 0:
        parts.append(f"↓{behind}")
    return "".join(parts)


def _fmt_ms_duration(ms: Any) -> str | None:
    try:
        ms_i = int(float(ms))
    except (TypeError, ValueError):
        return None
    if ms_i < 0:
        return None
    sec = ms_i // 1000
    if sec < 60:
        return f"{sec}s"
    minutes, s = divmod(sec, 60)
    if minutes < 60:
        return f"{minutes}m{s:02d}s" if s else f"{minutes}m"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h{minutes:02d}m" if minutes else f"{hours}h"


def _seg_cost_duration(d: dict[str, Any], uc: bool, *, ms_key: str, label: str) -> str | None:
    cost = _cost(d)
    ms = cost.get(ms_key)
    s = _fmt_ms_duration(ms)
    if not s:
        return None
    return f"{label} {s}" if not uc else f"{dim(uc, label)} {s}"


def seg_billing_wall(d: dict[str, Any], uc: bool) -> str | None:
    return _seg_cost_duration(d, uc, ms_key="total_duration_ms", label="wall")


def seg_billing_api(d: dict[str, Any], uc: bool) -> str | None:
    return _seg_cost_duration(d, uc, ms_key="total_api_duration_ms", label="API")


def seg_cost_session_lines(d: dict[str, Any], uc: bool) -> str | None:
    """Session/API line totals from ``cost`` (not git)."""
    cost = _cost(d)
    added = cost.get("total_lines_added")
    removed = cost.get("total_lines_removed")
    if added is None and removed is None:
        return None
    label = "usage"
    bits = []
    if added is not None:
        bits.append(f"+{added}" if not uc else green(uc, f"+{added}"))
    if removed is not None:
        bits.append(f"−{removed}" if not uc else red(uc, f"−{removed}"))
    if not bits:
        return None
    mid = "/".join(bits)
    return f"{label} {mid}" if not uc else f"{dim(uc, label)} {mid}"


def seg_model(d: dict[str, Any], uc: bool) -> str | None:
    return _nested_str_field(d, "model", "display_name", "id")


def seg_agent(d: dict[str, Any], uc: bool) -> str | None:
    return _nested_str_field(d, "agent", "name")


def seg_effort(d: dict[str, Any], uc: bool) -> str | None:
    return _nested_str_field(d, "effort", "level")


def seg_thinking(d: dict[str, Any], uc: bool) -> str | None:
    t = _thinking(d)
    en = t.get("enabled")
    chunks: list[str] = []
    if en is True:
        chunks.append(cyan(uc, "thinking ✓") if uc else "thinking ✓")
    elif en is False:
        chunks.append(dim(uc, "thinking ✗"))
    if d.get("fast_mode") is True:
        chunks.append(red(uc, "fast") if uc else "fast")
    return " · ".join(chunks) if chunks else None


def seg_tokens(d: dict[str, Any], uc: bool) -> str | None:
    cw = _context_window(d)
    inp = cw.get("total_input_tokens")
    out = cw.get("total_output_tokens")
    if inp is None and out is None:
        return None
    parts = []
    if inp is not None:
        parts.append(f"{inp}in")
    if out is not None:
        parts.append(f"{out}out")
    return " + ".join(parts)


def _fmt_tokens_km(n: int) -> str:
    """Compact token counts: ``K`` for thousands, ``M`` for millions (at most one decimal)."""
    if n < 0:
        return f"-{_fmt_tokens_km(-n)}"
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        v = n / 1000.0
        if abs(v - round(v)) < 1e-9:
            return f"{int(round(v))}K"
        s = f"{v:.1f}".rstrip("0").rstrip(".")
        return f"{s}K"
    v = n / 1_000_000.0
    if abs(v - round(v)) < 1e-9:
        return f"{int(round(v))}M"
    s = f"{v:.1f}".rstrip("0").rstrip(".")
    return f"{s}M"


def seg_context_pct(d: dict[str, Any], uc: bool) -> str | None:
    cw = _context_window(d)
    pct = cw.get("used_percentage")
    size = cw.get("context_window_size")
    if pct is None:
        return None
    try:
        pf = float(pct)
    except (TypeError, ValueError):
        chunk = f"{pct}%"
        return pct_colored(uc, None, chunk)

    pct_disp = int(round(pf))
    sz: int | None = None
    if size is not None:
        try:
            sz = int(float(size))
        except (TypeError, ValueError):
            sz = None

    if sz is not None:
        used = int(round(pf / 100.0 * float(sz)))
        used = max(0, min(used, sz))
        chunk = f"{_fmt_tokens_km(used)}/{_fmt_tokens_km(sz)} ({pct_disp}%)"
    else:
        chunk = f"{pct_disp}%"

    return pct_colored(uc, pf, chunk)


def seg_exceeds_200k(d: dict[str, Any], uc: bool) -> str | None:
    if d.get("exceeds_200k_tokens"):
        s = "[⚠ EXCEEDS 200k]"
        return red(uc, s) if uc else s
    return None


def seg_project_dir(
    d: dict[str, Any], uc: bool, *, path_tail_parts: int | None = None
) -> str | None:
    ws = _workspace(d)
    pdir = ws.get("project_dir")
    if not pdir:
        return None
    base = str(pdir)
    repo_r = _resolve_git_path(base)
    return _fmt_project_git_line(uc, repo_r, path_tail_parts, base)


def _fmt_usd_sig(v: float, sig: int = 3) -> str:
    """USD string with ``sig`` significant digits (e.g. ``.3g``)."""
    return f"${format(v, f'.{sig}g')}"


def seg_cost(d: dict[str, Any], uc: bool) -> str | None:
    cost = _cost(d)
    usd = cost.get("total_cost_usd")
    if usd is None:
        return None
    try:
        v = float(usd)
    except (TypeError, ValueError):
        return f"${usd}"
    return _fmt_usd_sig(v)


def seg_rate_limits(d: dict[str, Any], uc: bool) -> str | None:
    rl = _rate_limits(d)
    if not rl:
        return None
    parts: list[str] = []
    for win_key, label in _RATE_LIMIT_WINDOWS:
        bucket = rl.get(win_key) or {}
        pct = bucket.get("used_percentage")
        if pct is None:
            continue
        ps = f"{label}: {int(pct)}% ({fmt_time_until_reset(bucket.get('resets_at'))})"
        parts.append(pct_colored(uc, int(pct), ps))
    return "  ".join(parts) if parts else None


def _paths_effectively_same(a: str | None, b: str | None) -> bool:
    if not a or not b:
        return False
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


def seg_cwd_or_worktree(
    d: dict[str, Any], uc: bool, *, path_tail_parts: int | None = None
) -> str | None:
    ws = _workspace(d)
    cwd = ws.get("current_dir") or d.get("cwd")
    pdir = ws.get("project_dir")
    wt = ws.get("git_worktree")
    chunks: list[str] = []
    if wt:
        chunks.append(f"[worktree] {wt}")
    show_cwd = bool(cwd) and (
        not pdir or not _paths_effectively_same(str(cwd), str(pdir))
    )
    if not show_cwd:
        return "  ".join(chunks) if chunks else None

    cwd_n = _resolve_git_path(str(cwd))
    snap_cwd = _repo_git_snap(cwd_n)
    stats = snap_cwd.numstat
    if stats is None and pdir:
        pn = _resolve_git_path(str(pdir))
        if _path_inside_or_same(cwd_n, pn):
            stats = _repo_git_snap(pn).numstat

    if not snap_cwd.accessible:
        line = f"[cwd] {_path_tail_display(str(cwd), path_tail_parts)}"
    else:
        line = _fmt_cwd_git_line(uc, path_tail_parts, str(cwd), stats, snap_cwd)
    chunks.append(line)
    return "  ".join(chunks) if chunks else None


def seg_added_dirs(d: dict[str, Any], uc: bool, *, leaves_only: bool = False) -> str | None:
    ws = _workspace(d)
    dirs = ws.get("added_dirs") or []
    if not dirs:
        return None

    def fmt_one(x: Any) -> str:
        s = str(x).rstrip("/\\")
        if not leaves_only:
            return s
        name = Path(s).name
        return name if name else s

    shown = ", ".join(fmt_one(x) for x in dirs[:3])
    if len(dirs) > 3:
        shown += f" (+{len(dirs) - 3})"
    return f"+dirs: {shown}"


def seg_version(d: dict[str, Any], uc: bool) -> str | None:
    v = d.get("version")
    return f"v{v}" if v else None


def seg_output_style(d: dict[str, Any], uc: bool) -> str | None:
    return _nested_str_field(d, "output_style", "name")


def _bind(uc: bool) -> dict[str, Callable[[dict[str, Any]], str | None]]:
    def w(fn: Callable[[dict[str, Any], bool], str | None]) -> Callable[[dict[str, Any]], str | None]:
        return lambda d: fn(d, uc)

    return {
        "session_id": w(seg_session_id),
        "session_name": w(seg_session_name),
        "transcript_path": w(seg_transcript_path),
        "billing_wall": w(seg_billing_wall),
        "billing_api": w(seg_billing_api),
        "cost_session_lines": w(seg_cost_session_lines),
        "model": w(seg_model),
        "agent": w(seg_agent),
        "effort": w(seg_effort),
        "thinking": w(seg_thinking),
        "tokens": w(seg_tokens),
        "context_pct": w(seg_context_pct),
        "exceeds_200k": w(seg_exceeds_200k),
        "project_dir": w(seg_project_dir),
        "cost": w(seg_cost),
        "rate_limits": w(seg_rate_limits),
        "cwd_or_worktree": w(seg_cwd_or_worktree),
        "added_dirs": w(seg_added_dirs),
        "version": w(seg_version),
        "output_style": w(seg_output_style),
    }


DEFAULT_LAYOUT: dict[str, Any] = {
    "lines": [
        {
            "separator": " | ",
            "segments": [
                {"type": "version"},
                {"type": "session_id"},
                {"type": "session_name"},
            ],
        },
        {
            "separator": " | ",
            "segments": [
                {"type": "added_dirs"},
                {"type": "project_dir"},
                {"type": "cwd_or_worktree"},
            ],
        },
        {
            "separator": " · ",
            "segments": [
                {"type": "model"},
                {"type": "agent"},
                {"type": "output_style"},
                {"type": "effort"},
                {"type": "thinking"},
                {"type": "context_pct"},
                {"type": "exceeds_200k"},
            ],
        },
        {
            "separator": " | ",
            "segments": [
                {"type": "cost"},
                {"type": "billing_wall"},
                {"type": "billing_api"},
                {"type": "cost_session_lines"},
                {"type": "rate_limits"},
            ],
            "transcript_below": True,
        },
    ]
}


def _workspace_row_join(
    payload: dict[str, Any],
    uc: bool,
    sep: str,
    proj_parts: int,
    cwd_parts: int,
    dirs_leaves: bool,
) -> str:
    parts: list[str] = []
    ad = seg_added_dirs(payload, uc, leaves_only=dirs_leaves)
    if ad:
        parts.append(ad)
    pd = seg_project_dir(payload, uc, path_tail_parts=proj_parts)
    if pd:
        parts.append(pd)
    cw = seg_cwd_or_worktree(payload, uc, path_tail_parts=cwd_parts)
    if cw:
        parts.append(cw)
    return sep.join(parts)


def _best_workspace_tails(payload: dict[str, Any], uc: bool, sep: str) -> tuple[int, int, bool]:
    """Pick path tail depths (+dirs leaf mode) so the workspace row fits in ``WORKSPACE_LINE_MAX_VISIBLE`` while maximizing tail depth."""
    ws = _workspace(payload)
    pdir = ws.get("project_dir")
    cwd_raw = ws.get("current_dir") or payload.get("cwd")
    show_cwd = bool(cwd_raw) and (
        not pdir or not _paths_effectively_same(str(cwd_raw), str(pdir))
    )

    max_pk = _path_part_count(pdir) if pdir else 1
    max_ck = _path_part_count(cwd_raw) if show_cwd and cwd_raw else 1

    row = _workspace_row_join(payload, uc, sep, max_pk, max_ck, False)
    if _visible_width(row) <= WORKSPACE_LINE_MAX_VISIBLE:
        return max_pk, max_ck, False

    row = _workspace_row_join(payload, uc, sep, max_pk, max_ck, True)
    if _visible_width(row) <= WORKSPACE_LINE_MAX_VISIBLE:
        return max_pk, max_ck, True

    pk, ck = 1, 1
    dirs_leaves = True
    while True:
        row = _workspace_row_join(payload, uc, sep, pk, ck, dirs_leaves)
        if _visible_width(row) > WORKSPACE_LINE_MAX_VISIBLE:
            break
        grown = False
        if pk < max_pk:
            test = _workspace_row_join(payload, uc, sep, pk + 1, ck, dirs_leaves)
            if _visible_width(test) <= WORKSPACE_LINE_MAX_VISIBLE:
                pk += 1
                grown = True
                continue
        if ck < max_ck:
            test = _workspace_row_join(payload, uc, sep, pk, ck + 1, dirs_leaves)
            if _visible_width(test) <= WORKSPACE_LINE_MAX_VISIBLE:
                ck += 1
                grown = True
                continue
        if not grown:
            break
    return pk, ck, dirs_leaves


def _collect_line_parts(
    line: dict[str, Any],
    segs: dict[str, Callable[[dict[str, Any]], str | None]],
    payload: dict[str, Any],
) -> list[str]:
    parts: list[str] = []
    for seg in line["segments"]:
        fn = segs.get(seg["type"])
        if fn is None:
            continue
        piece = fn(payload)
        if piece:
            parts.append(piece)
    return parts


def render(layout: dict[str, Any], payload: dict[str, Any], uc: bool) -> str:
    global _GIT_SNAP_CACHE
    prev_cache = _GIT_SNAP_CACHE
    _GIT_SNAP_CACHE = {}
    try:
        segs = _bind(uc)
        eol = line_terminator()
        rows = []
        for line in layout["lines"]:
            sep = line["separator"]
            types = {s["type"] for s in line["segments"]}
            if types == WORKSPACE_COMPACT_TYPES:
                pk, ck, dleaves = _best_workspace_tails(payload, uc, sep)
                row = _workspace_row_join(payload, uc, sep, pk, ck, dleaves)
            else:
                parts = _collect_line_parts(line, segs, payload)
                row = sep.join(parts)
            rows.append(row)
            if line.get("transcript_below"):
                tp = payload.get("transcript_path")
                if tp:
                    w = _visible_width(row)
                    if w > 0:
                        fitted = _fit_path_suffix(str(tp), w)
                        rows.append(dim(uc, fitted))
        return eol.join(rows) + eol
    finally:
        _GIT_SNAP_CACHE = prev_cache


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        _append_execution_log(raw, "", exit_code=0)
        return 0
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"statusline: invalid JSON: {e}", file=sys.stderr)
        _append_execution_log(raw, None, error=str(e), exit_code=1)
        return 1

    if not isinstance(payload, dict):
        print("statusline: expected JSON object", file=sys.stderr)
        _append_execution_log(raw, None, error="expected JSON object", exit_code=1)
        return 1

    uc = use_color()
    out = render(DEFAULT_LAYOUT, payload, uc)
    _append_execution_log(raw, out, exit_code=0)
    sys.stdout.buffer.write(out.encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
