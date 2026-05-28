# Plan — Add `--dry-run` to `scripts/migrate.py`, cover it with tests, mention it in the README

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: a `--dry-run` flag on `scripts/migrate.py` that prints the rows it would update and delete without committing any database changes.
- **What moves**: nothing is renamed or moved; one new flag is added to the existing CLI, and one new guard wraps the mutation path.
- **What gets fixed**: no pre-existing bugs folded in; this is a pure additive change.
- **What changes for users**: a new `--dry-run` flag (default off, so existing invocations are unchanged); when set, the script logs the planned mutations and exits without writing.
- **What's still paused**: no `--dry-run` for the rollback path, no JSON output mode, no row-count cap — out of scope for this PR (track in `TODO`/issue if they come up later).
- **Delivery**: single PR, single commit on a branch like `feat/migrate-dry-run`. Solo project — no review-surface split.
- **Done when**: `python scripts/migrate.py --dry-run` prints planned changes and exits 0 with the DB untouched, `python scripts/migrate.py --help` shows the new flag, and `pytest tests/test_migrate.py -k dry_run` passes.

---

## Tier 2 — High-level overview

### Change 1: CLI flag wiring in `scripts/migrate.py`

- Assumption: the script uses `argparse` (note: if it actually uses `click`, swap `add_argument` for `@click.option` — the surface area is identical).
- Add a single boolean flag: `--dry-run` (store_true, default False), with help text: "Print planned updates and deletions without modifying the database."
- Thread the flag value into the existing migration entrypoint (e.g., `run_migration(..., dry_run: bool = False)`); do not pass it through a global.
- At each mutation site (UPDATE, DELETE, INSERT if any), branch on `dry_run`: if True, log the intended statement + affected primary keys; if False, execute as today.
- Wrap the whole run in a transaction; on `dry_run`, roll back unconditionally at the end as a belt-and-suspenders guarantee even if a logging branch is missed.

### Change 2: Output format for dry-run

- One log line per planned mutation, prefixed `[DRY-RUN]`, including operation (`UPDATE`/`DELETE`), table, and the primary-key list (or count if the list is large).
- End-of-run summary line: `[DRY-RUN] would update N rows across T tables; would delete M rows`.
- Use the script's existing logger (or `print` if it doesn't have one); do not introduce a new logging dependency.
- Exit code 0 on a successful dry-run; non-zero only if planning itself fails (e.g., DB unreachable, malformed source data).

### Change 3: Tests

- Add `tests/test_migrate.py::test_dry_run_does_not_mutate` — invokes the CLI (or calls `run_migration(dry_run=True)`) against a fixture DB (sqlite in-memory or whatever the project already uses) and asserts row counts before == after.
- Add `tests/test_migrate.py::test_dry_run_reports_planned_changes` — captures stdout/log output and asserts the `[DRY-RUN]` summary line is present and counts are non-zero when fixture data has matching rows.
- Reuse whatever fixture/test-DB helper the project already has; do not introduce a new test harness.

### Change 4: README mention

- Add one short subsection (or a one-liner under an existing "Usage" section) showing `python scripts/migrate.py --dry-run` with a one-line description.
- No screenshots, no long example output — link to `--help` for the canonical reference.

### Scope decisions (what's explicitly in vs out)

- IN: `--dry-run` flag, dry-run-aware mutation path, two tests, README mention, updated `--help` text (free with the argparse/click change).
- OUT: dry-run for the rollback/reverse-migration command (separate path, separate flag, separate PR if ever needed). Tracked in commit message footer as "Follow-up: dry-run for rollback path".
- OUT: machine-readable (`--output json`) dry-run output. Defer until a caller actually needs it.
- OUT: a `--limit N` cap on dry-run printout for very large migrations. Defer; current migrations are small enough.

### Counts anchoring scale

- 1 script touched (`scripts/migrate.py`).
- 1 test file touched or created (`tests/test_migrate.py`).
- 1 doc touched (`README.md`).
- 2 new tests.
- 0 files renamed, 0 files deleted.

### Why one PR (not three)

- Solo project, no external reviewers, no review-surface budget to amortize.
- The code, test, and doc changes are tightly coupled — splitting them produces a "code lands without test/doc" intermediate state that's worse than the merged change.

---

## Tier 3 — Implementer guide

### Step 1: Add the flag to the CLI parser

Land the flag first so the rest of the wiring has something to thread through.

