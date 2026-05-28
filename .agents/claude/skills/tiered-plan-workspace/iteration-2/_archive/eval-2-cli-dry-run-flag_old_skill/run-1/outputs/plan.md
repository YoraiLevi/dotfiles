# Plan — Add `--dry-run` flag to migrate.py, with help text, tests, and README mention

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: a `--dry-run` boolean flag on `scripts/migrate.py` that prints the rows it would update and delete instead of mutating the database.
- **What's added**: one CLI flag, one preview-print code path, two tests, one README paragraph.
- **What gets fixed**: nothing — this is a pure additive change. No existing behavior changes when the flag is absent.
- **What changes for users**: `python scripts/migrate.py --dry-run` now produces a no-op preview; default invocation behavior is unchanged.
- **What's still paused**: no rollback report, no diff-style output, no `--verbose` integration — out of scope for this PR.
- **Delivery**: one commit, one PR. Solo project — no review-surface budget to amortize.
- **Done when**: `pytest` passes, `python scripts/migrate.py --help` shows the flag, and `python scripts/migrate.py --dry-run` against a test DB leaves row counts unchanged.

**Assumption** (flag if wrong): `scripts/migrate.py` uses the stdlib `argparse` module for CLI parsing. If it uses `click`, `typer`, or hand-rolled `sys.argv` parsing, Step 1 below adjusts trivially but the exact syntax differs.

---

## Tier 2 — High-level overview

### Change 1: New `--dry-run` flag on the CLI

- Add a `--dry-run` boolean flag (argparse `action="store_true"`, default `False`) to the existing argument parser in `scripts/migrate.py`.
- Help text reads roughly: *"Print rows that would be updated or deleted, without mutating the database."*
- The flag's value flows into the migration entry point as a parameter (e.g., `run_migration(dry_run=args.dry_run)`).

### Change 2: Preview path in the migration logic

- At each mutation site (UPDATE, DELETE), branch on `dry_run`: if true, print a one-line description of the row (e.g., `[DRY-RUN] UPDATE users id=42 set status='archived'`) and skip the actual SQL execution.
- Read-only queries (SELECT for identifying target rows) run unchanged in both modes — that's how we know what to preview.
- The transaction is still opened, but committed only when `dry_run` is false. (If the script uses autocommit per statement, wrap mutation calls in an `if not dry_run:` guard at each call site instead.)
- Rationale: keeping the preview-print adjacent to the mutation call (rather than building a separate "planner" pass) means one source of truth for what gets mutated and what gets previewed — they cannot drift.

### Change 3: Tests for the flag

- Two tests, both in the existing test file for `migrate.py` (likely `tests/test_migrate.py` — confirm in Step 3).
- Test A: invoke the migration with `dry_run=True` against a seeded in-memory or temp DB; assert row counts before and after are identical, and assert the printed output contains the `[DRY-RUN]` marker.
- Test B: invoke with `dry_run=False` (or default) against the same seeded DB; assert that the expected mutations actually occurred.
- The two tests share a fixture for the seeded DB — write the fixture once if it does not already exist.

### Change 4: README mention

- One short paragraph (2-3 sentences) in `README.md` under the section that documents `scripts/migrate.py`. If no such section exists, add one.
- Show the invocation: `python scripts/migrate.py --dry-run`. Describe what it does and when to use it (e.g., before a production migration).

### Scope decisions (what's explicitly in vs out)

- **IN**: the flag, the preview prints, two tests, one README paragraph, updated `--help` output.
- **OUT**: structured diff output (e.g., JSON or unified-diff format) — defer until a user asks for it.
- **OUT**: a `--verbose` flag or log-level tuning — separate concern, separate PR if ever needed.
- **OUT**: dry-run for schema migrations (DDL) — current task scope is row-level data migration.
- **OUT**: refactoring the migration script's structure to make dry-run cleaner — only if the existing structure makes the guard genuinely awkward, in which case flag it as a Tier 2 asymmetry and stop to discuss.

### Counts anchoring scale

- Files touched: 3 (`scripts/migrate.py`, `tests/test_migrate.py` or equivalent, `README.md`).
- New flag: 1.
- New tests: 2.
- New README paragraphs: 1.
- Expected diff size: small — under 100 lines added, near-zero lines removed.

### Why one PR (not three)

- Solo project. No external reviewers, no review-surface budget to amortize across multiple PRs.
- The four changes (flag, preview path, tests, README) are tightly coupled — splitting them produces broken intermediate states (a flag with no preview path, or a preview path with no docs).
- One commit per the task brief.

---

## Tier 3 — Implementer guide

### Step 1: Add the `--dry-run` flag to the argparse parser

The flag has to exist before any code can branch on it.

- Open `scripts/migrate.py` and locate the `argparse.ArgumentParser` instance (search for `add_argument` or `ArgumentParser`).
- Add: `parser.add_argument("--dry-run", action="store_true", help="Print rows that would be updated or deleted, without mutating the database.")`.
- Note: argparse converts `--dry-run` to `args.dry_run` (hyphen becomes underscore). Use `args.dry_run` downstream.
- Thread `args.dry_run` into whatever function performs the migration. Common shapes:
  - If there's a `main()` that calls `run_migration(...)`, add `dry_run=args.dry_run` to that call.
  - If logic lives inline in `main()`, pass `dry_run` into the inner loop variables.

Checkpoint: `python scripts/migrate.py --help` lists `--dry-run` with the help text above.

### Step 2: Branch on `dry_run` at each mutation site

The preview must live where the mutation lives, so they cannot drift.

