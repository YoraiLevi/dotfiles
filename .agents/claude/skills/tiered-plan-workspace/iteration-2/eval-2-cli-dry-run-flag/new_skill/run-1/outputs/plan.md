# Plan — Add a safe-preview `--dry-run` mode to the data-migration CLI

> Read top-down. Tier 1 is the manager's "should we do this?" — Tier 2 is the decider's "is the approach sound?" — Tier 3 is the reviewer's per-change dig-in — Tier 4 is the implementer's grounded step-by-step.

> Assumption (called out per task): `scripts/migrate.py` is built on `argparse`. If it turns out to use `click` / `typer` / hand-rolled `sys.argv` parsing, Step 1 of Tier 4 needs to be adapted but the rest of the plan still holds.

---

## Tier 1 — Objective & worthwhileness

- **Problem**: running the migration CLI today is all-or-nothing — there is no way to see which rows would be updated or deleted without actually mutating the database. That means every change to the migration logic is verified either by reading code or by mutating real data and rolling back, both of which are slow and error-prone.
- **Why now**: the cost is recurring. Every time the migration is touched (schema tweak, new filter, bug-fix), the developer either takes a leap of faith or stands up a throwaway DB. A `--dry-run` flag removes that friction permanently and is cheap to add.
- **Success criteria**: invoking `python scripts/migrate.py --dry-run` on a real (or representative) database prints the exact set of rows that *would* be updated and deleted, the database is byte-for-byte unchanged afterward, and the same script without the flag continues to behave identically to today.
- **Risk surface**: (1) a write path is missed by the dry-run gate and mutates the DB anyway — silently defeats the purpose; (2) the printed preview drifts from what the real run does, giving false confidence.
- **Alternatives considered**: wrap every invocation in a manual DB transaction + rollback. Dismissed — requires external tooling discipline, easy to forget, and doesn't surface *what* would change in a readable form.

---

## Tier 2 — Approach & shape

- **Approach**: thread a single `dry_run: bool` through the migration entry point, gate every write (UPDATE/DELETE/commit) on `not dry_run`, and at each gated site emit a human-readable line describing the would-be action.
- **Why this approach**: one boolean, one gate pattern, one place it enters the program. Minimal surface area, easy to audit by grep, easy to test.
- **Why not a separate `migrate-preview.py` script**: duplicates the migration logic, guarantees drift between preview and real run — the exact failure mode Tier 1 calls out.
- **Scope IN**:
  - `--dry-run` flag on the CLI with help text.
  - Gating of all DB-mutating calls in `scripts/migrate.py`.
  - Preview output describing which rows would be updated / deleted.
  - Two tests covering the new flag.
  - README mention of the flag.
- **Scope OUT**:
  - Refactoring the migration logic itself — deferred, not needed for this change.
  - A dry-run mode for any *other* script in `scripts/` — out of scope; track as a follow-up issue if/when a second script needs it.
  - Structured (JSON) preview output — deferred; plain-text is sufficient for the stated use case. Track in README as a "future enhancement" only if asked.
- **Delivery**: one PR, one commit, solo dev. Branch named e.g. `feat/migrate-dry-run`.
- **Done when**: `python scripts/migrate.py --dry-run` on a seeded test DB prints the planned mutations and leaves the DB unchanged; `pytest` passes including the two new tests; `--help` shows the new flag; README references it.

---

## Tier 3 — Per-change overview

### Change 1: CLI surface — add the `--dry-run` flag

- Add a `--dry-run` argument to the existing argparse parser in `scripts/migrate.py`, default `False`, `action="store_true"`.
- Help text: short, action-oriented — something like `"Print the rows that would be updated or deleted without modifying the database."`
- Plumb the parsed value into the function(s) that perform the migration as a `dry_run: bool` parameter.
- **Why this matters for the objective**: this is the single entry point through which the new behavior is selected. Anchoring it as one boolean parameter (rather than a global, env var, or config flag) keeps the gating audit-able by grep in Change 2.

