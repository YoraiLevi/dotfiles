# eval-2 — run slash command + capture (with_skill)

## Result: FAIL

The Lab Notebook block did **NOT** render. The command was accepted and submitted
(autocomplete resolved it to the plugin `dgxsparklabs-command-example-multi`), but
the model turn it depends on returned a **401 auth error**, so neither the debug
args line nor the markdown block were produced.

## What rendered in the session

The slash command is a *prompt-type* command — `hello.md` instructs the model to
(1) print a `[command:hello] args=[$ARGUMENTS]` debug line and (2) print a Lab
Notebook markdown block. Producing that output requires a live model turn. In this
session every model call 401s, so the rendered region was just the error:

```
❯ /dgxsparklabs-command-example-multi:hello
  ⎿  Please run /login · API Error: 401 Invalid authentication credentials
✻ Brewed for 2s
```

The same `401 Invalid authentication credentials` error also appeared on the
session-start monitor turns (disk-usage, memory-usage, git-status) at launch,
confirming this is a session-wide auth failure, not specific to the command.

## Debug args line

**Did NOT appear.** No `[command:hello] args=[...]` line rendered, because the
model turn that would emit it failed with the 401 before producing any output.

## Was a Lab Notebook block rendered?

**No.** No `# Lab Notebook — <DATE>` block, no `## Entries`, no checkbox line.

## Root cause (environment, not a command defect)

- The command is correctly installed and namespace-resolves (autocomplete listed
  the plugin's siblings `:goodbye`, plus the skill `/notebook`).
- `/root/.claude/.credentials.json` exists (471 bytes) but the API rejects it with
  401; no `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` env var is set in the
  container. The stored OAuth credential is expired/invalid → `Please run /login`.
- Because `/hello` is prompt-driven (not deterministic text), it cannot render
  anything without a working model turn. This is an auth/credential gap in the
  `qa-claude` container, not a fault in the slash command itself.

## Commands used

```bash
# isolated session
docker exec qa-claude tmux kill-session -t dnc2s            # (idempotent cleanup)
docker exec qa-claude tmux new-session -d -s dnc2s -x 200 -y 50

# put the pane in /workspace/lsptest (respawn -c did NOT stick — pane stayed in
# /workspace/marketplace; had to cd explicitly inside the login shell)
docker exec qa-claude tmux respawn-pane -k -t dnc2s:0.0 -c /workspace/lsptest 'bash -l'
docker exec qa-claude tmux send-keys -t dnc2s:0.0 -l 'cd /workspace/lsptest'
docker exec qa-claude tmux send-keys -t dnc2s:0.0 Enter
docker exec qa-claude tmux list-panes -t dnc2s:0 -F '#{pane_current_path}'   # verify

# launch claude (no trust dialog — dir already trusted)
docker exec qa-claude tmux send-keys -t dnc2s:0.0 -l 'claude'
docker exec qa-claude tmux send-keys -t dnc2s:0.0 Enter
python wait_for_prompt.py --container qa-claude --target dnc2s:0.0 --timeout 45

# send the NAMESPACED slash command (has ':' → MSYS_NO_PATHCONV NOT needed)
docker exec qa-claude tmux send-keys -t dnc2s:0.0 -l '/dgxsparklabs-command-example-multi:hello'
docker exec qa-claude tmux send-keys -t dnc2s:0.0 Enter
python wait_for_prompt.py --container qa-claude --target dnc2s:0.0 --timeout 45 --verbose

# capture (wide buffer, de-blanked)
docker exec qa-claude tmux capture-pane -p -t dnc2s:0.0 -S -60 | grep -v '^[[:space:]]*$' | tail -n 30

# teardown
MSYS_NO_PATHCONV=1 docker exec qa-claude tmux send-keys -t dnc2s:0.0 -l '/exit'
docker exec qa-claude tmux send-keys -t dnc2s:0.0 Enter
docker exec qa-claude tmux kill-session -t dnc2s
```

## Gotchas hit

1. **`respawn-pane -c /workspace/lsptest` did not change cwd** — the pane (and the
   first claude launch) stayed in `/workspace/marketplace` (the login shell profile
   `cd`s there). Confirmed via the welcome banner showing the wrong dir, then via
   `list-panes -F '#{pane_current_path}'`. Fix: explicit `cd /workspace/lsptest`
   inside the shell before launching claude, verified with `list-panes`. Had to
   `/exit` the mis-located first claude and relaunch.
2. **Auth 401 masquerades as a command failure.** The skill's "prose ≠ proof" /
   "verify by real signals" guidance is what caught this: the rendered signal was
   an error line, not a Lab Notebook block. A model narrating success would have
   been wrong — the real on-screen signal proves the command output never rendered.
