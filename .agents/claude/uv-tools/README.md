# `~/.agents/claude/uv-tools/`

Python CLI tools installable via `uv tool install`. Each subdirectory is one
project. After installing, the tool's command shim lands in `~/.local/bin/`
and is invokable from PowerShell, bash, and Claude Code's `!` prefix.

## Currently installed

Both commands ship from a single package — [`./claude-tasks/`](./claude-tasks) —
with `[project.scripts]` declaring two entry points. They share session,
transcript, task-loading, and Obsidian helpers in `claude_tasks/common.py`.

| Command | Module | Purpose |
|---|---|---|
| `list-tasks`   | `claude_tasks.list_cli:main` | Prints the current session's task list to stdout — bullet list grouped by status with ANSI colors. Companion to the statusline summary. |
| `claude-tasks` | `claude_tasks.cli:main`      | Renders a markdown dashboard at `~/.claude/tasks/<session_id>/dashboard.md` containing **the current session's tasks AND the current plan**, then opens it in Obsidian (`obsidian://open?vault=.claude&file=tasks/<sid>/dashboard`). Snapshot — re-run to refresh. |

The `claude-tasks` command replaces the earlier separate `open-tasks` and
`open-plan` commands. Plan content is appended below the task list (separated
by a horizontal rule), with the plan's ATX headers demoted by one level so
they nest cleanly under the dashboard's structure. Plan resolution is the
same session-aware transcript discriminator (`"You should create your plan at"`
and `"Your plan has been saved to:"`) with a latest-modified fallback.

**Shared helpers** in `claude_tasks/common.py` used by both CLIs:
`get_session_id`, `get_session_name`, `pretty_session`, `find_session_transcript`,
`load_session_tasks`, `partition_by_status`, `build_obsidian_uri`,
`launch_uri`, `setup_utf8_stdout`, `_ancestor_pids`.

When you add a new tool, decide: does it slot into `claude-tasks` (shares
common helpers, related-to-session-state), or does it deserve its own package
(genuinely independent — different deps, different scope)? List it here
either way.

## Creating a new tool

Pick a layout based on size, scaffold the files, install. Five minutes.

### Layout A — single-file (best ≤ ~200 lines, no sub-modules)

```
<tool-name>/
├── pyproject.toml
└── <module>.py     # module-level def main(): ...
```

`pyproject.toml`:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "<tool-name>"
version = "0.1.0"
description = "<one line>"
requires-python = ">=3.11"
dependencies = []

[project.scripts]
"<tool-name>" = "<module>:main"

[tool.hatch.build.targets.wheel]
only-include = ["<module>.py"]
```

This pattern is what `~/.config/zellij/` uses for `zellij-dispatch`. Single-file
layouts are immune to the hatchling `.gitignore` trap (see below) because
hatchling never walks a directory.

### Layout B — package directory (best for larger or modular tools)

```
<tool-name>/
├── pyproject.toml
└── <package_name>/
    ├── __init__.py
    └── cli.py       # def main(): ...
```

`pyproject.toml`:

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "<tool-name>"
version = "0.1.0"
description = "<one line>"
requires-python = ">=3.11"
dependencies = []

[project.scripts]
"<tool-name>" = "<package_name>.cli:main"

[tool.hatch.build.targets.sdist]
include = ["<package_name>", "pyproject.toml"]

[tool.hatch.build.targets.wheel]
packages = ["<package_name>"]
```

This pattern is what `./open-plan/` uses. **Layout B relies on the umbrella
`.gitignore` in this directory to avoid the hatchling trap** — do not delete
that file.

Note: package name must be a valid Python identifier (underscores, not
hyphens), even though the tool name in `[project]` and `[project.scripts]`
can use hyphens. So `open-plan` (tool) → `open_plan` (package).

### Install

From any shell:

```pwsh
uv tool install C:/Users/devic/.agents/claude/uv-tools/<tool-name>
```

After install, the command `<tool-name>` is on PATH. Verify in both
PowerShell and bash to make sure the env-var-inheritance path works for any
shell.

### Update after editing code

```pwsh
uv tool install C:/Users/devic/.agents/claude/uv-tools/<tool-name> --reinstall
```

Or use `--editable` at install time so code changes apply without reinstall:

```pwsh
uv tool install --editable C:/Users/devic/.agents/claude/uv-tools/<tool-name>
```

### Remove

```pwsh
uv tool uninstall <tool-name>
```

## The hatchling gitignore trap (Layout B only)

If your build wheel comes out empty (only `dist-info/` inside, no source
files) and `import <package_name>` fails after install, you've hit the trap.

**Root cause.** Hatchling's file-discovery code (in
`hatchling/builders/config.py`) calls
`locate_file(self.root, ".gitignore", boundary=".git")`. That walks upward
from the project root looking for either a `.gitignore` (in which case it
applies the patterns to the project) or a `.git/` directory (in which case
it stops — a worktree boundary).

When there is no `.git/` anywhere up the path AND the home directory has a
populated `~/.gitignore`, the walk reaches `~/.gitignore`, applies its
patterns to our project files, and silently excludes the package directory's
source files. The wheel builds with just `dist-info/` and entry points; the
shim installs cleanly, but the package isn't importable.

Git itself does not have this problem because git refuses to operate
outside a worktree. Hatchling treats absence-of-`.git` as "keep walking,"
which is the bug.

**Three fixes, in increasing order of locality:**

1. **Umbrella `.gitignore` here** — the [`./.gitignore`](./.gitignore) in
   this directory exists to intercept the walk. Any project at any depth
   below this directory benefits automatically. **This is the recommended
   long-term solution** for projects living under
   `~/.agents/claude/uv-tools/`.

2. **Per-project `.gitignore`** — drop any `.gitignore` (even empty) into the
   project root. Hatchling will find that first and never walk upward.

3. **`ignore-vcs = true`** — add to `pyproject.toml`:
   ```toml
   [tool.hatch.build]
   ignore-vcs = true
   ```
   Disables all VCS-based exclusion. Per-project only. Use if the project
   lives outside `~/.agents/claude/uv-tools/` and creating an umbrella file
   isn't appropriate.

For projects under this directory, you don't need to do anything — the
umbrella `.gitignore` handles it.

## Companion Claude skill

A Claude Code skill named `make-uv-tool` lives at
[`.claude/skills/make-uv-tool/SKILL.md`](./.claude/skills/make-uv-tool/SKILL.md)
inside this directory. It scaffolds new tools here following the patterns
above and uses this README as its source of truth.

It is **project-local, not global** — Claude Code only discovers it when a
session is rooted in this directory (or a subdirectory). It will not pollute
the skill list of unrelated sessions elsewhere on the machine.

Invoke it by typing `/make-uv-tool` (when in a session under this dir), or
by asking in natural language ("make a new uv tool", "scaffold a CLI under
uv-tools", "add a tool installable by uv") — Claude matches the skill's
description and picks it up.

## Reference

- Hatchling source we read to diagnose this:
  `~/source/hatch/backend/src/hatchling/utils/fs.py:6` (`locate_file`)
  `~/source/hatch/backend/src/hatchling/builders/config.py:755` (call site)
- `uv tool` docs: https://docs.astral.sh/uv/concepts/tools/
- `[project.scripts]` spec (PEP 621):
  https://packaging.python.org/en/latest/specifications/pyproject-toml/#scripts
