---
name: make-uv-tool
description: Scaffold a new Python CLI tool under ~/.agents/claude/uv-tools/<name>/ that installs via `uv tool install` and becomes invokable as `<name>` from any shell (PowerShell, bash, Claude Code's `!` prefix). Use when the user asks to create a new uv-tool, make a new CLI installable with uv, scaffold a Python tool for Claude Code, or similar.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - PowerShell
  - Glob
---

# /make-uv-tool — Scaffold a new uv-installed CLI tool

This skill creates a new Python CLI project under
`~/.agents/claude/uv-tools/<tool-name>/`, installs it via `uv tool install`,
and verifies the resulting command works from bash, PowerShell, and Claude
Code's `!` prefix.

## Source of truth

**Always read `~/.agents/claude/uv-tools/README.md` first.** That README
documents the two valid layouts (single-file and package-directory), the
exact `pyproject.toml` templates for each, the hatchling-gitignore trap and
its three fixes, and the install/upgrade/uninstall commands. Do not duplicate
the README's content here — read it at invocation time so any future updates
to the README propagate to this skill.

## Procedure

1. **Gather requirements from the user**:
   - Tool name (kebab-case, e.g. `my-tool`). The Python package or module
     name will be the underscore-form (`my_tool`).
   - One-line description.
   - Layout choice — single-file or package-directory. Default to
     single-file unless the user has multiple modules or anticipates >200
     lines.

2. **Read `~/.agents/claude/uv-tools/README.md`** to get the current
   `pyproject.toml` template for the chosen layout. Use the exact template
   structure from the README, substituting in the user's tool name and
   description.

3. **Scaffold the files**:
   - Single-file: `pyproject.toml` + `<module>.py` at the project root.
   - Package-directory: `pyproject.toml` + `<package_name>/__init__.py` +
     `<package_name>/cli.py`. The CLI entry point should be `def main():`.

4. **Install with `uv tool install <project-path>`**. Use PowerShell. Capture
   and report any errors verbatim.

5. **Verify from BOTH shells**:
   - From PowerShell: `<tool-name>` (or a benign subcommand the user
     supplies).
   - From bash: same.
   Both should succeed. If only one works, env-var inheritance is broken —
   investigate before declaring done.

6. **Update the "Currently installed" table** in
   `~/.agents/claude/uv-tools/README.md` to include the new tool with its
   directory and a one-line purpose.

## Pitfalls to watch for

- **Empty wheel after install** (`ModuleNotFoundError: No module named
  '<package>'` on first invocation): the hatchling gitignore trap fired.
  This shouldn't happen for tools created under
  `~/.agents/claude/uv-tools/` because the umbrella `.gitignore` in that
  directory intercepts hatchling's walk. If it does happen, check that the
  umbrella `.gitignore` still exists; if it was deleted, restore it or fall
  back to per-project `[tool.hatch.build] ignore-vcs = true`.

- **Wrong env-var inheritance**: if the tool works from PowerShell but not
  bash (or vice versa) and the tool depends on env vars like
  `CLAUDE_CODE_SESSION_ID`, the tool's launcher script may not be
  propagating env vars correctly. uv-installed tools should not have this
  problem since uv uses `python.exe` directly and child processes inherit
  parent env. If the issue does appear, check that the Python code reads
  via `os.environ.get(...)` (which always works) rather than relying on
  any shell-specific mechanism.

- **Hyphen vs underscore confusion**: tool name `my-tool` in
  `[project.scripts]` and `[project]` `name`, but Python module/package
  name `my_tool` everywhere it appears in code or `packages = [...]`.
  Mismatch causes `ModuleNotFoundError`.

## When NOT to use this skill

- The user wants a one-off script with no need for a CLI shim — just write
  the `.py` file and have them invoke with `python script.py` or
  `uv run --script script.py`.
- The user wants a tool that lives outside `~/.agents/claude/uv-tools/`
  (e.g. a tool that ships with another project's source tree). The
  umbrella `.gitignore` won't protect it; document the alternative fixes
  from the README and ask which the user prefers.

## Arguments

Optional: tool name + description as a single string. If absent, ask the
user. Pass-through: `$ARGUMENTS`
