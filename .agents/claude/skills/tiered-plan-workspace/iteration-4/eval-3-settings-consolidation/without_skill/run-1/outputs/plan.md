# Plan: Consolidate per-environment JSON configs into a single TOML

**Scope:** Solo project. One PR, one release cycle of backwards-compat. Generic Python project.

---

## 1. Goal & non-goals

**Goal.** Replace `config/{dev,staging,prod}.json` with a single `config/settings.toml` that has one section per environment, plus a shared `[default]` section. Keep one release where the old JSONs still work (with a deprecation warning) so nothing breaks in the wild before the next tag.

**Non-goals.**
- Changing the *shape* of the settings (keys, types, semantics) — pure format/location migration.
- Introducing a new config library (e.g. Dynaconf, Hydra). Stick with stdlib + `tomllib`.
- Encrypting secrets, env-var overlay redesign, schema validation. Out of scope; can come later.
- Supporting both formats forever. The deprecation window is exactly one release.

---

## 2. Target shape

### File layout (after)

```
config/
  settings.toml          # new — single source of truth
  dev.json               # still readable for one release, warns
  staging.json           # ditto
  prod.json              # ditto
```

### `settings.toml` shape

```toml
[default]
# keys common to all environments live here; env sections override

[dev]
# dev-specific overrides

[staging]

[prod]
```

Resolution order at load time:
1. Start with `[default]`.
2. Deep-merge the requested environment section on top.
3. (Future: env-var overlay — out of scope.)

The merged dict is what the rest of the app sees. No code outside the loader should know about TOML, sections, or `[default]`.

---

## 3. Components to change

### 3.1 Settings loader (`<pkg>/config.py` or wherever `load_settings(env)` currently lives)

New behavior, in priority order:

1. If `config/settings.toml` exists → parse it, take `[default]`, deep-merge `[<env>]` on top, return.
2. Else if `config/<env>.json` exists → read it, **emit a deprecation warning** (`warnings.warn(..., DeprecationWarning)` + a `logger.warning(...)` so it shows up even when warnings are silenced), return its contents.
3. Else → raise the same error the loader raises today for a missing config.

The warning text should name the offending file and tell the user to run the migration command. Example:

> `config/dev.json is deprecated and will be removed in the next release. Run \`python -m <pkg>.config migrate\` to consolidate into config/settings.toml.`

Deep-merge semantics: dicts recurse, everything else (lists, scalars) replaces. Document this — it's the only behavior that's even slightly surprising.

### 3.2 Migration command

A one-shot CLI: `python -m <pkg>.config migrate`.

Behavior:
- Reads every `config/<env>.json` it finds.
- Computes the intersection of keys with identical values across all envs → those go in `[default]`.
- Each env section gets only the keys where its value differs from default (or is unique to it).
- Writes `config/settings.toml`. Refuses to overwrite if it already exists unless `--force` is passed.
- Does **not** delete the old JSONs. The user does that when they're confident.
- Prints a short summary: which keys promoted to `[default]`, which stayed env-specific.

Use `tomli_w` for writing (stdlib `tomllib` is read-only). Add it to dev deps only; runtime only needs `tomllib` (Python 3.11+) or `tomli` as a fallback on older Pythons.

### 3.3 Dump command (the new CLI flag)

`python -m <pkg>.config dump --env <env> [--format json|toml]`

- Runs the *real* loader (same code path the app uses), so what you see is what the app sees.
- Default `--format` is `json` (easier to pipe into `jq`, diff, etc.).
- Exits non-zero if loading fails. Useful for CI smoke checks.

If the app already has a top-level CLI (`<pkg>/__main__.py` or a `click`/`argparse` entry point), add `dump-config` as a subcommand there too — same implementation, just wired in.

### 3.4 Tests

