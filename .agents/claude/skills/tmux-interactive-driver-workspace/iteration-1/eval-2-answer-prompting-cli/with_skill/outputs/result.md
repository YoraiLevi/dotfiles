# eval-2 — answer-prompting-cli (with_skill)

## Result

- Printed line: `hello Ada, len=3`
- Matches expected `hello Ada, len=3`: YES
- Waited for the `name? ` prompt before typing: YES (poller exited 0 on `name\?\s*$`, stable for 2 polls)
- Verdict: PASS

## Commands used

```bash
# 1. Isolated session
docker exec qa-claude tmux new-session -d -s tid2s -x 200 -y 50

# 2. Write /tmp/greet.py exactly (path conversion disabled so /tmp is not mangled to a Windows path)
MSYS_NO_PATHCONV=1 docker exec qa-claude python3 -c "open('/tmp/greet.py','w').write(\"name = input('name? '); print(f'hello {name}, len={len(name)}')\")"
MSYS_NO_PATHCONV=1 docker exec qa-claude cat //tmp/greet.py   # verify exact contents

# 3. Launch the program (literal text, then Enter as a SEPARATE call)
docker exec qa-claude tmux send-keys -t tid2s -l 'python3 /tmp/greet.py'
docker exec qa-claude tmux send-keys -t tid2s Enter

# 4. WAIT until the `name? ` prompt is actually showing (tmux strips trailing space -> regex ends \s*$)
python wait_for_prompt.py --container qa-claude --target tid2s --ready-regex 'name\?\s*$' --timeout 15

# 5. Type Ada, then Enter as a SEPARATE call
docker exec qa-claude tmux send-keys -t tid2s -l 'Ada'
docker exec qa-claude tmux send-keys -t tid2s Enter

# 6. Wait for shell prompt to return, then read output (strip blanks, take real tail)
python wait_for_prompt.py --container qa-claude --target tid2s --timeout 15
docker exec qa-claude tmux capture-pane -p -t tid2s -S -40 | grep -v '^[[:space:]]*$' | tail -n 6

# 7. Clean up
docker exec qa-claude tmux kill-session -t tid2s
```

## Captured pane (proof)

```text
root@0c43182b8b60:/workspace/marketplace# python3 /tmp/greet.py
name? Ada
hello Ada, len=3
root@0c43182b8b60:/workspace/marketplace#
```
