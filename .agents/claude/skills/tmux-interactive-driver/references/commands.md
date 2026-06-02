# tmux command reference — driving interactive processes

Exhaustive copy-paste catalog. Replace `T` with your target (`session:window.pane`, e.g. `0:0.0`)
and prefix with `docker exec <container>` when the session lives in a container.

## Contents
- [1. Targets and addressing](#1-targets-and-addressing)
- [2. Create / inspect sessions, windows, panes](#2-create--inspect-sessions-windows-panes)
- [3. Sending input (send-keys) — the core](#3-sending-input-send-keys--the-core)
- [4. Control keys and special keys](#4-control-keys-and-special-keys)
- [5. Reading output (capture-pane)](#5-reading-output-capture-pane)
- [6. Waiting for readiness](#6-waiting-for-readiness)
- [7. Detach, attach, kill (lifecycle end)](#7-detach-attach-kill-lifecycle-end)
- [8. Resetting a stuck pane](#8-resetting-a-stuck-pane)
- [9. Quick failure-mode index](#9-quick-failure-mode-index)

## 1. Targets and addressing

`session:window.pane`. Pieces are optional from the right (`-t repl` = session repl, current window/pane).

```bash
tmux list-sessions -F '#{session_name}'                 # names of all sessions
tmux list-windows  -t repl -F '#{window_index} #{window_name}'
tmux list-panes    -t 0:0  -F '#{pane_index} cmd=#{pane_current_command} #{pane_width}x#{pane_height} cwd=#{pane_current_path}'
```
`pane_current_command` is your single most useful probe: it tells you what is *actually* running in
the pane (`bash`, `python3`, `node`, `claude`). If it's `bash` when you expected your REPL, the
launch failed.

## 2. Create / inspect sessions, windows, panes

```bash
tmux new-session  -d -s repl -x 200 -y 50    # NEW detached session "repl", 200x50 (bigger = less scroll loss)
tmux new-window   -t repl -n work            # new window "work" in session repl
tmux split-window -h -t 0:0                  # split current window left|right; new pane = next index
tmux split-window -v -t 0:0                  # split top/bottom
```
- `-d` = detached (don't attach your terminal). Always use it when scripting.
- After a horizontal split, the original pane keeps index `0`, the new one is `1` → target `0:0.1`.
- Size matters: a small pane scrolls content out of `capture-pane`'s visible area fast. `-x/-y` or
  `tmux resize-window -t repl -x 200 -y 50`.

Start a program in a pane (two steps — text, then Enter; see section 3):
```bash
tmux send-keys -t repl -l 'python3'; tmux send-keys -t repl Enter
```

## 3. Sending input (send-keys) — the core

**THE rule:** send the literal text with `-l`, then send `Enter` as a SEPARATE call.

```bash
tmux send-keys -t T -l 'print(2 + 2)'    # types the characters literally (-l = literal, no key names)
tmux send-keys -t T Enter                # presses Return (NO -l, so "Enter" is a key name)
```

Why two calls:
- `-l` disables key-name interpretation, so the whole string is typed verbatim — including spaces,
  quotes, parentheses. Good for code.
- Without `-l`, tmux reads each word as a **key name** (`Enter`, `Up`, `C-c`). That's how you press
  Return — but it also means a stray word like `Space` becomes a spacebar press, not the text "Space".
- ⚠ **Never combine them.** `send-keys -t T -l 'print(2+2)\nEnter'` literally types
  `print(2+2)\nEnter` and never submits — the #1 mistake. (`\n` inside `-l` is also literal, not a
  newline.)

Multi-line / multi-statement input — send each line then Enter, or send a heredoc-style block by
repeating the pair. To submit a blank line (e.g. end a Python block), `send-keys -t T Enter` alone.

Quoting: wrap the `-l` payload in single quotes so the shell doesn't expand `$`, backticks, `!`.
If the payload itself contains a single quote, use `'"'"'` or switch the outer quote.

**Semicolons:** tmux uses `;` as its own command separator and can split the payload even under `-l`.
A statement like `SELECT sum(n) FROM t;` arrives without its `;` and the REPL waits in continuation
mode. Escape it: `send-keys -t T -l 'SELECT sum(n) FROM t\;'`.

## 4. Control keys and special keys

Send these **without** `-l` (they are key names):

| Key | Meaning |
|---|---|
| `Enter` (or `C-m`) | Return / submit the line |
| `C-c` | interrupt the current line/command (SIGINT to foreground) |
| `C-d` | EOF — quits many REPLs (python, node, sh) from an empty line |
| `C-u` | clear the current input line (real typed chars only) |
| `Escape` | cancel a menu / leave a mode |
| `Tab` | completion / next field |
| `Up` `Down` `Left` `Right` | arrows (history, menu navigation) |
| `Space` | space (use as a key when a TUI binds it, e.g. toggles) |
| `BSpace` | backspace |

```bash
tmux send-keys -t T C-c            # interrupt
tmux send-keys -t T C-d            # EOF / quit the REPL
tmux send-keys -t T Down Enter     # arrow down then select (menu)
```

## 5. Reading output (capture-pane)

```bash
tmux capture-pane -p -t T                          # the VISIBLE screen, as plain text
tmux capture-pane -p -t T -S -40                   # + 40 lines of scrollback (use when it scrolled)
tmux capture-pane -p -t T -S -                     # the ENTIRE scrollback buffer
tmux capture-pane -p -e -t T                       # include ANSI colour escapes (assert on colour)
```
Post-process to find the real content (tmux pads below the cursor with blank lines):
```bash
tmux capture-pane -p -t T -S -40 | grep -v '^[[:space:]]*$' | tail -n 12   # drop blanks, last 12 real lines
```
- `-p` prints to stdout (without it, capture goes to a tmux buffer).
- **Trailing whitespace is stripped per line** — don't expect a prompt's trailing space to be present.
- For file-based evidence (logs, output files), `cat` the file instead — don't scrape the screen.

## 6. Waiting for readiness

Prefer the bundled poller over `sleep`:
```bash
python ../scripts/wait_for_prompt.py --target T --ready-regex '>>>\s*$' --timeout 20
# exit 0 → ready to send;  exit 1 → timed out, do NOT send, capture & investigate
```
Per-REPL ready-regexes (end with `\s*$`, never a literal space):

| REPL | ready-regex | busy-regex (optional) |
|---|---|---|
| python3 | `>>>\s*$` | |
| node | `>\s*$` | |
| psql | `=[#>]\s*$` | |
| irb | `>\s*$` | |
| sqlite3 | `^sqlite>\s*$` | |
| gdb / pdb | `\(gdb\)\s*$` / `\(Pdb\)\s*$` | |
| claude (TUI) | `❯` | `esc to interrupt` |

`--settle N` requires N identical consecutive polls (default 2) — raise it for programs that stream
output with pauses. `--busy-regex` marks "not ready while this matches" (a spinner, `Running…`).

If you cannot use the script, the inline equivalent is: capture, strip trailing blanks, check the
last non-blank line matches your prompt, sleep a short interval, repeat — with a timeout.

## 7. Detach, attach, kill (lifecycle end)

```bash
tmux detach -s repl                  # detach any attached client (session keeps running)
tmux kill-session -t repl            # destroy the session and everything in it
tmux kill-pane -t 0:0.1              # close one pane
tmux kill-server                     # nuke ALL sessions (last resort)
```
For scripted runs you typically `new-session -d` at the start and `kill-session` at the end. Use a
**unique session name per concurrent task** (e.g. `eval-3`) so parallel drivers don't collide on the
same pane.

## 8. Resetting a stuck pane

```bash
tmux respawn-pane -k -t 0:0.0 -c /abs/work 'bash -l'   # kill whatever's in the pane, fresh shell
tmux kill-pane -a -t 0:0.0                              # kill ALL panes except 0:0.0 (cleanup splits)
```
`respawn-pane -k` is the reliable "get me back to a known state" move when a REPL is wedged, a menu
is stuck, or a previous run left the pane mid-dialog.

## 9. Quick failure-mode index

| Symptom | Likely cause | Fix |
|---|---|---|
| typed `Enter` appears as text, nothing submits | text + `Enter` in one `-l` call | two separate `send-keys` calls |
| `capture-pane` blank / clipped | only visible screen; blank rows below cursor | `-S -40 \| grep -v '^[[:space:]]*$' \| tail` |
| ready-regex never matches | tmux stripped the prompt's trailing space | end regex with `\s*$`, not a space |
| anchored regex (`^sqlite>`) never matches | poller needs `re.MULTILINE` for `^`/`$` per line | bundled poller now compiles MULTILINE; or drop the `^` |
| a statement hangs in `...>` continuation | a literal `;` was eaten as tmux's separator | escape it: `-l '... t\;'` |
| input interleaves with output | sent before program was ready | `wait_for_prompt.py` then send |
| pane shows `bash`, capture empty | launch failed (bad `cd`/relative path) | absolute paths; check `pane_current_command` |
| poller crashes on `❯` (Windows) | cp1252 can't decode the glyph | force `encoding="utf-8"` (bundled poller does) |
| parallel drivers clobber each other | shared session/pane | one `new-session -d -s <unique>` per task |