- Open `scripts/migrate.py`. Locate the `argparse.ArgumentParser` construction (or the `@click.command` decorator if it's click).
- Add: `parser.add_argument("--dry-run", action="store_true", help="Print planned updates and deletions without modifying the database.")`
- If click: `@click.option("--dry-run", is_flag=True, default=False, help="...")`.
- Confirm the parsed `args.dry_run` (or `dry_run` kwarg) is available at the call site of the migration function.

Checkpoint: `python scripts/migrate.py --help` shows `--dry-run` with the new help text. The script still runs end-to-end without the flag exactly as before.

### Step 2: Thread `dry_run` into the migration function

Pass it explicitly; resist the global.

- Locate the top-level function the CLI calls (likely `run_migration`, `main`, `migrate`, or similar — grep for the function called immediately after `parser.parse_args()`).
- Add `dry_run: bool = False` to its signature.
- At the CLI invocation site, pass `dry_run=args.dry_run`.

Checkpoint: `python scripts/migrate.py --dry-run` runs without error; behavior is still wrong (it will mutate) — that's Step 3.

### Step 3: Guard the mutation sites

This is the load-bearing change. Do it carefully.

- Inside `run_migration`, identify every place a write statement is executed (look for `.execute(...)` with UPDATE/DELETE/INSERT, or ORM `.save()` / `.delete()` calls).
- For each: replace the unconditional execute with:
  - If `dry_run`: log `f"[DRY-RUN] {op} {table} pk={pk_list}"` and continue.
  - Else: execute as today.
- After the main loop, if `dry_run`: log the summary line `f"[DRY-RUN] would update {n_update} rows across {n_tables} tables; would delete {n_delete} rows"`.
- Wrap the whole `run_migration` body in an explicit transaction. On `dry_run`, call `conn.rollback()` (or the ORM equivalent) at the end unconditionally; on the real path, `conn.commit()`.

Checkpoint: `python scripts/migrate.py --dry-run` prints `[DRY-RUN]` lines and the summary; querying the DB after shows zero changes.

### Step 4: Add the tests

Land tests in the same commit as the code so the PR is self-verifying.

- Open or create `tests/test_migrate.py`.
- Reuse the project's existing test-DB fixture (grep for `@pytest.fixture` in `tests/` to find it).
- Test 1: `test_dry_run_does_not_mutate` — seed the fixture DB with rows the migration would touch, call `run_migration(dry_run=True)` (or invoke via subprocess/`CliRunner` if click), assert the row counts and content are unchanged.
- Test 2: `test_dry_run_reports_planned_changes` — same seed, capture stdout (`capsys`) or the logger output (`caplog`), assert `[DRY-RUN]` appears and the summary counts are > 0.
- If invoking the CLI as a subprocess, prefer calling `run_migration` directly — it's faster and avoids subprocess env quirks.

Checkpoint: `pytest tests/test_migrate.py -k dry_run -v` shows both tests passing.

### Step 5: Update the README

Last so it reflects the shipped behavior.

- Open `README.md`. Find the section that documents `scripts/migrate.py` (likely "Usage", "Scripts", or similar).
- Add a one-liner or short subsection:
  - `python scripts/migrate.py --dry-run` — preview the migration's planned updates and deletions without touching the database.
- No need to paste example output; `--help` is the source of truth.

Checkpoint: `grep -n "dry-run" README.md` shows the new mention. Visually skim the section to confirm it reads cleanly.

### Step 6: Commit and open the PR

- Stage exactly: `scripts/migrate.py`, `tests/test_migrate.py`, `README.md`.
- Commit message: `feat(migrate): add --dry-run flag to preview planned changes` with a body that lists the three deltas (CLI flag, tests, README) and the OUT items.
- Push the branch and open the PR.

Checkpoint: PR diff shows three files, no incidental edits, all CI green.

### Critical files (patterns repeat; representative paths only)

- `scripts/migrate.py` — CLI parser, `run_migration` function, every `.execute(UPDATE|DELETE|INSERT ...)` call site.
- `tests/test_migrate.py` — new or extended, reuses existing DB fixture.
- `README.md` — usage section for `migrate.py`.

### Reusable utilities (referenced, not reinvented)

- Existing test-DB fixture in `tests/` (grep for `@pytest.fixture` to locate) — do not stand up a new in-memory DB harness.
- Existing logger configured in `scripts/migrate.py` (if any) — reuse for `[DRY-RUN]` lines rather than mixing `print` and logger calls.
- Existing transaction-management pattern in `run_migration` (if it already commits/rolls back) — extend it; don't introduce a parallel transaction scope.

### Assumptions (call out before coding)

- The script uses `argparse`. If it actually uses `click`, the parser-change line in Step 1 is the only diff; the rest of the plan is unchanged.
- The project has at least one pytest fixture for a test database. If not, this plan grows by one step (stand up a sqlite-backed fixture) — flag and confirm before proceeding.
- The migration runs inside a single transaction today, or can be wrapped in one without breaking semantics. If migrations rely on multiple independent transactions, the unconditional-rollback safety net in Step 3 needs to be per-transaction instead of per-run — flag and confirm.

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Use the `tiered-plan` skill format.
- Tier 1: 5-7 bullets covering what ships, what moves, what's fixed, user impact, what's deferred (with pointer), delivery target, done-when verification.
- Tier 2: one section per major change (shape + rationale + asymmetries), then scope decisions (explicit IN/OUT), counts/math anchoring scale, and "why one PR" for solo devs.
- Tier 3: numbered steps, each with one-sentence rationale, bulleted file-path action items, a Checkpoint verification line. End with Critical files (patterns, not enumeration) and Reusable utilities (cite by path).
- Style: bullets only, no tables, declarative voice, no hedging, no multi-PR splits unless a concrete review-surface reason exists. Honest about asymmetries. All deferred work has a tracking pointer.
