from __future__ import annotations

import sys

from .names import HookContext, build_dispatch, log_hook


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print("usage: python -m dotfiles_githooks <hook-name> [args...]", file=sys.stderr)
        return 2
    return _run_hook(argv)


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
