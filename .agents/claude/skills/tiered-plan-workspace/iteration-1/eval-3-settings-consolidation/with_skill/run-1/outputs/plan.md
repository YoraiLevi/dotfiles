# Plan — Consolidate per-env JSON settings into a single TOML, with one-release back-compat and a dump-config CLI flag

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: a single `config/settings.toml` with `[dev]`, `[staging]`, `[prod]` sections replaces the per-environment JSON files, plus a migration script, one-release back-compat loader, and a `--dump-config` CLI flag.
- **What moves**: `config/dev.json`, `config/staging.json`, `config/prod.json` are folded into `config/settings.toml`; the JSON files are retained (untouched) for one release as a deprecated fallback.
- **What gets fixed**: nothing user-visible — this is a pure consolidation; bug fixes are out of scope for this PR.
- **What changes for users**: settings authors edit one TOML file instead of three JSONs; a deprecation warning fires if the loader falls back to the old JSONs; new `app --dump-config [--env ENV]` prints the merged effective config.
- **What's still paused**: removal of the JSON fallback path and the deprecation warning ships in the next release, tracked in `ROADMAP.md` under "Remove legacy JSON settings".
- **Delivery**: one PR, one commit, solo. Branch: `chore/settings-toml-consolidation`.
- **Done when**: `python -m scripts.migrate_settings --check` reports parity for all three envs, `pytest tests/test_settings.py` is green, `app --dump-config --env prod` prints the same effective config as before the change.

---

## Tier 2 — High-level overview

### Change 1: TOML schema + loader

- New file `config/settings.toml` with three top-level tables: `[dev]`, `[staging]`, `[prod]`. Optional `[default]` table for shared keys (merged under each env).
- Loader uses stdlib `tomllib` (Python 3.11+) or `tomli` on older runtimes; pick one based on the project's `python_requires`.
- Loader signature stays the same as today: `load_settings(env: str) -> dict`. Internal implementation changes; call sites do not.
- Precedence on merge: `[default]` < `[<env>]`. Env-level keys override defaults. No deep merge of nested tables in v1 — top-level override only. Asymmetry: this is simpler than what some teams expect; called out explicitly so reviewers don't assume deep merge.
- Rationale: TOML gives sections natively, comments, and trailing commas; one file means one diff per settings change instead of three.

### Change 2: Migration script

- New `scripts/migrate_settings.py` reads the three JSONs and emits a single TOML to stdout (or `-o` path).
- Supports `--check` mode: loads both old (JSON) and new (TOML) for each env, compares the resulting dicts, exits non-zero on drift.
- Idempotent: running it twice produces the same TOML.
- Rationale: makes the migration auditable and reversible; `--check` is also the verification recipe in CI for the back-compat window.

### Change 3: One-release back-compat loader

- If `config/settings.toml` exists, load it. Done.
- Else, if any of `config/{dev,staging,prod}.json` exist, load the matching JSON, emit a `DeprecationWarning` via `warnings.warn(...)` with a pointer to the migration script.
- Else, raise `SettingsNotFoundError` with both paths in the message.
- The fallback path and the warning are removed in the next release (tracked in `ROADMAP.md`).
- Rationale: keeps any external scripts or local dev environments that still ship JSON working for one cycle without silent behavior change.

### Change 4: `--dump-config` CLI flag

- New flag on the existing top-level CLI: `app --dump-config [--env ENV] [--format toml|json]`.
- Prints the merged effective config (defaults + env overrides) and exits 0.
- Default `--env` is the same env the app would pick by default (env var `APP_ENV` or `dev`).
- Default `--format` is `toml` for round-trip friendliness; `json` for piping into `jq`.
- Rationale: gives operators and CI a way to verify what the app actually sees, which is the most common confusion when consolidating configs.

### Scope decisions (what's explicitly in vs out)

- IN: new TOML, loader rewrite, migration script with `--check`, JSON fallback with deprecation warning, `--dump-config` flag, tests for all four.
- IN: update README's "Configuration" section to point at TOML.
- OUT: removing the JSON fallback (next release, tracked in `ROADMAP.md`).
- OUT: deep-merge semantics for nested tables (deferred; open an issue if a real use case appears).
- OUT: env var overrides / 12-factor style overlay (not requested; out of scope).
- OUT: secrets handling changes (settings file is not a secrets store; unchanged).
- OUT: schema validation (e.g., pydantic) — separate concern, separate PR.

### Counts / math anchoring scale

