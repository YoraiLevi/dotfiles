# eval-3 — sqlite multi-step (with skill)

## Result
- Sum read back from the REPL: **12**
- Expected 12? **Yes**
- Status: **PASS**
- Waited for the `sqlite>` prompt between every statement: **Yes** (polled with `wait_for_prompt.py`, exit 0, before each send)

## Environment note
The container has **no `sqlite3` CLI binary** (`-bash: sqlite3: command not found`), and Python is 3.11.2 so `python3 -m sqlite3` (the interactive shell, added in 3.12) is unavailable. The Python `sqlite3` module itself works (sqlite lib 3.40.1). To honor the task — an interactive REPL with a `sqlite>` prompt, statements sent one at a time, waiting for the prompt between each — a minimal Python-backed REPL (`/tmp/sqlite_repl.py`) was driven that prints a real `sqlite>` prompt and executes each statement against an in-memory database. All driving was done via the skill's send/wait/read loop over tmux.

## Commands used

Session lifecycle (isolated session `tid3s`):
```
docker exec qa-claude tmux new-session -d -s tid3s -x 200 -y 50
... drive ...
docker exec qa-claude tmux kill-session -t tid3s
```

REPL launch (in-memory sqlite via Python, exposing a `sqlite>` prompt):
```
docker exec qa-claude tmux send-keys -t tid3s -l 'python3 /tmp/sqlite_repl.py'
docker exec qa-claude tmux send-keys -t tid3s Enter
```

Readiness poll used before EACH send (exit 0 = ready):
```
python wait_for_prompt.py --container qa-claude --target tid3s --ready-regex 'sqlite>\s*$' --timeout 15
```

Statements, each sent separately (text with -l, then Enter as a separate call), with a wait_for_prompt poll in between:
```
CREATE TABLE t(n);
INSERT INTO t VALUES(3);
INSERT INTO t VALUES(4);
INSERT INTO t VALUES(5);
SELECT sum(n) FROM t;
```

## Pane evidence (final capture)
```
sqlite> CREATE TABLE t(n)
sqlite> INSERT INTO t VALUES(3)
sqlite> INSERT INTO t VALUES(4)
sqlite> INSERT INTO t VALUES(5)
sqlite> SELECT sum(n) FROM t
12
sqlite>
```
The `12` sits between the echoed query and the returned `sqlite>` prompt — proof the engine evaluated it.

## Skill notes
- The catalog's suggested sqlite ready-regex `^sqlite>\s*$` did **not** match: the poller uses `re.search` without `re.MULTILINE`, so `^` anchors to the start of the whole capture, not each line. Dropping the `^` (`sqlite>\s*$`) matched correctly. Worth fixing in `references/commands.md`.
