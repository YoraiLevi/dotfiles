# WSL dotfiles (bare Git repo)

## Install and setup

Git directory: **`~/.dotfiles`**. Work tree: **`$HOME`** (config and tracked files live alongside normal dotfiles).

Layout matches the bare-repo pattern documented in **[YoraiLevi/dotfiles](https://github.com/YoraiLevi/dotfiles)** ([README](https://raw.githubusercontent.com/YoraiLevi/dotfiles/refs/heads/master/README.md)): no separate checkout directory — Git metadata lives in **`~/.dotfiles`**, tracked files appear directly under **`$HOME`**.

### Clone the bare repo and check out the `WSL` branch

This WSL distro uses the **`WSL`** branch on the remote (one branch per machine). Replace the clone URL with SSH or HTTPS depending on how you authenticate.

1. **Define the `dotfiles` alias** for this shell session (repeat after reopening the terminal until your **`~/.bashrc`** is restored):

   ```bash
   alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
   ```

2. **Bare clone** into **`~/.dotfiles`**:

   ```bash
   git clone --bare git@github.com:YoraiLevi/dotfiles.git "$HOME/.dotfiles"
   ```

   HTTPS example:

   ```bash
   git clone --bare https://github.com/YoraiLevi/dotfiles.git "$HOME/.dotfiles"
   ```

3. **Quiet status by default** (same as upstream template):

   ```bash
   dotfiles config --local status.showUntrackedFiles no
   ```

4. **Fetch and check out the machine branch `WSL`**:

   ```bash
   dotfiles fetch origin
   dotfiles checkout WSL
   ```

   If Git refuses because existing files in **`$HOME`** would be overwritten, move those paths aside (or use the conflict loop from the upstream **Restoring a machine from scratch** section), then run **`dotfiles checkout WSL -- .`** again.

   **First time creating this branch** (only if **`WSL` does not exist on the remote yet): start from **`master`**, then publish:

   ```bash
   dotfiles fetch origin
   dotfiles checkout -b WSL origin/master
   dotfiles push -u origin WSL
   ```

5. **Verify**:

   ```bash
   dotfiles branch --show-current    # expect: WSL
   dotfiles status
   ```

After a clone, continue with **WSL-specific setup** in the next subsection (hooks, symlinks, remote).

### WSL-specific setup

1. **`~/.gitignore`** — Comes from **`dotfiles checkout WSL`**. If **`dotfiles status`** still lists everything under **`$HOME`**, restore it: **`dotfiles checkout WSL -- .gitignore`**.

2. **Git hooks** — Hooks live in **`~/.dotfiles/.githooks/`**. Tell Git to use them (**path is relative to `$HOME`**, not to `~/.dotfiles`):

   ```bash
   dotfiles config core.hooksPath .dotfiles/.githooks
   ```

   If the **`dotfiles`** alias is not loaded yet:

   ```bash
   git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" config core.hooksPath .dotfiles/.githooks
   ```

   Verify: `dotfiles config --get core.hooksPath` → `.dotfiles/.githooks`. If hooks fail to run, ensure scripts there are executable (`chmod +x`).

3. **Symlinks from Windows** — Run **`~/.local/opt/setup-wsl2-symlinks`** (e.g. `-q` for quiet, `-F` to skip SSH chmod pass). This mirrors `%USERPROFILE%\.wsl2\home`, `.ssh`, Claude agents, optional `.wsl2\etc`, and copies `wsl.conf`; details below.

4. **`/etc` and `wsl.conf`** — If you use the `.wsl2\etc` mirror or Windows-backed `wsl.conf`, apply those steps with appropriate privileges (see script header).

5. **Remote and auth** — The bare clone sets **`origin`**. Adjust URL or credentials if **`dotfiles push`** / **`dotfiles fetch`** fails.

**Optional:** install the auto-commit systemd timer — `bash ~/.dotfiles/dotfiles-timer.sh help` (and use `dotfiles-timer` if aliased in `~/.bashrc`).

---

## Daily usage

Shell alias (from **`~/.bashrc`**):

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

---

## Explanation

### What this repo is for

Tracked paths are **WSL/Linux glue**: symlink installer, Git hooks, timer helpers, and other files that belong in Git—not the bulk of shell or editor config stored under **`%USERPROFILE%\.wsl2\home`** on Windows.

Keep a single source of truth: **canonical interactive dotfiles** are on Windows and mirrored into WSL via symlinks. If you also use **Chezmoi** (or similar) on Windows, avoid editing the same logical file in two managers.

Shared dotfiles workflow (**`master`**, merging between machines, bootstrap scripts) matches **[YoraiLevi/dotfiles](https://github.com/YoraiLevi/dotfiles)** — see the upstream [README](https://raw.githubusercontent.com/YoraiLevi/dotfiles/refs/heads/master/README.md) for **Daily use**, **Multiple machines**, and **Restoring a machine from scratch**.

### Windows-side layout (sources of truth)

| Windows path | Role |
|--------------|------|
| `%USERPROFILE%\.wsl2\home\` | Mirror of Linux `$HOME` paths (files symlinked into WSL) |
| `%USERPROFILE%\.ssh\` | SSH keys and config → `~/.ssh/` |
| `%USERPROFILE%\.wsl2\etc\` | Files symlinked under `/etc/` (needs sufficient privileges) |
| `%USERPROFILE%\.wsl2\wsl.conf` | Copied to `/etc/wsl.conf` (not symlinked) |

`~/winHome` and **`~/homeWin`** should resolve to **`%USERPROFILE%`** as a WSL path.

### Symlink refresh: `setup-wsl2-symlinks`

Script: **`~/.local/opt/setup-wsl2-symlinks`** (tracked in this repo).

It creates **relative** symlinks into the Windows tree, optionally fixes permissions on SSH targets (unless `-F`), mirrors **`%USERPROFILE%\.wsl2\home`** into **`$HOME`**, mirrors Claude agents and **`~/.claude.json`**, handles **`/etc`** and **`wsl.conf`** as documented in the script.

Typical flags:

- **`-q` / `--quiet`** — less output
- **`-F` / `--fast`** — skip chmod/chown on `~/.ssh`

Your **`~/.bashrc`** may source this script in WSL on login; adjust if you prefer running it only manually or on a schedule.

### Git hooks

Hooks are **not** in **`~/.dotfiles/hooks`** (default bare-repo hooks directory). They sit under **`~/.dotfiles/.githooks/`** inside the work tree so Git can track them. **`core.hooksPath`** must be set (see [Install and setup](#install-and-setup)) or commits will not run your hooks.

### Auto-commit timer (optional)

**`dotfiles-timer.sh`** writes a systemd user unit that runs **`.auto-commit.sh`** to commit and push tracked changes on an interval.

### Secrets and noise

- **`~/.gitignore`** excludes private keys, `.env`, AWS credential patterns, etc.
- Paths **outside** `%USERPROFILE%\.wsl2\home` (e.g. `.aws`) are not created by default; add symlinks or automation yourself if needed.

### Related files in this repo

| Path | Purpose |
|------|---------|
| `.local/opt/setup-wsl2-symlinks` | WSL ↔ Windows symlink mirror |
| `.dotfiles/.githooks/` | Hook dispatcher and symlinks |
| `.dotfiles/dotfiles-timer.{sh,ps1}` | Timer install helpers |
| `.dotfiles/.auto-commit.sh` | Invoked by the systemd timer |
