#!/usr/bin/env python3
r"""wait_for_prompt.py — block until an interactive process in a tmux pane is
ready for the next input, then exit 0. Exit 1 on timeout.

WHY THIS EXISTS
The single most common failure when driving a REPL through tmux is sending the
next keystroke while the program is still producing output. The input then
either interleaves with the output, lands in a half-drawn prompt, or is eaten
entirely. You cannot fix this by "sleeping a bit" — output timing is
unpredictable. The reliable fix is to POLL the pane until it looks idle, then
send. This script is that poll, so callers never have to eyeball the screen.

READY is defined as ALL of:
  1. the ready-regex matches somewhere in the last few visible lines
     (the prompt has come back), AND
  2. the busy-regex (if given) does NOT match (no spinner / "running…"), AND
  3. the captured screen is byte-identical for `--settle` consecutive polls
     (the output has stopped changing — this catches mid-generation pauses
     that briefly look idle).

USAGE
  wait_for_prompt.py [--target 0:0.0] [--ready-regex RE] [--busy-regex RE]
                     [--timeout 30] [--interval 0.5] [--settle 2]
                     [--container NAME] [--lines 12] [--verbose]

  --target       tmux target  session:window.pane  (default 0:0.0)
  --ready-regex  prompt-ready pattern, tested against the last non-blank lines.
                 IMPORTANT: tmux `capture-pane` STRIPS trailing whitespace from
                 every line, so a prompt that is really "> " is captured as ">".
                 NEVER anchor on a trailing space (`>>> $` will never match) —
                 end with `\s*$` (or just `$`). Default `[\$#>%❯]\s*$` matches
                 most prompts. OVERRIDE per REPL for precision:
                   python  '>>>\s*$'      node  '>\s*$'      psql  '=[#>]\s*$'
                   claude  '❯\s*$'        irb   '>\s*$'      sqlite '^sqlite>\s*$'
  --busy-regex   if this matches, NOT ready (optional). e.g. for claude:
                   'esc to interrupt|(✶|✻|✢|·|✻)\\s'
  --timeout      seconds before giving up and exiting 1 (default 30)
  --interval     seconds between polls (default 0.5)
  --settle       require this many consecutive identical+ready captures
                 (default 2). Raise to 3-4 for chatty/async programs.
  --container    if set, capture via `docker exec <container> tmux …`
  --lines        how many trailing lines of the pane to test (default 12)
  --verbose      print each poll's decision to stderr

EXIT CODES
  0  ready (caller may now send the next input)
  1  timed out (the program is still busy or the prompt never returned —
     do NOT send input; capture the full pane and investigate)
  2  bad usage / tmux not reachable

EXAMPLE
  # wait for a python REPL in the default pane, then send a line:
  python wait_for_prompt.py --ready-regex '>>>\s*$' && \
    tmux send-keys -t 0:0.0 -l 'print(2+2)' && tmux send-keys -t 0:0.0 Enter
"""
import argparse
import re
import subprocess
import sys
import time


def capture(target, container, lines):
    """Return the last `lines` visible rows of the pane as one string."""
    cmd = []
    if container:
        cmd += ["docker", "exec", container]
    cmd += ["tmux", "capture-pane", "-p", "-t", target]
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=10
        ).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        sys.stderr.write("wait_for_prompt: cannot capture pane: %r\n" % e)
        return None
    rows = out.splitlines()
    # CRITICAL: tmux pads the pane with blank rows BELOW the cursor, so a naive
    # rows[-lines:] grabs whitespace and misses the prompt line (which sits at
    # the cursor, higher up). Strip trailing blank rows first, THEN take the
    # last `lines`. This is the same "tail clips the block" trap that bites
    # callers who pipe `capture-pane -p | tail -n N` directly.
    while rows and not rows[-1].strip():
        rows.pop()
    return "\n".join(rows[-lines:]) if rows else ""


def main():
    ap = argparse.ArgumentParser(add_help=True)
    # Defaults are TUNED FOR THE CLAUDE CODE TUI:
    #   ready = the input prompt char `❯` is on screen (the TUI is up), AND
    #   busy  = `esc to interrupt` is NOT shown (Claude shows it only while a
    #           turn is generating). Claude streams, so settle=3 (3 identical
    #           polls) avoids firing during a mid-generation pause.
    ap.add_argument("--target", default="0:0.0")
    ap.add_argument("--ready-regex", default=r"❯")
    ap.add_argument("--busy-regex", default=r"esc to interrupt")
    ap.add_argument("--timeout", type=float, default=45.0)
    ap.add_argument("--interval", type=float, default=0.5)
    ap.add_argument("--settle", type=int, default=3)
    ap.add_argument("--container", default="")
    ap.add_argument("--lines", type=int, default=16)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    ready_re = re.compile(a.ready_regex)
    busy_re = re.compile(a.busy_regex) if a.busy_regex else None

    deadline = a.timeout  # we measure elapsed via a counter, not wall clock,
    elapsed = 0.0          # so the script is reproducible and clock-skew-proof
    last = None
    stable = 0

    while elapsed <= deadline:
        screen = capture(a.target, a.container, a.lines)
        if screen is None:
            return 2

        ready = bool(ready_re.search(screen))
        busy = bool(busy_re.search(screen)) if busy_re else False
        unchanged = screen == last

        if a.verbose:
            sys.stderr.write(
                "[%.1fs] ready=%s busy=%s unchanged=%s stable=%d\n"
                % (elapsed, ready, busy, unchanged, stable)
            )

        if ready and not busy and unchanged:
            stable += 1
            if stable >= a.settle:
                return 0
        else:
            stable = 0

        last = screen
        time.sleep(a.interval)
        elapsed += a.interval

    sys.stderr.write(
        "wait_for_prompt: TIMED OUT after %.1fs — pane still busy or prompt "
        "never returned. Do NOT send input; capture the full pane "
        "(tmux capture-pane -p -S -50) and investigate.\n" % a.timeout
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
