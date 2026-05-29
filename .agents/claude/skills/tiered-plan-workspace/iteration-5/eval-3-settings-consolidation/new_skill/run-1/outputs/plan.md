# Plan: Consolidate per-environment JSON config files into a single TOML

## 1. Objective

- Replace `config/{dev,staging,prod}.json` with a single `config/settings.toml` that has `[dev]`, `[staging]`, `[prod]` sections (plus a `[default]` section for shared keys).
- Cuts three files of drift-prone duplication down to one, and lets shared keys live in `[default]` instead of being copy-pasted across environments.
- Ship one release of backwards compatibility: if the old JSONs are present, read them, emit a `DeprecationWarning`, and continue. Next release removes the fallback.
- Add a CLI flag that dumps the fully-merged, environment-resolved config (so users can see what the loader actually produced after `[default]` + env overlay + any old-JSON fallback).

**Definition of Done**:
- `config/settings.toml` exists, contains `[default]` + one section per environment, and is the canonical source.
- `python -m <pkg> --dump-config --env <name>` prints the merged config for that environment to stdout as TOML, exits 0.
- Loading with only the TOML present works for all three environments and matches what the old JSONs produced (verified by a parity test).
- Loading with only the old JSONs present still works, emits exactly one `DeprecationWarning` per process pointing at `config/settings.toml` as the new path, and resolves to the same values.
- Loading with both present prefers the TOML and ignores the JSONs silently (no warning — TOML wins, JSON is dead weight on that machine).
- A migration script `scripts/migrate_config_to_toml.py` converts an existing `config/*.json` set to `config/settings.toml` and is idempotent.
- `CHANGELOG.md` (or equivalent) documents the deprecation with the removal-release target.
- All existing tests pass; new tests cover: TOML-only load, JSON-only load + warning, both-present precedence, migration round-trip, `--dump-config` output.

**Open questions**:
- Python version floor — `tomllib` is stdlib from 3.11. If the project supports 3.10 or earlier, we need `tomli` as a runtime dep for reading and `tomli-w` for writing/dumping. If 3.11+, only `tomli-w` is needed for the dump path. *Resolves with*: the project's `pyproject.toml` `requires-python`.
- Removal release — when does the JSON fallback get deleted? Default proposal: next minor release after this one. *Resolves with*: confirmation, or a specific version number to bake into the deprecation message.
- Are there any keys in the existing JSONs whose values are environment-identical? If yes, the migration script should hoist them into `[default]`. If no, every key stays under its env section. *Resolves with*: running the migration script in dry-run mode and inspecting output, or a quick `diff` of the three JSONs.

## 2. Approach

**Strategy: introduce a new TOML-first loader that overlays `[default]` with `[<env>]`; keep the old JSON loader as a fallback path guarded by file-presence checks, behind a one-shot `DeprecationWarning`.**

Why this shape:
- TOML-first means new installs never touch the JSON code path — the deprecation surface is small and removable in one diff next release.
- Overlay (`[default]` then env section) is the standard TOML config pattern and lets the migration script de-duplicate shared keys cleanly.

Technical mechanics:
- **TOML reading**: `tomllib.load(f, ...)` (stdlib, 3.11+) or `tomli.load` (3.10 and below). Wrap in a small `_read_toml(path)` helper so the import site is one place to change.
- **TOML writing** (for `--dump-config` and the migration script): `tomli_w.dump(...)`. Stdlib has no TOML writer, so `tomli-w` is required regardless of Python version.
- **Merge semantics**: `merged = {**toml_data.get("default", {}), **toml_data.get(env, {})}` — shallow merge. If existing configs have nested dicts that need deep merge, swap to a small recursive merge helper (note in implementer guide).
- **Deprecation warning**: `warnings.warn(msg, DeprecationWarning, stacklevel=2)` — `stacklevel=2` so the warning points at the caller's `load_config()` site, not at the loader internals. Gate with a module-level `_warned = False` flag so it fires once per process even if `load_config()` is called repeatedly.
- **Precedence**: check TOML first; if present, use it and return. Only fall through to JSON if TOML is absent. This means a half-migrated machine (TOML written, JSONs not yet deleted) does the right thing automatically.
- **CLI flag**: `--dump-config` (with optional `--env <name>`, defaulting to the same env-resolution logic the app uses normally — env var, then default). Emits merged TOML to stdout via `tomli_w.dumps`. Exits 0 on success, non-zero if the env doesn't exist in the file.
- **Migration script**: reads all three JSONs, computes the intersection of keys with identical values across all three (those become `[default]`), writes the rest under per-env sections. Idempotent: if `config/settings.toml` already exists, refuse to overwrite without `--force`.

