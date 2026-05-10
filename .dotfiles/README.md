# Windows dotfiles (bare Git repo)

This machine tracks **branch `TP412FAC`** on [`YoraiLevi/dotfiles`](https://github.com/YoraiLevi/dotfiles). Git metadata lives in **`%USERPROFILE%\.dotfiles`**; the work tree is **`%USERPROFILE%`** (`$HOME` in PowerShell), so tracked configs sit next to everything else under your profile.

The layout follows the bare-repo pattern from the upstream repo ([README](https://raw.githubusercontent.com/YoraiLevi/dotfiles/refs/heads/master/README.md)): no separate checkout directory — only the bare Git dir plus files in your home directory.

## Install and setup

### 1. Dotfiles Git alias (PowerShell)

Add to your profile (`$PROFILE`) or run each session until restored:

```powershell
function dotfiles { git --git-dir="$HOME\.dotfiles" --work-tree="$HOME" @args }
```

Git for Windows also understands Unix-style paths; `~\` and `$HOME\` both resolve under your user profile.

### 2. Bare clone into `~\.dotfiles`

```powershell
git clone --bare git@github.com:YoraiLevi/dotfiles.git "$HOME\.dotfiles"
```

HTTPS:

```powershell
git clone --bare https://github.com/YoraiLevi/dotfiles.git "$HOME\.dotfiles"
```

### 3. Quiet status (optional)

Matches the upstream template; this repo may use **`status.showUntrackedFiles yes`** so noisy untracked files are visible — set **`no`** if you prefer a minimal status:

```powershell
dotfiles config --local status.showUntrackedFiles no
```

### 4. Fetch and check out **`TP412FAC`**

```powershell
dotfiles fetch origin
dotfiles checkout TP412FAC
```

If checkout refuses because existing files would be overwritten, move those paths aside (or follow upstream **Restoring a machine from scratch**), then run **`dotfiles checkout TP412FAC`** again.

**First time creating this branch** (only if **`TP412FAC`** does not exist on the remote): branch from **`master`** and publish:

```powershell
dotfiles fetch origin
dotfiles checkout -b TP412FAC origin/master
dotfiles push -u origin TP412FAC
```

### 5. Hooks path (required for tracked hooks)

Hooks live under **`.dotfiles\.githooks\`** in the work tree (tracked files). The bare repo should already set **`core.hooksPath`** to **`.dotfiles/.githooks`** (relative to `$HOME`). If commits skip hooks, confirm:

```powershell
dotfiles config --get core.hooksPath
# expect: .dotfiles/.githooks
```

If empty:

```powershell
dotfiles config core.hooksPath .dotfiles/.githooks
```

### 6. Verify

```powershell
dotfiles branch --show-current   # expect: TP412FAC
dotfiles status
```

---

## Daily usage

```powershell
dotfiles status
dotfiles add -p <paths>
dotfiles commit -m "message"
dotfiles push
```

Equivalent:

```powershell
git --git-dir="$HOME\.dotfiles" --work-tree="$HOME" <command>
```

---

## Explanation

### What this repo is for

Single source of truth for **interactive dotfiles on Windows**, with optional mirroring or reuse in WSL. Shared workflow on **`master`** (merging between machines, bootstrap scripts) matches **[YoraiLevi/dotfiles](https://github.com/YoraiLevi/dotfiles)** — see the upstream README for **Daily use**, **Multiple machines**, and **Restoring a machine from scratch**.

If you also use **Chezmoi** (or similar) on Windows, avoid editing the same logical file in two managers.

### Git hooks (Windows-specific behavior)

- **Location**: **`~\.dotfiles\.githooks\`** — not the bare repo’s default `hooks` folder; **`core.hooksPath`** must point there or hooks will not run.
- **Runner**: Each hook name is a small **`#!/bin/sh`** stub that runs **`Run-GitHook.ps1`** via **`pwsh`** (PowerShell **7+**). Git for Windows ships `sh`; **`#Requires -Version 7.0`** applies to the dispatcher script.
- **`pre-commit`** (the interesting part): refreshes machine inventory files under your profile — for example VS Code / Cursor extension lists (first found of `cursor` / `code-insiders`), **`Get-InstalledModule`** → **`.powershell\pwsh-modules.txt`**, **`choco export`** → **`.choco\packages.config`**, and **`wsl`** snapshots for **`apt-mark showmanual`**, **`snap list`**, and **`apt-cache policy`** under **`.wsl2\`**. Those paths are meant to be committed so restores stay reproducible; **`wsl`** must work from this PC if you want those lines to succeed.

Other hook names are dispatched in **`Run-GitHook.ps1`** but currently only log unless you extend them.

### Auto-commit timer (optional, Windows)

**`dotfiles-timer.ps1`** replaces Linux **systemd** timers. It writes **`.auto-commit.ps1`** (and in non-admin mode a loop + Startup-folder launcher) that **`git add`**, commits when there are staged changes, and **`push`**.

- **Run as Administrator**: installs a Scheduled Task **`dotfiles-git-commit`** (logon + repeating trigger).
- **Normal user**: Startup-folder **`.vbs`** launcher runs a hidden **`pwsh`** loop; logs go to **`%TEMP%\dotfiles-auto-commit.log`**.

See **`pwsh dotfiles-timer.ps1`** with no arguments for usage (`install`, `status`, `logs`, etc.).

### Secrets and noise

**`~/.gitignore`** excludes private keys, `.env`, AWS credential patterns, and similar paths.

### Related files in this repo

| Path | Purpose |
|------|---------|
| `.dotfiles/.githooks/` | Hook stubs + **`Run-GitHook.ps1`** dispatcher |
| `.dotfiles/dotfiles-timer.ps1` | Windows auto-commit installer (Task Scheduler or startup loop) |
| `.dotfiles/.auto-commit.ps1` | Generated/maintained by **`dotfiles-timer.ps1`** — bare-path **`git`** commit + push |
