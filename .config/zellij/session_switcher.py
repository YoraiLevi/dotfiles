import atexit
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TEMP = Path(os.environ.get("TEMP", os.environ.get("TMP", os.path.expanduser("~"))))
LOCK = TEMP / "zellij-session-switcher.lock"
TIME_DIR = TEMP / "zellij-session-times"


def _kill_if_our_process(pid: int) -> None:
    try:
        result = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
            capture_output=True, text=True, encoding="utf-8",
        )
        if str(pid) in result.stdout:
            name = result.stdout.split(",")[0].strip('"').lower()
            if "python" in name or "uv" in name:
                subprocess.run(
                    ["taskkill", "/PID", str(pid), "/F"],
                    capture_output=True,
                )
    except Exception:
        pass


def acquire_lock() -> None:
    if LOCK.exists():
        try:
            existing_pid = int(LOCK.read_text().strip())
            _kill_if_our_process(existing_pid)
        except (ValueError, OSError):
            pass
        LOCK.unlink(missing_ok=True)
    LOCK.write_text(str(os.getpid()))
    atexit.register(lambda: LOCK.unlink(missing_ok=True))


def get_sessions() -> list[str]:
    result = subprocess.run(
        ["zellij", "ls", "--no-formatting"],
        capture_output=True, text=True, encoding="utf-8",
    )
    lines = [l.strip() for l in result.stdout.splitlines() if l.strip()]
    return [l.split()[0] for l in lines if l.split()]


def prune_time_files(session_names: list[str]) -> None:
    if not TIME_DIR.exists():
        return
    for f in TIME_DIR.iterdir():
        if f.name not in session_names:
            f.unlink(missing_ok=True)


def read_time(session_name: str) -> float | None:
    p = TIME_DIR / session_name
    if not p.exists():
        return None
    try:
        t = float(p.read_text().strip())
        # Stale .NET Ticks guard: any value past year 2100 as Unix timestamp
        if t > 4_102_444_800:
            p.unlink(missing_ok=True)
            return None
        return t
    except (ValueError, OSError):
        return None


def format_elapsed(t: float) -> str:
    elapsed = time.time() - t
    if elapsed < 60:
        return f"{int(elapsed)}s"
    elif elapsed < 3600:
        m, s = divmod(int(elapsed), 60)
        return f"{m}m{s}s"
    elif elapsed < 86400:
        h, rem = divmod(int(elapsed), 3600)
        return f"{h}h{rem // 60}m"
    else:
        d, rem = divmod(int(elapsed), 86400)
        return f"{d}d{rem // 3600}h"


def sort_key(name: str, current: str) -> float:
    if name == current:
        return float("inf")
    t = read_time(name)
    if t is None:
        return float("inf") - 1
    return -t


def count_clients(name: str) -> tuple[str, int]:
    result = subprocess.run(
        ["zellij", "--session", name, "action", "list-clients"],
        capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        return name, 0
    lines = [l for l in result.stdout.splitlines()[1:] if l.strip()]
    return name, len(lines)


def make_label(i: int) -> str:
    if i <= 9:
        return str(i)
    if i == 10:
        return "0"
    return " "


def run_fzf(numbered: list[str]) -> tuple[str, str] | None:
    fzf_input = "\n".join(numbered)
    result = subprocess.run(
        [
            "fzf",
            "--expect", "ctrl-d,ctrl-n",
            "--nth", "2..",
            "--header", "enter:switch  ctrl-d:delete  ctrl-n:new  esc:close",
            "--bind",
            "1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept,"
            "4:pos(4)+accept,5:pos(5)+accept,6:pos(6)+accept,"
            "7:pos(7)+accept,8:pos(8)+accept,9:pos(9)+accept,0:pos(10)+accept",
        ],
        input=fzf_input,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        return None
    lines = result.stdout.splitlines()
    key = lines[0] if lines else ""
    selected = lines[1] if len(lines) >= 2 else ""
    return key, selected


def main() -> None:
    acquire_lock()
    current = os.environ.get("ZELLIJ_SESSION_NAME", "")

    while True:
        session_names = get_sessions()
        if not session_names:
            break

        os.system("cls" if sys.platform == "win32" else "clear")
        prune_time_files(session_names)
        session_names.sort(key=lambda n: sort_key(n, current))

        with ThreadPoolExecutor(max_workers=20) as ex:
            client_counts = dict(ex.map(count_clients, session_names))

        lines = []
        for name in session_names:
            count = client_counts.get(name, 0)
            t = read_time(name)
            elapsed = format_elapsed(t) if t is not None else "never"
            suffix = " (current)" if name == current else ""
            lines.append(f"{name} ({count} attached) [{elapsed}]{suffix}")

        numbered = [f"{make_label(i + 1)}  {line}" for i, line in enumerate(lines)]

        outcome = run_fzf(numbered)
        if outcome is None:
            break
        key, selected = outcome

        if key == "ctrl-n":
            new_name = input("New session name: ").strip()
            if new_name:
                subprocess.run(["zellij", "action", "switch-session", new_name])
            break

        if not selected:
            break

        # Item format: "N  name (K attached) [elapsed][ (current)]"
        name = selected.split()[1]

        if key == "ctrl-d":
            if name == current:
                input("Cannot delete the current session. Press Enter to continue")
            else:
                r = subprocess.run(
                    ["zellij", "delete-session", name],
                    capture_output=True,
                )
                if r.returncode != 0:
                    confirm = input(f"Session '{name}' is active. Kill it? [y/N] ")
                    if confirm.lower() == "y":
                        subprocess.run(
                            ["zellij", "kill-session", name],
                            capture_output=True,
                        )
        else:
            subprocess.run(["zellij", "action", "switch-session", name])
            break


if __name__ == "__main__":
    main()
