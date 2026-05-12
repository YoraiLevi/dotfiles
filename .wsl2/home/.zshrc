# =============================================================================
# ~/.zshrc — dispatcher that loads one of three profiles
#
# To make zsh your default login shell (run once, then open a new terminal):
#   chsh -s /usr/bin/zsh
# Until you do that, start a zsh session manually by typing: zsh
#
# Switch between profiles at runtime with:  zsh-profile {lean|omz|zinit}
# =============================================================================

ZDOTDIR_LOCAL="${HOME}/.zsh"

# Load the active profile name (default = lean) before sourcing anything else,
# because some plugin managers want to be initialised very early (e.g. p10k
# instant prompt) — putting profile selection first lets the profile file
# decide whether to opt-in.
[ -r "${ZDOTDIR_LOCAL}/profile.env" ] && source "${ZDOTDIR_LOCAL}/profile.env"
: "${ZSH_PROFILE:=lean}"

source "${ZDOTDIR_LOCAL}/common.zsh"
source "${ZDOTDIR_LOCAL}/profiles/${ZSH_PROFILE}.zsh"
source "${ZDOTDIR_LOCAL}/switch-profile.zsh"
