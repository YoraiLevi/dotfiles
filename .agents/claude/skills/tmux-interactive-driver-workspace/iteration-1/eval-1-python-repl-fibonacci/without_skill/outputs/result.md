# Result: Python REPL Fibonacci (fib(10))

## Value read back from the REPL
`FIB_RESULT= 55` (the value printed by the REPL was **55**)

## Was it 55?
Yes. PASS.

## How it was obtained
The value was read from the REPL's own output captured from the tmux pane — not
computed by hand. I printed with a unique sentinel (`FIB_RESULT=`) so the result
was unambiguous to locate in the captured screen.

Captured pane tail:
```
>>> print("FIB_RESULT=", fib(10))
FIB_RESULT= 55
>>>
```

## Commands used (isolated tmux session `c1b` inside container `qa-claude`)
```bash
# 1. Create own isolated session
docker exec qa-claude tmux new-session -d -s c1b

# 2. Start python3
docker exec qa-claude tmux send-keys -t c1b 'python3' Enter

# 3. Define fib (fib(1)=1, fib(2)=1), blank line closes the block
docker exec qa-claude tmux send-keys -t c1b \
  'def fib(n):' Enter \
  '    a,b=1,1' Enter \
  '    for _ in range(n-1): a,b=b,a+b' Enter \
  '    return a' Enter '' Enter

# 4. Compute + print with sentinel
docker exec qa-claude tmux send-keys -t c1b 'print("FIB_RESULT=", fib(10))' Enter

# 5. Read output back from the REPL
docker exec qa-claude tmux capture-pane -p -t c1b

# 6. Tear down
docker exec qa-claude tmux kill-session -t c1b
```

## How I knew the REPL was ready before each send (readiness method)
I **polled the screen**, never a fixed sleep. After each `send-keys` I ran a
`capture-pane` loop (up to 30 iterations, 0.2s apart) and checked the pane for a
specific ready-marker before sending the next line:

- After `python3`: polled until the pane contained `>>>` (banner + primary prompt).
- After the multi-line `def fib`: polled until the **last non-empty line** was
  exactly `>>>` — confirming the block was accepted and we left the `...`
  continuation prompt, not still mid-definition.
- After `print(... fib(10))`: polled until the pane contained the sentinel
  `FIB_RESULT= `, then read the value after it.

Every readiness check passed on the first poll, so input was never sent into a
not-yet-ready REPL.

## Did I ever send input before the REPL was ready?
No. Every line was gated on a screen-state poll confirming the expected prompt
before the next send.
