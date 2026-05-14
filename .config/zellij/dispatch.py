"""Zellij action dispatcher — single source of truth, installed via uv tool.

config.kdl invokes us as `zellij-dispatch <action>`. Two dispatch paths:

  1. Python-implemented actions registered in HANDLERS (e.g. `launch-profile`)
     run inline — no subprocess, no fzf, stdlib only.
  2. Anything else is resolved as `scripts/<action>.{ps1,sh}` and shelled out.

Naming convention is the registry — drop a `scripts/<name>.ps1`/`<name>.sh`
pair and it's invocable without editing this file.
"""
from __future__ import annotations

import contextlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Iterator

# We're installed via `uv tool install`, so __file__ lives in a venv — not in
# ~/.config/zellij/. Resolve config paths from $HOME directly.
HOME = Path.home()
CONFIG_DIR = HOME / ".config" / "zellij"
SCRIPTS = CONFIG_DIR / "scripts"
PROFILES_JSON = CONFIG_DIR / "profiles.json"
WT_SETTINGS = (
    HOME / "AppData" / "Local" / "Packages"
    / "Microsoft.WindowsTerminal_8wekyb3d8bbwe" / "LocalState" / "settings.json"
)

OS_KEY = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(
    platform.system()
)


# Windows-only %VAR% expansion. We avoid os.path.expandvars on Windows because it
# also expands $VAR / ${VAR}, which mangles PowerShell commandlines that contain
# literal $variable references (e.g. `$InformationPreference=$ENV:Foo`). Mirrors
# [Environment]::ExpandEnvironmentVariables: only %VAR% is touched, unset vars
# are left as the literal text.
_PERCENT_VAR = re.compile(r"%([^%\s]+)%")


def _expand_env(s: str) -> str:
    if platform.system() == "Windows":
        return _PERCENT_VAR.sub(
            lambda m: os.environ.get(m.group(1), m.group(0)), s
        )
    return os.path.expandvars(s)


def main() -> int:
    args = sys.argv[1:]
    if not args:
        actions = sorted(_list_actions())
        msg = "usage: zellij-dispatch <action> [args...]"
        if actions:
            msg += f"\nactions: {', '.join(actions)}"
        print(msg, file=sys.stderr)
        return 2

    action, rest = args[0], args[1:]
    handler = HANDLERS.get(action)
    if handler is not None:
        return handler(rest)
    return _run_script_action(action, rest)


# ── Action discovery ──────────────────────────────────────────────────────────

def _list_actions() -> set[str]:
    known = set(HANDLERS)
    if SCRIPTS.is_dir():
        ext = "ps1" if platform.system() == "Windows" else "sh"
        known |= {p.stem for p in SCRIPTS.glob(f"*.{ext}")}
    return known


def _run_script_action(action: str, rest: list[str]) -> int:
    ext = "ps1" if platform.system() == "Windows" else "sh"
    script = SCRIPTS / f"{action}.{ext}"
    if not script.exists():
        print(
            f"zellij-dispatch: no implementation at {script}", file=sys.stderr
        )
        return 2
    if platform.system() == "Windows":
        cmd = ["pwsh", "-NoProfile", "-NoLogo", "-File", str(script), *rest]
    else:
        cmd = [str(script), *rest]
    return subprocess.call(cmd)


# ── JSONC parsing ─────────────────────────────────────────────────────────────

_TRAILING_COMMA = re.compile(r",(\s*[\]}])")


