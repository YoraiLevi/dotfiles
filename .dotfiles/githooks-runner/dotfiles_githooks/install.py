from __future__ import annotations

import os
import stat
from pathlib import Path

from .names import HOOK_NAMES


def _shell_quote_single(path: str) -> str:
    """Quote for POSIX sh single-quoted string."""
    return "'" + path.replace("'", "'\"'\"'") + "'"


def render_stub(*, uv_executable: str | None) -> str:
    """POSIX stub: resolves .dotfiles root from hook dir (.dotfiles/.githooks -> .dotfiles)."""
    uv_cmd = _shell_quote_single(os.path.normpath(uv_executable)) if uv_executable else "uv"
    # ROOT is the parent of .githooks (i.e. ~/.dotfiles when hooks live in ~/.dotfiles/.githooks).
    lines = [
        "#!/bin/sh",
        "# dotfiles_githooks launcher (POSIX; Git for Windows uses sh.exe). LF line endings only.",
        'HERE="$(cd "$(dirname "$0")" && pwd)"',
        'ROOT="$(cd "$HERE/.." && pwd)"',
        f'exec {uv_cmd} run --project "$ROOT/githooks-runner" python -m dotfiles_githooks "$(basename "$0")" "$@"',
        "",
    ]
    return "\n".join(lines)


def install_stubs(*, hooks_dir: Path, runner_dir: Path, uv_exe: str | None) -> None:
    hooks_dir.mkdir(parents=True, exist_ok=True)
    _ = runner_dir.resolve()  # validate path exists
    if not runner_dir.is_dir():
        raise FileNotFoundError(f"runner directory not found: {runner_dir}")
    text = render_stub(uv_executable=uv_exe)
    for name in HOOK_NAMES:
        path = hooks_dir / name
        path.write_text(text, encoding="utf-8", newline="\n")
        mode = path.stat().st_mode
        path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
