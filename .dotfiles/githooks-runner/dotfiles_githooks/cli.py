from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .install import install_stubs
from .names import HOOK_NAMES, HookContext, build_dispatch, log_hook


def _resolve_repo_defaults() -> tuple[Path, Path]:
    """When running from template checkout: .dotfiles/githooks-runner -> hooks at .dotfiles/.githooks."""
    here = Path(__file__).resolve()
    runner_dir = here.parents[1]  # .../githooks-runner
    dotfiles_dir = runner_dir.parent  # .../.dotfiles
    hooks_dir = dotfiles_dir / ".githooks"
    return hooks_dir, runner_dir


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print("usage: python -m dotfiles_githooks install | <hook-name> [args...]", file=sys.stderr)
        return 2
    if argv[0] == "install":
        return _cmd_install(argv[1:])
    return _run_hook(argv)


def _cmd_install(args: list[str]) -> int:
    p = argparse.ArgumentParser(prog="python -m dotfiles_githooks install")
    p.add_argument(
        "--hooks-dir",
        type=Path,
        default=None,
        help="Directory to write POSIX stubs (default: <repo>/.dotfiles/.githooks next to this package)",
    )
    p.add_argument(
        "--runner-dir",
        type=Path,
        default=None,
        help="Directory containing pyproject.toml for uv run --project (default: .../githooks-runner)",
    )
    p.add_argument(
        "--uv-exe",
        default=None,
        help="Optional explicit uv executable path written into stubs (default: uv from PATH)",
    )
    ns = p.parse_args(args)
    default_hooks, default_runner = _resolve_repo_defaults()
    hooks_dir = ns.hooks_dir or default_hooks
    runner_dir = ns.runner_dir or default_runner
    try:
        install_stubs(
            hooks_dir=hooks_dir.resolve(),
            runner_dir=runner_dir.resolve(),
            uv_exe=ns.uv_exe,
        )
    except OSError as e:
        print(f"[dotfiles_githooks] install failed: {e}", file=sys.stderr)
        return 1
    print(f"[dotfiles_githooks] wrote {len(HOOK_NAMES)} stubs under {hooks_dir}", file=sys.stderr)
    return 0


def _run_hook(argv: list[str]) -> int:
    hook_name = argv[0]
    rest = argv[1:]
    dispatch = build_dispatch()
    fn = dispatch.get(hook_name)
    if fn is None:
        log_hook(hook_name, msg="unknown hook name")
        return 0
    ctx = HookContext(hook_name=hook_name, argv=rest)
    try:
        return int(fn(ctx))
    except Exception as e:  # noqa: BLE001 — surface unexpected errors in hooks
        log_hook(hook_name, msg=f"error: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