def _read_jsonc(path: Path) -> Any:
    """Read a JSON file that may contain // line comments and trailing commas.

    WT's settings.json is JSONC, and profiles.json gets edited by hand — being
    permissive here costs ~10 lines and avoids a class of frustrating errors.
    """
    text = path.read_text(encoding="utf-8-sig")
    out: list[str] = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        c = text[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return json.loads(_TRAILING_COMMA.sub(r"\1", "".join(out)))


# ── launch-profile ────────────────────────────────────────────────────────────

def launch_profile(_args: list[str]) -> int:
    with _single_instance_lock():
        profiles = _load_profiles()
        if not profiles:
            print("launch-profile: no profiles found", file=sys.stderr)
            return 1

        pick = _pick_profile(profiles)
        if pick is None:
            return 0

        if platform.system() == "Windows":
            return _spawn_windows(pick)
        return _spawn_posix(pick)


def _load_profiles() -> list[dict[str, Any]]:
    """Resolve profiles for this OS. On Windows, merge in Windows Terminal.

    Internal record: {name, command (list[str]) OR commandline (str), env, cwd, source}.
    """
    if OS_KEY is None:
        return []
    resolved: list[dict[str, Any]] = []
    seen: set[str] = set()

    # 1. profiles.json — explicit, takes precedence on name clash.
    if PROFILES_JSON.is_file():
        try:
            data = _read_jsonc(PROFILES_JSON)
            for p in data.get("profiles", []):
                entry = p.get(OS_KEY)
                if not (entry and entry.get("command")):
                    continue
                cmd = [_expand_env(str(a)) for a in entry["command"]]
                env = {
                    k: _expand_env(str(v))
                    for k, v in (entry.get("env") or {}).items()
                }
                cwd = entry.get("cwd")
                if cwd:
                    cwd = os.path.expanduser(_expand_env(cwd))
                resolved.append({
                    "name": p["name"],
                    "command": cmd,
                    "env": env,
                    "cwd": cwd,
                    "source": "json",
                })
                seen.add(p["name"])
        except (json.JSONDecodeError, OSError, KeyError) as e:
            print(
                f"warning: failed to read {PROFILES_JSON}: {e}",
                file=sys.stderr,
            )

    # 2. Windows Terminal — merge auto-discovered profiles, JSON wins on clash.
    if platform.system() == "Windows" and WT_SETTINGS.is_file():
        try:
            wt = _read_jsonc(WT_SETTINGS)
            wt_profiles = wt.get("profiles", {})
            defaults_env_raw = (wt_profiles.get("defaults") or {}).get(
                "environment"
            ) or {}
            defaults_env = {
                k: _expand_env(str(v))
                for k, v in defaults_env_raw.items()
            }
            for wp in wt_profiles.get("list", []):
                if wp.get("hidden") or not wp.get("commandline"):
                    continue
                if wp.get("name") in seen:
                    continue
                env = dict(defaults_env)
                for k, v in (wp.get("environment") or {}).items():
                    env[k] = _expand_env(str(v))
                cwd = wp.get("startingDirectory")
                if cwd:
                    cwd = _expand_env(cwd)
                resolved.append({
                    "name": wp["name"],
                    "commandline": _expand_env(wp["commandline"]),
                    "env": env,
                    "cwd": cwd,
                    "source": "wt",
                })
                seen.add(wp["name"])
        except (json.JSONDecodeError, OSError, KeyError) as e:
            print(
                f"warning: failed to read Windows Terminal settings: {e}",
                file=sys.stderr,
            )

    return resolved


def _pick_profile(profiles: list[dict[str, Any]]) -> dict[str, Any] | None:
    """Pick a profile interactively.

    On a TTY: raw-mode fzf-style picker (↑/↓/Enter/Esc/digit shortcut).
    Otherwise: line-based picker (number or substring + Enter).
    """
    if not profiles:
        return None
    if sys.stdin.isatty() and sys.stdout.isatty():
        return _pick_profile_interactive(profiles)
    return _pick_profile_line_based(profiles)


# ── Picker: line-based (fallback for non-TTY) ─────────────────────────────────

def _pick_profile_line_based(
    profiles: list[dict[str, Any]],
) -> dict[str, Any] | None:
    print()
    print("Profiles:")
    width = len(str(len(profiles)))
    for i, p in enumerate(profiles, 1):
        tag = " [wt]" if p["source"] == "wt" else ""
        print(f"  {i:>{width}}  {p['name']}{tag}")
    print()
    while True:
        try:
            choice = input(
                "Select (number or partial name; Enter to cancel): "
            ).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if not choice:
            return None
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(profiles):
                return profiles[idx]
            print(
                f"  out of range; choose 1-{len(profiles)}", file=sys.stderr
            )
            continue
        ci = choice.casefold()
        matches = [p for p in profiles if ci in p["name"].casefold()]
        if len(matches) == 1:
            return matches[0]
        if not matches:
            print(f"  no profile matches {choice!r}", file=sys.stderr)
            continue
        print("  ambiguous; matches:", file=sys.stderr)
        for m in matches:
            print(f"    - {m['name']}", file=sys.stderr)


# ── Picker: interactive raw-mode (fzf-style) ──────────────────────────────────

def _pick_profile_interactive(
    profiles: list[dict[str, Any]],
) -> dict[str, Any] | None:
    n = len(profiles)
    width = len(str(n))
    idx = 0

    def render_line(i: int, selected: bool) -> str:
        p = profiles[i]
        tag = " [wt]" if p["source"] == "wt" else ""
        line = f"  {i + 1:>{width}}  {p['name']}{tag}"
        return f"\x1b[7m{line}\x1b[0m" if selected else line

    def status_line(i: int) -> str:
        return (
            f"  \x1b[2m↑/↓ select · enter accept · "
            f"esc cancel · 1-9/0 jump  ({i + 1}/{n})\x1b[0m"
        )

    def draw_initial() -> None:
        for i in range(n):
            sys.stdout.write(render_line(i, i == idx) + "\n")
        sys.stdout.write(status_line(idx) + "\n")
        sys.stdout.flush()

    def redraw() -> None:
        # Move cursor up to the first list line, then clear-and-redraw each.
        sys.stdout.write(f"\x1b[{n + 1}F")
        for i in range(n):
            sys.stdout.write("\x1b[2K" + render_line(i, i == idx) + "\n")
        sys.stdout.write("\x1b[2K" + status_line(idx) + "\n")
        sys.stdout.flush()

    _enable_windows_ansi()
    with _raw_mode():
        draw_initial()
        while True:
            key = _read_key()
            if key in ("UP", "k"):
                idx = (idx - 1) % n
            elif key in ("DOWN", "j"):
                idx = (idx + 1) % n
            elif key == "HOME":
                idx = 0
            elif key == "END":
                idx = n - 1
            elif key == "ENTER":
                return profiles[idx]
            elif key in ("ESC", "CTRL_C", "q"):
                return None
            elif key and key.isdigit():
                d = int(key)
                target = 9 if d == 0 else d - 1
                if 0 <= target < n:
                    return profiles[target]
                continue
            else:
                continue
            redraw()


def _enable_windows_ansi() -> None:
    """Turn on ANSI escape processing on classic Windows conhost. No-op elsewhere."""
    if platform.system() != "Windows":
        return
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        STD_OUTPUT_HANDLE = -11
        ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        h = kernel32.GetStdHandle(STD_OUTPUT_HANDLE)
        mode = ctypes.c_uint()
        if kernel32.GetConsoleMode(h, ctypes.byref(mode)):
            kernel32.SetConsoleMode(
                h, mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING
            )
    except Exception:
        pass


@contextlib.contextmanager
def _raw_mode() -> Iterator[None]:
    """Put stdin in raw mode on POSIX. No-op on Windows (msvcrt.getch is always raw)."""
    if platform.system() == "Windows":
        yield
        return
    import termios
    import tty

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        yield
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def _read_key() -> str | None:
    """Read a single key event. Returns a normalized name or a printable char."""
    if platform.system() == "Windows":
        import msvcrt

        ch = msvcrt.getch()
        if ch in (b"\x00", b"\xe0"):
            code = msvcrt.getch()
            return {
                b"H": "UP", b"P": "DOWN",
                b"K": "LEFT", b"M": "RIGHT",
                b"G": "HOME", b"O": "END",
            }.get(code)
        if ch == b"\r" or ch == b"\n":
            return "ENTER"
        if ch == b"\x1b":
            return "ESC"
        if ch == b"\x03":
            return "CTRL_C"
        if ch == b"\x04":
            return "CTRL_D"
        if ch == b"\x0e":
            return "CTRL_N"
        try:
            return ch.decode("utf-8")
        except UnicodeDecodeError:
            return None

    import select

    ch = sys.stdin.read(1)
    if ch == "\x1b":
        # Distinguish bare Esc from CSI sequence: peek for more bytes briefly.
        r, _, _ = select.select([sys.stdin], [], [], 0.05)
        if not r:
            return "ESC"
        ch2 = sys.stdin.read(1)
        if ch2 != "[":
            return "ESC"
        ch3 = sys.stdin.read(1)
        return {
            "A": "UP", "B": "DOWN",
            "C": "RIGHT", "D": "LEFT",
            "H": "HOME", "F": "END",
        }.get(ch3)
    if ch in ("\r", "\n"):
        return "ENTER"
    if ch == "\x03":
        return "CTRL_C"
    if ch == "\x04":
        return "CTRL_D"
    if ch == "\x0e":
        return "CTRL_N"
    return ch


# ── Spawn: Windows ────────────────────────────────────────────────────────────

_CMD_NEEDS_QUOTING = re.compile(r'[\s"&|<>^]')


def _quote_cmd_arg(arg: str) -> str:
    if _CMD_NEEDS_QUOTING.search(arg):
        return '"' + arg.replace('"', '""') + '"'
    return arg


def _spawn_windows(profile: dict[str, Any]) -> int:
    """Write %TEMP%\\zellij-launcher.cmd and have zellij `new-tab` exec it.

    We funnel everything through a .cmd because the `commandline` string from
    WT is cmd.exe-flavored and passing it as zellij argv mangles backslashes
    and quoting. The .cmd is OEM (CP437)-encoded to match cmd.exe defaults.
    """
    cwd = profile.get("cwd") or os.getcwd()
    if "commandline" in profile:
        cmdline = profile["commandline"]
    else:
        cmdline = " ".join(_quote_cmd_arg(a) for a in profile["command"])

    cmd_path = Path(tempfile.gettempdir()) / "zellij-launcher.cmd"
    lines = ["@echo off"]
    for k, v in profile.get("env", {}).items():
        escaped = v.replace('"', '""')
        lines.append(f'set "{k}={escaped}"')
    lines.append(
        'if not "%WSLENV%"=="" ('
        'call set "WSLENV=ZELLIJ_SESSION_NAME/u:ZELLIJ/u:ZELLIJ_PANE_ID/u:USERPROFILE/u:%%WSLENV%%"'
        ') else ('
        'set "WSLENV=ZELLIJ_SESSION_NAME/u:ZELLIJ/u:ZELLIJ_PANE_ID/u:USERPROFILE/u"'
        ')'
    )
    lines.append(cmdline)
    lines.append("if errorlevel 1 pause")
    cmd_path.write_bytes(("\r\n".join(lines) + "\r\n").encode("cp437", errors="replace"))

    zellij = shutil.which("zellij") or "zellij"
    comspec = os.environ.get("ComSpec") or r"C:\Windows\System32\cmd.exe"
    argv = [zellij]
    session = os.environ.get("ZELLIJ_SESSION_NAME")
    if session:
        argv += ["--session", session]
    argv += [
        "action", "new-tab", "--close-on-exit", "--cwd", cwd,
        "--", comspec, "/c", str(cmd_path),
    ]
    return subprocess.call(argv)


# ── Spawn: POSIX ──────────────────────────────────────────────────────────────

def _spawn_posix(profile: dict[str, Any]) -> int:
    """zellij action new-tab -- [env K=V ...] <cmd> <args>."""
    cwd = profile.get("cwd") or os.getcwd()
    zellij = shutil.which("zellij") or "zellij"
    argv = [zellij]
    session = os.environ.get("ZELLIJ_SESSION_NAME")
    if session:
        argv += ["--session", session]
    argv += ["action", "new-tab", "--close-on-exit", "--cwd", cwd, "--"]
    env_kv = [f"{k}={v}" for k, v in profile.get("env", {}).items()]
    if env_kv:
        argv += ["env", *env_kv]
    argv += profile["command"]
    return subprocess.call(argv)


# ── switch-session ────────────────────────────────────────────────────────────

# Recency timestamps on disk are .NET ticks (100-ns intervals since 0001-01-01
# UTC). Same format the pwsh prompt (`profile.ps1:1041`), the bashrc hook
# (`.bashrc:518`), and ssh-ts-listener.ps1 write — so this picker stays interop
# with timestamps produced by any shell across SSH or WSL.
NET_EPOCH_TICKS = 621_355_968_000_000_000
_RECENCY_DIR = Path(tempfile.gettempdir()) / "zellij-session-times"
# One shared lock for every interactive picker — only one menu open at a time.
# Lives next to config.kdl so it's discoverable alongside the rest of the
# picker's state (gitignore this if your dotfiles repo is in the same dir).
_PICKER_LOCK_FILE = CONFIG_DIR / "picker.lock"


def _now_ticks() -> int:
    return int(time.time() * 10_000_000) + NET_EPOCH_TICKS


def _elapsed_str(ticks: int) -> str:
    """Mirror switch-session.ps1:56-60: <60s 'Ns', <60m 'MmSs', <24h 'HhMm', else 'DdHh'."""
    secs = max(0, (_now_ticks() - ticks) // 10_000_000)
    if secs < 60:
        return f"{secs}s"
    if secs < 3600:
        return f"{secs // 60}m{secs % 60}s"
    if secs < 86400:
        return f"{secs // 3600}h{(secs % 3600) // 60}m"
    return f"{secs // 86400}d{(secs % 86400) // 3600}h"


def _read_session_ticks(name: str) -> int | None:
    f = _RECENCY_DIR / name
    if not f.is_file():
        return None
    try:
        return int(f.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def _client_count(name: str) -> int:
    """Count attached clients via `zellij --session <name> action list-clients`."""
    try:
        r = subprocess.run(
            ["zellij", "--session", name, "action", "list-clients"],
            capture_output=True, text=True, timeout=5,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return 0
    # First line is the header; count remaining non-empty lines.
    return sum(1 for line in r.stdout.splitlines()[1:] if line.strip())


def _list_sessions() -> list[dict[str, Any]]:
    """Build the sorted session list: current first, then by recency desc, then unknowns last."""
    try:
        r = subprocess.run(
            ["zellij", "ls", "--no-formatting"],
            capture_output=True, text=True, timeout=5,
        )
    except (subprocess.SubprocessError, FileNotFoundError):
        return []

    # `zellij ls` includes EXITED ("attach to resurrect") sessions. Filter them out
    # of the picker (`switch-session` doesn't reanimate them), but keep them in
    # `all_names` so the recency-dir prune below doesn't drop their timestamps —
    # if the user later resurrects one, the "last used" tick is preserved.
    all_names: list[str] = []
    live_names: list[str] = []
    for line in r.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        name = line.split()[0]
        all_names.append(name)
        if "EXITED" not in line:
            live_names.append(name)
    if not live_names:
        return []

    # Prune recency files for sessions zellij has forgotten entirely.
    if _RECENCY_DIR.is_dir():
        try:
            for f in _RECENCY_DIR.iterdir():
                if f.is_file() and f.name not in all_names:
                    try:
                        f.unlink()
                    except OSError:
                        pass
        except OSError:
            pass

    counts: dict[str, int] = {}
    with ThreadPoolExecutor(max_workers=20) as ex:
        for name, count in zip(live_names, ex.map(_client_count, live_names)):
            counts[name] = count

    current = os.environ.get("ZELLIJ_SESSION_NAME", "")
    sessions: list[dict[str, Any]] = []
    for name in live_names:
        sessions.append({
            "name": name,
            "clients": counts.get(name, 0),
            "ticks": _read_session_ticks(name),
            "is_current": name == current,
        })

    # Group ordering:
    #   0 — non-current with a recency timestamp (most recent first)
    #   1 — non-current never-used (no timestamp on disk)
    #   2 — the current session itself (sinks to bottom)
    # This mirrors switch-session.ps1:28-41 and means the default-highlighted
    # row 0 always lands on the most-recent non-current session — i.e. "select
    # the most recent used one, and never the current".
    def sort_key(s: dict[str, Any]) -> tuple[int, int]:
        if s["is_current"]:
            return (2, 0)
        if s["ticks"] is None:
            return (1, 0)
        return (0, -s["ticks"])

    sessions.sort(key=sort_key)
    return sessions


@contextlib.contextmanager
def _single_instance_lock() -> Iterator[None]:
    """Global single-menu mutex shared by all interactive pickers.

    If the lockfile holds a still-live PID, terminate it before we proceed —
    this is what makes pressing any picker keybind *replace* whatever picker
    is currently open (Ctrl+Shift+A → kills an open launcher; Ctrl+Shift+\\\\`
    → kills an open switcher; double-press of the same keybind → same kill).
    Mirrors the kill-prev pattern in the original switch-session.ps1:1-14 and
    launcher.ps1:8-19, but with one lock so the two pickers are mutually
    exclusive instead of independent.

    `os.kill(pid, signal.SIGTERM)` works cross-platform: on Windows it maps to
    TerminateProcess; on POSIX it sends SIGTERM. Errors are swallowed (stale
    pid, recycled pid pointing at an unrelated process we can't signal, etc.)
    so the new picker still runs even if cleanup of the old one fails.
    """
    if _PICKER_LOCK_FILE.is_file():
        try:
            prev = int(_PICKER_LOCK_FILE.read_text(encoding="utf-8").strip())
            if prev and prev != os.getpid():
                try:
                    os.kill(prev, signal.SIGTERM)
                except (ProcessLookupError, PermissionError, OSError):
                    pass
        except (OSError, ValueError):
            pass
    try:
        _PICKER_LOCK_FILE.write_text(str(os.getpid()), encoding="utf-8")
    except OSError:
        pass
    try:
        yield
    finally:
        try:
            _PICKER_LOCK_FILE.unlink()
        except OSError:
            pass


def _position_label(i: int) -> str:
    if i < 9:
        return str(i + 1)
    if i == 9:
        return "0"
    return " "


def _format_session_row(s: dict[str, Any], label: str) -> str:
    elapsed = _elapsed_str(s["ticks"]) if s["ticks"] is not None else "never"
    current_tag = " (current)" if s["is_current"] else ""
    return (
        f"  {label}  {s['name']} ({s['clients']} attached) "
        f"[{elapsed}]{current_tag}"
    )


def _switch_session_interactive(
    sessions: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """Raw-mode picker.

    Returns:
      {"action": "switch", "name": <name>}  — caller invokes `zellij action switch-session`
      {"action": "new",    "name": <name>}  — same; new session
      {"action": "refresh"}                  — list changed (Ctrl-D); caller reloads & redraws
      None                                   — cancel (Esc/q/Ctrl-C)
    """
    n = len(sessions)
    idx = 0

    def row(i: int, selected: bool) -> str:
        line = _format_session_row(sessions[i], _position_label(i))
        return f"\x1b[7m{line}\x1b[0m" if selected else line

    def status(i: int) -> str:
        return (
            f"  \x1b[2m↑/↓ select · enter switch · ctrl-d delete · "
            f"ctrl-n new · 1-9/0 jump · esc cancel  ({i + 1}/{n})\x1b[0m"
        )

    def draw_initial() -> None:
        # Clear screen so refresh-after-delete doesn't leave stale rows above.
        sys.stdout.write("\x1b[H\x1b[2J")
        for i in range(n):
            sys.stdout.write(row(i, i == idx) + "\n")
        sys.stdout.write(status(idx) + "\n")
        sys.stdout.flush()

    def redraw() -> None:
        sys.stdout.write(f"\x1b[{n + 1}F")
        for i in range(n):
            sys.stdout.write("\x1b[2K" + row(i, i == idx) + "\n")
        sys.stdout.write("\x1b[2K" + status(idx) + "\n")
        sys.stdout.flush()

    _enable_windows_ansi()
    with _raw_mode():
        draw_initial()
        while True:
            key = _read_key()
            if key in ("UP", "k"):
                idx = (idx - 1) % n
            elif key in ("DOWN", "j"):
                idx = (idx + 1) % n
            elif key == "HOME":
                idx = 0
            elif key == "END":
                idx = n - 1
            elif key == "ENTER":
                return {"action": "switch", "name": sessions[idx]["name"]}
            elif key in ("ESC", "CTRL_C", "q"):
                return None
            elif key == "CTRL_N":
                return _prompt_new_session()
            elif key == "CTRL_D":
                _handle_delete(sessions[idx])
                return {"action": "refresh"}
            elif key and key.isdigit():
                d = int(key)
                target = 9 if d == 0 else d - 1
                if 0 <= target < n:
                    return {"action": "switch", "name": sessions[target]["name"]}
                continue
            else:
                continue
            redraw()


def _prompt_new_session() -> dict[str, Any] | None:
    """Read a session name with cooked input(). Called from inside _raw_mode(),
    but input() temporarily takes over stdin and works regardless."""
    sys.stdout.write("\n")
    sys.stdout.flush()
    try:
        name = input("New session name (Enter to cancel): ").strip()
    except (EOFError, KeyboardInterrupt):
        return None
    if not name:
        return None
    return {"action": "new", "name": name}


def _handle_delete(session: dict[str, Any]) -> None:
    """`zellij delete-session`; on non-zero exit (session has clients), prompt
    `Kill it? [y/N]` and `zellij kill-session` on `y`. No-op for current session."""
    name = session["name"]
    if session["is_current"]:
        sys.stdout.write(f"\n  cannot delete current session: {name}\n")
        sys.stdout.flush()
        time.sleep(0.6)
        return
    r = subprocess.run(
        ["zellij", "delete-session", name],
        capture_output=True, text=True,
    )
    if r.returncode == 0:
        return  # silent success — matches the pwsh/sh scripts
    sys.stdout.write(f"\n  Session '{name}' is active. Kill it? [y/N] ")
    sys.stdout.flush()
    ans = _read_key()
    sys.stdout.write("\n")
    sys.stdout.flush()
    if ans in ("y", "Y"):
        subprocess.run(
            ["zellij", "kill-session", name],
            capture_output=True, text=True,
        )


def _switch_session_line_based(
    sessions: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """Non-TTY fallback (piped input, CI). Numeric-only select; no Ctrl-D/Ctrl-N."""
    print()
    print("Sessions:")
    for i, s in enumerate(sessions):
        print(_format_session_row(s, _position_label(i)))
    print()
    while True:
        try:
            choice = input("Select (number; Enter to cancel): ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return None
        if not choice:
            return None
        if not choice.isdigit():
            print("  must be a number", file=sys.stderr)
            continue
        idx = int(choice) - 1
        if not (0 <= idx < len(sessions)):
            print(
                f"  out of range; choose 1-{len(sessions)}", file=sys.stderr
            )
            continue
        return {"action": "switch", "name": sessions[idx]["name"]}


def switch_session(_args: list[str]) -> int:
    """Top-level handler. Refresh-redraw loop until the user picks/creates or cancels."""
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    with _single_instance_lock():
        while True:
            sessions = _list_sessions()
            if not sessions:
                print("no zellij sessions", file=sys.stderr)
                return 0
            if interactive:
                outcome = _switch_session_interactive(sessions)
            else:
                outcome = _switch_session_line_based(sessions)
            if outcome is None:
                return 0
            if outcome["action"] in ("switch", "new"):
                return subprocess.call(
                    ["zellij", "action", "switch-session", outcome["name"]]
                )
            # outcome["action"] == "refresh"; rebuild and redraw


# ── Action registry ───────────────────────────────────────────────────────────

HANDLERS: dict[str, Callable[[list[str]], int]] = {
    "launch-profile": launch_profile,
    "switch-session": switch_session,
}


if __name__ == "__main__":
    raise SystemExit(main())
