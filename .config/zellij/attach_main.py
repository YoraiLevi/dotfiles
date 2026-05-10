import argparse
import dataclasses
import os
import re
import subprocess
import sys
from pathlib import Path


class ZellijException(Exception):
    pass


class ZellijSessionNotFoundException(ZellijException):
    def __init__(self, session: str) -> None:
        super().__init__(f"Zellij session '{session}' not found.")
        self.session_name = session


class ZellijSessionInUseException(ZellijException):
    def __init__(self, session: str) -> None:
        super().__init__(f"Zellij session '{session}' is currently in use by other clients.")
        self.session_name = session


class ZellijCommandException(ZellijException):
    def __init__(self, message: str, exit_code: int, raw_output: str) -> None:
        super().__init__(message)
        self.exit_code = exit_code
        self.raw_output = raw_output


@dataclasses.dataclass
class ZellijClient:
    client_id: int
    pane_id: str
    command: str


def get_zellij_clients(session_name: str) -> list[ZellijClient]:
    result = subprocess.run(
        ["zellij", "--session", session_name, "action", "list-clients"],
        capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        error = (result.stdout + result.stderr).strip()
        if (
            "There is no active session" in error
            or "not found. The following sessions are active" in error
        ):
            raise ZellijSessionNotFoundException(session_name)
        raise ZellijCommandException("Zellij command failed.", result.returncode, error)

    clients = []
    for line in (result.stdout + result.stderr).splitlines()[1:]:
        m = re.match(r"^(?P<client_id>\d+)\s+(?P<pane_id>\S+)\s+(?P<command>.+)$", line)
        if m:
            clients.append(ZellijClient(
                client_id=int(m.group("client_id")),
                pane_id=m.group("pane_id"),
                command=m.group("command").strip(),
            ))
    return clients


def new_zellij_tab(session_name: str, shell_path: str, cwd: str | None = None) -> str:
    if cwd is None:
        cwd = str(Path.cwd())
    result = subprocess.run(
        [
            "zellij", "--session", session_name,
            "action", "new-tab", "--close-on-exit", "--cwd", cwd,
            "--", shell_path,
        ],
        capture_output=True, text=True, encoding="utf-8",
    )
    if result.returncode != 0:
        error = (result.stdout + result.stderr).strip()
        if "There is no active session" in error:
            raise ZellijSessionNotFoundException(session_name)
        raise ZellijCommandException("Failed to create new tab.", result.returncode, error)
    return result.stdout.strip()


def remove_zellij_session(session_name: str, force: bool = False) -> None:
    cmd = ["zellij", "delete-session", session_name]
    if force:
        cmd.append("--force")
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        error = (result.stdout + result.stderr).strip()
        if "not found" in error or result.returncode == 2:
            raise ZellijSessionNotFoundException(session_name)
        if "exists and is active" in error:
            raise ZellijSessionInUseException(session_name)
        raise ZellijCommandException("Failed to delete session.", result.returncode, error)


def connect_zellij_session(session_name: str, create: bool = False) -> None:
    cmd = ["zellij", "attach"]
    if create:
        cmd.append("--create")
    cmd.append(session_name)
    result = subprocess.run(cmd)
    if result.returncode != 0:
        raise ZellijSessionNotFoundException(session_name)


def get_zellij_auto_name() -> str:
    MAX_LEN = 36
    git_result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, encoding="utf-8",
    )
    if git_result.returncode == 0 and git_result.stdout.strip():
        return Path(git_result.stdout.strip()).name[:MAX_LEN]

    home = str(Path.home())
    cwd = str(Path.cwd())
    cwd_display = cwd.replace(home, "~")
    cwd_clean = re.sub(r"[^a-zA-Z0-9/\\~\-_\.]", "", cwd_display)
    parts = [p for p in re.split(r"[/\\]", cwd_clean) if p]

    for count in (4, 3, 2, 1):
        if len(parts) >= count:
            candidate = "-".join(parts[-count:])
            if len(candidate) <= MAX_LEN:
                return candidate

    return (parts[-1] if parts else "zellij")[:MAX_LEN]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Attach to or create a Zellij session.")
    parser.add_argument("--shell", default="", help="Shell executable to use")
    parser.add_argument("--session-name", default="", help="Zellij session name")
    return parser.parse_args()


def main() -> None:
    if not os.environ.get("TERM"):
        os.environ["TERM"] = "xterm-256color"

    args = parse_args()

    try:
        if os.environ.get("ZELLIJ"):
            shell = args.shell or os.environ.get("SHELL", "pwsh")
            result = subprocess.run([shell])
            sys.exit(result.returncode)

        session_name = args.session_name or get_zellij_auto_name()

        try:
            clients: list[ZellijClient] | None = get_zellij_clients(session_name)
        except (ZellijSessionNotFoundException, ZellijCommandException):
            clients = None

        if args.shell:
            os.environ["SHELL"] = args.shell

        if clients is None:
            try:
                remove_zellij_session(session_name)
            except (ZellijSessionNotFoundException, ZellijSessionInUseException, ZellijCommandException):
                pass
            connect_zellij_session(session_name, create=True)
        else:
            if len(clients) > 0:
                shell = os.environ.get("SHELL") or args.shell or "pwsh"
                new_zellij_tab(session_name, shell, str(Path.cwd()))
            connect_zellij_session(session_name)

    except ZellijCommandException as e:
        lines = [
            "=== Zellij command failed ===",
            f"Exit code: {e.exit_code}",
            f"Exception type: {type(e).__name__}",
            f"Message: {e}",
        ]
        if e.raw_output:
            lines += ["", "--- Captured stdout/stderr ---", e.raw_output.rstrip()]
        else:
            lines += ["", "--- Captured stdout/stderr --- (none)"]
        print("\n".join(lines), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        lines = [
            "=== Unexpected error ===",
            f"Exception type: {type(e).__name__}",
            f"Message: {e}",
        ]
        inner = e.__cause__ or e.__context__
        while inner:
            lines += [
                "",
                "--- Inner exception ---",
                f"Type: {type(inner).__name__}",
                f"Message: {inner}",
            ]
            inner = inner.__cause__ or inner.__context__
        print("\n".join(lines), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