- Search `scripts/migrate.py` for SQL mutation calls. Patterns to grep:
  - `cursor.execute("UPDATE` / `cursor.execute("DELETE` / `cursor.execute('UPDATE` / `cursor.execute('DELETE`
  - `cursor.execute(` followed by a query variable — inspect those query strings.
  - ORM equivalents if applicable: `.update(`, `.delete(`, `session.delete(`.
- At each site, restructure to:
  ```python
  if dry_run:
      print(f"[DRY-RUN] {describe_row(row)}")
  else:
      cursor.execute(...)
  ```
  where `describe_row` is a short helper (define it once at module scope, or inline if there's only one or two sites).
- If the script opens an explicit transaction and calls `conn.commit()` at the end, guard the commit: `if not dry_run: conn.commit()`. If `dry_run` is true, call `conn.rollback()` instead, to be defensive against any accidental mutation that slipped through.
- If a mutation is built dynamically (e.g., bulk update from a list comprehension), the print can summarize: `[DRY-RUN] UPDATE users — N rows: ids=[...]`.

Checkpoint: `python scripts/migrate.py --dry-run` against a populated test DB prints `[DRY-RUN]` lines and `SELECT COUNT(*)` against the affected tables returns the same number before and after.

### Step 3: Locate or create the test file, then add two tests

Confirm where existing tests for `migrate.py` live before writing new ones.

- Search for test files: glob for `tests/test_migrate*.py` and `test/test_migrate*.py`. If multiple, use the one already importing from `scripts.migrate`.
- If no test file exists yet, create `tests/test_migrate.py` and add the minimum bootstrapping (imports, a DB fixture).
- Test A — `test_dry_run_does_not_mutate`:
  - Set up a seeded DB (in-memory SQLite is simplest if the project supports it; otherwise reuse whatever fixture the project already has).
  - Call the migration entry point with `dry_run=True` (or invoke as a subprocess: `subprocess.run([sys.executable, "scripts/migrate.py", "--dry-run", ...], capture_output=True)`).
  - Assert: row counts on affected tables are identical pre- and post-call.
  - Assert: captured stdout contains `[DRY-RUN]`.
- Test B — `test_default_run_mutates`:
  - Same fixture, call without `dry_run` (or without the flag).
  - Assert: row counts changed as expected (the specifics depend on the migration's intended effect — mirror an existing test if one is there).
- Prefer calling the Python function directly over subprocess if the entry point is importable — it's faster and easier to assert on.

Checkpoint: `pytest tests/test_migrate.py -v` shows both new tests passing, and the existing test suite still passes.

### Step 4: Update the README

The docs catch users who never read `--help`.

- Open `README.md`. Search for a section mentioning `migrate.py` or "migration".
- Add (or extend) a short subsection:
  ```markdown
  ### Dry-run mode

  Pass `--dry-run` to preview what the migration would do without touching the database:

      python scripts/migrate.py --dry-run

  This prints the rows that would be updated or deleted. Useful for sanity-checking a migration before running it against production data.
  ```
- If the README has a "Usage" or "CLI" section that lists existing flags, also add `--dry-run` to that list with the same one-line description.

Checkpoint: `grep -i "dry-run" README.md` returns at least one hit; render the README locally (or on GitHub preview) and confirm the section reads cleanly.

### Step 5: Final verification + commit

End-to-end check before committing.

- Run the full test suite: `pytest` (or whatever the project uses — check for `Makefile`, `pyproject.toml` `[tool.pytest.ini_options]`, or a `tox.ini`).
- Run `python scripts/migrate.py --help` and visually confirm `--dry-run` appears.
- Run `python scripts/migrate.py --dry-run` against a non-production DB and eyeball the output.
- Stage and commit: one commit, message along the lines of `feat(migrate): add --dry-run flag for previewing migrations`.
- Open the PR.

Checkpoint: PR is green (tests pass in CI if CI exists), and the diff is the expected 3 files.

### Critical files (patterns repeat; representative paths only)

- `scripts/migrate.py` — the CLI script: flag declaration + mutation-site guards.
- `tests/test_migrate.py` (or equivalent — locate in Step 3) — two new tests + possibly a shared DB fixture.
- `README.md` — one new subsection or paragraph.

### Reusable utilities (referenced, not reinvented)

- `argparse.ArgumentParser.add_argument` with `action="store_true"` — stdlib, no new dependency.
- Whatever DB fixture or seeding helper the existing tests use — reuse it; do not build a parallel test-DB harness.
- Any existing logging / print helper in `scripts/migrate.py` — prefer it over raw `print()` if one is already there, so dry-run output respects the script's existing output conventions.

### Commit hygiene

- One commit, conventional-commit style if the repo already uses it (check `git log --oneline -20`).
- No AI co-author trailer unless the user has explicitly asked for one in this repo.

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Three tiers: Tier 1 = 5-7 bullets covering what ships / what's added / user-visible change / what's deferred / delivery / done-when. Tier 2 = one section per major change, plus IN/OUT scope, plus counts. Tier 3 = numbered steps with file paths, exact edits where non-obvious, and a Checkpoint line per step.
- Bullets only. No tables. No prose paragraphs over three sentences.
- Declarative voice. No "we might consider" hedging.
- Solo-dev default: one PR, one commit. Multi-PR only when there's a concrete review-surface reason.
- Always explicit IN / OUT scope lists. Always point deferred items at where they're tracked.
- Honest about asymmetries: if part of the change doesn't fit the uniform pattern, say so in plain words.
- End with a Meta section that reproduces these instructions so the format is self-propagating.
