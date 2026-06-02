# Eval 1 — Python REPL Fibonacci (with skill)

## Value read back from the REPL
`55`

## Was it 55?
Yes — PASS.

## Definition used
fib(1)=1, fib(2)=1, so the base case returns `1` for `n < 3`:
```python
def fib(n):
    return 1 if n<3 else fib(n-1)+fib(n-2)
print(fib(10))
```

## Captured REPL output (proof — value came from the REPL, not computed by hand)
```text
>>> def fib(n):
...     return 1 if n<3 else fib(n-1)+fib(n-2)
...
>>> print(fib(10))
55
>>>
```

## Commands used (isolated session `tid1s`)
```bash
# Create isolated session + launch python3
docker exec qa-claude tmux new-session -d -s tid1s -x 200 -y 50
docker exec qa-claude tmux send-keys -t tid1s.0 -l 'python3'
docker exec qa-claude tmux send-keys -t tid1s.0 Enter

# Wait for the >>> prompt before sending anything (poll, never sleep)
python wait_for_prompt.py --container qa-claude --target tid1s.0 --ready-regex '>>>\s*$' --timeout 15

# Define fib (text via -l, Enter as separate calls; blank line ends the block)
docker exec qa-claude tmux send-keys -t tid1s.0 -l 'def fib(n):'
docker exec qa-claude tmux send-keys -t tid1s.0 Enter
docker exec qa-claude tmux send-keys -t tid1s.0 -l '    return 1 if n<3 else fib(n-1)+fib(n-2)'
docker exec qa-claude tmux send-keys -t tid1s.0 Enter
docker exec qa-claude tmux send-keys -t tid1s.0 Enter

# Wait for prompt, then compute
python wait_for_prompt.py --container qa-claude --target tid1s.0 --ready-regex '>>>\s*$' --timeout 15
docker exec qa-claude tmux send-keys -t tid1s.0 -l 'print(fib(10))'
docker exec qa-claude tmux send-keys -t tid1s.0 Enter

# Wait for prompt to return, then read the output
python wait_for_prompt.py --container qa-claude --target tid1s.0 --ready-regex '>>>\s*$' --timeout 15
docker exec qa-claude tmux capture-pane -p -t tid1s.0 -S -20 | grep -v '^[[:space:]]*$' | tail -n 6

# Tear down the isolated session
docker exec qa-claude tmux kill-session -t tid1s
```

## Input-before-ready?
No. A `wait_for_prompt.py` poll (ready-regex `>>>\s*$`) gated every send; input was only sent after the poller returned exit 0 (ready + idle).
