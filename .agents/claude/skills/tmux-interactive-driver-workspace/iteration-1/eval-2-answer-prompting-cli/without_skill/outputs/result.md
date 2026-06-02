# Result — eval-2 answer-prompting-cli (without_skill)

## Printed line (exact)

```
hello Ada, len=3
```

## Outcome

- Expected: `hello Ada, len=3`
- Actual:   `hello Ada, len=3`
- **PASS**
- Waited for the `name? ` prompt before typing: **YES** — screen poll, not a fixed sleep.

## How I knew the prompt was showing (readiness method)

Screen poll. After launching, I captured the pane in a loop
(`tmux capture-pane -t c2b -p`) and grepped for the regex `name\? *$`, only
sending `Ada` once it matched (matched on the first poll). The regex tolerates
zero-or-more trailing spaces because tmux strips the trailing space at end of
line — an exact `grep "name? "` (with literal trailing space) fails for that
reason. I used the same poll technique to detect the final output line
(`grep "hello Ada"`) before reading it back.

## Isolation

Own session `c2b`; killed when done.

## Commands used

```sh
# 1. Isolated session
docker exec qa-claude tmux new-session -d -s c2b

# 2. Create /tmp/greet.py with EXACT single-quoted content
#    (base64 round-trip to avoid shell quoting + Git-Bash path mangling on the Windows host)
CONTENT="name = input('name? '); print(f'hello {name}, len={len(name)}')"
B64=$(printf "%s\n" "$CONTENT" | base64 -w0)
docker exec qa-claude sh -c "echo $B64 | base64 -d > //tmp/greet.py"
docker exec qa-claude sh -c 'cat //tmp/greet.py'
#   -> name = input('name? '); print(f'hello {name}, len={len(name)}')
#   (// instead of / keeps Git Bash from rewriting the path to a Windows temp dir)

# 3. Launch python3 in the pane
docker exec qa-claude tmux send-keys -t c2b 'python3 //tmp/greet.py' Enter

# 4. WAIT for the name? prompt via screen poll (do not type until ready)
for i in $(seq 1 30); do
  SCREEN=$(docker exec qa-claude tmux capture-pane -t c2b -p)
  echo "$SCREEN" | grep -qE "name\? *$" && break
  sleep 0.2
done

# 5. Type Ada
docker exec qa-claude tmux send-keys -t c2b 'Ada' Enter

# 6. WAIT for output via screen poll, then read it back
for i in $(seq 1 30); do
  SCREEN=$(docker exec qa-claude tmux capture-pane -t c2b -p)
  echo "$SCREEN" | grep -q "hello Ada" && break
  sleep 0.2
done
docker exec qa-claude tmux capture-pane -t c2b -p

# 7. Tear down
docker exec qa-claude tmux kill-session -t c2b
```

## Captured pane (proof)

```
root@0c43182b8b60:/workspace/marketplace# python3 //tmp/greet.py
name? Ada
hello Ada, len=3
root@0c43182b8b60:/workspace/marketplace#
```
