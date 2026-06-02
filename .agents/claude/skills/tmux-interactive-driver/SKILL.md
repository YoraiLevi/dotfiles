---
name: tmux-interactive-driver
description: >-
  Drive interactive command-line REPLs and long-running interactive processes through tmux —
  send input, wait until the program is actually ready, and read its output back programmatically.
  Use whenever you need to interact with a running interactive process rather than run a one-shot
  command: a Python/Node/psql/irb/sqlite REPL, an SSH session, a TUI, a debugger (gdb/pdb), or a
  nested `claude` session. Trigger phrases: "drive a REPL", "test in a tmux session", "interact
  with a running interactive process", "feed input to a process on stdin", "automate a CLI that
  prompts", "send-keys / capture-pane". Covers tmux send-keys (and the literal-text vs Enter/C-m
  gotcha), capture-pane reads, a wait_for_prompt readiness poller, and session lifecycle
  (new-session/new-window/detach/kill-session). NOT for one-shot non-interactive shell commands —
  run those directly with the Bash tool; reach for this only when a process stays open and exchanges
  input/output across multiple steps.
---

# tmux-interactive-driver

## Overview

Some programs don't take their input as command-line arguments — they **open and wait**, reading
from stdin and printing to a live terminal: REPLs (`python3`, `node`, `psql`, `irb`, `sqlite3`),
debuggers (`pdb`, `gdb`), SSH sessions, full-screen TUIs, and nested AI CLIs like `claude`. You
cannot drive these with one Bash call, because the Bash tool runs a command, waits for it to exit,
and returns — but the REPL never exits, so the call hangs or you only ever see the banner.

**tmux** solves this: it runs the interactive program inside a detached terminal you can poke at
from the outside. You push keystrokes in with `send-keys` and read the screen back with
`capture-pane`. Your control commands return instantly; the REPL keeps running between them.

The whole skill rests on **three moves**, and almost every failure is getting one of them wrong:

1. **Send** — type text with `send-keys -l '<text>'`, then send `Enter` as a **separate** call.
2. **Wait** — never send the next input until the program is ready again. Don't guess with `sleep`;
   poll the screen with `scripts/wait_for_prompt.py` until the prompt returns and output stops.
3. **Read** — `capture-pane -p` returns the *visible* screen; widen with `-S -N` for scrollback,
   and when the real evidence is a file (a log, an output file), read the **file**, not the screen.

For the exhaustive copy-paste command catalog (every lifecycle verb, key name, and flag), read
**`references/commands.md`**. For driving a nested `claude` session specifically — which has its own
idle-detection and TUI gotchas — use the companion **`drive-nested-claude`** skill. This skill is
the general engine; that one is the specialized application.

### The mental model: target, send, capture

- A tmux **target** is `session:window.pane`, e.g. `0:0.0` = session `0`, window `0`, pane `0`.
- You **send** keystrokes to a target and **capture** the rendered screen from it.
- Everything is asynchronous: keystrokes are delivered immediately but the program reacts on its own
  clock, so you must **wait for readiness between steps** or your input lands in the wrong place.

### Transport: local, Docker, or remote

The exact same tmux commands work wherever the session lives. If the program runs **inside a Docker
container**, prefix every tmux call with `docker exec <container>`:

```bash
tmux send-keys -t 0:0.0 -l 'print(2+2)'                    # local tmux
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'print(2+2)'   # tmux inside a container
```

`scripts/wait_for_prompt.py` takes `--container <name>` to drive the container case.

## Examples

### Example 1 — drive a Python REPL end to end (verified live)

```bash
PROMPT=scripts/wait_for_prompt.py    # adjust to the skill's path

# 1. Start the REPL in a fresh pane (here, inside container qa-claude):
docker exec qa-claude tmux respawn-pane -k -t 0:0.0 -c /work 'bash -l'
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'python3'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter

# 2. WAIT until the >>> prompt is actually up (poll, don't sleep):
python "$PROMPT" --container qa-claude --target 0:0.0 --ready-regex '>>>\s*$' --timeout 15

# 3. Send a statement, then Enter as a SEPARATE call:
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'print(6*7)'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter

# 4. WAIT for the prompt to return (the computation finished), then READ:
python "$PROMPT" --container qa-claude --target 0:0.0 --ready-regex '>>>\s*$' --timeout 15
docker exec qa-claude tmux capture-pane -p -t 0:0.0 -S -20 | grep -v '^[[:space:]]*$' | tail -n 4
```

