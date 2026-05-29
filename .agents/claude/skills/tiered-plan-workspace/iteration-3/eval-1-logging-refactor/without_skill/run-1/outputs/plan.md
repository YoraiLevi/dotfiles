# Plan: Move `log` module to `src/observability/` and rename `Logger` → `StructuredLogger`

## 1. Objective

Two coupled changes shipped as one PR:

1. **Relocate** `src/utils/log.py` → `src/observability/log.py`.
2. **Rename** the misleading `Logger` class → `StructuredLogger` (reflects what it actually does).

Both changes preserve the old import path **and** the old class name for **one release** behind a `DeprecationWarning`. After that release, the shim is removed.

Non-goals:
- No behavior change to logging output, formatting, or sinks.
- No new features on `StructuredLogger`.
- No refactor of call sites beyond the import/name update.

---

## 2. Approach

**Strategy: keep the implementation in the new location; make the old location a thin re-export shim that warns on import.**

Why this shape:

- A shim at the *old* location is the standard Python deprecation pattern — minimal code, no duplicate implementation, easy to delete in the next release.
- Renaming `Logger` → `StructuredLogger` is done in-place at the new module; the old name becomes a module-level alias that emits a warning on *access* (via `__getattr__`), so existing `from utils.log import Logger` keeps working.
- Single PR, single commit is appropriate: the two changes touch the same file set and removing them independently would leave a half-migrated state.

Alternatives considered and rejected:
- *Two PRs (move first, rename second).* Doubles the churn at every call site and creates a window where the new module name suggests "structured logging" while the class is still called `Logger`.
- *Forward the old module as an `import *` and keep `Logger` as the canonical name.* Defers the rename indefinitely; the whole point of this PR is to fix the name.
- *Hard break, no shim.* User explicitly asked for one-release back-compat.

Deprecation mechanics:
- Old path `src/utils/log.py` emits `DeprecationWarning` at **import time** via `warnings.warn(..., stacklevel=2)`.
- Old class name `Logger` (when accessed from either path) emits `DeprecationWarning` via module-level `__getattr__` (PEP 562). Using `__getattr__` rather than a top-level alias means *unused* access doesn't warn — only code that actually touches `Logger` triggers the warning, which is the signal we want.
- Both warnings carry a clear message: what's deprecated, what to use instead, and the version it will be removed in.

Removal plan: a `TODO(remove-in-vX.Y)` comment on the shim file and on the `__getattr__` block, plus a tracking note in `CHANGELOG.md`.

---

## 3. Per-change overview

### 3.1 Create `src/observability/__init__.py`
New empty package marker (or a minimal one that re-exports `StructuredLogger` for convenience: `from .log import StructuredLogger`).

### 3.2 Create `src/observability/log.py`
This is the new home of the implementation. It is the *moved* file with one in-file rename:
- Class `Logger` → `StructuredLogger`.
- Add a module-level `__getattr__` that resolves the old name `Logger` to `StructuredLogger` and emits `DeprecationWarning`.
- Update the module docstring to reflect the new location and the rename.
- `__all__` lists `StructuredLogger` only.

### 3.3 Replace `src/utils/log.py` with a deprecation shim
The file at the old path becomes a thin shim:
- Emits `DeprecationWarning` at import time.
- Re-exports every public symbol from `src.observability.log` so existing call sites continue to work unchanged.
- Forwards `Logger` access via its own `__getattr__` (so `from utils.log import Logger` still resolves and warns).
- File contains a `TODO(remove-in-vX.Y)` marker.

### 3.4 Update all internal call sites
- Change imports: `from src.utils.log import Logger` → `from src.observability.log import StructuredLogger`.
- Change constructor calls: `Logger(...)` → `StructuredLogger(...)`.
- Update any type hints, isinstance checks, or string references.
- Internal code must not rely on the shim — only external/downstream users do.

