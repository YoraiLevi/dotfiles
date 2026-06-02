# Eval 3 — sqlite3 multi-step interactive session (without_skill)

## Result
- Sum read back from sqlite: **12**
- Expected 12: **YES**
- Status: **PASS**
- Waited for `sqlite>` prompt between every statement: **YES**

## Environment notes
- `sqlite3` was not installed in the `qa-claude` container; installed it via `apt-get install -y sqlite3` (v3.40.1).
- Drove an interactive `sqlite3 :memory:` REPL inside an isolated tmux session named `tid3b`.
- Gotcha: a literal `;` passed through `docker exec ... tmux send-keys -l '...'` was stripped by tmux's command separator. Fixed by escaping it as `\;`, which delivers a literal semicolon to the REPL.

## Commands used
Session setup:
```
docker exec qa-claude tmux new-session -d -s tid3b
docker exec qa-claude tmux send-keys -t tid3b 'sqlite3 :memory:' C-m
```

Each statement sent literally, with the semicolon escaped, followed by Enter (C-m), then polled until the last pane line was `sqlite>` before sending the next:
```
docker exec qa-claude tmux send-keys -t tid3b -l 'CREATE TABLE t(n)\;'      ; docker exec qa-claude tmux send-keys -t tid3b C-m
docker exec qa-claude tmux send-keys -t tid3b -l 'INSERT INTO t VALUES (3)\;'; docker exec qa-claude tmux send-keys -t tid3b C-m
docker exec qa-claude tmux send-keys -t tid3b -l 'INSERT INTO t VALUES (4)\;'; docker exec qa-claude tmux send-keys -t tid3b C-m
docker exec qa-claude tmux send-keys -t tid3b -l 'INSERT INTO t VALUES (5)\;'; docker exec qa-claude tmux send-keys -t tid3b C-m
docker exec qa-claude tmux send-keys -t tid3b -l 'SELECT sum(n) FROM t\;'    ; docker exec qa-claude tmux send-keys -t tid3b C-m
```

Readiness poll (between every statement):
```
for i in $(seq 1 20); do
  out=$(docker exec qa-claude tmux capture-pane -t tid3b -p)
  last=$(printf '%s' "$out" | tail -n 1)
  case "$last" in *"sqlite>") echo READY; break;; esac
  sleep 0.3
done
```

## Final pane transcript (relevant lines)
```
sqlite> CREATE TABLE t(n);
sqlite> INSERT INTO t VALUES (3);
sqlite> INSERT INTO t VALUES (4);
sqlite> INSERT INTO t VALUES (5);
sqlite> SELECT sum(n) FROM t;
12
sqlite>
```

Cleanup: `docker exec qa-claude tmux kill-session -t tid3b`
