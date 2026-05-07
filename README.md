# dotfiles-template

Manage dotfiles across machines using a bare git repository. No symlinks, no extra tools — just git.

The trick: a bare repo stored at `~/.dotfiles` with `$HOME` as its work-tree, accessed via a short alias.

> **`<placeholder>`** — anything in angle brackets is something you must replace with your own value before running the command.

> ⚠️ **Never track secret files.** With auto-commit enabled, any tracked file is pushed within 60 seconds of being modified. The included `.gitignore` blocks the most common ones (`.ssh/id_*`, `.netrc`, `.aws/credentials`, `.env*`, `*.pem`, `*.key`) defensively. Audit before running `config add` on anything new.

---

## The `config` command

Add one of these to your shell profile and use `config` everywhere you'd use `git`:

**Bash / Zsh** (`~/.bashrc` or `~/.zshrc`):
```bash
alias config='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

**PowerShell** (`$PROFILE`):
```powershell
function config { git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" @args }
```

---

## Using this template (no fork required)

You don't need to fork on GitHub. Clone directly, set up your own repo, then bring it down to your machine as a bare repo.

### 1. Create your own GitHub repo from this template

```bash
# Clone this template
git clone https://github.com/DgxSparkLabs/dotfiles-template.git dotfiles
cd dotfiles

# Point it at your own repo
git remote remove origin
git remote add origin https://github.com/<YOU>/dotfiles.git
git push -u origin master
```

Or if you prefer a fresh history (no template commits):
```bash
git clone https://github.com/DgxSparkLabs/dotfiles-template.git dotfiles
cd dotfiles
rm -rf .git
git init
git add .
git commit -m "Initial dotfiles setup"
git branch -M master    # pin to master regardless of your git default
git remote add origin https://github.com/<YOU>/dotfiles.git
git push -u origin master
```

> **Why not fork?** Forks stay linked to the upstream repo on GitHub, which can clutter your profile and creates an implicit relationship you probably don't want for personal dotfiles.

### 2. Set up the bare repo on this machine

```bash
git clone --bare git@github.com:<YOU>/dotfiles.git $HOME/.dotfiles
config config --local status.showUntrackedFiles no

# Populate $HOME with master's tracked files
config checkout master
```

If `config checkout master` fails with **"untracked working tree files would be overwritten/removed"**, your `$HOME` already has files at paths master tracks. Pick one resolution and re-run:

- **Keep master's version, back yours up first:**
  ```bash
  mv ~/.bashrc ~/.bashrc.backup     # repeat for each conflicting file
  config checkout master
  ```
- **Keep your version, untrack the path on master:**
  ```bash
  config rm --cached <path-1> <path-2>
  config commit -m "Untrack OS-managed paths"
  config push
  config checkout master
  ```
- **Selective checkout — only write paths that don't conflict:**
  ```bash
  config checkout master -- .bashrc .gitconfig .config/   # list paths you want
  ```

Verify the work-tree is fully in sync:

```bash
config status
```

It should show **no** "Changes to be committed". If it shows `deleted: <files>`, the bare-clone index didn't fully populate — force-write the remaining tracked files:

```bash
config checkout master -- .
config status     # confirm clean
```

### 3. Create this machine's branch

This template uses **one branch per machine**, with `master` holding shared configs. Pick a short, descriptive name for each machine:

| `<machine-name>` | Use for |
|---|---|
| `desktop-home`, `desktop-work` | Stationary desktops, distinguished by location |
| `laptop-personal`, `laptop-work` | Laptops, distinguished by ownership |
| `vm-dev`, `wsl-ubuntu` | Virtual machines and WSL distros |
| `server-home`, `vps-prod` | Remote servers |

> Confirm `config status` is clean from step 2 before proceeding — otherwise any staged deletions follow into the new branch and your first commit there will silently delete those files from master.

```bash
config checkout -b <machine-name> master
config push -u origin <machine-name>
```

### 4. Add your dotfiles

```bash
config add ~/.bashrc
config commit -m "Add bashrc"
config push
```

For the ongoing per-machine workflow, see [Multiple machines](#multiple-machines).

---

## Daily use

You're always on your machine's branch (`<machine-name>`). Routine changes commit and push there:

```bash
config status
config add ~/.config/someapp/config
config commit -m "Add someapp config"
config push                 # pushes to <machine-name> on origin
```

For changes you want every machine to inherit, see [Multiple machines](#multiple-machines) — those go on `master`.

### Auto-commit (optional)

Automatically stage and push changes to already-tracked dotfiles on a schedule. Uses `git add -u` — new files must still be added manually with `config add`.

**Linux** (systemd user timer, runs every minute):
```bash
bash dotfiles-timer.sh install
# reinstall | disable | remove | status | logs
```

**Windows** (Task Scheduler, runs every minute):
```powershell
pwsh dotfiles-timer.ps1 install
# reinstall | uninstall | status | logs
```

The commit script is stored inside `~/.dotfiles/` (the bare repo), keeping it out of your work-tree and off `config status`.

### Submodules (optional)

> ⚠️ **Known limitation:** submodule operations (`add`, `init`, `update`) don't always compose cleanly with the bare-repo `--git-dir`/`--work-tree` pattern — a long-standing git issue. The instructions below work for many users but may fail on some git versions. If you hit errors, alternatives include committing the files directly or using a tool like `chezmoi` that has first-class submodule support.
>
> Reference (may become stale): [git mailing list discussion, 2012](https://www.spinics.net/lists/git/msg185334.html)

For shell plugins or large tool configs, use submodules instead of copying files:

```bash
config submodule add https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
```

On a new machine after cloning:
```bash
config submodule init
config submodule update
```

---

## Managing `.gitignore`

The included `.gitignore` contains:
```
/*
!/.*
```

This ignores everything in `$HOME` except hidden files/dirs (those starting with `.`). This prevents `config status` from flooding with every file in your home directory.

**To also track a non-hidden directory** (e.g. `~/bin`), add a negation line to `.gitignore`:
```
/*
!/.*
!/bin
```

Then commit the updated `.gitignore`:
```bash
config add ~/.gitignore
config commit -m "Unignore ~/bin"
```

> Note: a `.gitignore` placed inside an ignored subdirectory will not be read by git — the negation must always be added to the root `.gitignore`.

---

## Multiple machines

Use one branch per machine, with `master` holding shared configs. Each machine branch merges from `master` to pull shared changes.

```bash
# Pull shared changes from master onto this machine
config merge master
```

To share a change across all machines: commit it to `master`, push, then run `config merge master` on each other machine.

### Adding another machine

Repeat [Using this template](#using-this-template-no-fork-required) **steps 2–4** on the new machine, picking a new `<machine-name>` in step 3. Step 1 (creating the GitHub repo) only happens once, on your first machine.

If a branch for this machine already exists on the remote (e.g. you set it up before and are reinstalling), substitute step 3 with:

```bash
config checkout <machine-name>     # checkout the existing branch instead of creating one
```

For full disaster-recovery automation, see [Restoring a machine from scratch](#restoring-a-machine-from-scratch).

---

## Restoring a machine from scratch

The `config` alias lives in your profile — which hasn't been restored yet. Define it temporarily first, then check out your machine's branch (which restores the profile):

```bash
#!/bin/bash
# bootstrap.sh — run once on a fresh machine
REPO="git@github.com:<YOU>/dotfiles.git"
BRANCH="<machine-name>"

git clone --bare "$REPO" "$HOME/.dotfiles"
alias config='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
config config --local status.showUntrackedFiles no

# Back up any conflicting OS defaults, then checkout
config checkout "$BRANCH" -- . 2>/dev/null || {
  config checkout "$BRANCH" 2>&1 | grep $'^\t' | while IFS= read -r file; do
    file="${file#$'\t'}"
    [ -e "$HOME/$file" ] && mv "$HOME/$file" "$HOME/$file.bak"
  done
  config checkout "$BRANCH" -- .
}

exec $SHELL
```

Save this as `bootstrap.sh` in your repo and run it with `bash bootstrap.sh` on any new or reset machine.

**PowerShell (`bootstrap.ps1`):**
```powershell
# bootstrap.ps1 — run once on a fresh machine
$REPO = "git@github.com:<YOU>/dotfiles.git"
$BRANCH = "<machine-name>"

git clone --bare $REPO "$HOME/.dotfiles"
function config { git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" @args }
config config --local status.showUntrackedFiles no

# Back up any conflicting OS defaults, then checkout
config checkout $BRANCH -- . 2>$null
if ($LASTEXITCODE -ne 0) {
    config checkout $BRANCH 2>&1 | Where-Object { $_ -match "^\t" } | ForEach-Object {
        $file = $_.Trim()
        if (Test-Path "$HOME\$file") {
            Move-Item "$HOME\$file" "$HOME\$file.bak" -Force
        }
    }
    config checkout $BRANCH -- .
}

. $PROFILE
```

Run with `pwsh bootstrap.ps1` on any new or reset Windows machine.