### Change 2: Gate every write + emit preview lines

- Locate every DB-mutating call in `scripts/migrate.py` — UPDATE statements, DELETE statements, and any explicit `commit()` calls.
- Wrap each in the same pattern: if `dry_run`, print a one-line description of the would-be action (with identifying info like primary key / row count); else, execute as today.
- Read paths (SELECT, dry-run-relevant lookups to *determine* what would change) stay unchanged — they're safe and necessary even in dry-run.
- **Honest asymmetry**: if the migration computes which rows to delete *based on* a prior UPDATE's effect (e.g., "delete rows where status now equals X after the update"), pure gating will under-report deletions in dry-run mode. If that pattern exists, the dry-run path needs to compute the would-be-updated set in memory and use it to drive the deletion preview. Step 2 of Tier 4 calls this out as a check.
- **Why this matters for the objective**: the success criterion is "the preview matches what the real run would do." Uniform gating + the asymmetry check above are what make that true.

### Change 3: Two tests for the new flag

- Test A — *no mutation in dry-run*: seed an in-memory / fixture DB, invoke the migration with `dry_run=True`, assert the DB state is unchanged afterward.
- Test B — *preview output mentions affected rows*: invoke with `dry_run=True`, capture stdout, assert the output contains the identifiers of rows that would have been touched (compared against a known fixture).
- **Why this matters for the objective**: Test A directly validates the safety property ("DB unchanged"); Test B validates the usefulness property ("you can see what would happen"). Together they cover the two halves of the risk surface in Tier 1.

### Change 4: README mention

- Add a short subsection (or a line under existing usage) showing the dry-run invocation and one sentence on when to use it.
- **Why this matters for the objective**: the feature only pays off if developers know it exists. README is the discovery surface.

### Counts / scale anchoring

- One CLI file touched: `scripts/migrate.py`.
- One test file touched or created (likely `tests/test_migrate.py`).
- One docs file touched: `README.md`.
- Total: ~3 files, one commit.

### Honest debt

- No existing test infrastructure for `scripts/migrate.py` is assumed. If `tests/test_migrate.py` does not yet exist, this PR creates it with a minimal fixture — acknowledged as net-new test surface, not a refactor of existing tests.

---

## Tier 4 — Implementer guide

### Step 1: Add the `--dry-run` flag to the argparse parser

This step lands here because the flag is the user-facing entry point — every other change is downstream of how the value enters the program, so it has to exist (and be named) before anything else can reference it.

- Open `scripts/migrate.py` and locate the `argparse.ArgumentParser` setup (look for `add_argument` calls or a `build_parser` / `parse_args` helper).
- Add: `parser.add_argument("--dry-run", action="store_true", help="Print the rows that would be updated or deleted without modifying the database.")`, because `action="store_true"` defaults to `False` and gives the cleanest `args.dry_run` access pattern.
- In the function called by `main()` (or `main()` itself), accept a `dry_run: bool` parameter (or pull `args.dry_run` and pass it down), because Change 2 needs the value reachable at every write site without resorting to a module-global.
- If the migration is split across multiple helper functions, thread `dry_run` through each one that performs writes — do not introduce a global, because globals make Change 2's gating non-local and hard to audit.

Checkpoint: `python scripts/migrate.py --help` shows `--dry-run` with the help text. `python scripts/migrate.py --dry-run` runs without error (even if it still mutates — gating comes in Step 2).

### Step 2: Gate every write and emit preview lines

This step lands here because the flag is now reachable everywhere it needs to be, and gating is the load-bearing change that delivers the actual behavior — without it, Step 1 is cosmetic.