**Scope IN**:
- New `config/settings.toml` and the loader changes to read it.
- `--dump-config` CLI flag.
- One-release JSON fallback with `DeprecationWarning`.
- `scripts/migrate_config_to_toml.py` migration script with dry-run + force flags.
- Tests covering the four load scenarios (TOML-only, JSON-only, both, neither → error).
- `CHANGELOG.md` deprecation note.

**Scope OUT**:
- Removing the JSON fallback code — out because this release is the deprecation release; deletion lands next release → tracked as a `TODO(remove-in-v<next>)` comment in the loader + a CHANGELOG entry.
- Schema validation of the TOML (pydantic / jsonschema) — out because the existing JSON loader doesn't validate either; adding it here conflates two changes → defer to a follow-up issue once the TOML format is stable.
- Secrets handling / env-var interpolation in TOML — out because no current key needs it and TOML supports literal strings fine; adding interpolation is a separate concern → follow-up if/when a secret-bearing key appears.
- Multi-file TOML composition (`settings.d/` directory) — out because one file covers the stated need; splitting is a separate refactor → defer until a real reason appears.
- Hot-reload / watch mode for config changes — out, no requirement → not tracked, mention in CHANGELOG only if asked.

**Delivery**: one PR, one commit on branch `feat/toml-config-consolidation`. Solo.

## 3. Per-change overview

### 3.1 `config/settings.toml` (new file, committed)

- Top-level `[default]` section with keys shared across all environments (whatever the migration script identifies).
- Three sections: `[dev]`, `[staging]`, `[prod]`, each with env-specific overrides.
- Header comment block stating "canonical config — JSON files in this directory are deprecated and will be removed in v<next>."

### 3.2 `src/<pkg>/config.py` (or wherever `load_config` lives — loader module)

- Add `_read_toml(path)` helper that conditionally imports `tomllib` (3.11+) or `tomli` (older).
- Rewrite `load_config(env: str)` to:
  - Try `config/settings.toml` first; if present, merge `[default]` + `[env]` and return.
  - Else look for `config/<env>.json`; if present, emit `DeprecationWarning` (once per process), load JSON, return.
  - Else raise the existing "config not found" error.
- Add module-level `_DEPRECATION_WARNED = False` flag.
- Tag the JSON code path with `# TODO(remove-in-v<next>): JSON fallback — see CHANGELOG`.

### 3.3 CLI entry point (`src/<pkg>/__main__.py` or `cli.py`)

