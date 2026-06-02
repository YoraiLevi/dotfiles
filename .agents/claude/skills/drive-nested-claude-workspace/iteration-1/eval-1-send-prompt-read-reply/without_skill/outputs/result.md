# Eval 1 — Send prompt, read reply (without skill)

## Claude's exact reply

The nested `claude` instance did **not** produce a natural-language answer. Submitting the
prompt produced an API error rendered directly beneath the prompt in the transcript:

```
❯ In one short sentence, what is 7 times 6?
  ⎿  Please run /login · API Error: 401 Invalid authentication credentials
```

The exact reply text is:

> Please run /login · API Error: 401 Invalid authentication credentials

The nested instance is unauthenticated (401), so it could not generate a substantive answer.
The same `Please run /login · API Error: 401` error also appeared on every session-start
Monitor event (disk-usage, memory-usage, git-status), confirming the auth failure is
session-wide and not specific to my prompt.

## Does it mention 42?

**No.** The reply is an authentication error and contains no arithmetic answer; "42" does not
appear.

## Commands used

```bash
# 1. Create isolated session
docker exec qa-claude tmux new-session -d -s dnc1b -x 200 -y 50

# 2. Launch claude in the target cwd
docker exec qa-claude tmux send-keys -t dnc1b 'cd /workspace/lsptest && claude' Enter

# 3. Poll the screen while it booted / ran its first (Monitor) turn
docker exec qa-claude tmux capture-pane -t dnc1b -p        # repeated with sleeps

# 4. Type the prompt WITHOUT submitting, to confirm it landed in the input box
docker exec qa-claude tmux send-keys -t dnc1b 'In one short sentence, what is 7 times 6?'
docker exec qa-claude tmux capture-pane -t dnc1b -p

# 5. Submit
docker exec qa-claude tmux send-keys -t dnc1b Enter

# 6. Poll until generation finished
docker exec qa-claude tmux capture-pane -t dnc1b -p        # repeated with sleeps

# 7. Stability check: two captures 3s apart must be byte-identical
docker exec qa-claude tmux capture-pane -t dnc1b -p > /tmp/cap_a.txt
docker exec qa-claude tmux capture-pane -t dnc1b -p > /tmp/cap_b.txt
diff /tmp/cap_a.txt /tmp/cap_b.txt

# 8. Cleanup
docker exec qa-claude tmux send-keys -t dnc1b C-c
docker exec qa-claude tmux kill-session -t dnc1b
```

## How I detected the turn had finished

Two independent signals, both required:

1. **No active generation indicator** — the running spinner with the
   `esc to interrupt` footer was gone; the footer reverted to `? for shortcuts · ← for agents`,
   and the spinner line showed a static past-tense form (`Crunched for 3s`) rather than an
   animating one.
2. **Screen stability** — two `capture-pane` snapshots taken 3 seconds apart were
   byte-identical (`diff` returned no differences), confirming nothing was still streaming.
   This guards against mistaking the input box reappearing for actual completion.

I also waited for the **first** (session-start Monitor) turn to finish the same way before
sending my prompt, and I typed the prompt without `Enter` first to verify it was sitting in
the input box (never sent while a turn was generating).

## Isolation

Used a dedicated session `dnc1b` (created `-x 200 -y 50`), and killed it on completion. No
"trust this folder" dialog appeared (the folder was already trusted).
