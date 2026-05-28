# Plan: Add `--dry-run` flag to `scripts/migrate.py`

## Context

- Solo project, single PR, single commit acceptable.
- Goal: let the user preview what the migration would do (rows updated, rows deleted) without mutating the database.
- Scope: CLI flag + help text + a couple of tests + README mention.

## Assumptions

- `scripts/migrate.py` uses `argparse` (per task instruction).
- The script currently performs mutations through a small number of identifiable call sites (e.g. `UPDATE` / `DELETE` SQL, or ORM `session.commit()` / `.delete()` calls). If mutations are scattered across many files, the surface area grows and this plan needs revisiting.
- There is an existing test file or test directory (e.g. `tests/test_migrate.py`); if not, we create one.
- A `README.md` exists at the repo root with a section describing how to run `migrate.py`.
- The DB layer can be no-op'd cleanly (either we never open a transaction, or we open one and roll back). Preferred approach below.

## Design

### Flag shape

- Add `--dry-run` as a boolean flag (`action="store_true"`), default `False`.
- Help text: `"Print the rows that would be updated or deleted without modifying the database. Exits 0 on success."`
- Expose the resolved value as `args.dry_run` and thread it into the migration entry function (e.g. `run_migration(dry_run: bool = False)`).

### Behavior contract

- When `dry_run` is `True`:
  - The script still reads from the DB to determine what would change.
  - For every row that *would* be updated: log `WOULD UPDATE id=<pk> set <col>=<new>` (or equivalent structured line).
  - For every row that *would* be deleted: log `WOULD DELETE id=<pk>`.
  - Print a summary at the end: `dry-run: would update N rows, would delete M rows. No changes committed.`
  - Exit code `0`.
- When `dry_run` is `False`: existing behavior, unchanged.

### Implementation approach (pick one — recommend A)

- **A. Guard at the mutation site.** Wrap each `UPDATE`/`DELETE`/`commit` with `if not dry_run: ...` and log the would-do line in both branches. Simplest, lowest risk of "I thought it was rolled back but it wasn't".
- **B. Transaction-rollback wrapper.** Run the whole migration inside a transaction and roll back at the end when `dry_run` is set. Cleaner conceptually but relies on every mutation respecting the transaction boundary (no autocommit, no side-effect-ful raw connections). Skip unless we already know the DB layer is transactional end-to-end.

Going with **A** unless the codebase already has a transactional pattern that makes **B** trivial.

### Logging

- Use the script's existing logger if there is one; otherwise `print()` is acceptable for a solo CLI.
- Prefix dry-run lines with `[dry-run]` so they're greppable.

## Changes by file

### `scripts/migrate.py`

- Add `parser.add_argument("--dry-run", action="store_true", help="...")` next to other args.
- Pass `args.dry_run` into the migration function.
- At each mutation site:
  - Log the "would do" line unconditionally (so the dry-run output and real-run audit trail look the same).
  - Skip the actual mutation when `dry_run` is True.
- Skip the final `commit()` when `dry_run` is True; instead emit the summary line.

### `tests/test_migrate.py` (new or extended)

- **Test 1 — `test_dry_run_does_not_mutate`:** seed a small in-memory DB (or mock the DB layer), invoke the migration with `dry_run=True`, assert that no rows were updated and none were deleted. Assert the summary line was emitted.
- **Test 2 — `test_dry_run_reports_intended_changes`:** seed data that the migration would touch, run with `dry_run=True`, capture stdout/logs, assert the expected `WOULD UPDATE` / `WOULD DELETE` lines appear with the right primary keys.
- Optional sanity test: `test_non_dry_run_still_mutates` — guard against the refactor accidentally turning the real run into a no-op. Cheap and worth it.

### `README.md`

- In the section that documents `scripts/migrate.py`, add a short subsection or bullet:
  - `--dry-run`: preview the migration without writing. Example:
    ```
    python scripts/migrate.py --dry-run
    ```
  - One sentence on what the output looks like and that exit code is 0.

## Risks / things to watch

- **Silent partial mutation.** If a mutation happens via a path we forgot to guard (e.g. a helper that opens its own connection), dry-run lies. Mitigation: grep for `UPDATE`, `DELETE`, `.commit(`, `.delete(` in `scripts/migrate.py` and any module it imports, and confirm every hit is guarded.
- **Read-only side effects.** If the migration writes to anything other than the DB (e.g. a log table, a file, an external API), decide per-sink whether `--dry-run` suppresses it. Default: suppress all writes; document any exceptions in the help text.
- **Test isolation.** If tests hit a real DB, dry-run tests must still clean up. Prefer SQLite in-memory or a mock layer.

## Execution order

1. Read `scripts/migrate.py` and inventory mutation sites.
2. Add the flag + plumb `dry_run` through.
3. Guard each mutation site, add the "would do" log line.
4. Add the summary line at the end.
5. Write the two tests, run them, confirm both pass.
6. Update README.
7. Single commit, single PR.

## Out of scope

- No new logging framework.
- No refactor of the DB layer.
- No `--verbose` / `--quiet` flags — only `--dry-run`.

State-check: plan written; no code changed; awaiting approval to implement.
