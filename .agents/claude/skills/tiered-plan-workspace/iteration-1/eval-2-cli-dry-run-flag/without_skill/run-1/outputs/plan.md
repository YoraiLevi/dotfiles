# Plan: Add `--dry-run` flag to `scripts/migrate.py`

## Context & Assumptions

- **Project shape:** Generic Python project, solo developer, single PR.
- **CLI framework:** Assume `argparse` (stdlib, no extra dep). If the script actually uses `click`, swap `add_argument` for `@click.option("--dry-run", is_flag=True)` — the rest of the plan is unchanged.
- **DB layer:** Assume migration code goes through a small set of mutation call sites (e.g. `cursor.execute(UPDATE...)`, `cursor.execute(DELETE...)`, or an ORM `.save()` / `.delete()`). Exact shape unknown; plan treats them as the integration surface.
- **Out of scope:** No new dependencies, no refactor of the migration logic itself, no transaction-rollback strategy beyond the simple skip-mutation approach.

## Goal

When `--dry-run` is passed, the script:
1. Performs all read-side work (selects, diffs, decisions).
2. Prints each row it *would* update and each row it *would* delete, in a clear human-readable form.
3. Skips every mutating DB call.
4. Exits 0 on success, like a normal run.

---

## Design

### 1. Flag wiring (argparse)

In the `argparse` setup block, add:

```python
parser.add_argument(
    "--dry-run",
    action="store_true",
    help="Show which rows would be updated or deleted without modifying the database.",
)
```

Pass `args.dry_run` into the function(s) that perform the migration. Prefer threading it as an explicit parameter (`def migrate(..., dry_run: bool = False)`) rather than reading a global — easier to test.

### 2. Mutation gating

Identify every DB-mutating call site in `scripts/migrate.py`. For each one:

- **Option A (preferred): guard at the call site.**
  ```python
  if dry_run:
      print(f"[dry-run] would UPDATE row id={row.id} set {changes!r}")
  else:
      cursor.execute(UPDATE_SQL, ...)
  ```
- **Option B (if there are many call sites): wrap the DB handle in a thin adapter** that no-ops `execute()` for write SQL when `dry_run=True` and logs the statement. More invasive — only worth it if there are >5 mutation sites.

Default to Option A unless the call-site count makes it noisy.

### 3. Output format

Keep it greppable and stable:

```
[dry-run] UPDATE users id=42 fields={"email": "new@x"}
[dry-run] DELETE orders id=1001
[dry-run] summary: 12 updates, 3 deletes, 0 mutations applied
```

Print summary at the end regardless of verbosity — useful for the test assertions.

### 4. Help text

The `help=` string on the flag (above) is the primary doc. Also update the module-level docstring / `parser.description` if it lists what the script does, so `--help` output mentions dry-run as a supported mode.

---

## Tests

Add to the existing test file for `migrate.py` (or create `tests/test_migrate.py` if none exists).

### Test 1: `--dry-run` does not mutate

- Set up an in-memory SQLite DB (or mock the DB cursor — depends on existing test style) with a known fixture row that the migration would normally change.
- Invoke the migration entry point with `dry_run=True`.
- Assert: the row in the DB is unchanged after the call.
- Assert: stdout (captured via `capsys`) contains the expected `[dry-run] UPDATE ...` line.

### Test 2: `--dry-run` reports the right counts

- Fixture with N rows that would update and M rows that would delete.
- Run with `dry_run=True`, capture stdout.
- Assert the summary line shows `N updates, M deletes`.
- Optional: also assert that without `--dry-run`, the same fixture *does* mutate (sanity check that the flag is actually doing something — prevents a regression where mutation gating is removed and the test still passes).

### Test invocation style

Prefer calling the `migrate()` function directly with `dry_run=True` rather than shelling out to the CLI — faster, easier to assert on. One additional small test can invoke argparse via `parser.parse_args(["--dry-run"])` to confirm the flag parses to `True`.

---

## README update

Add a short section (or extend the existing "Usage" section) for `scripts/migrate.py`:

```markdown
### Dry run

To preview what the migration would do without touching the database:

    python scripts/migrate.py --dry-run

This prints every row that would be updated or deleted, followed by a summary. No writes are performed. Useful for reviewing a migration before running it for real.
```

Place it adjacent to the existing migration usage docs. If there's a "Flags" or "Options" table for the script, add `--dry-run` there too.

---

## Execution order (one PR, one commit or two)

1. Add the flag to argparse + thread `dry_run` through the call chain.
2. Gate each mutation call site.
3. Add `[dry-run]` print statements + summary.
4. Update help text / parser description.
5. Write the two tests; run them; confirm they pass and that the non-dry-run path still mutates.
6. Update README.
7. Manual smoke test: `python scripts/migrate.py --dry-run` against a dev DB, eyeball output, confirm DB unchanged.
8. Commit, open PR.

Single commit is fine for a solo PR this size. Split into `feat: add --dry-run` and `docs: ...` only if you want a cleaner log.

---

## Risks / things to double-check

- **Hidden mutations.** If the script does any writes outside the obvious `execute(UPDATE/DELETE)` sites — e.g. a `connection.commit()` that flushes ORM session state, a logging table that gets a row appended, a cache-invalidation call that hits another service — those need to be gated too. Audit before merging.
- **Read-side side effects.** If the migration uses `SELECT ... FOR UPDATE` or otherwise takes locks during the read phase, dry-run still takes those locks. Probably fine for a preview, but worth noting in the README if it could affect a live DB.
- **Exit code.** Dry-run should exit 0 on success. If the script currently exits non-zero when "nothing to do", make sure dry-run with zero changes doesn't trip that.
- **Transaction boundaries.** If the existing script wraps everything in a transaction and rolls back on error, dry-run should still not open a write transaction at all — simpler and safer than relying on rollback.

---

## Done criteria

- `python scripts/migrate.py --help` shows `--dry-run` with a clear description.
- `python scripts/migrate.py --dry-run` on a fixture DB prints planned changes and leaves the DB byte-identical.
- Both new tests pass; existing tests still pass.
- README has the dry-run section.
- PR description links the README change and the test file.
