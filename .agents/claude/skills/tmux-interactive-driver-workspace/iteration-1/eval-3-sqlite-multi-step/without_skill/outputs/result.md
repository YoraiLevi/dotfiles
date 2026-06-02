# eval-3-sqlite-multi-step (without_skill)

## Result
- Sum read back: `12`
- Was it 12? YES
- PASS/FAIL: PASS
- Waited for `sqlite>` prompt between every statement: YES

## Commands used
All driven via `docker exec qa-claude tmux ...` against an OWN session `c3b`.

```
docker exec qa-claude tmux new-session -d -s c3b
docker exec qa-claude tmux send-keys -t c3b 'sqlite3 :memory:' Enter
# each SQL statement: text sent first, Enter sent as a SEPARATE call
docker exec qa-claude tmux send-keys -t c3b 'CREATE TABLE t(n)\;'
docker exec qa-claude tmux send-keys -t c3b Enter
docker exec qa-claude tmux send-keys -t c3b 'INSERT INTO t VALUES (3)\;'
docker exec qa-claude tmux send-keys -t c3b Enter
docker exec qa-claude tmux send-keys -t c3b 'INSERT INTO t VALUES (4)\;'
docker exec qa-claude tmux send-keys -t c3b Enter
docker exec qa-claude tmux send-keys -t c3b 'INSERT INTO t VALUES (5)\;'
docker exec qa-claude tmux send-keys -t c3b Enter
docker exec qa-claude tmux send-keys -t c3b 'SELECT sum(n) FROM t\;'
docker exec qa-claude tmux send-keys -t c3b Enter
# cleanup
docker exec qa-claude tmux send-keys -t c3b '.quit'
docker exec qa-claude tmux send-keys -t c3b Enter
docker exec qa-claude tmux kill-session -t c3b
```

sqlite3 was already installed in the container (`/usr/bin/sqlite3`, v3.40.1) — no install needed.

## How I detected the prompt between statements
After each Enter I ran `docker exec qa-claude tmux capture-pane -t c3b -p` and
read the LAST line of the pane. A statement was treated as complete only when
the final line was exactly `sqlite>` (the primary prompt). The continuation
prompt `   ...>` means sqlite is still waiting for a statement terminator, i.e.
NOT yet back at the prompt — so I would not send the next statement. The
`sqlite>` vs `...>` distinction is the whole basis of prompt detection here.

## Gotchas I hit and solved myself
1. **Trailing `;` was silently swallowed by tmux.** tmux `send-keys` treats a
   bare `;` as its own command separator. The first attempt
   `send-keys -t c3b 'CREATE TABLE t(n);' Enter` delivered `CREATE TABLE t(n)`
   WITHOUT the `;` (and printed a spurious `unknown command: Enter`), leaving
   sqlite on the `   ...>` continuation prompt because the statement never
   terminated.
   - Fix: escape the semicolon as `\;` inside the send-keys argument
     (`'CREATE TABLE t(n)\;'`). The literal `;` then reaches sqlite and the
     statement terminates, returning to `sqlite>`.

2. **Bundling `Enter` with a `;`-containing argument was unreliable.** I split
   each statement into two separate calls: one `send-keys` for the SQL text,
   then a separate `send-keys -t c3b Enter`. Deterministic afterward.

3. **Recovering the first stranded statement.** The initial `CREATE TABLE` had
   already landed on `   ...>` before I switched to `\;`. I sent a standalone
   escaped `\;` + Enter, which terminated the pending statement and dropped back
   to `sqlite>` (visible as the `   ...> ;` line). The DDL completed correctly,
   so the later inserts and the sum were unaffected.

## Final pane transcript (relevant tail)
```
sqlite> CREATE TABLE t(n)
   ...> ;
sqlite> INSERT INTO t VALUES (3);
sqlite> INSERT INTO t VALUES (4);
sqlite> INSERT INTO t VALUES (5);
sqlite> SELECT sum(n) FROM t;
12
sqlite>
```

Session `c3b` was killed after `.quit`.
