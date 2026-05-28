# Migration Plan: `src/utils/log.py` → `src/observability/log.py`

## Goals

1. Move the logging module from `src/utils/log.py` to `src/observability/log.py`.
2. Rename the misleading `Logger` class to `StructuredLogger` to reflect what it actually does.
3. Update all in-repo callers to the new import path and class name.
4. Provide backwards compatibility for **one release**:
   - The old import path `src/utils/log.py` must keep working.
   - The old `Logger` symbol must keep working.
   - Both must emit a `DeprecationWarning` so downstream users see a clear migration signal.
5. Remove the compatibility shim in the release **after** the deprecation release.

## Non-goals

- No behavior change to logging semantics (format, levels, sinks, handlers).
- No public API additions beyond the rename.
- No changes to test infrastructure beyond what is needed to validate the move.

---

## Constraints & guiding principles

- **Single source of truth** lives in `src/observability/log.py`. The old path becomes a thin re-export shim — no logic duplication.
- **One PR per release window** if possible. The deprecation shim ships in release **N**; the removal ships in release **N+1**.
- **Deprecation warning must fire on import**, not on first use — that's where the call site lives and where the fix is easiest.
- **Public surface stays identical** during the deprecation window. Any symbol importable from `src.utils.log` before the change must remain importable from there after the change.

---

## Step-by-step plan

### Step 1 — Inventory current state

Before touching anything, gather the full picture:

1. Read `src/utils/log.py` end-to-end. Note every public symbol (classes, functions, module-level constants, `__all__` if present).
2. Grep the repo for all callers:
   - `from src.utils.log import ...`
   - `from utils.log import ...` (if the project uses bare imports)
   - `import src.utils.log`
   - `src.utils.log.<symbol>` attribute access
   - References to the `Logger` class specifically (constructor calls, isinstance checks, type hints, subclasses).
3. Note any **test files** that import from `src/utils/log.py` — they may need both an update and a regression test added.
4. Note any **documentation** (`docs/`, README, docstrings elsewhere) that references the old path or the `Logger` name.
5. Check `pyproject.toml` / `setup.cfg` / `setup.py` for:
   - Package data or entry points referencing `utils.log`.
   - `mypy`, `ruff`, `pytest` config that may pin to the old path (e.g. `--cov=src.utils.log`).

Output of this step: a checklist of every file to touch.

---

### Step 2 — Create the new module

1. Create `src/observability/__init__.py` if the package doesn't already exist.
   - Re-export `StructuredLogger` (and any other intended public symbols) so `from src.observability import StructuredLogger` works.
2. Create `src/observability/log.py` with the **moved** code from `src/utils/log.py`.
3. In the new file, rename `class Logger` → `class StructuredLogger`. Update all internal self-references (docstrings, factory functions, `__repr__`, type hints inside the same file).
4. Update `__all__` in the new module to list `StructuredLogger` (and other public symbols), no longer `Logger`.

Do NOT delete the old file yet.

---

### Step 3 — Convert the old module into a deprecation shim

Replace the contents of `src/utils/log.py` with a small re-export shim. Sketch:

```python
"""Deprecated. Use ``src.observability.log`` instead.

This module is a temporary compatibility shim and will be removed
in the release after the current one.
"""
import warnings

from src.observability.log import (
    StructuredLogger,
    # ... re-export every other public symbol from the new module
)

warnings.warn(
    "src.utils.log is deprecated and will be removed in the next release. "
    "Import from src.observability.log instead. "
    "The 'Logger' class has been renamed to 'StructuredLogger'.",
    DeprecationWarning,
    stacklevel=2,
)

# Backwards-compatible alias for the renamed class.
Logger = StructuredLogger

__all__ = [
    "StructuredLogger",
    "Logger",
    # ... mirror the new module's __all__ plus the legacy "Logger"
]
```

Notes on this shim:

- **Use `DeprecationWarning`**, not `FutureWarning` or `UserWarning`. `DeprecationWarning` is the standard for "this will be removed".
- **`stacklevel=2`** so the warning points at the caller's import line, not the shim.
- The warning fires **once per import site** by Python's default warning filter — that's what we want.
- The `Logger = StructuredLogger` alias must be a true alias (same class object), so `isinstance(x, Logger)` keeps working for callers that haven't migrated.
- If the old module had `__version__`, module-level config, side-effects on import — preserve those in the shim, or move them to the new module and re-export.

---

### Step 4 — Update all in-repo callers

Now that the new module exists and the old path still works, migrate the repo itself off the deprecation shim. We do NOT want our own test suite producing deprecation warnings.

For each file from the Step 1 inventory:

1. Change `from src.utils.log import Logger` → `from src.observability.log import StructuredLogger`.
2. Change `from src.utils.log import X` → `from src.observability.log import X` for every other symbol.
3. Update any code that constructs `Logger(...)` → `StructuredLogger(...)`.
4. Update type hints: `def foo(log: Logger)` → `def foo(log: StructuredLogger)`.
5. Update docstrings that mention `Logger` or `src.utils.log`.

Do this in one sweep so the repo is internally consistent.

---

### Step 5 — Tests