- Grep `scripts/migrate.py` for the SQL verbs / ORM methods that mutate: typical hits are `UPDATE`, `DELETE`, `.update(`, `.delete(`, `.save(`, `cursor.execute(` on mutating SQL, and any explicit `conn.commit()` / `session.commit()`.
- At each hit, apply the same pattern: `if dry_run: print(f"[dry-run] would <action> <identifier>"); else: <existing call>`, because uniformity makes the gating reviewable at a glance and reduces the chance a future write site silently bypasses the gate.
- Make the preview line informative — include primary key, table name, or row count so the output is actually useful, because a preview that just says "would update some rows" fails the Tier 1 success criterion.
- Check for the asymmetry called out in Tier 3 Change 2: if any DELETE's row-selection depends on the result of a prior UPDATE, the dry-run branch needs to compute the would-be-updated set in memory (e.g., by running the SELECT that the UPDATE's WHERE clause implies) and feed it to the DELETE-preview, because otherwise dry-run under-reports.
- If there is a top-level `try / commit / except / rollback` block, make sure the `commit()` is also gated, because an un-gated commit defeats every other gate upstream.

Checkpoint: invoke against a throwaway / fixture DB with `--dry-run`. Confirm (a) stdout shows one preview line per would-be mutation with identifying info, and (b) the DB is byte-for-byte unchanged (compare row counts and a checksum of affected tables before/after).

### Step 3: Add tests for the new flag

This step lands here because the behavior now exists and is stable enough to assert against — writing tests earlier would lock in an interface that Step 2 might still be reshaping.

- If `tests/test_migrate.py` does not exist, create it. Use whatever DB fixture pattern the project already uses elsewhere; if none exists, an in-memory SQLite seeded by the test is the lowest-overhead option.
- Test A (safety): seed the fixture DB with rows that the migration would normally touch; invoke the migration entry point with `dry_run=True` (call the Python function directly rather than shelling out to the script, because direct calls are faster and don't depend on subprocess plumbing); snapshot the DB before and after; assert equality.
- Test B (usefulness): same seed; invoke with `dry_run=True` and capture stdout (`capsys` if pytest); assert the captured output contains the primary keys (or other identifying tokens) of the rows the fixture set up as "would be touched."
- Do not test every possible mutation path — two tests covering the two halves of the success criterion is the stated scope, because exhaustive coverage is out of scope for this PR.

Checkpoint: `pytest tests/test_migrate.py` passes. Both tests fail if Step 2's gating is removed (sanity check that the tests actually exercise the gate — flip a gate locally to confirm, then revert).

### Step 4: Update the README

This step lands here because the behavior and its tests are now stable, so the docs won't need a second edit. Documenting earlier risks the docs describing an interface that later changed.

- Open `README.md` and locate the section that documents `scripts/migrate.py` usage. If no such section exists, add a brief one (heading + one fenced code block).
- Add (or extend) a usage block showing `python scripts/migrate.py --dry-run` and one sentence on when to use it ("Use `--dry-run` to preview which rows would be updated or deleted without modifying the database.").
- Keep it short — a feature mention, not a tutorial, because anything longer drifts from the source of truth (the `--help` output).

Checkpoint: `grep -n dry-run README.md` returns the new mention. Visually confirm it sits with the other migration docs, not orphaned in an unrelated section.

### Critical files

- `scripts/migrate.py` — CLI parser, migration entry point, every write site.
- `tests/test_migrate.py` — new (or extended) test file for the two flag tests.
- `README.md` — usage section that mentions the new flag.

### Reusable utilities (referenced, not reinvented)

- Existing argparse parser in `scripts/migrate.py` — extend, don't replace.
- Whatever DB fixture / connection helper the project already exposes for scripts — reuse in the tests if it exists.
- `pytest`'s `capsys` (or `capfd`) — for capturing stdout in Test B.

### Hygiene constraints

- One commit on one PR. Branch e.g. `feat/migrate-dry-run`.
- Commit message: imperative subject line describing the user-visible change (e.g., `Add --dry-run flag to migrate.py`), with a short body covering the safety guarantee and the test coverage. No AI co-author attribution.
- Do not rename or move `scripts/migrate.py` — the change is purely additive to keep the diff reviewable.
- If the project uses a formatter / linter (black, ruff, etc.), run it before committing so the diff doesn't include unrelated reformat noise.