Expected pane tail:
```text
>>> print(6*7)
42
>>>
```
The `42` between the echoed input and the returned `>>>` prompt is the proof the REPL evaluated it.

### Example 2 — the readiness poller is the heart of it

The poller (`wait_for_prompt.py`) blocks until the pane is **ready AND idle**: the prompt regex
matches the last non-blank lines, an optional busy-regex does *not* match, and the screen is
byte-identical for a few consecutive polls (so a mid-output pause can't fool it). Exit `0` = go;
exit `1` = timed out, do **not** send input.

```bash
# Generic shell prompt (default regex handles $ # > % ❯):
python scripts/wait_for_prompt.py --target 0:0.0
# psql: wait for the "db=#" or "db=>" prompt:
python scripts/wait_for_prompt.py --target 0:0.0 --ready-regex '=[#>]\s*$'
# A program that streams (raise --settle so a streaming pause doesn't read as idle):
python scripts/wait_for_prompt.py --target 0:0.0 --busy-regex 'Running|\.\.\.' --settle 4
```

Wire it into a send like this — only send if the wait succeeded:

```bash
python scripts/wait_for_prompt.py --target 0:0.0 --ready-regex '>>>\s*$' \
  && tmux send-keys -t 0:0.0 -l 'data = load()' \
  && tmux send-keys -t 0:0.0 Enter
```

### Example 3 — full session lifecycle (start clean, work, tear down)

```bash
tmux new-session -d -s repl -x 200 -y 50     # detached session named "repl", sized generously
tmux send-keys -t repl -l 'node'             # start node in it
tmux send-keys -t repl Enter
python scripts/wait_for_prompt.py --target repl --ready-regex '>\s*$'
tmux send-keys -t repl -l 'console.log(1+1)'; tmux send-keys -t repl Enter
python scripts/wait_for_prompt.py --target repl --ready-regex '>\s*$'
tmux capture-pane -p -t repl -S -20 | tail -n 5
tmux kill-session -t repl                    # done — clean up
```

See `references/commands.md` for `new-window`, `split-window`, `detach`, sending control keys
(`C-c`, `C-d`, `C-u`), and reading scrollback.

## Troubleshooting

Each entry is a real failure mode with its cause and the fix. Most were found by actually driving
REPLs through tmux (some are recorded in this project's `PITFALLS.md`).

### Input "didn't go in" — you typed the word `Enter` instead of pressing it
- **Cause:** `send-keys -l 'print(1)\nEnter'` (or putting the text and `Enter` in one call) sends the
  *literal characters*; `-l` means "no key-name interpretation," so `Enter` is typed, not pressed.
- **Solution:** Two separate calls. `send-keys -t T -l '<text>'` then `send-keys -t T Enter`. The
  text call uses `-l`; the key call does **not** (so tmux interprets `Enter`/`C-c`/`Down` as keys).
  `C-m` is the raw carriage return and is equivalent to `Enter` if you ever need it inline.

### A `;` in your input vanishes / the line lands unfinished
- **Cause:** tmux treats `;` as its own **command separator**, and it can split the `send-keys` payload
  even inside `-l '...'`. Sending `SELECT sum(n) FROM t;` delivers `SELECT sum(n) FROM t` and drops the
  `;`, so the REPL sits in continuation mode (`...>`) waiting for the statement to end. (Found via eval
  driving sqlite.) Other tmux-special characters in the payload can bite the same way.
- **Solution:** escape the semicolon as `\;` in the payload: `send-keys -t T -l 'SELECT sum(n) FROM t\;'`.
  Equivalently, send the terminator as its own key. When a statement "hangs" with no error, suspect an
  eaten `;` first — capture the pane and look for a `...>`/continuation prompt.

### `capture-pane | tail -n N` comes back blank or clipped
- **Cause:** `capture-pane -p` returns only the **visible** screen, and tmux pads the area **below the
  cursor with blank rows**. `| tail -n 8` then grabs those blanks (or, after scrolling, a fragment),
  so you wrongly conclude the step failed. (A freshly-launched REPL shows its prompt high with empty
  space beneath — the classic case.)
- **Solution:** Strip trailing blanks and widen with scrollback:
  `capture-pane -p -t T -S -40 | grep -v '^[[:space:]]*$' | tail -n 12`. When the proof is a file
  (an output file, a log), read the **file** directly — the screen is for prompts and dialogs, files
  are for evidence. `wait_for_prompt.py` already strips trailing blank rows internally.

### Your ready-regex never matches even though the prompt is clearly there
- **Cause:** **tmux `capture-pane` strips trailing whitespace from every line.** A prompt that is
  really `>>> ` (trailing space) is captured as `>>>`. A regex anchored on that space (`>>> $`) can
  never match. Verified live: `cat -A` of the captured line shows `>>>$` (no space before the EOL).
- **Solution:** End prompt regexes with `\s*$` (or just `$`), never a literal trailing space:
  `>>>\s*$`, `>\s*$`, `=[#>]\s*$`, `❯`. The poller's default (`[\$#>%❯]\s*$`) already accounts for this.

### Input lands mid-output / interleaves with the program's text
- **Cause:** You sent the next keystroke before the program finished reacting. Output timing is
  unpredictable, so a fixed `sleep` is a coin flip — too short and you race it, too long and you're slow.
- **Solution:** Replace every "sleep then send" with "**wait_for_prompt then send**." Poll until the
  prompt returns and the screen is stable; only then send. For programs that *stream* (print, pause,
  print again), add a `--busy-regex` and raise `--settle` so a streaming gap isn't mistaken for idle.

### `wait_for_prompt.py` crashes or mangles a non-ASCII prompt on Windows
- **Cause:** On Windows, `subprocess(text=True)` decodes with the OS codepage (cp1252), which cannot
  decode glyphs like `❯` (U+276F); stdout can also come back `None`. Either breaks the capture.
- **Solution:** The bundled poller already forces `encoding="utf-8", errors="replace"` and guards a
  `None` stdout. If you write your own capture, do the same — never rely on the locale codepage for
  terminal output.

### The pane shows `bash` when you expected your program (a blank capture)
- **Cause:** Your launch command failed — almost always a bad `cd`. A pane's working directory and
  `$HOME` can differ from a `docker exec bash -lc` shell, so a relative path or `~` may not resolve.
- **Solution:** Use **absolute paths** in the launch, and verify with
  `tmux list-panes -t 0:0 -F '#{pane_index} #{pane_current_command}'` — if it says `bash` not your
  program, the launch didn't take. Re-launch and confirm `pane_current_command` before driving.

### A REPL won't quit / you can't get back to the shell
- **Cause:** REPLs trap `Ctrl-C` (it interrupts the current line, not the process). Sending text like
  `exit` without Enter does nothing; some REPLs need EOF.
- **Solution:** Send the REPL's own quit (`exit()` + Enter for python, `.exit` for node) or send EOF
  with `send-keys -t T C-d`. As a last resort, `tmux respawn-pane -k -t T '<shell>'` kills whatever's
  in the pane and gives you a fresh shell; `tmux kill-session -t <name>` removes the whole session.

## Test suites

### Trigger suite (does the skill fire when it should?)

**Should trigger:**
- "I started a `psql` session in tmux and need to run a few queries and read the results — drive it for me."
- "Open a python REPL and feed it these statements one at a time, checking the output of each before the next."
- "There's a long-running interactive process in pane 0:0.1; send it `status` and capture what it prints."
- "Automate this CLI installer that keeps prompting me for input — interact with it in a tmux session."
- "Drive a nested claude session in the container and read its reply." *(this skill, or hand off to `drive-nested-claude`)*

**Should NOT trigger (near-misses):**
- "Run `pytest` and tell me if it passes." → one-shot command; use the Bash tool directly.
- "Read `/var/log/syslog` and find the errors." → file read, not an interactive process.
- "Write a tmux config that sets the status bar colour." → editing a config, not driving a process.
- "Kill the process listening on port 8080." → one-shot admin command, no interactive exchange.

### Functionality suite (does the skill actually work?)

- **Given** a fresh pane, **when** the agent starts `python3` and uses `wait_for_prompt.py` before each
  send, **then** sending `print(6*7)` yields `42` in the capture and no input is ever interleaved.
- **Given** a prompt whose real form has a trailing space, **when** the agent writes the ready-regex,
  **then** it ends with `\s*$` (not a literal space) and the wait succeeds.
- **Given** a program still producing output, **when** the agent calls `wait_for_prompt.py`, **then**
  it blocks (exit 1 on timeout) rather than returning ready, and the agent does not send input.
- **Given** the task is a one-shot command (`ls`, `pytest`), **when** evaluated, **then** the agent
  does NOT spin up tmux and just runs it directly.
