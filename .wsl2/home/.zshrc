# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# -------
alias dotfiles='git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
alias dotfiles-timer='bash $HOME/.dotfiles/dotfiles-timer.sh'


TODO HISTFILE CONFIGURATION

# https://stackoverflow.com/a/40158199/12603110
rescue_history() { fc -W 2>/dev/null }
trap rescue_history SIGHUP

# https://gist.github.com/zachbrowne/8bc414c9f30192067831fafebd14255c Frees Ctrl-S from XOFF flow control.
# [[ -t 0 ]] && stty -ixon 2>/dev/null



setopt AUTO_CD # `cd foo` optional — bare dir name cd's
setopt AUTO_PUSHD # cd pushes to dir stack
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
export LESS='-R' # color-pass-through for pagers

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# enable color support of ls and also add handy aliases
export CLICOLOR=1
if command -v dircolors >/dev/null; then
    if [ -r "$HOME/.dircolors" ]; then
        eval "$(dircolors -b "$HOME/.dircolors")"
    else
        eval "$(dircolors -b)"
    fi

    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias egrep='egrep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip -color=auto'

fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

if [ -f ~/.zsh_aliases ]; then
    . ~/.zsh_aliases
fi

# Prevent accidental pip install into system Python
export PIP_REQUIRE_VIRTUALENV=true
# Load pyenv automatically by appending
# the following to
# ~/.bash_profile if it exists, otherwise ~/.profile (for login shells)
# and ~/.bashrc (for interactive shells) :

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init - zsh)"
fi

# uv / uvx — lazy-load shell completions on first invocation
uv() {
    unset -f uv uvx
    if command -v uv >/dev/null 2>&1; then
        eval "$(command uv generate-shell-completion zsh 2>/dev/null)"
        eval "$(command uvx --generate-shell-completion zsh 2>/dev/null)"
    fi
    command uv "$@"
}
uvx() {
    unset -f uv uvx
    if command -v uv >/dev/null 2>&1; then
        eval "$(command uv generate-shell-completion zsh 2>/dev/null)"
        eval "$(command uvx --generate-shell-completion zsh 2>/dev/null)"
    fi
    command uvx "$@"
}
# set PATH so it includes user's private bin if it exists
[ -d "$HOME/bin"        ] && path=("$HOME/bin"        $path)
# set PATH so it includes user's private .bin if it exists
[ -d "$HOME/.bin"       ] && path=("$HOME/.bin"       $path)
# set PATH so it includes user's private bin if it exists
[ -d "$HOME/.local/bin" ] && path=("$HOME/.local/bin" $path)

# https://www.youtube.com/watch?v=Wl7CDe9jsuo
alias mv='mv -iv'
alias cp='cp -riv'
alias mkdir='mkdir -vp'


# Directory navigation improvements
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias bd='cd "$OLDPWD"'  # cd into the old directory

up() {
    local d="" i limit=$1
    for ((i=1; i <= limit; i++)); do d="$d/.."; done
    d="${d#/}"
    [ -z "$d" ] && d=..
    cd "$d"
}

cd() {
    builtin cd "$@" && {
        local count
        count=$(command ls -go 2>/dev/null | wc -l)
        if [ "$count" -lt 15 ]; then
            command ls -go --color=auto -F
        fi
    }
}

extract() {
    local archive
    for archive in "$@"; do
        if [ -f "$archive" ]; then
            case "$archive" in
                *.tar.bz2)   tar xvjf "$archive"    ;;
                *.tar.gz)    tar xvzf "$archive"    ;;
                *.bz2)       bunzip2  "$archive"    ;;
                *.rar)       rar x    "$archive"    ;;
                *.gz)        gunzip   "$archive"    ;;
                *.tar)       tar xvf  "$archive"    ;;
                *.tbz2)      tar xvjf "$archive"    ;;
                *.tgz)       tar xvzf "$archive"    ;;
                *.zip)       unzip    "$archive"    ;;
                *.Z)         uncompress "$archive"  ;;
                *.7z)        7z x     "$archive"    ;;
                *)           echo "extract: don't know how to handle '$archive'" >&2 ;;
            esac
        else
            echo "extract: '$archive' is not a valid file" >&2
        fi
    done
}

