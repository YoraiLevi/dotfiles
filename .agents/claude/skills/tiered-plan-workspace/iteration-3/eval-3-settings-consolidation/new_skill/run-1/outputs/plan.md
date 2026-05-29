# Plan — Consolidate per-environment JSON settings into a single TOML

## Goal & worthwhileness

### Problem

- Settings live in N parallel files under `config/` (`dev.json`, `staging.json`, `prod.json`), one per environment.
- Shared values are duplicated across files, so a change to a shared key requires N edits and drift is invisible.
- There is no single place to read "what does the merged config for env X look like?" — debugging requires mentally overlaying files.
- JSON has no comments, so the rationale for individual settings has nowhere to live next to the value.

### Why now

- Adding a new environment (or a new shared key) currently means a multi-file edit with no enforcement that the files stay aligned.
- A consolidated TOML with `[default]` + `[dev]` / `[staging]` / `[prod]` sections lets shared values live once and per-env overrides live next to the value they override.
- This is cheaper to do now (3 files, no external consumers) than after the file count grows or other repos start reading these.

### Success criteria

- A single `config/settings.toml` is the source of truth for all environments.
- The loader, given an environment name, returns the same Python dict it returned before the change (modulo deprecation logging).
- If the old per-env JSON files are present, the loader still works and emits a one-time deprecation warning per process.
- A `--dump-config` CLI flag prints the fully-merged config for a given env to stdout in a stable format.
- All existing call sites that ask the loader for a setting keep working with no code changes at the call site.

### Risk surface

- Silent semantic drift: TOML's type model differs from JSON in small ways (e.g., no `null`, datetimes are first-class). Any key that relied on `null` or on JSON's number-vs-string ambiguity needs an explicit decision.
- Merge semantics: `[default]` + `[<env>]` overlay needs a defined rule (shallow vs deep merge). Picking the wrong one silently changes effective config.
- Backwards-compat trap: if both the TOML and the legacy JSONs exist, which wins? Need an explicit precedence rule, not an accident of file-system iteration order.
- One-release window: if the deprecation warning is too quiet, the JSONs never get deleted and the "one release" promise slips.

## Approach

- **Strategy**:
  - Introduce `config/settings.toml` with a `[default]` table plus one table per environment (`[dev]`, `[staging]`, `[prod]`).
  - Rewrite the loader to read TOML first; fall back to the legacy JSONs only if the TOML is missing.
  - Ship a migration script that reads the existing JSONs and writes the consolidated TOML, factoring shared values into `[default]`.
  - Add a `--dump-config <env>` CLI flag that prints the merged config the loader would return for that env.

- **Why this approach**:
  - Single source of truth eliminates duplication without forcing a one-shot cutover — the fallback path keeps the old files working for one release.
  - Deep-merging `[default]` under `[<env>]` is the mental model users already have ("env overrides default"), so it matches how the JSONs are used today.
  - A migration script (vs hand-editing) makes the rewrite reproducible and reviewable as a diff.

- **Why not [alternative — keep JSON, just add a `default.json`]**:
  - Solves the duplication problem but not the "no comments, no merged view, no schema" problems.
  - Still N+1 files for N environments. The whole point is consolidation.

- **Why not [alternative — YAML]**:
  - TOML has stricter syntax (less footgun surface around indentation and implicit typing) and is already the Python ecosystem default (`pyproject.toml`).
  - `tomllib` is in the stdlib for Python 3.11+; no new runtime dep for reads.

- **Scope IN**:
  - New `config/settings.toml` with `[default]` + per-env tables.
  - Loader rewrite with TOML-primary, JSON-fallback behavior.
  - One-shot migration script (`scripts/migrate_settings_to_toml.py`) committed alongside the change.
  - Deprecation warning when the JSON fallback path fires.
  - `--dump-config <env>` CLI flag on the project's existing CLI entry point.
  - README / `docs/configuration.md` updated to describe the new layout and the deprecation window.

- **Scope OUT**:
  - Deleting the legacy JSONs — explicitly deferred to the next release; tracked as a follow-up note at the bottom of `docs/configuration.md` and a TODO in the loader at the fallback branch.
  - Schema validation (e.g., pydantic models for settings) — out of scope, tracked in ROADMAP as "typed settings".
  - Secret handling / env-var interpolation — out of scope, current behavior preserved as-is.
  - Writing TOML programmatically at runtime — not needed; the migration script is the only writer and it can use `tomli-w` as a dev-only dep.

- **Delivery**: one PR, one commit on `chore/settings-toml`. Solo.

- **Done when**:
  - `python -m <project> --dump-config dev` prints the same merged dict (key-for-key) as the old loader did for dev.
  - Deleting `config/settings.toml` and re-running the same command still works, prints the same dict, and emits exactly one `DeprecationWarning` mentioning the legacy JSON path.
  - `pytest` passes.

## Per-change overview

### Change 1: New `config/settings.toml`

- Top-level layout:
  - `[default]` — every key that has the same value in all three JSONs today.
  - `[dev]` / `[staging]` / `[prod]` — only the keys that differ from `[default]` for that env.
