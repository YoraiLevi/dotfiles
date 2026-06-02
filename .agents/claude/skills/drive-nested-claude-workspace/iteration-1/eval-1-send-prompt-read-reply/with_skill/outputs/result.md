# Eval 1 — send a prompt to a nested claude and read the reply

## Claude's exact reply

The nested claude session did **not** produce a math answer. After the prompt
`In one short sentence, what is 7 times 6?` was submitted, the turn finished
generating and the only output rendered beneath the prompt was an API error:

```
❯ In one short sentence, what is 7 times 6?
  ⎿  Please run /login · API Error: 401 Invalid authentication credentials
✻ Sautéed for 2s
```

The same `Please run /login · API Error: 401 Invalid authentication credentials`
also appeared for every session-start monitor event, confirming the session has
no valid credentials — it cannot reach the model at all. There is no assistant
prose answer to read because the model never responded.

## Does it mention 42?

**No.** The reply is an authentication error, not a numeric answer. 42 does not
appear. (I did not fabricate a "42" answer — the on-screen signal is the auth
error, and the skill's core rule is to report the real signal, not plausible
prose.)

## Result

**FAIL** (does not mention 42 — the session is unauthenticated and produced no
math answer).

## Commands used

Isolated session (own session `dnc1s`, never touched `0:0.0` or `dnc1b`):

```bash
# create own isolated session
docker exec qa-claude tmux new-session -d -s dnc1s -x 200 -y 50

# launch claude in the target cwd
docker exec qa-claude tmux send-keys -t dnc1s -l 'cd /workspace/lsptest && claude'
docker exec qa-claude tmux send-keys -t dnc1s Enter

# wait out boot + session-start (monitor) turn — claude-tuned poller
python wait_for_prompt.py --container qa-claude --target dnc1s --timeout 30
docker exec qa-claude tmux list-panes -t dnc1s -F '#{pane_current_command}'  # => claude

# send the prompt (text, then Enter as a SEPARATE call)
docker exec qa-claude tmux send-keys -t dnc1s -l 'In one short sentence, what is 7 times 6?'
docker exec qa-claude tmux send-keys -t dnc1s Enter

# wait for the turn to FINISH generating (not just for the box to reappear)
python wait_for_prompt.py --container qa-claude --target dnc1s --timeout 45 --verbose

# read the reply
docker exec qa-claude tmux capture-pane -p -t dnc1s -S -40 | grep -v '^[[:space:]]*$' | tail -n 12

# teardown
docker exec qa-claude tmux kill-session -t dnc1s
```

No "trust this folder" dialog appeared (the dir was already trusted), so none
was accepted.

## How I detected the turn had finished

Used `scripts/wait_for_prompt.py` with its claude-tuned defaults
(`--ready-regex '❯'`, `--busy-regex 'esc to interrupt'`, `--settle 3`). The
poller returns ready only when ALL hold: the `❯` prompt is present, the
`esc to interrupt` busy indicator is ABSENT, and the screen is byte-stable for
3 consecutive polls. I did **not** gate on the `❯` prompt alone (it is on screen
the entire time, including mid-generation).

Verbose trace after sending the prompt:

```
[0.0s] ready=True busy=False unchanged=False stable=0
[0.5s] ready=True busy=False unchanged=True stable=0
[1.0s] ready=True busy=False unchanged=True stable=1
[1.5s] ready=True busy=False unchanged=True stable=2  -> exit 0
```

The turn was short (the 401 error returns almost immediately, no streaming),
so `busy` was already `False`; the settle counter still enforced 3 stable polls
before declaring the turn finished. I sent no input while a spinner / busy
indicator was up.
