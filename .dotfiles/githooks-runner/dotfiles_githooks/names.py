from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from typing import Callable, Final

# All hook filenames we ship as POSIX stubs (parity with common Git + git-p4 hooks).
HOOK_NAMES: Final[tuple[str, ...]] = (
    "applypatch-msg",
    "pre-applypatch",
    "post-applypatch",
    "pre-commit",
    "pre-merge-commit",
    "prepare-commit-msg",
    "commit-msg",
    "post-commit",
    "pre-rebase",
    "post-checkout",
    "post-merge",
    "post-rewrite",
    "pre-push",
    "pre-receive",
    "update",
    "post-receive",
    "post-update",
    "reference-transaction",
    "push-to-checkout",
    "pre-auto-gc",
    "sendemail-validate",
    "post-index-change",
    "p4-changelist",
    "p4-prepare-changelist",
    "p4-post-changelist",
    "p4-pre-submit",
)

# Hooks where Git commonly passes ref/revision data on stdin (drain so large pipes do not stall).
STDIN_HOOK_NAMES: Final[frozenset[str]] = frozenset(
    {
        "pre-push",
        "pre-receive",
        "post-receive",
        "post-update",
        "reference-transaction",
    }
)


@dataclass
class HookContext:
    hook_name: str
    argv: list[str]


HookFn = Callable[[HookContext], int]


def log_hook(hook_name: str, *, msg: str | None = None) -> None:
    line = f"[dotfiles_githooks] {hook_name}"
    if msg:
        line = f"{line}: {msg}"
    print(line, file=sys.stderr)


def drain_stdin_if_needed(hook_name: str) -> None:
    if hook_name not in STDIN_HOOK_NAMES:
        return
    if sys.stdin is None:
        return
    if sys.stdin.isatty():
        return
    # Consume stdin so Git does not block waiting for the hook to read (server/client hooks).
    try:
        sys.stdin.read()
    except OSError:
        pass


def hook_default(ctx: HookContext) -> int:
    if os.environ.get("DOTFILES_GITHOOKS_VERBOSE"):
        log_hook(ctx.hook_name)
    drain_stdin_if_needed(ctx.hook_name)
    return 0


def build_dispatch() -> dict[str, HookFn]:
    # Single implementation for every shipped hook; specialize individual hooks later.
    d: dict[str, HookFn] = {}
    for name in HOOK_NAMES:
        d[name] = hook_default
    return d
