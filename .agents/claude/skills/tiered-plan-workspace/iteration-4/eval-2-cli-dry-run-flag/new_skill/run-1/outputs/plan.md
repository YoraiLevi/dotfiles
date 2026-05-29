# Plan: add `--dry-run` flag to `scripts/migrate.py`

## 1. Objective

- Let operators preview a migration — which rows would be updated, which deleted — without mutating the database.
- De-risk migrations by making "look before you leap" a one-flag operation instead of a separate scratch script.
- Cover the new flag with help text, a couple of tests, and a README mention so it's discoverable.

## 2. Approach

**Strategy: thread a single `dry_run: bool` through the migration entry point; gate every write at the lowest point (commit / execute) and emit a structured preview line in its place.**

Why this shape:

- The write boundary is the one place we can be confident *nothing* mutates — gating higher up risks missing a path.
- A single boolean keeps the diff small and the test surface obvious.

Mechanics:

- **Argparse**: add a `--dry-run` store-true flag, default `False`. Help text states clearly that no DB writes occur.
  ```python
  parser.add_argument(
      "--dry-run",
      action="store_true",
      help="Preview changes (rows to update/delete) without writing to the database.",
  )
  ```
- **Write gate**: wrap the existing commit/execute path. In dry-run mode, print one line per intended mutation (`WOULD UPDATE id=<id> ...`, `WOULD DELETE id=<id> ...`) and skip the write. Roll back the transaction at the end so any intermediate SELECTs leave no trace.
  ```python
  if args.dry_run:
      print(f"WOULD {op} id={row.id} ...")
  else:
      cursor.execute(sql, params)
  # at end:
  conn.rollback() if args.dry_run else conn.commit()
  ```
- **Output**: stdout, plain text, one line per row. No JSON mode — out of scope.
- **Tests**: two pytest cases against an in-memory SQLite (or whatever the existing tests use):
  1. `--dry-run` prints the expected `WOULD ...` lines.
  2. `--dry-run` leaves the DB byte-identical to its pre-run state (assert row count + checksum of target tables unchanged).

Scope IN:

- `--dry-run` flag, help text, write gating, preview output.
- Two pytest cases.
- One README paragraph under the migration script's usage section.

Scope OUT:

- Structured (JSON) preview output — defer; add only if a consumer asks.
- Dry-run for any other script in `scripts/` — defer; tracked as "extend pattern" in commit message if relevant.
- Refactoring existing migration internals beyond the write gate.

Delivery: one PR, one commit, one branch. Solo.
Done when: `python scripts/migrate.py --dry-run` prints preview lines, DB state unchanged; `pytest` green; README shows the flag.

## 3. Implementer guide

### Step 1 — Add the argparse flag and plumb `dry_run` to the migration function

- Edit `scripts/migrate.py`. Add the argument near the existing flags:
  ```python
  parser.add_argument(
      "--dry-run",
      action="store_true",
      help="Preview changes (rows to update/delete) without writing to the database.",
  )
  ```
- Pass `args.dry_run` into the function that performs the migration (rename param to `dry_run: bool = False`).

Checkpoint: `python scripts/migrate.py --help` shows the new flag with the expected description.

### Step 2 — Gate writes and emit preview lines

- At each mutation site, branch on `dry_run`:
  ```python
  if dry_run:
      print(f"WOULD UPDATE id={row.id} set <fields>")
  else:
      cursor.execute(update_sql, params)
  ```
- Same shape for deletes (`WOULD DELETE id=...`).
- At the end of the migration: `conn.rollback()` when `dry_run`, else `conn.commit()`. This catches anything that bypassed the per-site gate.

Checkpoint: run `python scripts/migrate.py --dry-run` against a dev DB; observe `WOULD ...` lines; query the affected tables and confirm nothing changed.

### Step 3 — Add the two pytest cases

Add to the existing test module for `migrate.py` (or create `tests/test_migrate.py` if none exists):

```python
def test_dry_run_prints_preview(capsys, seeded_db):
    migrate(db=seeded_db, dry_run=True)
    out = capsys.readouterr().out
    assert "WOULD UPDATE" in out
    assert "WOULD DELETE" in out

def test_dry_run_does_not_mutate(seeded_db):
    before = snapshot(seeded_db)  # row counts + simple checksum
    migrate(db=seeded_db, dry_run=True)
    after = snapshot(seeded_db)
    assert before == after
```

Checkpoint: `pytest tests/test_migrate.py -k dry_run` passes.

### Step 4 — README mention

Add a short paragraph under the migration script's usage section in `README.md`:

```markdown
### Previewing a migration

Pass `--dry-run` to see which rows would be updated or deleted without
touching the database:

    python scripts/migrate.py --dry-run
```

Checkpoint: `grep -n dry-run README.md` returns the new lines.

### Step 5 — Commit

- `git add scripts/migrate.py tests/test_migrate.py README.md`
- Commit message: `feat(migrate): add --dry-run flag for safe preview of migrations`

Checkpoint: `git log -1` shows the single commit; `pytest` green; manual `--dry-run` still clean.