- `test_loader_reads_toml`: TOML present, JSONs absent → returns merged dict.
- `test_loader_falls_back_to_json`: TOML absent, JSON present → returns JSON dict, emits `DeprecationWarning` (use `pytest.warns`).
- `test_loader_prefers_toml_over_json`: both present → TOML wins, no warning.
- `test_deep_merge`: nested dict in `[default]` + override in `[dev]` → merged correctly, sibling keys preserved.
- `test_migrate_produces_loadable_toml`: write fixture JSONs, run migrate, load resulting TOML, assert it equals the original dict per env.
- `test_migrate_factors_common_keys`: identical key across all envs ends up in `[default]`, not duplicated.
- `test_dump_matches_loader`: `dump --env dev` output parses back to the same dict the loader returns.

One golden-file test for the migration of a realistic fixture is worth more than five small ones.

### 3.5 Docs

- `README.md` (or `docs/configuration.md` if it exists): replace JSON examples with TOML, document the `[default]` + override model, document the dump CLI, note the one-release deprecation.
- `CHANGELOG.md`: entry under "Deprecated" for the JSONs, under "Added" for TOML + dump.
- Inline docstring on `load_settings` explaining merge order.

---

## 4. Migration / rollout

Solo, so this is sequencing not coordination:

1. **This release (N):** Land TOML loader + migration command + dump CLI + deprecation warning on JSON path. Run the migration locally, commit `config/settings.toml` alongside the existing JSONs. App now reads TOML; JSONs are dead code on disk but still wired up as fallback.
2. **Between N and N+1:** Use the app normally. If the deprecation warning ever fires, something pointed at an old JSON — investigate before N+1.
3. **Release N+1:** Delete the JSON fallback branch from the loader, delete the JSON files, delete the deprecation warning. Migration command can stay (cheap) or go (one fewer thing to maintain). Lean toward deleting.

---

## 5. Risks & how they're handled

- **Silent behavior change from deep-merge.** If anything in the current code path was relying on JSON-level *replacement* of a nested dict (i.e. the env JSON wholesale replaced a default), the new merge will preserve sibling keys it didn't before. **Mitigation:** the migration command produces TOML where each env section contains *exactly* the keys that env had before, so the merged result is bit-identical to the old JSON. Common keys only move to `[default]` if they're identical across *all* envs. Add the `test_migrate_produces_loadable_toml` test specifically to catch this.
- **Type drift JSON → TOML.** JSON has no datetime, TOML does; JSON allows `null`, TOML does not. **Mitigation:** the migration command should refuse and report if it encounters a `null` value, and tell the user to either set a real default or remove the key. Document this.
- **Forgetting to delete JSONs at N+1.** **Mitigation:** add a TODO with the target version next to the fallback branch, and a CHANGELOG entry now under "Planned for N+1".
- **`tomllib` not available.** Only an issue if the project supports Python < 3.11. **Mitigation:** check `pyproject.toml` / `setup.cfg` for `python_requires`. If < 3.11, add `tomli` as a runtime dep with the standard `try: import tomllib except ImportError: import tomli as tomllib` shim.

---

## 6. Order of work (suggested commits)

1. Add `tomllib`/`tomli` shim + `tomli_w` to dev deps. Empty `settings.toml` checked in.
2. Implement TOML loader path. Tests for it. (App still uses JSON path because TOML is empty.)
3. Implement migration command. Run it locally. Commit the populated `settings.toml`.
4. Wire deprecation warning into JSON fallback. Test it fires.
5. Implement `dump` CLI. Test it.
6. Docs + CHANGELOG.

Each step is independently revertable. Step 3 is the only one that changes runtime behavior in any user-visible way (and only if someone was depending on the JSON files being read — which after step 3 they aren't, by default).

---

## 7. Definition of done

- `config/settings.toml` exists, populated, app reads from it.
- Running with old JSONs present (and TOML absent) still works and warns.
- `python -m <pkg>.config migrate` reproduces the current TOML byte-for-byte from the JSONs (i.e. idempotent).
- `python -m <pkg>.config dump --env prod` prints the same dict the app would see at startup in prod.
- All tests in 3.4 pass.
- CHANGELOG has Deprecated + Added entries. README/docs updated.
- TODO marker placed at the JSON fallback branch naming the removal target.
