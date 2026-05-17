# `~/.agents/claude/uv-tools/`

Python CLI tools installable via `uv tool install`. Each subdirectory is one
project. After installing, the tool's command shim lands in `~/.local/bin/`
and is invokable from PowerShell, bash, and Claude Code's `!` prefix.

## Currently installed

| Tool | Source | Purpose |
|---|---|---|
| `open-plan` | [`./open-plan/`](./open-plan) | Opens the current Claude Code session's plan file in Obsidian (via the harness's `CLAUDE_CODE_SESSION_ID` env var and the JSONL transcript). |

When you add a new tool, list it here.

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

## Reference

- Hatchling source we read to diagnose this:
  `~/source/hatch/backend/src/hatchling/utils/fs.py:6` (`locate_file`)
  `~/source/hatch/backend/src/hatchling/builders/config.py:755` (call site)
- `uv tool` docs: https://docs.astral.sh/uv/concepts/tools/
- `[project.scripts]` spec (PEP 621):
  https://packaging.python.org/en/latest/specifications/pyproject-toml/#scripts
