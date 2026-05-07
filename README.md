# dotfiles-template

Manage dotfiles across machines using a bare git repository. No symlinks, no extra tools — just git.

The trick: a bare repo stored at `~/.dotfiles` with `$HOME` as its work-tree, accessed via a short alias.

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