### 3.5 Tests
- Move existing tests for `log.py` from `tests/utils/test_log.py` → `tests/observability/test_log.py`. Update imports and class names inside.
- Add a new test file `tests/observability/test_log_deprecation.py` that asserts:
  - Importing `src.utils.log` emits exactly one `DeprecationWarning`.
  - Accessing `src.utils.log.Logger` emits a `DeprecationWarning`.
  - Accessing `src.observability.log.Logger` emits a `DeprecationWarning`.
  - `Logger is StructuredLogger` (same object) so existing `isinstance` checks keep passing.
  - The shim re-exports all symbols that `src.observability.log.__all__` declares.

### 3.6 Docs and changelog
- `CHANGELOG.md`: under the upcoming release, note (a) the move, (b) the rename, (c) the deprecation, (d) the version when the shim will be removed.
- If there is a `docs/` reference to `utils.log.Logger`, update it to the new path/name and add a short "Deprecation" callout.
- If there's a public API reference page, regenerate or hand-edit it.

### 3.7 Lint/CI
- Ensure `pyproject.toml` / `setup.cfg` package discovery still finds `src/observability/` (usually automatic with `find:` or `setuptools.find_packages`, but worth a glance).
- If the project filters `DeprecationWarning` to errors in tests (`-W error::DeprecationWarning`), the deprecation tests must use `pytest.warns(DeprecationWarning)` to consume the warning rather than letting it bubble.

---

## 4. Implementer guide

### Step 0 — Branch and baseline
- Branch off `main`: `git checkout -b refactor/move-log-to-observability`.
- Run the full test suite first; record any pre-existing failures so they aren't blamed on this PR.

### Step 1 — Create the new module
1. `mkdir src/observability` and add `src/observability/__init__.py`:
   ```python
   from .log import StructuredLogger

   __all__ = ["StructuredLogger"]
   ```
2. `git mv src/utils/log.py src/observability/log.py` (use `git mv` so history follows the file).
3. In `src/observability/log.py`:
   - Rename the class: `class Logger:` → `class StructuredLogger:`.
   - Update all internal self-references (e.g., `cls`, factory methods, repr strings) to `StructuredLogger`.
   - Update the module docstring.
   - Set `__all__ = ["StructuredLogger", ...other public symbols]`.
   - Add at the bottom of the module:
     ```python
     def __getattr__(name):
         if name == "Logger":
             import warnings
             warnings.warn(
                 "Logger is deprecated and will be removed in vX.Y. "
                 "Use StructuredLogger instead.",
                 DeprecationWarning,
                 stacklevel=2,
             )
             return StructuredLogger
         raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
     ```

### Step 2 — Recreate the old path as a shim
Create a new `src/utils/log.py` (the old file was `git mv`-ed away in step 1, so this is a fresh file at the old path):