- Comments next to non-obvious values (the migration script preserves nothing here; comments are added by hand on a follow-up pass if/when worth it — out of scope for this PR).
- **Why this matters for the goal**: this is the single source of truth that makes the duplication problem go away. Everything else in the plan exists to read this file or to migrate to it.

### Change 2: Loader rewrite

- New module-level function `load_settings(env: str) -> dict`:
  - If `config/settings.toml` exists, parse it with `tomllib`, deep-merge `[default]` under `[<env>]`, return.
  - Else, look for `config/<env>.json`; if present, parse it, log one `DeprecationWarning`, return.
  - Else, raise `FileNotFoundError` with both paths in the message.
- Precedence is fixed: TOML wins if both exist. The deprecation warning fires only on the fallback branch, so a present-but-stale JSON is silently ignored once TOML is in place — that's intentional, because the next release deletes the JSONs anyway.
- **Why this matters for the goal**: this is the contract every caller already depends on. Keeping the function's signature stable is what makes the migration invisible to call sites.

### Change 3: Migration script

- `scripts/migrate_settings_to_toml.py`:
  - Reads `config/dev.json`, `config/staging.json`, `config/prod.json`.
  - Computes the intersection of keys with equal values across all three → goes into `[default]`.
  - Per-env diffs → go into `[dev]` / `[staging]` / `[prod]`.
  - Writes `config/settings.toml` with `tomli-w`.
- Idempotent: re-running overwrites the TOML deterministically (keys sorted) so the diff is reviewable.
- **Why this matters for the goal**: the consolidation is mechanical, and a script makes it auditable. The migration's correctness is checkable by diffing the loader's output before and after.

### Change 4: `--dump-config` CLI flag

- Add `--dump-config <env>` to the existing CLI entry point.
- Action: call `load_settings(env)`, pretty-print the resulting dict (JSON with `indent=2`, sorted keys) to stdout, exit 0.
- **Why this matters for the goal**: gives users (and the verification step in this plan) a single command that shows exactly what the loader produced. Replaces the mental-overlay debugging step.

### Change 5: Docs

- Update `docs/configuration.md` (or create it if absent — generic Python project, may not exist yet):
  - New layout description with a minimal `settings.toml` example.
  - Deprecation note: "the per-env JSONs are read with a warning for this release; remove them after upgrading."
  - `--dump-config` usage.
- **Why this matters for the goal**: a future reader landing in `config/` needs to know why there's a TOML file and what happens to the JSONs. Without this, the deprecation period is invisible.

## Implementation

### Step 1: Write `config/settings.toml` by hand from the existing JSONs

This step lands first because the loader rewrite has nothing to read until the TOML exists, and writing it by hand once (rather than running the migration script first) lets the migration script's correctness be checked against a known-good file.

- Open all three JSONs side-by-side.
- For each key, decide:
  - Same value in all three → goes into `[default]`.
  - Differs in any env → goes into the env-specific table for the env(s) where it differs from default.
- Save to `config/settings.toml`.
- This is throwaway-ish: Step 3 will regenerate it via the script. We do it by hand first because that produces the oracle to compare the script's output against, because trusting the script's output without a sanity check is how silent migration bugs ship.

Checkpoint: `python -c "import tomllib; tomllib.loads(open('config/settings.toml').read())"` exits 0.

### Step 2: Rewrite the loader

This step lands before the migration script because the script and the CLI flag both call `load_settings`, so we need the new signature in place first.

- Locate the existing loader (likely `<project>/config.py` or `<project>/settings.py` — grep for the JSON file names).
- Replace the body of `load_settings(env)` with:
  - Try `config/settings.toml`; if found, parse with `tomllib`, deep-merge `[default]` under `[<env>]`, return.
  - Else try `config/<env>.json`; if found, emit `warnings.warn(..., DeprecationWarning, stacklevel=2)` once per process, parse, return.
  - Else raise `FileNotFoundError` listing both attempted paths.
- Use `stacklevel=2` on the warning, because we want the warning to point at the caller's `load_settings(...)` line, not at the loader's internal `warnings.warn` line.
- Guard the once-per-process behavior with a module-level `_warned: set[str] = set()` keyed by env, because Python's default warning filter dedupes by (message, category, module, lineno) and we want dedup by env, not by call site.
- Deep-merge helper: a small recursive function that, for dict-valued keys, recurses; for everything else, the env value wins. Tested implicitly by the dump-config checkpoint below.

Checkpoint: in a REPL, `from <project>.settings import load_settings; load_settings('dev')` returns a dict. Delete the TOML, re-run, observe one `DeprecationWarning` and the same dict.

### Step 3: Write and run the migration script

This step lands after the loader because we want to verify the script's output against the hand-written TOML from Step 1 using the loader's own merge logic — i.e., the script is correct iff loading the script-generated TOML produces the same dict as loading the JSONs did.

- Create `scripts/migrate_settings_to_toml.py`:
  - Load all three JSONs.
  - Compute `default = {k: v for k in shared_keys if v_dev == v_staging == v_prod}`.
  - Compute per-env tables as `{k: v for k, v in env.items() if (k, v) not in default.items()}`.
  - Write with `tomli_w.dump(...)` to a temp path, then atomic-rename to `config/settings.toml`, because a half-written TOML during a crash would brick the loader on next run.