nop() { return }

# ~/.auth/*.env — dotenv-style (KEY=value) and export KEY=value lines (allexport)
if [ -d "$HOME/.auth" ]; then
    set -a
    for f in "$HOME/.auth"/*.env(N); do
        [ -f "$f" ] && source "$f" 2>/dev/null
    done
    set +a
    # Other credential scripts (skip .json data and *.env — loaded above)
    for f in "$HOME/.auth"/*(N); do
        case "$f" in *.json|*.env) continue ;; esac
        [ -f "$f" ] && source "$f" 2>/dev/null
    done
fi

[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"
[ -f "$HOME/.env"           ] && source "$HOME/.env"

alias edit-profile='${EDITOR:-nano} ~/.zshrc'
alias edp='edit-profile'

claude() {
    IS_SANDBOX=1 CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE=10000000 \
        command claude --enable-auto-mode --allow-dangerously-skip-permissions "$@"
}


typeset -U path      # de-dup PATH entries

if grep -qi microsoft /proc/version 2>/dev/null || [ -n "$WSL_DISTRO_NAME" ]; then
    # echo "Running inside WSL"
    alias explorer="explorer.exe"
    # alias chezmoi="chezmoi.exe"
    alias wsl="wsl.exe"
    alias pwsh="pwsh.exe"
    alias powershell="powershell.exe"
    alias cmd="cmd.exe"
    alias zellij="zellij.exe"
    command -v tssh >/dev/null 2>&1 && alias ssh='tssh'
    # export SHELL="wsl.exe"
    export BROWSER=/mnt/c/PROGRA~2/Microsoft/Edge/Application/msedge.exe
    # alias tssh="tssh.exe"
    # NOT calling: . "$HOME/.local/bin/setup-wsl2-symlinks" -q  (bashrc does this)
else
    # echo "Running outside WSL"
    export SHELL="zsh"
fi

export GTK_THEME=Adwaita:dark

if [ -n "$SSH_CONNECTION" ] && [ -z "$DISPLAY" ]; then
    export BROWSER="$HOME/.local/bin/ssh-copy-text-to-clipboard"
fi

# zellij da -y > /dev/null # delete dead sessions

# ---- Session timestamp updater
if [ -n "$ZELLIJ_SESSION_NAME" ]; then
    if [ -n "$USERPROFILE" ] && command -v wslpath >/dev/null 2>&1; then
        _ZELLIJ_TIMEDIR="$(wslpath -u "$USERPROFILE" 2>/dev/null)/AppData/Local/Temp/zellij-session-times"
    else
        _ZELLIJ_TIMEDIR="/tmp/zellij-session-times"
    fi
    command mkdir -p "$_ZELLIJ_TIMEDIR" 2>/dev/null

    _zellij_update_timestamp() {
        local ns
        ns=$(date +%s%N 2>/dev/null)
        printf '%s' "$(( ns / 100 + 621355968000000000 ))" \
            > "$_ZELLIJ_TIMEDIR/$ZELLIJ_SESSION_NAME" 2>/dev/null
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _zellij_update_timestamp
fi

# ---- SSH auto-attach + first-pane MOTD
if [[ -z "$ZELLIJ" ]]; then
    if [ -n "$SSH_CONNECTION" ] && [[ -t 0 ]] && command -v zellij >/dev/null 2>&1; then
        zellij attach main -c
    fi
elif [[ "$ZELLIJ_PANE_ID" == "0" ]]; then
    local_motd="/tmp/.motd-shown-$(id -u)"
    today=$(date +%Y-%m-%d)
    if [[ ! -f "$local_motd" || "$(cat "$local_motd")" != "$today" ]]; then
        run-parts /etc/update-motd.d/ 2>/dev/null
        echo "$today" > "$local_motd"
    fi
    unset local_motd today
fi