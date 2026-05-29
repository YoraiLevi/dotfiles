# Plan: Add `--dry-run` to `scripts/migrate.py`

## 1. Objective

- Add a `--dry-run` flag to the data-migration CLI so we can preview which rows would be updated or deleted without mutating the database.
- Motivation: safer pre-flight checks before running migrations on real data; useful for review and for reproducing reports of "what changed".

**Definition of Done:**

- `python scripts/migrate.py --dry-run` runs end-to-end without opening a write transaction (no `UPDATE` / `DELETE` / `INSERT` executed against the DB).
- The dry-run output prints, per affected table, the count and a sample of rows that *would* be updated and deleted.
- `python scripts/migrate.py --help` lists `--dry-run` with a one-line description.
- Two new tests pass: (a) dry-run prints planned changes; (b) dry-run leaves the DB untouched.
- `README.md` mentions `--dry-run` in the usage section with a one-line example.
- Existing migration tests still pass unchanged.

## 2. Approach

**Strategy: thread a single `dry_run: bool` from `argparse` down into the migration functions; gate every mutating call behind it and print a planned-change summary instead.**

Why this shape:

- Minimal blast radius — one flag, one boolean parameter, no new abstractions.
- Mutation sites are already centralized in the migration helpers, so gating happens in a small number of well-known places.

Mechanics that matter:

- `argparse`: `parser.add_argument("--dry-run", action="store_true", help="Print planned changes without modifying the database.")` — `action="store_true"` so the default is `False` and existing invocations are unchanged.
- Argparse turns `--dry-run` into the attribute `args.dry_run` (hyphen-to-underscore). Pass it explicitly as a kwarg to migration functions; do not stash it on a module-level global.
- Gating pattern at each mutation site:
  - Compute the candidate rows (the `SELECT` that drives the change runs in both modes).
  - If `dry_run`: log `[DRY-RUN] would UPDATE <table> rows=<n> sample=<first 3 ids>` and return.
  - Else: execute the mutation as today.
- Wrap the dry-run path in a transaction that is rolled back at the end, so any accidental write during a `SELECT`-with-side-effects is reverted. Belt-and-suspenders against a future contributor adding a mutation without gating it.

**Scope IN:**

- `argparse` flag + help text in `scripts/migrate.py`.
- `dry_run` plumbed into the migration entrypoints and respected at every existing `UPDATE` / `DELETE` / `INSERT` call site.
- Two pytest tests covering the new flag.
- One-paragraph mention in `README.md` with a usage example.

**Scope OUT:**

- Structured JSON output of planned changes — out because nobody has asked for machine-readable diffs yet; defer until a consumer appears -> note in `STATE.md` under "deferred".
- A `--yes` / `--confirm` interactive prompt for the non-dry-run path — out because this PR only adds a preview mode, not new safety prompts -> follow-up if we decide we want them.
- Coloured terminal output for the dry-run summary — out because it adds a dependency and the plain log lines are already grep-friendly -> not tracked; revisit only on request.
- Refactoring the migration functions to return a planned-changes object — out because the print-as-you-go pattern matches the existing code shape; a return-based refactor is a bigger change -> follow-up if a second caller ever needs the data.

**Delivery:** one PR, one commit, on a `feat/migrate-dry-run` branch. Solo.

## 3. Implementer guide

### Step 1 - Add the flag and thread it through

In `scripts/migrate.py`, register the argument and pass it into the entrypoint:

```python
parser.add_argument(
    "--dry-run",
    action="store_true",
    help="Print planned changes without modifying the database.",
)
args = parser.parse_args()
run_migration(conn, dry_run=args.dry_run)
```

Update `run_migration` (and any helpers it calls that mutate) to accept `dry_run: bool = False`, and gate each mutation site:

```python
def _apply_updates(conn, rows, *, dry_run: bool) -> None:
    if dry_run:
        sample = [r["id"] for r in rows[:3]]
        print(f"[DRY-RUN] would UPDATE users rows={len(rows)} sample={sample}")
        return
    conn.execute("UPDATE users SET ... WHERE id = ANY(:ids)", {"ids": [r["id"] for r in rows]})
```

Apply the same gate to every `DELETE` / `INSERT` site. Keep all `SELECT` queries unchanged so the preview is accurate.

Wrap the dry-run path so it never commits:

```python
if dry_run:
    with conn.begin() as tx:
        _do_work(conn, dry_run=True)
        tx.rollback()
else:
    _do_work(conn, dry_run=False)
```

Checkpoint: `python scripts/migrate.py --help` shows the new flag; `python scripts/migrate.py --dry-run` runs without error against a local test DB.

### Step 2 - Tests

Add to the existing migration test module (e.g. `tests/test_migrate.py`):

```python
def test_dry_run_prints_planned_changes(capsys, seeded_db):
    migrate.run_migration(seeded_db, dry_run=True)
    out = capsys.readouterr().out
    assert "[DRY-RUN] would UPDATE" in out
    assert "[DRY-RUN] would DELETE" in out

def test_dry_run_does_not_mutate_db(seeded_db):
    before = snapshot(seeded_db)  # however the existing tests snapshot state
    migrate.run_migration(seeded_db, dry_run=True)
    after = snapshot(seeded_db)
    assert before == after
```

Rationale for this ordering: writing the tests after the gating exists (rather than first) is intentional here — the gating shape is small and obvious, and the tests double as the verification that Step 1's wrap-and-rollback actually holds.

Checkpoint: `pytest tests/test_migrate.py -k dry_run` passes; full `pytest` is still green.

### Step 3 - README

In `README.md`, under the existing migration usage section, add:

```markdown
### Preview a migration

Use `--dry-run` to print which rows would be updated or deleted without
touching the database:

    python scripts/migrate.py --dry-run
```

Checkpoint: `grep -n dry-run README.md` returns the new lines; rendered README looks right in a Markdown preview.

### Step 4 - Commit and open the PR

- `git add scripts/migrate.py tests/test_migrate.py README.md`
- Commit message: `feat(migrate): add --dry-run preview mode`
- Push branch, open PR, self-review against the Definition of Done in section 1.

Checkpoint: every Definition-of-Done bullet checked off before merging.
