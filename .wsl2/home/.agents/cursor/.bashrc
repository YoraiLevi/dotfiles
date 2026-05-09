# this is a custom behavior to include the .bashrc file in the agent shell
if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
fi