- Add `tomli-w` to dev-only deps (`pyproject.toml` `[project.optional-dependencies].dev` or equivalent), because production reads use stdlib `tomllib`; only the migration writes.
- Run the script: `python scripts/migrate_settings_to_toml.py`.
- Diff the regenerated `config/settings.toml` against the hand-written one from Step 1. Differences should be cosmetic (key order, whitespace). Any semantic difference is a script bug — fix and re-run.

Checkpoint: `diff <(python -m <project> --dump-config dev) <(python -m <project> --dump-config dev)` (run before and after regenerating the TOML) is empty. More important: for each env, the merged dict equals what the JSON-only loader returned pre-change. Capture that via a one-off script: load each `<env>.json` directly, compare to `load_settings(env)`, assert equal.

### Step 4: Add `--dump-config` to the CLI

This step lands after the loader so the flag has something to call, and after the migration script so the dumped output reflects the consolidated TOML rather than the legacy JSONs.

- Locate the CLI entry point (likely `<project>/__main__.py`, `<project>/cli.py`, or a `click`/`argparse`/`typer` definition — grep for `add_argument` / `@click.command` / `app = typer.Typer`).
- Add `--dump-config ENV` as a top-level flag (not a subcommand), because it's a diagnostic that should work regardless of which subcommand the project otherwise dispatches to.
- Handler:
  - Call `load_settings(env)`.
  - `print(json.dumps(merged, indent=2, sort_keys=True, default=str))`, with `default=str` because TOML datetimes are first-class and `json.dumps` would otherwise crash on them.
  - Exit 0 immediately, without running the rest of the CLI's normal flow, because the user asked for a dump and nothing else.

Checkpoint: `python -m <project> --dump-config dev | python -c "import json,sys; json.load(sys.stdin)"` exits 0 for each of dev, staging, prod.

### Step 5: Update docs

This step lands last because the doc references the final shape of the file and the final CLI command, both settled by Steps 1–4.

- Edit (or create) `docs/configuration.md`:
  - New layout: brief description of `[default]` + `[<env>]` and the deep-merge rule.
  - Minimal example (~10 lines of TOML showing a default and one env override).
  - Deprecation notice: "Per-env JSONs under `config/` are read with a `DeprecationWarning` for this release and will be removed in the next. Run `scripts/migrate_settings_to_toml.py` to generate the TOML, then delete the JSONs."
  - `--dump-config` usage example with expected output shape.
- Add a TODO comment at the JSON-fallback branch in the loader: `# TODO(<next-release-tag>): remove JSON fallback`, because the deprecation window only closes if there's a forcing function in the code itself, not just in docs.

Checkpoint: `grep -n "dump-config\|settings.toml\|DeprecationWarning" docs/configuration.md` returns matches for all three.

### Step 6: Final end-to-end verification

This step lands last because it exercises the whole new path top-to-bottom and is the gate before commit.

- With `config/settings.toml` present and the JSONs still present:
  - `python -m <project> --dump-config dev` → expected merged dict, no warning (TOML wins).
- Move the JSONs aside: `mkdir /tmp/old-json && mv config/*.json /tmp/old-json/`.
  - `python -m <project> --dump-config dev` → same merged dict, no warning (TOML still wins, JSONs absent).
- Move the TOML aside and restore the JSONs:
  - `python -m <project> --dump-config dev` → same merged dict, exactly one `DeprecationWarning` on stderr.
- Restore the TOML; leave the JSONs in place (final repo state for this PR).
- `pytest` passes.

Checkpoint: all three dumps above produce byte-identical stdout (since we sorted keys and pretty-printed). The deprecation warning appears exactly once on the fallback path and nowhere else.

### Critical files

- `config/settings.toml` — new source of truth.
- `config/{dev,staging,prod}.json` — kept this release, deleted next.
- `<project>/settings.py` (or wherever `load_settings` lives) — loader rewrite + deprecation warning + JSON-fallback TODO.
- `<project>/__main__.py` or `<project>/cli.py` — `--dump-config` flag.
- `scripts/migrate_settings_to_toml.py` — one-shot migrator, committed for auditability.
- `docs/configuration.md` — new/updated docs.
- `pyproject.toml` — `tomli-w` added under dev deps.

### Reusable utilities

- `tomllib` (stdlib, Python 3.11+) — reads.
- `tomli-w` (dev-only) — writes, used by migration script only.
- `warnings.warn(..., DeprecationWarning, stacklevel=2)` — standard deprecation idiom.
- `json.dumps(..., indent=2, sort_keys=True, default=str)` — stable diff-friendly dump for `--dump-config`.

### Hygiene constraints

- One commit. Commit message names the goal ("consolidate per-env JSON settings into single TOML") and notes the one-release deprecation window.
- Do not delete the legacy JSONs in this PR — that's the next release's job and the whole point of the fallback.
- No AI co-author attribution in the commit.
- The migration script is committed (not run-and-discarded), because the next release's "delete the JSONs" PR will reference it in its commit message as the reproducer.
