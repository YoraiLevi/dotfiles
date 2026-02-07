# windows -> wsl2:
home="$(wslpath -u "$(cmd.exe /c "echo %USERPROFILE%" | tr -d '\r' | sed 's|\\|/|g')")/.wsl2/home/"
shopt -s dotglob      # include hidden files
for file in "$home"/*; do
    if [ -f "$file" ]; then
        target=~/"$(basename "$file")"
        rm -f ~/"$target" 2> /dev/null        # remove existing file/symlink
        ln -sf "$file" "$target"              # create symlink
    fi
done
