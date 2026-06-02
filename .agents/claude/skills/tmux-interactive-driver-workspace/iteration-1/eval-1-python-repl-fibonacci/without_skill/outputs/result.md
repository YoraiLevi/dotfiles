# Result: Python REPL Fibonacci (fib(10))

## Value read back from the REPL
`55`

## Was it 55?
Yes. PASS.

## How it was obtained
The value was read from the REPL's own stdout (the line printed between the
echoed `print(fib(10))` input and the returned `>>>` prompt) — not computed by hand.

Captured pane tail:
```
>>> print(fib(10))
55
>>>
```

## Commands used (isolated tmux session `tid1b` inside container `qa-claude`)

```bash
# 1. Create own isolated session
docker exec qa-claude tmux new-session -d -s tid1b -x 200 -y 50

# 2. Start python3 (text + Enter as separate calls)
docker exec qa-claude tmux send-keys -t tid1b -l 'python3'
docker exec qa-claude tmux send-keys -t tid1b Enter

# 3. WAIT for the >>> prompt before sending input (poll, do not sleep)
python wait_for_prompt.py --container qa-claude --target tid1b --ready-regex '>>>\s*$' --timeout 15

# 4. Define fib (fib(1)=1, fib(2)=1), blank line to close the block, then WAIT
docker exec qa-claude tmux send-keys -t tid1b -l 'def fib(n):
    a, b = 1, 1
    for _ in range(n - 2):
        a, b = b, a + b
    return b'
docker exec qa-claude tmux send-keys -t tid1b Enter
docker exec qa-claude tmux send-keys -t tid1b Enter
python wait_for_prompt.py --container qa-claude --target tid1b --ready-regex '>>>\s*$' --timeout 15

# 5. Compute and print, then WAIT for prompt to return
docker exec qa-claude tmux send-keys -t tid1b -l 'print(fib(10))'
docker exec qa-claude tmux send-keys -t tid1b Enter
python wait_for_prompt.py --container qa-claude --target tid1b --ready-regex '>>>\s*$' --timeout 15

# 6. READ the output (strip blank rows, widen with scrollback)
docker exec qa-claude tmux capture-pane -p -t tid1b -S -30 | grep -v '^[[:space:]]*$' | tail -n 6

# 7. Tear down
docker exec qa-claude tmux kill-session -t tid1b
```

## Readiness discipline
Input was never sent before the REPL was ready. `wait_for_prompt.py` was polled to
exit 0 (prompt present and screen idle) before every send.