- Files added: 2 (`config/settings.toml`, `scripts/migrate_settings.py`).
- Files modified: ~3 (loader module, CLI entrypoint, README).
- Files retained-but-deprecated: 3 (`config/{dev,staging,prod}.json`).
- Tests added: ~6 cases (load each env from TOML, fallback to JSON with warning, missing-both error, `--dump-config` smoke for each env, `--check` parity).

### Why one PR (not three)

- Solo dev. No reviewers to amortize across, no merge-queue contention.
- The four changes are tightly coupled: the loader rewrite requires the TOML to exist, the back-compat path requires the loader rewrite, the `--dump-config` flag tests the loader, and the migration script writes the TOML the loader reads. Splitting forces ordering games for no gain.
- Total diff is small (~300-500 lines including tests).

---

## Tier 3 — Implementer guide

### Step 1: Add the TOML schema and a stub `config/settings.toml`

The schema lands first so the loader has something to read in step 2.

- Create `config/settings.toml` with three sections (`[dev]`, `[staging]`, `[prod]`) and an optional `[default]` table.
- For step 1, the file can be a placeholder with one key per section — real values come from the migration in step 3.
- Document the precedence rule (`[default]` < `[<env>]`, top-level keys only) as a comment block at the top of the TOML file.

Checkpoint: `python -c "import tomllib; tomllib.load(open('config/settings.toml','rb'))"` returns without error.

### Step 2: Rewrite the loader

The loader gates everything downstream — land it before the migration so `--check` in step 3 can call it.

- Locate the existing `load_settings(env)` (likely in `app/config.py`, `app/settings.py`, or similar — grep for `dev.json`).
- Replace the JSON-reading body with: try TOML first, fall back to JSON with `warnings.warn(..., DeprecationWarning, stacklevel=2)`, else raise `SettingsNotFoundError`.
- Keep the function signature and return type identical. Call sites do not change.
- Use `tomllib` if `sys.version_info >= (3, 11)` else `tomli` (add `tomli` to `pyproject.toml` / `requirements.txt` conditionally).
- Merge logic: `merged = {**toml_data.get("default", {}), **toml_data[env]}`. One level only.
- Raise `ValueError` with a useful message if `env` is not one of the known sections.

Checkpoint: `pytest tests/test_settings.py::test_load_each_env_from_toml` is green (write this test as part of step 2).

### Step 3: Add the migration script

Lands after the loader so `--check` mode can call `load_settings` against both file shapes.

- Create `scripts/migrate_settings.py` with `argparse`:
  - `--input-dir` (default `config/`).
  - `--output` (default `-` for stdout).
  - `--check` (compare JSON-loaded vs TOML-loaded dict for each env, exit non-zero on drift).
- Write helpers:
  - `read_json_envs(dir) -> dict[str, dict]` — reads `dev.json`, `staging.json`, `prod.json`.
  - `to_toml(envs: dict[str, dict]) -> str` — emits TOML with sections in env order; use `tomli_w` (add as dev dep) or hand-format simple cases.
  - `extract_defaults(envs) -> tuple[dict, dict[str, dict]]` — optional: hoist keys identical across all three envs into `[default]`. Make this opt-in via `--hoist-defaults` to keep the default migration mechanical.
- For `--check`, load via the new loader for each env, load the raw JSON for each env, assert dict equality, print a diff (e.g., via `difflib` or `deepdiff`) on mismatch.

Checkpoint: `python -m scripts.migrate_settings -o config/settings.toml` followed by `python -m scripts.migrate_settings --check` exits 0 for all three envs.

### Step 4: Run the migration for real

Now the placeholder TOML from step 1 gets replaced with the real merged content.

- Run `python -m scripts.migrate_settings -o config/settings.toml` (consider `--hoist-defaults` if the JSONs share a lot of keys; otherwise skip).
- Eyeball the diff against the three JSON files — order may differ, but every key should be present.
- Re-run `python -m scripts.migrate_settings --check` to confirm parity.

Checkpoint: `--check` exits 0; `git diff config/settings.toml` looks like the union of the three JSONs.

### Step 5: Add the `--dump-config` CLI flag

Lands after the loader is stable so the flag has something correct to print.

