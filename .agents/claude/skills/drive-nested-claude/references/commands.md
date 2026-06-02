# Driving a nested `claude` session — command reference

Copy-paste catalog specific to operating a Claude Code TUI inside a tmux pane. For base tmux verbs
(targets, splits, capture-pane flags, lifecycle), see the `tmux-interactive-driver` skill's
`references/commands.md`. Replace `T` with your target (e.g. `0:0.0`) and `qa-claude` with your
container (drop `docker exec qa-claude` for a local session).

> **Windows hosts:** every bare-slash command below (`/config`, `/theme`, `/agents`, `/clear`,
> `/exit`, `/compact`, `/mcp`) MUST be prefixed with `MSYS_NO_PATHCONV=1` or the slash is rewritten to
> a Windows path. Namespaced slashes (`/plugin:cmd`) do NOT need it.

## Contents
- [1. Launch and reach idle](#1-launch-and-reach-idle)
- [2. Send a prompt and wait for the turn to finish](#2-send-a-prompt-and-wait-for-the-turn-to-finish)
- [3. Answer dialogs (trust / edit / tool permission)](#3-answer-dialogs-trust--edit--tool-permission)
- [4. Slash menus and TUI navigation](#4-slash-menus-and-tui-navigation)
- [5. Verify by real signals, per construct](#5-verify-by-real-signals-per-construct)
- [6. Teardown and reset](#6-teardown-and-reset)

## 1. Launch and reach idle

```bash
docker exec qa-claude tmux respawn-pane -k -t 0:0.0 -c /workspace 'bash -l'   # clean pane, abs cwd
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'claude'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
# Wait out boot + any session-start turn (monitors/hooks may narrate first):
python scripts/wait_for_prompt.py --container qa-claude --target 0:0.0 --timeout 45
```
First launch in a new dir shows **"Do you want to trust the files in this folder?"** → `Enter`. If the
dir was trusted before, no dialog — don't wait for one. Confirm claude is really up:
`docker exec qa-claude tmux list-panes -t 0:0 -F '#{pane_index} #{pane_current_command}'` → expect
`claude`/`node`, not `bash`.

## 2. Send a prompt and wait for the turn to finish

```bash
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'In one short sentence, what is 2+2?'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
python scripts/wait_for_prompt.py --container qa-claude --target 0:0.0 --timeout 45
docker exec qa-claude tmux capture-pane -p -t 0:0.0 -S -40 | grep -v '^[[:space:]]*$' | tail -n 6
```
Readiness (claude-tuned defaults): ready = `❯` on screen, busy = `esc to interrupt` shown. The poller
returns only when `❯` is present, `esc to interrupt` is gone, and the screen is stable for `--settle`
(3) polls. Do not send a follow-up while a spinner (`✻ …`, `esc to interrupt`) is visible — it queues.

## 3. Answer dialogs (trust / edit / tool permission)

```bash
sleep 8                                                        # let the dialog render (~6-9s)
docker exec qa-claude tmux capture-pane -p -t 0:0.0 | tail -n 10   # confirm WHICH dialog is up
docker exec qa-claude tmux send-keys -t 0:0.0 Enter           # accept highlighted option 1 (Yes)
# "Yes, allow all this session" = option 2:
docker exec qa-claude tmux send-keys -t 0:0.0 Down
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
docker exec qa-claude tmux send-keys -t 0:0.0 Escape          # dismiss / cancel a dialog
```

## 4. Slash menus and TUI navigation

```bash
# /agents — OPENS ON THE "Running" TAB. Go Left to "Agents" to see plugin agents:
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t 0:0.0 -l '/agents'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter; sleep 3
docker exec qa-claude tmux send-keys -t 0:0.0 Left            # → Agents tab
docker exec qa-claude tmux capture-pane -p -t 0:0.0 | tail -n 20

# /config — set a value (write commits on the inner list-Enter):
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t 0:0.0 -l '/config'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter; sleep 3
docker exec qa-claude tmux send-keys -t 0:0.0 -l 'output style'; sleep 1   # type to filter the row
docker exec qa-claude tmux send-keys -t 0:0.0 Enter; sleep 1               # select the row
docker exec qa-claude tmux send-keys -t 0:0.0 Space; sleep 1               # open the value list
docker exec qa-claude tmux send-keys -t 0:0.0 Down Down; docker exec qa-claude tmux send-keys -t 0:0.0 Enter   # commit
docker exec qa-claude tmux send-keys -t 0:0.0 Escape                       # close the panel (non-destructive)

# /theme — its own picker (real command); highlight starts on the ACTIVE theme, so compute N:
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t 0:0.0 -l '/theme'
docker exec qa-claude tmux send-keys -t 0:0.0 Enter; sleep 2
docker exec qa-claude tmux capture-pane -p -t 0:0.0 | grep -nE '❯|from ' | head   # find the ❯ row, count Downs to target
```
Slash autocomplete: type `/<prefix>` (no Enter) and `capture-pane` to see the dropdown; namespaced
plugin commands render full-path, skills render as bare `/name`.

## 5. Verify by real signals, per construct

Never trust the chat prose. Establish a control, act, then read the **signal**:

| Construct | Real signal (read this, not the chat) |
|---|---|
| hook | `docker exec qa-claude bash -lc 'cat /tmp/hook-fired-<event>.log'` — marker + JSON payload. `rm -f` first as the control. |
| command | the rendered block in the pane (`capture-pane … -S -40`), e.g. a `[command:hello] args=[…]` line. |
| skill | the skill's output block; namespaced slash resolved. |
| sub-agent | a `dgxsparklabs-…:summarizer(…)` task header + a `Done (N tool use…)` line. |
| mcp | a `Called plugin:…:<server>` line + the proxy log `/tmp/mcp_proxy_<server>.log` (`-> request / <- response`). |
| monitor | probe with tool use FORBIDDEN; the model recites `[monitor:<name>]` context it could only have from injection. |
| output-style | `cat .claude/settings.local.json` → namespaced `"outputStyle"`. Set a different one first as control. |
| theme | `grep theme ~/.claude/settings.json` → `custom:<plugin>:<stem>` (USER scope). Reset to another theme first. |
| lsp | EDIT (not read) a buggy file → a `(example-lsp)`-tagged diagnostic + the server log `/tmp/example_lsp.log`. |

## 6. Teardown and reset

```bash
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t 0:0.0 -l '/exit'   # clean exit; fires SessionEnd
docker exec qa-claude tmux send-keys -t 0:0.0 Enter
# Force a clean slate mid-run:
docker exec qa-claude tmux respawn-pane -k -t 0:0.0 -c /workspace 'bash -l'
docker exec qa-claude bash -lc 'rm -f /tmp/hook-fired-*.log /tmp/mcp_proxy_*.log /tmp/example_lsp.log'
```
For parallel QA, give each driver its **own** session (`tmux new-session -d -s eval-<id>`) so they
don't share pane `0:0.0`.