```python
# TODO(remove-in-vX.Y): delete this shim along with the Logger alias
# in src/observability/log.py.
"""Deprecated shim. Import from src.observability.log instead."""
import warnings

warnings.warn(
    "src.utils.log is deprecated and will be removed in vX.Y. "
    "Import from src.observability.log instead.",
    DeprecationWarning,
    stacklevel=2,
)

from src.observability.log import *  # noqa: F401,F403
from src.observability.log import __all__  # re-export the public surface

def __getattr__(name):
    if name == "Logger":
        warnings.warn(
            "Logger is deprecated and will be removed in vX.Y. "
            "Use StructuredLogger from src.observability.log instead.",
            DeprecationWarning,
            stacklevel=2,
        )
        from src.observability.log import StructuredLogger
        return StructuredLogger
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

Note: the `from ... import *` covers normal public symbols; `__getattr__` covers the renamed `Logger`. The module-level `warnings.warn` fires once per process per import (because Python caches modules in `sys.modules`).

### Step 3 — Update internal call sites
1. Find them all:
   ```
   # find imports of the old module
   rg -n "from src\.utils\.log|import src\.utils\.log|from utils\.log|import utils\.log" src/ tests/
   # find references to the old class name
   rg -n "\bLogger\b" src/ tests/
   ```
   (Be careful with the second one — the standard library has `logging.Logger`. Inspect each hit; do not blanket-replace.)
2. For each internal hit:
   - Rewrite the import: `from src.observability.log import StructuredLogger`.
   - Rewrite the usage: `Logger(...)` → `StructuredLogger(...)`, including type hints (`: Logger` → `: StructuredLogger`) and any `isinstance(x, Logger)`.
3. Internal code (everything under `src/`) must not import from `src.utils.log` after this step — only external consumers should hit the shim.

### Step 4 — Update tests
1. `git mv tests/utils/test_log.py tests/observability/test_log.py` (create `tests/observability/__init__.py` if the project uses init files in tests).
2. Inside the moved test file, update imports and class names the same way as in step 3.
3. Add `tests/observability/test_log_deprecation.py`:
   ```python
   import importlib
   import sys
   import warnings
   import pytest

   def test_old_module_path_warns():
       sys.modules.pop("src.utils.log", None)
       with pytest.warns(DeprecationWarning, match="src.utils.log is deprecated"):
           importlib.import_module("src.utils.log")

   def test_old_class_name_warns_from_old_path():
       import src.utils.log as old
       with pytest.warns(DeprecationWarning, match="Logger is deprecated"):
           _ = old.Logger

   def test_old_class_name_warns_from_new_path():
       import src.observability.log as new
       with pytest.warns(DeprecationWarning, match="Logger is deprecated"):
           _ = new.Logger

   def test_old_class_name_is_structured_logger():
       import src.observability.log as new
       with warnings.catch_warnings():
           warnings.simplefilter("ignore", DeprecationWarning)
           assert new.Logger is new.StructuredLogger
   ```

### Step 5 — Docs and changelog
- `CHANGELOG.md` (under the next-release heading):
  ```
  ### Changed
  - Moved `src.utils.log` to `src.observability.log`.
  - Renamed `Logger` to `StructuredLogger` to reflect its actual behavior.

  ### Deprecated
  - Importing from `src.utils.log` is deprecated and will be removed in vX.Y.
    Import from `src.observability.log` instead.
  - The class name `Logger` is deprecated and will be removed in vX.Y.
    Use `StructuredLogger`.
  ```
- Grep `docs/` for `utils.log` and `Logger\b` and update any references; add a short deprecation note where appropriate.

### Step 6 — Verify locally
- Run the full test suite. Both old-path and new-path tests should pass.
- Run with `-W error::DeprecationWarning` once and confirm the *production* code path (not the deprecation tests) raises no `DeprecationWarning` — i.e., no internal code still hits the shim or the old name.
- Spot-check that `git log --follow src/observability/log.py` shows pre-move history (confirms `git mv` preserved it).

### Step 7 — Commit and PR
- Single commit, message along these lines:
  ```
  refactor(log): move to src/observability and rename Logger -> StructuredLogger

  - Move src/utils/log.py -> src/observability/log.py (history preserved via git mv).
  - Rename Logger -> StructuredLogger; module name now matches the class's actual behavior.
  - Old import path and old class name kept as deprecation shims for one release
    (removed in vX.Y); both emit DeprecationWarning.
  - Update all internal call sites; tests moved alongside the module.
  ```
- PR description should mirror the changelog entries and explicitly call out the removal target version.

### Step 8 — File the removal ticket
Create an issue titled "Remove `src.utils.log` shim and `Logger` alias in vX.Y" linking to this PR. Without this, the shim will outlive its welcome.

---

## 5. Open questions for you

- **What is `vX.Y`?** The exact next-release version number needs to land in the warning messages, the changelog, and the removal ticket. Pick it before merging.
- **Does the project use a `src/` layout package prefix (`src.utils.log`) or a flat one (`utils.log`)?** I've written the plan assuming `src.utils.log`. If imports are flat, adjust the strings in the warnings, the shim, and the tests accordingly.
- **Is `DeprecationWarning` filtered to errors in CI?** If yes, the deprecation tests must wrap with `pytest.warns(...)` (already done above) and any internal code still hitting the shim will fail CI — which is desirable, but worth confirming before pushing.
