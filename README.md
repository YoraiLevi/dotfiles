# dotfiles-template

Manage dotfiles across machines using a bare git repository. No symlinks, no extra tools — just git.

The trick: a bare repo stored at `~/.dotfiles` with `$HOME` as its work-tree, accessed via a short alias.

---

## Using this template (no fork required)

You don't need to fork on GitHub. Clone directly, then push to your own repo:

```bash
# 1. Clone this template
git clone https://github.com/DgxSparkLabs/dotfiles-template.git dotfiles
cd dotfiles

# 2. Point it at your own repo
git remote remove origin
git remote add origin https://github.com/YOU/dotfiles.git
git push -u origin master
```

Or if you prefer a fresh history (no template commits):
```bash
# Start clean: copy files, init a new repo, push
git clone https://github.com/DgxSparkLabs/dotfiles-template.git dotfiles
cd dotfiles
rm -rf .git
git init
git add .
git commit -m "Initial dotfiles setup"
git remote add origin https://github.com/YOU/dotfiles.git
git push -u origin master
```

> **Why not fork?** Forks stay linked to the upstream repo on GitHub, which can clutter your profile and creates an implicit relationship you probably don't want for personal dotfiles.

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

## First machine — new repo

```bash
git init --bare $HOME/.dotfiles
config config --local status.showUntrackedFiles no
config branch -M main

# Add your dotfiles
config add ~/.bashrc
config commit -m "Initial commit"

config remote add origin git@github.com:YOU/dotfiles.git
config push -u origin main
```

---

## New machine — clone existing repo

```bash
git clone --bare git@github.com:YOU/dotfiles.git $HOME/.dotfiles
config config --local status.showUntrackedFiles no
config checkout main -- .
```

If checkout fails due to conflicting files already on the machine:
```bash
# Back up conflicts, then retry
mv ~/.bashrc ~/.bashrc.backup
config checkout main -- .
```

---

## Daily use

```bash
config status
config add ~/.config/someapp/config
config commit -m "Add someapp config"
config push
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

Use one branch per machine, with `main` holding shared configs. Each machine branch merges from `main` to pull shared changes.

```bash
# On each machine, create its branch from main
config checkout -b machine-laptop
config push -u origin machine-laptop

# Pull shared changes from main onto this machine
config merge main
```

To share a change across all machines: commit it to `main`, then `config merge main` on each machine.

---

## Restoring a machine from scratch

The `config` alias lives in your profile — which hasn't been restored yet. Define it temporarily first, then check out your machine's branch (which restores the profile):

```bash
#!/bin/bash
# bootstrap.sh — run once on a fresh machine
REPO="git@github.com:YOU/dotfiles.git"
BRANCH="machine-laptop"  # change to this machine's branch

git clone --bare "$REPO" "$HOME/.dotfiles"
alias config='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
config config --local status.showUntrackedFiles no

# Back up any conflicting OS defaults, then checkout
config checkout "$BRANCH" -- . 2>/dev/null || {
  config checkout "$BRANCH" 2>&1 | grep "^\s" | awk '{print $1}' \
    | xargs -I{} sh -c 'mv "$HOME/{}" "$HOME/{}.bak"'
  config checkout "$BRANCH" -- .
}

exec $SHELL
```

Save this as `bootstrap.sh` in your repo and run it with `bash bootstrap.sh` on any new or reset machine.

**PowerShell (`bootstrap.ps1`):**
```powershell
# bootstrap.ps1 — run once on a fresh machine
$REPO = "git@github.com:YOU/dotfiles.git"
$BRANCH = "machine-laptop"  # change to this machine's branch

git clone --bare $REPO "$HOME/.dotfiles"
function config { git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" @args }
config config --local status.showUntrackedFiles no

# Back up any conflicting OS defaults, then checkout
config checkout $BRANCH -- . 2>$null
if ($LASTEXITCODE -ne 0) {
    config checkout $BRANCH 2>&1 | Where-Object { $_ -match "^\t" } | ForEach-Object {
        $file = $_.Trim()
        Move-Item "$HOME\$file" "$HOME\$file.bak" -Force
    }
    config checkout $BRANCH -- .
}

. $PROFILE
```

Run with `pwsh bootstrap.ps1` on any new or reset Windows machine.

---

## Auto-commit (optional)

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

---

## Submodules (optional)

For shell plugins or large tool configs, use submodules instead of copying files:

```bash
config submodule add https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
```

On a new machine after cloning:
```bash
config submodule init
config submodule update
```
