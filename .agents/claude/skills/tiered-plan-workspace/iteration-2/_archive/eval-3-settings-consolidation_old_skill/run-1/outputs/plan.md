# Plan — Consolidate per-env JSON config into single TOML, add migration + back-compat + dump CLI

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: A single `config/settings.toml` with `[dev]` / `[staging]` / `[prod]` sections replaces the three per-environment JSON files, with a one-release back-compat shim that still reads the old JSONs (and logs a deprecation warning) when the TOML is absent.
- **What moves**: `config/dev.json`, `config/staging.json`, `config/prod.json` collapse into `config/settings.toml`. A new `scripts/migrate_config.py` produces the TOML from whatever JSONs exist. Settings loader moves to a single entry point (`settings.load(env)`).
- **What gets fixed**: Drift between the three JSONs (today, a key added to `dev.json` silently lacks a counterpart in `staging.json`). The TOML's shared `[default]` table plus per-env overrides makes the common-vs-divergent split explicit.
- **What changes for users (i.e. you, the operator)**: New `--dump-config` CLI flag prints the fully-merged effective config (default + env overrides) for the selected environment as TOML to stdout. Old JSONs keep working for one release; a `DeprecationWarning` fires on every load from JSON.
- **What's still paused**: Secrets handling (env-var interpolation, `.env` loading, vault integration) — tracked in ROADMAP under "config: secrets pipeline". Schema validation (pydantic / dataclass) — tracked under "config: typed settings".
- **Delivery**: One PR, one commit, on branch `chore/config-toml-consolidation`. Solo dev.
- **Done when**: `python -m app --env prod --dump-config` prints the merged prod config from `settings.toml`; deleting `settings.toml` and re-running prints the same config (sourced from the JSONs) plus a deprecation warning on stderr; `pytest` passes.

---

## Tier 2 — High-level overview

### Change 1: TOML schema with default + per-env overrides

