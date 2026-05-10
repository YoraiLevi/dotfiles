# WSL dotfiles (bare Git repo)

This directory is the **Git directory** for a bare repository whose **work tree is `$HOME`**.

## Daily Git commands

Use the shell alias (defined in `~/.bashrc`):

```bash
dotfiles status
dotfiles add -p <paths>
dotfiles commit -m "message"
dotfiles push
```

Equivalent:

```bash
git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" <command>
```

## What this repo is for

Tracked paths are **WSL/Linux glue**: symlink installer, Git hooks, timer helpers, and small files that should live in Git—not the bulk of shell/editor config.

**Canonical dotfiles for interactive use** are maintained under Windows and mirrored into WSL by symlinks (see below). Managing the same text in both Chezmoi (Windows) and this repo would cause drift; keep a clear split.

## Windows-side layout (sources of truth)

Roughly:

| Windows path | Role |
|--------------|------|
| `%USERPROFILE%\.wsl2\home\` | Mirror of Linux `$HOME` paths (files symlinked into WSL) |
| `%USERPROFILE%\.ssh\` | SSH keys and config → `~/.ssh/` |
| `%USERPROFILE%\.wsl2\etc\` | Files symlinked under `/etc/` (needs sufficient privileges) |
| `%USERPROFILE%\.wsl2\wsl.conf` | Copied to `/etc/wsl.conf` (not symlinked) |

`~/winHome` (and `~/homeWin`) should point at `%USERPROFILE%` in WSL path form.

## Symlink refresh: `setup-wsl2-symlinks`

Script: **`~/.local/opt/setup-wsl2-symlinks`** (tracked in this repo).

It creates **relative** symlinks from WSL into the Windows tree, optionally fixes permissions on SSH targets, mirrors `%USERPROFILE%\.wsl2\home` into `$HOME`, mirrors Claude agents, and handles `/etc` + `wsl.conf` as documented in the script header.

Typical flags:

- `-q` / `--quiet` — less noise
- `-F` / `--fast` — skip the chmod/chown pass on `~/.ssh`

After cloning this repo on a new WSL distro or machine, run the script once (from an interactive shell or systemd); your `~/.bashrc` may also source it in WSL—see your own config.

## Auto-commit timer (optional)

- **`dotfiles-timer.sh`** — installs a systemd user timer that runs **`.auto-commit.sh`** to commit and push tracked changes periodically.
- Invoke: `dotfiles-timer` (if aliased) or `bash ~/.dotfiles/dotfiles-timer.sh help`.

## Fresh clone checklist

1. Clone or fetch so **`~/.dotfiles`** exists and contains this repo’s objects.
2. Ensure **`~/.gitignore`** is present (tracked) so `git status` is not flooded.
3. Run **`~/.local/opt/setup-wsl2-symlinks`** (with `-q` if you prefer) so Windows-backed configs appear under `$HOME`, `~/.ssh`, etc.
4. If you use `/etc` mirroring or `wsl.conf`, run the parts that need root as appropriate.
5. Configure `git config` remote/auth if you plan to push.

## Secrets and noise

- **`~/.gitignore`** excludes keys, `.env`, AWS credentials patterns, etc. Do not commit private material.
- Paths **outside** `%USERPROFILE%\.wsl2\home` (e.g. extra mirrors like `.aws`) are not created by default; maintain them explicitly or extend automation if needed.

## Related files in this repo

| Path | Purpose |
|------|---------|
| `.local/opt/setup-wsl2-symlinks` | WSL ↔ Windows symlink mirror |
| `.dotfiles/.githooks/` | Unified hook dispatcher + symlinks |
| `.dotfiles/dotfiles-timer.{sh,ps1}` | Timer install / Windows helper |
| `.dotfiles/.auto-commit.sh` | Used by the systemd timer |
