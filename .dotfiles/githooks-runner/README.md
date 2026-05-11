# dotfiles-githooks

Python dispatcher for Git hooks under `~/.dotfiles/.githooks/`. Hooks are thin POSIX `#!/bin/sh` stubs that run:

`uv run --project …/githooks-runner python -m dotfiles_githooks <hook-name> "$@"`

See the main template [README.md](../../README.md) for setup (`core.hooksPath`, `uv sync`).