- Add `--dump-config` flag (argparse / click / typer — match what's already there).
- When set: call `load_config(env)`, serialize result with `tomli_w.dumps`, write to stdout, exit 0.
- If `--env` is also passed, use it; else use the same env-resolution the app normally uses.

### 3.4 `scripts/migrate_config_to_toml.py` (new file)

- CLI: `python scripts/migrate_config_to_toml.py [--dry-run] [--force]`.
- Reads `config/{dev,staging,prod}.json`.
- Computes shared-key intersection: keys present in all three with identical values → `[default]`.
- Remaining keys → respective `[<env>]` sections.
- Writes `config/settings.toml` via `tomli_w.dump`. Refuses to overwrite unless `--force`.
- `--dry-run` prints the TOML to stdout instead of writing.

### 3.5 `tests/test_config.py` (extend existing or new)

- TOML-only present → loads correctly, no warning.
- JSON-only present → loads correctly, exactly one `DeprecationWarning` per process.
- Both present → TOML wins, no warning.
- Neither → existing error path still raises.
- Parity: a fixture TOML and a fixture JSON set with equivalent data produce equal merged dicts.
- Migration script: given a fixture JSON triple, produces an expected TOML; running again with `--force` is idempotent.
- `--dump-config` produces parseable TOML that round-trips back to the same merged dict.

### 3.6 `pyproject.toml`

- Add `tomli-w` to runtime deps.
- Add `tomli` to runtime deps only if `requires-python < 3.11` (see open question).

### 3.7 `CHANGELOG.md`

- Under next release: "Deprecated: per-environment `config/*.json` files. Use `config/settings.toml` instead. JSON fallback will be removed in v<next>. Run `scripts/migrate_config_to_toml.py` to migrate."

## 4. Implementer guide

### Step 1 — Branch and confirm Python floor

- `git checkout -b feat/toml-config-consolidation`.
- Check `pyproject.toml` for `requires-python`. Note whether `tomli` is needed alongside `tomli-w`.

Checkpoint: branch exists; you know whether to add one or two deps.

### Step 2 — Add dependencies

- Edit `pyproject.toml`. Add `tomli-w` always; add `tomli ; python_version < "3.11"` if floor is below 3.11.
- Reinstall the project locally (`pip install -e .` or `uv sync`).

Checkpoint: `python -c "import tomli_w"` succeeds; if on 3.10 or older, `python -c "import tomli"` also succeeds.

### Step 3 — Write the migration script first

Rationale: writing the migration script before touching the loader gives you a real `config/settings.toml` to test the new loader against, instead of hand-crafting a fixture.

```python
# scripts/migrate_config_to_toml.py
"""Migrate config/{dev,staging,prod}.json to config/settings.toml."""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

import tomli_w

CONFIG_DIR = Path("config")
ENVS = ("dev", "staging", "prod")
OUT = CONFIG_DIR / "settings.toml"


def load_json_envs() -> dict[str, dict]:
    out = {}
    for env in ENVS:
        p = CONFIG_DIR / f"{env}.json"
        if not p.exists():
            sys.exit(f"missing {p}")
        out[env] = json.loads(p.read_text())
    return out


def split_default_and_overrides(envs: dict[str, dict]) -> dict[str, dict]:
    """Hoist keys whose value is identical across all envs into [default]."""
    if not envs:
        return {}
    all_keys = set().union(*(d.keys() for d in envs.values()))
    default: dict = {}
    for k in all_keys:
        values = [d.get(k, ...) for d in envs.values()]
        if all(v == values[0] and v is not ... for v in values):
            default[k] = values[0]
    result: dict[str, dict] = {"default": default} if default else {}
    for env, data in envs.items():
        result[env] = {k: v for k, v in data.items() if k not in default}
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    merged = split_default_and_overrides(load_json_envs())

    if args.dry_run:
        sys.stdout.write(tomli_w.dumps(merged))
        return 0

    if OUT.exists() and not args.force:
        sys.exit(f"{OUT} exists; pass --force to overwrite")

    OUT.write_bytes(tomli_w.dumps(merged).encode("utf-8"))
    print(f"wrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- Run `python scripts/migrate_config_to_toml.py --dry-run` and eyeball the output.
- Run for real: `python scripts/migrate_config_to_toml.py`.
- Open `config/settings.toml`, add the deprecation header comment manually:

```toml
# Canonical configuration.
# The per-environment JSON files in this directory are deprecated and will be
# removed in v<next>. Use this file instead.
```

Checkpoint: `config/settings.toml` exists with `[default]` (if applicable) + `[dev]` + `[staging]` + `[prod]`. The dry-run output matches the file content.

### Step 4 — Rewrite the loader

Locate the existing `load_config` (likely `src/<pkg>/config.py`). Replace with:

```python
# src/<pkg>/config.py
from __future__ import annotations
import json
import sys
import warnings
from pathlib import Path
from typing import Any

if sys.version_info >= (3, 11):
    import tomllib  # stdlib
else:
    import tomli as tomllib  # type: ignore[no-redef]

CONFIG_DIR = Path("config")
TOML_PATH = CONFIG_DIR / "settings.toml"

_DEPRECATION_WARNED = False


def _read_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as f:
        return tomllib.load(f)


def load_config(env: str) -> dict[str, Any]:
    if TOML_PATH.exists():
        data = _read_toml(TOML_PATH)
        if env not in data and "default" not in data:
            raise KeyError(f"env {env!r} not found in {TOML_PATH}")
        return {**data.get("default", {}), **data.get(env, {})}

    # TODO(remove-in-v<next>): JSON fallback. See CHANGELOG.
    json_path = CONFIG_DIR / f"{env}.json"
    if json_path.exists():
        global _DEPRECATION_WARNED
        if not _DEPRECATION_WARNED:
            warnings.warn(
                f"Loading config from {json_path} is deprecated; "
                f"migrate to {TOML_PATH} (see scripts/migrate_config_to_toml.py). "
                f"JSON support will be removed in v<next>.",
                DeprecationWarning,
                stacklevel=2,
            )
            _DEPRECATION_WARNED = True
        return json.loads(json_path.read_text())

    raise FileNotFoundError(
        f"no config found: tried {TOML_PATH} and {json_path}"
    )
```

- Replace `<pkg>` and `<next>` with concrete values.
- If the existing loader returns a different shape (e.g. a dataclass), wrap the dict in whatever the rest of the app expects — don't change the return type as part of this PR.

Checkpoint: `python -c "from <pkg>.config import load_config; print(load_config('dev'))"` prints the merged dev config.

### Step 5 — Add `--dump-config` to the CLI

Find the existing CLI entry point. Add the flag using whichever framework is already in use. argparse example:

```python
parser.add_argument(
    "--dump-config",
    action="store_true",
    help="print the merged config for the resolved environment and exit",
)
parser.add_argument("--env", default=None, help="environment name override")
```

Then early in `main()`:

```python
if args.dump_config:
    import tomli_w
    env = args.env or resolve_env_normally()
    sys.stdout.write(tomli_w.dumps(load_config(env)))
    return 0
```

Checkpoint: `python -m <pkg> --dump-config --env dev` prints valid TOML that parses back to the same dict.

### Step 6 — Tests

Add to `tests/test_config.py`. Use `tmp_path` + `monkeypatch.chdir(tmp_path)` so each test gets an isolated `config/` directory.

```python
import json
import warnings
import tomli_w
from <pkg>.config import load_config

def _write(p, payload):
    p.parent.mkdir(parents=True, exist_ok=True)
    if p.suffix == ".json":
        p.write_text(json.dumps(payload))
    else:
        p.write_bytes(tomli_w.dumps(payload).encode())

def test_toml_only(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path / "config/settings.toml",
           {"default": {"a": 1}, "dev": {"b": 2}})
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        assert load_config("dev") == {"a": 1, "b": 2}
        assert not any(issubclass(x.category, DeprecationWarning) for x in w)

def test_json_only_warns(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path / "config/dev.json", {"a": 1, "b": 2})
    # reset module-level flag
    import <pkg>.config as cfg
    cfg._DEPRECATION_WARNED = False
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        assert load_config("dev") == {"a": 1, "b": 2}
        depr = [x for x in w if issubclass(x.category, DeprecationWarning)]
        assert len(depr) == 1

def test_toml_wins_over_json(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    _write(tmp_path / "config/settings.toml", {"dev": {"k": "toml"}})
    _write(tmp_path / "config/dev.json", {"k": "json"})
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        assert load_config("dev") == {"k": "toml"}
        assert not any(issubclass(x.category, DeprecationWarning) for x in w)

def test_neither_raises(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "config").mkdir()
    try:
        load_config("dev")
    except FileNotFoundError:
        pass
    else:
        raise AssertionError("expected FileNotFoundError")
```

Add a migration-script test that runs it against a fixture JSON triple and asserts the resulting TOML matches an expected dict (load it back with `tomllib` and compare).

Checkpoint: `pytest` passes. Existing tests still green.

### Step 7 — CHANGELOG and finalize

- Add a CHANGELOG entry under the upcoming release:
  ```
  ### Deprecated
  - `config/{dev,staging,prod}.json` — migrate to `config/settings.toml`.
    Run `python scripts/migrate_config_to_toml.py`. JSON support will be
    removed in v<next>.

  ### Added
  - `config/settings.toml` as the canonical config format.
  - `--dump-config` CLI flag to print the merged config.
  - `scripts/migrate_config_to_toml.py` migration helper.
  ```
- Commit:
  ```
  git add config/settings.toml scripts/migrate_config_to_toml.py \
          src/<pkg>/config.py src/<pkg>/__main__.py \
          tests/test_config.py pyproject.toml CHANGELOG.md
  git commit -m "feat(config): consolidate per-env JSONs into settings.toml"
  ```
- Delete the old JSONs? **No** — leave them in this release so users running off the deprecation path still have a working fallback. They get deleted in the next release alongside the JSON code path. Add a note in CHANGELOG saying "the JSON files remain in this release for fallback; delete them locally once you've verified `settings.toml` works."

Checkpoint: branch has one commit. `pytest` green. Manual `python -m <pkg> --dump-config --env prod` produces sensible output. Open PR.
