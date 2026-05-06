#!/usr/bin/env bash

_ghost_history_file="$HOME/.bash_history"
_ghost_max_entries=10000
_ghost_last_render=""
_ghost_suggestion=""
_ghost_suppress=""
_ghost_last_prompt=""
_ghost_last_line=""

declare -A _ghost_index

_ghost_load_history() {
    local line count=0
    declare -A seen

    mapfile -t lines < <(tail -n "$_ghost_max_entries" "$_ghost_history_file" 2>/dev/null)

    for ((i=${#lines[@]}-1; i>=0; i--)); do
        line="${lines[i]}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || -n "${seen[$line]+_}" ]] && continue
        seen["$line"]=1
        _ghost_index["${line:0:1}"]+="${line}"$'\n'
        (( ++count >= _ghost_max_entries )) && break
    done
}

_ghost_find() {
    local prefix="$1"
    _ghost_suggestion=""
    [[ -z "$prefix" ]] && return
    local bucket=${prefix:0:1}
    local len=${#prefix}
    local entry
    while IFS= read -r entry; do
        [[ "$entry" == "$prefix"* && ${#entry} -gt len ]] && {
            _ghost_suggestion="${entry:$len}"
            break
        }
    done <<< "${_ghost_index[$bucket]}"
}

_ghost_render() {
    [[ -n "$_ghost_suppress" ]] && return
    [[ $READLINE_POINT -ne ${#READLINE_LINE} ]] && return

    local prefix="${READLINE_LINE:0:$READLINE_POINT}"
    _ghost_find "$prefix"

    local state="$READLINE_LINE|$_ghost_suggestion"
    [[ "$state" == "$_ghost_last_render" ]] && return
    _ghost_last_render="$state"

    local p="${PS1@P}"
    p="${p##*$'\n'}"
    _ghost_last_prompt="$p"
    _ghost_last_line="$READLINE_LINE"
    printf '\e[s\r\e[K%s%s' "$p" "$READLINE_LINE"
    [[ -n "$_ghost_suggestion" ]] && printf '\e[38;5;245m%s\e[0m' "$_ghost_suggestion"
    printf '\e[u'
}

_ghost_dismiss() {
    local had="${_ghost_last_render#*|}"
    _ghost_suggestion=""
    _ghost_last_render=""
    [[ -z "$had" ]] && return
    local p="${PS1@P}"
    p="${p##*$'\n'}"
    printf '\e[s\r\e[K%s%s\e[u' "$p" "$READLINE_LINE"
}

_ghost_ps0_cleanup() {
    [[ -n "$_ghost_last_render" ]] && printf '\e[1A\r%s%s\e[K\e[1B\r' "$_ghost_last_prompt" "$_ghost_last_line"
    _ghost_last_render=""
}

_ghost_insert() {
    _ghost_suppress=""
    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_key}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT++))
    _ghost_last_render=""
    _ghost_render
}

_ghost_accept() {
    if [[ $READLINE_POINT -lt ${#READLINE_LINE} ]]; then
        ((READLINE_POINT++))
        if [[ $READLINE_POINT -eq ${#READLINE_LINE} ]]; then
            _ghost_last_render=""
            _ghost_render
        fi
        return
    fi
    [[ -z "$_ghost_suggestion" ]] && return
    [[ "$_ghost_last_render" != "$READLINE_LINE|$_ghost_suggestion" ]] && return

    READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${_ghost_suggestion}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT+=${#_ghost_suggestion}))
    _ghost_last_render=""
    _ghost_suggestion=""
}

_ghost_left() {
    _ghost_dismiss
    (( READLINE_POINT > 0 )) && ((READLINE_POINT--))
}

_ghost_home() {
    _ghost_dismiss
    READLINE_POINT=0
}

_ghost_end() {
    READLINE_POINT=${#READLINE_LINE}
    _ghost_last_render=""
    _ghost_render
}

_ghost_backspace() {
    (( READLINE_POINT == 0 )) && return
    _ghost_dismiss
    _ghost_suppress=1
    READLINE_LINE="${READLINE_LINE:0:$((READLINE_POINT-1))}${READLINE_LINE:$READLINE_POINT}"
    ((READLINE_POINT--))
}

_ghost_bind_char() {
    local key="$1"
    bind -x "\"$key\": _ghost_key=$(printf '%q' "$key"); _ghost_insert"
}

_ghost_load_history

PS0='$(_ghost_ps0_cleanup)'"${PS0}"

bind -x '"\e[C":  _ghost_accept'   # Right Arrow
bind -x '"\e[D":  _ghost_left'     # Left Arrow
bind -x '"\eOD":  _ghost_left'     # Left Arrow (alt sequence)
bind -x '"\e[H":  _ghost_home'     # Home
bind -x '"\eOH":  _ghost_home'     # Home (alt sequence)
bind -x '"\e[1~": _ghost_home'     # Home (linux console)
bind -x '"\e[F":  _ghost_end'      # End
bind -x '"\eOF":  _ghost_end'      # End (alt sequence)
bind -x '"\e[4~": _ghost_end'      # End (linux console)
bind -x '"\C-a":  _ghost_home'     # Ctrl+A
bind -x '"\C-e":  _ghost_end'      # Ctrl+E
bind -x '"\C-h":  _ghost_backspace'
bind -x '"\C-?":  _ghost_backspace'
bind -x '"\e":    _ghost_dismiss'  # Escape

for c in {a..z} {A..Z} {0..9} \
         ' ' '-' '_' '/' '.' ',' '@' '=' '+' \
         '>' '<' '|' '&' ':' ';' '*' '?' '!' '%' \
         '#' '~' '^' '(' ')' '[' ']' '{' '}'; do
    _ghost_bind_char "$c"
done

# echo "Ghost enabled - Right Arrow accepts suggestions"