1. **Keep existing logging tests passing** against the new path. Move/rename test files if their location mirrors the source tree (e.g. `tests/utils/test_log.py` → `tests/observability/test_log.py`).
2. **Add a new compatibility test** — this is the load-bearing test for the deprecation contract:

   ```python
   # tests/utils/test_log_deprecation.py
   import warnings
   import pytest

   def test_old_import_path_still_works_and_warns():
       with warnings.catch_warnings(record=True) as caught:
           warnings.simplefilter("always")
           from src.utils import log as legacy_log
           # Reload to guarantee the warning fires even if another
           # test already imported it.
           import importlib
           importlib.reload(legacy_log)

       assert any(
           issubclass(w.category, DeprecationWarning)
           and "src.observability.log" in str(w.message)
           for w in caught
       )

   def test_legacy_logger_alias_is_structured_logger():
       from src.utils.log import Logger
       from src.observability.log import StructuredLogger
       assert Logger is StructuredLogger
   ```

3. **Configure pytest** so deprecation warnings from our own code are errors going forward, but the legacy shim's warning is allow-listed (or asserted on as above). Otherwise the shim itself will start failing CI.
   - Option A: in `pyproject.toml`, add a `filterwarnings` entry that ignores `DeprecationWarning` originating from `src.utils.log`.
   - Option B: only escalate `DeprecationWarning` in CI for first-party modules, leaving the shim test to use `warnings.catch_warnings` locally.
   - Pick A if the project already has a global `-W error` policy; B otherwise.

---

### Step 6 — Documentation & changelog

1. Update any doc that references `src.utils.log` or `Logger`.
2. Add a `CHANGELOG.md` (or equivalent) entry under the next release:
   - **Deprecated**: `src.utils.log` module — use `src.observability.log` instead. Will be removed in the release after this one.
   - **Deprecated**: `Logger` class — renamed to `StructuredLogger`. The old name remains as an alias for one release.
   - **Added**: `src.observability.log` module containing `StructuredLogger` (formerly `Logger`).
3. If there is a migration guide / upgrade doc, add a one-paragraph sed-friendly mapping:
   - `from src.utils.log import Logger` → `from src.observability.log import StructuredLogger`

---

### Step 7 — Release N (the deprecation release)

Ship the state above. After this release:

- Downstream code importing `src.utils.log` keeps working but emits a `DeprecationWarning`.
- Downstream code using `Logger` keeps working but emits the same warning (because importing the symbol from the shim is what fires it).
- All first-party code is already on the new path.

---

### Step 8 — Release N+1 (the removal release)

In a separate PR, after release N has shipped:

1. Delete `src/utils/log.py` entirely.
2. Delete `tests/utils/test_log_deprecation.py`.
3. Remove the `filterwarnings` allow-list entry added in Step 5.
4. Remove the `Logger` alias references from docs.
5. CHANGELOG entry under release N+1: **Removed**: `src.utils.log` shim and `Logger` alias.
6. If `src/utils/__init__.py` re-exported anything from the old `log.py`, clean that up too.

---

## Risks & pitfalls

- **Warning suppression in downstream apps.** Python silences `DeprecationWarning` by default outside `__main__`. Many users will not see the warning unless they run with `-W default::DeprecationWarning` or use pytest. This is the standard tradeoff — accept it, but call it out in the changelog so users know to grep their code.
- **Circular imports.** If the new `src/observability/` package imports from anywhere that itself imports logging, ordering matters. Keep `src/observability/log.py` import-light (stdlib only, ideally) to avoid cycles.
- **Import-time side effects.** If the old `log.py` had module-level code (configuring root handlers, reading env vars, etc.), make sure the new module performs those side effects exactly once. The shim re-importing from the new module is fine — Python caches modules — but verify nothing relies on `src.utils.log` being the module that "owns" the side effect.
- **Pickled `Logger` instances.** If anything pickles loggers (uncommon but possible — e.g. multiprocessing), the class's `__module__` changes from `src.utils.log` to `src.observability.log`. Old pickles won't unpickle into the new class. If this matters, set `StructuredLogger.__module__ = "src.utils.log"` on the alias path — but only if pickling is actually in use.
- **`isinstance` checks in third-party code** that imported `Logger` from the old path will still work because `Logger is StructuredLogger`. Confirm this with the test in Step 5.
- **Stale references in CI config, Dockerfiles, lint rules.** The Step 1 inventory should catch these, but they're easy to miss because they aren't `.py` files.
- **Two deprecation warnings, one cause.** If a caller does `from src.utils.log import Logger`, they get one warning (the module import). If they then do `from src.utils.log import some_other_thing`, Python's import cache means the module body doesn't re-execute, so no second warning. Good. But if a caller does `import src.utils.log` and then `src.utils.log.Logger`, they get one warning at import time and silent attribute access after. That's correct behavior; no fix needed.

---

## Definition of done

- [ ] `src/observability/log.py` exists and contains the full implementation with `StructuredLogger`.
- [ ] `src/observability/__init__.py` re-exports the public surface.
- [ ] `src/utils/log.py` is a thin shim that re-exports from the new path, aliases `Logger = StructuredLogger`, and emits a `DeprecationWarning` on import.
- [ ] Every first-party caller imports from `src.observability.log` and uses `StructuredLogger`.
- [ ] A regression test asserts the shim still works and the warning fires.
- [ ] A test asserts `Logger is StructuredLogger`.
- [ ] Test suite runs clean — no `DeprecationWarning` from our own code, shim warning is allow-listed or explicitly asserted.
- [ ] CHANGELOG entry written for release N (deprecation).
- [ ] Removal PR drafted (or at minimum, a tracking issue filed) for release N+1.
