# Result — eval-2 answer-prompting-cli

## Printed line (exact)

```
hello Ada, len=3
```

## Outcome

- Expected: `hello Ada, len=3`
- Actual:   `hello Ada, len=3`
- **PASS**
- Waited for the `name? ` prompt before typing: **YES** (polled with `wait_for_prompt.py`, exit 0, then visually confirmed the pane showed `name?` before sending `Ada`).

## Commands used

```bash
# 1. Isolated session
docker exec qa-claude tmux new-session -d -s tid2b -x 200 -y 50

# 2. Create /tmp/greet.py with exact contents (no trailing newline)
docker exec qa-claude bash -lc "printf '%s' \"name = input('name? '); print(f'hello {name}, len={len(name)}')\" > /tmp/greet.py"

# 3. Launch python3 in the pane (text + Enter as separate send-keys calls)
docker exec qa-claude tmux send-keys -t tid2b -l 'python3 /tmp/greet.py'
docker exec qa-claude tmux send-keys -t tid2b Enter

# 4. WAIT for the name? prompt (do not type until ready)
python "C:/Users/devic/.claude/skills/tmux-interactive-driver/scripts/wait_for_prompt.py" \
  --container qa-claude --target tid2b --ready-regex 'name\? *$' --timeout 15

# 5. Type Ada, then Enter (separate calls)
docker exec qa-claude tmux send-keys -t tid2b -l 'Ada'
docker exec qa-claude tmux send-keys -t tid2b Enter

# 6. WAIT for shell prompt to return, then read output
python "C:/Users/devic/.claude/skills/tmux-interactive-driver/scripts/wait_for_prompt.py" \
  --container qa-claude --target tid2b --ready-regex '#\s*$' --timeout 15
docker exec qa-claude tmux capture-pane -p -t tid2b -S -10 | grep -v '^[[:space:]]*$' | tail -n 5

# 7. Tear down
docker exec qa-claude tmux kill-session -t tid2b
```

## Captured pane (proof)

```
root@0c43182b8b60:/workspace/marketplace# python3 /tmp/greet.py
name? Ada
hello Ada, len=3
root@0c43182b8b60:/workspace/marketplace#
```