- Find the CLI entrypoint (likely `app/__main__.py`, `app/cli.py`, or whatever `pyproject.toml`'s `[project.scripts]` points at).
- Add `--dump-config` (action `store_true`), `--env` (default from `os.environ.get("APP_ENV", "dev")`), and `--format` (choices `["toml", "json"]`, default `"toml"`).
- When `--dump-config` is set: call `load_settings(env)`, serialize to the chosen format (`tomli_w.dumps` or `json.dumps(..., indent=2, sort_keys=True)`), print, exit 0.
- The flag must short-circuit before the normal app startup path so it works in environments where the app can't actually run (e.g., missing DB).

Checkpoint: `app --dump-config --env prod` prints the prod config and exits 0; `app --dump-config --env prod --format json | python -m json.tool` round-trips cleanly.

### Step 6: Tests

Bundled into one step because they touch one test file.

- `tests/test_settings.py`:
  - `test_load_each_env_from_toml` — TOML present, JSON absent, asserts dict shape.
  - `test_fallback_to_json_warns` — TOML absent, JSONs present, asserts `DeprecationWarning` and correct dict.
  - `test_missing_both_raises` — TOML absent, JSONs absent, asserts `SettingsNotFoundError`.
  - `test_unknown_env_raises` — TOML present, ask for env `qa`, asserts `ValueError`.
  - `test_default_table_merges_under_env` — TOML has `[default]` + `[dev]`, asserts env wins on conflicts.
- `tests/test_cli.py`:
  - `test_dump_config_toml` — invokes CLI with `--dump-config --env dev --format toml`, asserts exit 0 and valid TOML on stdout.
  - `test_dump_config_json` — same for JSON.
- `tests/test_migrate_settings.py`:
  - `test_check_passes_after_migration` — point at a fixture dir, run migration, run `--check`, assert exit 0.

Checkpoint: `pytest -q` is green.

### Step 7: Docs + ROADMAP entry

Last because the prior steps determine what the docs say.

- Update `README.md` "Configuration" section: TOML is the source of truth; show a snippet; mention the JSON fallback is deprecated and removed next release.
- Add a `ROADMAP.md` entry: "Remove legacy JSON settings fallback" with a link to the PR landing this consolidation.
- If a `CHANGELOG.md` exists, add an entry under the next-release section noting the new TOML format, the deprecation, and the new CLI flag.

Checkpoint: `grep -r 'dev.json' README.md` returns no stale references; `ROADMAP.md` mentions the removal item.

### Critical files (patterns repeat; representative paths only)

- `config/settings.toml` — new source of truth.
- `config/{dev,staging,prod}.json` — retained, untouched, deprecated.
- `app/settings.py` (or wherever `load_settings` lives — grep `def load_settings`) — loader logic.
- `app/cli.py` (or wherever the CLI entrypoint lives) — `--dump-config` flag.
- `scripts/migrate_settings.py` — new migration + check tool.
- `tests/test_settings.py`, `tests/test_cli.py`, `tests/test_migrate_settings.py` — test surface.
- `README.md`, `ROADMAP.md`, `CHANGELOG.md` — docs.

### Reusable utilities (referenced, not reinvented)

- `tomllib` (stdlib, Python 3.11+) → TOML read. Fall back to `tomli` on older runtimes.
- `tomli_w` → TOML write (used by migration script and `--dump-config --format toml`).
- `warnings.warn(..., DeprecationWarning, stacklevel=2)` → standard deprecation signal; do not roll a custom logger path.
- `argparse` → already in use for the existing CLI; reuse the existing parser rather than introducing `click` / `typer`.
- `difflib.unified_diff` → cheap human-readable drift output in `--check` mode; only pull in `deepdiff` if dicts get nested enough that unified diff over `pprint` is unreadable.

### Commit hygiene

- Single commit on `chore/settings-toml-consolidation`. Message: `refactor(settings): consolidate per-env JSONs into settings.toml with one-release back-compat and --dump-config`.
- No AI co-author trailer unless the project's existing commits use one (check `git log` first).
- Use `git add -p` to keep the diff scoped; do not stage the deprecated JSONs as modified (they should be byte-identical).

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Produce a three-tier plan with progressive disclosure.
- Tier 1: 5-7 bullets covering what ships, what moves, what gets fixed, what changes for users, what's deferred, delivery target (branch + commit count), and a one-line "done when" verification recipe.
- Tier 2: one section per major change (bullets only, 3-5 bullets each, with rationale and any asymmetries called out); cross-cutting Scope (explicit IN / OUT lists with pointers for OUT items); a counts/math section; a one-bullet "why one PR" justification for solo devs.
- Tier 3: numbered steps, each with a one-sentence rationale, bulleted actions with specific file paths, and a Checkpoint verification command. Plus a "Critical files" list (patterns + representative paths, not exhaustive) and a "Reusable utilities" list with paths.
- Style: bullets only, no tables, no prose paragraphs longer than three sentences, declarative voice, honest about asymmetries, scope discipline (explicit IN/OUT).
- Default to solo-developer assumptions (one PR, one commit) unless told otherwise.
- Skip the format entirely for one-line bug fixes or trivially atomic changes.