- Single file `config/settings.toml` with four tables: `[default]`, `[dev]`, `[staging]`, `[prod]`.
- `[default]` holds keys common to all environments; each `[<env>]` table holds only that environment's overrides.
- Effective config = `deep_merge(default, env_table)`. Last write wins per key path; nested tables are merged recursively, not replaced wholesale.
- Loader returns a plain `dict` (no schema validation in this PR — that's deferred).
- Unknown environments raise `ConfigError` listing the available env tables.

### Change 2: Migration script (one-shot, idempotent)

- `scripts/migrate_config.py` reads any of `config/{dev,staging,prod}.json` that exist, computes the intersection of keys with identical values across all three → those become `[default]`, the rest become per-env overrides.
- Idempotent: re-running with `settings.toml` already present is a no-op unless `--force` is passed.
- Prints a diff-style summary (keys promoted to default, keys kept per-env) to stdout so the operator can sanity-check before committing.
- Not invoked at runtime. Operator runs it once, reviews the output, commits the TOML.

### Change 3: One-release backwards compatibility

- Loader resolution order: (1) `config/settings.toml` if present, (2) `config/<env>.json` if present, else `ConfigError`.
- When the JSON path is taken, emit `warnings.warn("config/<env>.json is deprecated; run scripts/migrate_config.py to generate settings.toml", DeprecationWarning, stacklevel=2)` and `logger.warning(...)` once per process.
- No silent fallback: if both `settings.toml` and the JSONs exist, TOML wins and a single info-level log line notes the JSONs are being ignored.
- Removal of JSON support is tracked as a follow-up: ROADMAP item "config: drop JSON back-compat after one release".

### Change 4: `--dump-config` CLI flag

- New flag on the existing CLI entry point. Resolves the same way the runtime loader does (TOML or JSON fallback).
- Output format: TOML, written to stdout. This means the operator can pipe it into a file as a starting point for a new env.
- Exit code 0 on success, non-zero on `ConfigError`. No side effects (does not start the app).

### Scope decisions (what's explicitly in vs out)

- IN: TOML schema, loader rewrite, migration script, deprecation shim for JSON, `--dump-config` flag, tests covering all four.
- OUT: schema validation / typed settings (ROADMAP: "config: typed settings"); secrets / env-var interpolation (ROADMAP: "config: secrets pipeline"); removing JSON support entirely (ROADMAP: "config: drop JSON back-compat after one release"); config hot-reload (not on ROADMAP, file an issue if needed).
- OUT: changing any actual config *values*. The migration must preserve current behavior byte-for-byte modulo the default/override split.

### Counts anchoring scale

- Files removed (eventually, not this PR): 3 (`dev.json`, `staging.json`, `prod.json`).
- Files added: 2 (`config/settings.toml`, `scripts/migrate_config.py`).
- Loader module: ~1 file rewritten (likely `app/config.py` or `app/settings.py` — confirm at Step 1).
- CLI: 1 flag added to whatever the existing `argparse` / `click` / `typer` entry point is.
- Tests added: ~4 new test modules (loader, merge, migration, CLI dump).
- Net LOC: roughly +250 / -150, mostly tests.

### Why one PR (not three)

- Solo dev. No external reviewers, no review-surface budget to amortize across multiple PRs.
- The four changes are tightly coupled: the loader can't ship without the back-compat shim, the migration script is what produces the TOML the loader reads, and the dump flag is the verification surface for the whole thing.
- Splitting would create transient broken states (loader expects TOML that doesn't exist yet) with no benefit.

---

## Tier 3 — Implementer guide

### Step 1: Locate and inventory the current loader

[Have to know what we're replacing before we replace it.]

- Grep for `dev.json`, `staging.json`, `prod.json` to find every read site: `grep -rn -E "(dev|staging|prod)\.json" --include="*.py"`.
- Grep for `json.load`, `json.loads`, `Path("config")` to find the loader function and any ad-hoc readers.
- Note the loader's current signature and return type — the new loader must match it (no caller changes in this PR).
- Inventory the three JSONs: list every top-level key in each, note which keys differ. This drives the migration script's default-promotion logic and is also a sanity check for the manual review of the generated TOML.

Checkpoint: A short note (scratch, not committed) listing the loader module path, the loader function signature, and the count of distinct top-level keys across the three JSONs.

### Step 2: Add `tomllib` / `tomli` import path

[Decide the TOML reader before writing the loader.]

- Python 3.11+: use stdlib `tomllib` (read-only, which is what the loader needs).
- Python 3.10 or earlier: add `tomli` to `pyproject.toml` / `requirements.txt` runtime deps.
- For *writing* TOML (migration script + `--dump-config`): stdlib has no writer. Add `tomli-w` (small, no deps) to runtime deps. Justify in the commit body: writing TOML is on the hot path for `--dump-config`, can't be dev-only.
- Confirm the project's minimum Python version in `pyproject.toml` before picking.

Checkpoint: `python -c "import tomllib; import tomli_w"` (or `tomli` substitute) succeeds in the project venv.

### Step 3: Write the loader

[Loader before migration script so the migration script's output can be validated against it.]

- Module: same path as the existing loader (likely `app/config.py` or `app/settings.py` — from Step 1).
- Public API: `load(env: str) -> dict`. Keep any existing wrapper functions as thin shims that delegate to `load`.
- Resolution order inside `load`:
  1. If `config/settings.toml` exists: parse it, deep-merge `[default]` with `[<env>]`, return.
  2. Else if `config/<env>.json` exists: read it, fire `DeprecationWarning` + `logger.warning` once per process (use a module-level `_warned: set[str]` guard), return its contents as-is.
  3. Else: raise `ConfigError(f"no config found for env={env!r}")`.
- If both TOML and JSONs exist: TOML wins, log one info-level line `"settings.toml present; ignoring legacy config/*.json"` (also guarded by `_warned`).
- Deep-merge helper: recursive, dict-into-dict merges by key, scalars and lists are replaced wholesale (don't try to merge lists element-wise — that's a footgun).
- Unknown env: raise `ConfigError` with the list of `[<env>]` tables found in the TOML.

Checkpoint: Unit test passes for the merge helper (default-only key survives, env-only key survives, env overrides default scalar, nested dict merges by key).

### Step 4: Write the migration script

[After the loader, so the script's output can be round-tripped through the loader.]

- File: `scripts/migrate_config.py`. Standalone, runnable as `python scripts/migrate_config.py [--force] [--out config/settings.toml]`.
- Algorithm:
  1. Read whichever of `config/{dev,staging,prod}.json` exist (don't require all three — partial migrations are valid).
  2. Compute `common = {k: v for k, v in dev.items() if all(env.get(k) == v for env in [staging, prod])}` — recursive on nested dicts.
  3. Per-env overrides: `env_overrides[name] = {k: v for k, v in env.items() if common.get(k) != v}`.
  4. Emit `[default]` + one `[<env>]` per JSON found, in stable order (default, dev, staging, prod).
- Idempotency: if `--out` already exists, refuse unless `--force` is passed. Print: `"settings.toml already exists. Re-run with --force to overwrite."` and exit 1.
- Summary output (to stdout, before the TOML write): `"Promoted N keys to [default]. Per-env override counts: dev=X, staging=Y, prod=Z."`
- Use `tomli_w.dumps()` for serialization. Preserve key order (insertion order is fine — Python dicts are ordered).

Checkpoint: Run `python scripts/migrate_config.py --out /tmp/test.toml` against the real JSONs; diff `load("prod")` output before vs after by piping the existing JSON loader's result against the new TOML-backed loader's result. They must be equal.

### Step 5: Add `--dump-config` CLI flag

[Now that the loader is solid, expose it.]

- Locate the existing CLI entry point (likely `app/__main__.py`, `app/cli.py`, or a `[project.scripts]` entry in `pyproject.toml`).
- Add `--dump-config` as a flag (no value). When set: call `load(env)`, serialize the resulting dict with `tomli_w.dumps()`, write to stdout, exit 0.
- The existing `--env` flag (if present) drives which env to dump. If there's no `--env` flag yet, infer from `APP_ENV` / equivalent env var, or default to `dev` and document it.
- The flag short-circuits before any app initialization — no DB connections, no logging setup beyond the deprecation warning. Treat it as a pure read.

Checkpoint: `python -m app --env prod --dump-config | head -5` shows valid TOML starting with the first top-level key in prod's effective config.

### Step 6: Tests

[Last because earlier steps' checkpoints have already exercised most of this informally — now we lock it down.]

- `tests/test_config_loader.py`: TOML path, JSON fallback path (asserts `DeprecationWarning` via `pytest.warns`), both-present path (asserts TOML wins + info log), neither-present path (asserts `ConfigError`), unknown-env path.
- `tests/test_config_merge.py`: deep-merge unit tests (default-only, env-only, scalar override, nested dict merge, list replacement-not-merge).
- `tests/test_migrate_config.py`: synthesize three in-memory JSONs with known commonalities, run the migration in a `tmp_path`, parse the output, assert `[default]` contains the common keys and each `[<env>]` contains the right overrides. Also assert `--force` behavior.
- `tests/test_cli_dump.py`: invoke the CLI with `--dump-config` via `subprocess` or the CLI framework's test runner, assert stdout is valid TOML and round-trips back through the loader to the same dict.

Checkpoint: `pytest` is green. `pytest -k deprecation` shows the deprecation test passes specifically.

### Step 7: Run the migration on the real JSONs and commit

[The migration's output is part of this PR — it's the new source of truth.]

- Run `python scripts/migrate_config.py` (no `--force` since `settings.toml` doesn't exist yet).
- Review the printed summary. Eyeball `config/settings.toml` — does the default/override split match your mental model of what's truly shared?
- If a key was promoted to `[default]` that shouldn't have been (e.g., it happens to match across all three today but is semantically per-env), manually move it back into each `[<env>]` table. Note this in the commit body.
- Do NOT delete the JSONs in this PR — back-compat depends on them being readable. Their removal is the ROADMAP follow-up.
- Add a one-line note to `config/dev.json` etc. — wait, JSON has no comments. Skip. The deprecation warning on load is the user-facing signal; the ROADMAP entry is the maintainer-facing signal.

Checkpoint: `git diff --stat` shows the four added files and zero modifications to the JSONs. `python -m app --env prod --dump-config > /tmp/prod-toml.txt`, then temporarily rename `settings.toml`, re-run, diff the two outputs — they must be byte-identical modulo the deprecation warning on stderr.

### Step 8: Update docs

[Last because the doc has to describe what shipped, not what was planned.]

- Update `README.md` (or `docs/configuration.md` if it exists): new TOML schema, the `[default]` + `[<env>]` convention, the migration script invocation, the `--dump-config` flag, the one-release deprecation window for JSON.
- Add a ROADMAP entry: "config: drop JSON back-compat after one release" with the target release tag (next minor or next major — pick based on project's versioning convention).
- Don't add a CHANGELOG entry unless the project has a CHANGELOG. If it does, the entry goes under "Changed" (TOML is new) and "Deprecated" (JSON support).

Checkpoint: A fresh reader of the README can run `python scripts/migrate_config.py` and `python -m app --env dev --dump-config` without asking questions.

### Critical files (patterns repeat; representative paths only)

- `app/config.py` or `app/settings.py` — loader (rewritten). Confirm exact path in Step 1.
- `app/__main__.py` or `app/cli.py` — CLI entry, gains `--dump-config` flag.
- `config/settings.toml` — new, sole source of truth going forward.
- `config/{dev,staging,prod}.json` — kept as-is for back-compat; deletion deferred to follow-up PR.
- `scripts/migrate_config.py` — new, one-shot tool, not on the runtime path.
- `tests/test_config_*.py` — four new test modules.
- `pyproject.toml` / `requirements.txt` — `tomli` (if Py <3.11) + `tomli-w` added to runtime deps.
- `README.md` (or `docs/configuration.md`) — doc updates.
- `ROADMAP.md` (if it exists) — new follow-up entry.

### Reusable utilities (referenced, not reinvented)

- `tomllib` (stdlib, Py 3.11+) or `tomli` — TOML parsing.
- `tomli_w.dumps()` — TOML serialization for the migration script and `--dump-config`.
- `warnings.warn(..., DeprecationWarning, stacklevel=2)` — stdlib, standard mechanism. Pair with a module-level `_warned` set to avoid spam.
- `logging` — use the existing project logger, don't create a new one.
- `pytest.warns(DeprecationWarning)` — for the back-compat test.
- Project's existing CLI framework (argparse / click / typer) — don't introduce a new one for one flag.

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Three tiers: Tier 1 = 5-7 bullets, 60-second read, covers what ships / what moves / what's fixed / what changes for users / what's deferred / delivery target / done-when.
- Tier 2 = one section per major change (bullets describing shape + rationale), plus cross-cutting Scope (IN / OUT with pointers for OUT), counts anchoring scale, why-one-PR rationale.
- Tier 3 = numbered steps, each with one-sentence rationale + bulleted actions with file paths + Checkpoint line. Also Critical files (pattern-based, not exhaustive) and Reusable utilities (cite by path).
- Bullets only. No tables. No prose paragraphs > 3 sentences. Declarative voice ("X happens, then Y"). Honest about asymmetries.
- Default to solo dev, one PR, one commit. Multi-PR splits only if explicitly requested.
- Always include explicit IN / OUT lists. OUT items must point at where they're tracked.
- End with a Meta section so the format propagates.
