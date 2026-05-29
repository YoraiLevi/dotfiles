# Plan — Add `--dry-run` to `scripts/migrate.py`

## Goal

- Let me run the migration end-to-end and see exactly which rows it would update and delete, without touching the database.
  - Removes the "guess and hope" step before a real migration run.
  - Gives me a copy-pasteable record of intended changes for the PR description / a sanity check against prod data.
- Keep the feature small and obvious: a single flag, default off, no behavior change for existing invocations.
- Make the flag discoverable: it must show up in `--help` and be mentioned in the README so future-me doesn't forget it exists.

### Assumptions

- `scripts/migrate.py` uses `argparse` (confirm on first read; if it's `click` or `typer`, swap the flag wiring but the plan structure holds).
- The mutating operations are funneled through a small number of call sites (e.g. an `update_row` / `delete_row` helper or a session/transaction commit). If they're scattered, Step 1 widens to thread a flag down — flagged as a risk below.

## Approach

- **What we're going to do**:
  - Add a boolean `--dry-run` flag (default `False`) to the argparse parser.
  - Thread it into the code paths that perform updates and deletes.
  - At each mutation site, branch: if dry-run, log the intended action; else, perform it as today.
  - Wrap the whole run in a transaction rollback (or skip commit) when dry-run is set, as a belt-and-braces guard against a missed branch.
- **Why this approach**:
  - The log-and-skip pattern matches what the user actually wants to see ("which rows would change").
  - The transaction-rollback guard makes the flag safe even if I miss a mutation site, because the worst case is an aborted transaction rather than a stealth write.
- **Scope IN**:
  - `--dry-run` flag + help text in `scripts/migrate.py`.
  - Two tests covering: (a) flag set → no DB mutation + intended actions printed; (b) flag unset → existing behavior unchanged.
  - One README section/paragraph mentioning the flag with a usage example.
- **Scope OUT**:
  - A `--verbose` / `--quiet` flag for tuning dry-run output — deferred; open an issue if I actually want it after using dry-run once.
  - Structured output (JSON) of the dry-run plan — deferred; same trigger.
  - Refactoring scattered mutation sites into a single helper — only do this if Step 1 reveals they're scattered enough to make threading the flag ugly; otherwise out.
- **Delivery**: one PR, one commit, solo.

## Implementation

### Step 1: Map the mutation sites and wire the flag through

This step lands first because I need to know *where* to branch before I can branch — and because finding the mutation sites confirms whether the "log-and-skip" approach is clean or whether I need a refactor.

- Grep `scripts/migrate.py` for the DB-mutating calls (`session.commit`, `.delete(`, `UPDATE`, `INSERT`, raw `execute(` of DML, etc.) — because the flag is only useful if every mutation site honors it.
- Add `--dry-run` to the argparse parser with `action="store_true"` and a help string like `"Print intended updates/deletes without committing to the DB."`, because the help text is the discoverability surface the user explicitly called out.
- Pass the resulting `args.dry_run` into whatever function does the actual work (likely `main()` → migration entry point), because keeping the flag at the argparse layer would force globals.
- At each mutation site, replace `do_mutation(...)` with:
  - `if dry_run: log.info("would <verb> <identifier>: <delta>")`
  - `else: do_mutation(...)`
  - Use a consistent prefix like `"[DRY-RUN]"` in the log line, because grepping the dry-run output later is the main way I'll consume it.
- As a safety net, gate the final `session.commit()` (or equivalent) behind `if not dry_run`, and explicitly `session.rollback()` in the dry-run path, because a missed mutation site shouldn't silently corrupt the DB.

Checkpoint:
- `python scripts/migrate.py --help` shows `--dry-run` with the help string.
- `python scripts/migrate.py --dry-run` against a dev DB exits 0, prints `[DRY-RUN]` lines, and `SELECT` afterward shows untouched rows.

### Step 2: Add the two tests

This step lands here because the wiring is now stable enough to lock in with tests — and writing the tests will surface any mutation site I missed in Step 1.

- Test A — `test_dry_run_does_not_mutate`:
  - Set up a fixture DB with a known row that the migration would update *and* one it would delete.
  - Invoke the migration entry point with `dry_run=True` (or via the CLI, whichever matches the existing test style).
  - Assert: both rows are unchanged after the call, because that's the load-bearing guarantee of the flag.
  - Assert: captured log/stdout contains the `[DRY-RUN]` markers for both intended actions, because "shows what it would do" is the other half of the contract.
- Test B — `test_normal_run_still_mutates`:
  - Same fixture, invoke without `--dry-run`.
  - Assert: the update row reflects the new value and the delete row is gone, because this is the regression test confirming the flag didn't accidentally short-circuit the real path.
- Co-locate with existing tests for `migrate.py` (likely `tests/test_migrate.py`); if no test file exists, create one mirroring the project's conventions, because I don't want to invent a new test layout for a small change.

Checkpoint:
- `pytest tests/test_migrate.py -k dry_run` passes both new tests.
- Full `pytest` is still green — no existing test regressed.

### Step 3: README mention

This step lands last because the README example should reflect actual observed CLI output, not what I *think* it'll print.

- Add a short subsection (e.g. under an existing "Usage" or "Migrations" section) covering:
  - One-line description of what `--dry-run` does.
  - A copy-pasteable command: `python scripts/migrate.py --dry-run`.
  - A 2-3 line snippet of representative `[DRY-RUN]` output, because seeing the shape of the output is what convinces a future reader (me) to actually use the flag before a real run.
- Keep it under ~10 lines — because over-documenting a one-flag feature is the surest way to make the README harder to scan.

Checkpoint:
- `grep -n dry-run README.md` returns the new section.
- The command in the README, run verbatim, produces output matching the snippet.
