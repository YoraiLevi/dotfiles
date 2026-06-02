#!/usr/bin/env sh
# wait_for_prompt.sh — POSIX fallback for wait_for_prompt.py.
# Block until an interactive process in a tmux pane is idle, then exit 0.
# Exit 1 on timeout. See wait_for_prompt.py for the full rationale.
#
# READY = ready-regex matches the last visible lines AND busy-regex (if set)
# does not match AND the capture is identical for SETTLE consecutive polls.
#
# Usage:
#   wait_for_prompt.sh [-t target] [-r ready_re] [-b busy_re] \
#                      [-T timeout_s] [-i interval_s] [-s settle] \
#                      [-c container] [-n lines] [-v]
#
# Defaults: target=0:0.0  ready='[$#>%] ?$'  timeout=30  interval=0.5
#           settle=2  lines=12
# Override ready_re per REPL:  python '>>> $'  node '> $'  claude '❯'
#
# Example:
#   ./wait_for_prompt.sh -r '>>> $' && \
#     tmux send-keys -t 0:0.0 -l 'print(2+2)' && tmux send-keys -t 0:0.0 Enter

target="0:0.0"; ready='[$#>%] ?$'; busy=""; timeout=30; interval=0.5
settle=2; container=""; lines=12; verbose=0

while [ $# -gt 0 ]; do
  case "$1" in
    -t) target=$2; shift 2;;
    -r) ready=$2; shift 2;;
    -b) busy=$2; shift 2;;
    -T) timeout=$2; shift 2;;
    -i) interval=$2; shift 2;;
    -s) settle=$2; shift 2;;
    -c) container=$2; shift 2;;
    -n) lines=$2; shift 2;;
    -v) verbose=1; shift;;
    *) echo "wait_for_prompt: unknown arg $1" >&2; exit 2;;
  esac
done

# strip_trailing_blanks: tmux pads the pane with blank rows BELOW the cursor;
# drop them so the prompt (the last non-blank line) survives the `tail`.
strip_trailing_blanks() {
  awk '{a[NR]=$0} END{n=NR; while(n>0 && a[n] ~ /^[[:space:]]*$/) n--; for(i=1;i<=n;i++) print a[i]}'
}
cap() {
  if [ -n "$container" ]; then
    docker exec "$container" tmux capture-pane -p -t "$target" 2>/dev/null | strip_trailing_blanks | tail -n "$lines"
  else
    tmux capture-pane -p -t "$target" 2>/dev/null | strip_trailing_blanks | tail -n "$lines"
  fi
}

# elapsed counter (not wall clock) → reproducible, clock-skew-proof
elapsed=0; last=""; stable=0
# integer-ish loop: convert timeout/interval to a step count
steps=$(awk "BEGIN{print int($timeout/$interval)+1}")
i=0
while [ "$i" -le "$steps" ]; do
  screen=$(cap)
  if [ -z "$screen" ] && ! cap >/dev/null 2>&1; then
    echo "wait_for_prompt: cannot capture pane (tmux/docker unreachable)" >&2
    exit 2
  fi
  is_ready=0; is_busy=0; is_same=0
  echo "$screen" | grep -Eq "$ready" && is_ready=1
  [ -n "$busy" ] && echo "$screen" | grep -Eq "$busy" && is_busy=1
  [ "$screen" = "$last" ] && is_same=1
  [ "$verbose" = 1 ] && echo "[$elapsed s] ready=$is_ready busy=$is_busy same=$is_same stable=$stable" >&2
  if [ "$is_ready" = 1 ] && [ "$is_busy" = 0 ] && [ "$is_same" = 1 ]; then
    stable=$((stable+1))
    [ "$stable" -ge "$settle" ] && exit 0
  else
    stable=0
  fi
  last=$screen
  sleep "$interval"
  elapsed=$(awk "BEGIN{print $elapsed+$interval}")
  i=$((i+1))
done

echo "wait_for_prompt: TIMED OUT after ${timeout}s — still busy or prompt never returned. Do NOT send input; capture the full pane and investigate." >&2
exit 1
