# Plan: Move logging module to `src/observability/`, rename `Logger` → `StructuredLogger`, keep old import path working for one release

## 1. Objective

- The logging module lives at `src/utils/log.py` but it isn't a generic util — it owns structured logging, which is an observability concern. Move it to `src/observability/log.py` so the package layout reflects its actual role.
- The class is named `Logger`, but it emits structured records (not stdlib-`logging`-style line logs). Rename to `StructuredLogger` so the name matches behavior and stops colliding with `logging.Logger` in readers' heads.
- One-release backwards compatibility: existing imports of `src.utils.log` and `src.utils.log.Logger` must keep working for one version, emitting a `DeprecationWarning` that points at the caller.

Non-goals:

- Changing log format, transport, or any runtime behavior of the logger.
- Hunting external (out-of-repo) consumers — they get the deprecation warning like everyone else.

## 2. Approach

**Strategy: move the implementation to `src/observability/log.py` with the renamed class as canonical, and leave `src/utils/log.py` as a thin shim that re-exports from the new location and warns on import + on the old name.**

Why this shape:

- The shim is the standard Python deprecation pattern: one file change accommodates every old caller without us having to touch their code in the same PR.
- Keeping the implementation in exactly one place (the new path) means there's no drift risk between two copies during the deprecation window.

Mechanics that matter:

- Use `git mv src/utils/log.py src/observability/log.py` so the rename is preserved as a rename in history (not delete + add). Then edit the moved file to rename the class.
- The class rename is done at the definition site in the new file; `Logger = StructuredLogger` stays as a module-level alias inside `src/observability/log.py` for the deprecation window so old-name consumers (via the shim) keep resolving.
- The shim at `src/utils/log.py` does:
  - `from src.observability.log import *` plus an explicit `__all__` mirror to keep public surface stable.
  - A module-level `warnings.warn(..., DeprecationWarning, stacklevel=2)` so the warning points at the **caller's import line**, not at the shim.
  - A `__getattr__(name)` (PEP 562) that emits a second, more specific warning when callers reach for `Logger` by name, telling them to switch to `StructuredLogger`.
- `DeprecationWarning` (not `PendingDeprecationWarning`): we're committing to removal next release, not "someday."
- In-repo callers get rewritten to the new path + new name in the same PR. The shim exists for out-of-repo / not-yet-discovered callers, not as an excuse to leave the repo half-migrated.
- Add an `__init__.py` at `src/observability/` if it doesn't exist; leave `src/utils/__init__.py` alone (other utils still live there).

Scope IN:

- Move `src/utils/log.py` → `src/observability/log.py`.
- Rename `Logger` → `StructuredLogger` at the definition site; keep `Logger` as a deprecated alias in the new module for one release.
- Add deprecation shim at `src/utils/log.py`.
- Update every in-repo caller to import from `src.observability.log` and use `StructuredLogger`.
- Update tests that import the old path or assert on the old class name.
- Update any docs / README snippets that show the old import.

Scope OUT:

- Removing the shim. Tracked as a follow-up issue tagged for the next release ("Remove `src/utils/log.py` deprecation shim").
- Removing the `Logger = StructuredLogger` alias in the new module. Same follow-up issue.
- Refactoring the logger's internals, output format, or sinks. Not this PR.
- Migrating external consumers. They get the warning; that's the contract.

Delivery: one PR, one commit on branch `refactor/log-to-observability`. Solo.

Done when:

- New path imports and works; old path imports, works, and emits exactly one `DeprecationWarning` per process per import site; full test suite green; grep for `src.utils.log` and `from src.utils import log` in the repo returns only the shim file itself.

## 3. Per-change overview

### 3.1 `src/observability/log.py` (new canonical location)

- Created via `git mv` from `src/utils/log.py` so history is preserved.
- Class `Logger` renamed to `StructuredLogger` at the definition.
- Module-level alias `Logger = StructuredLogger` added for shim consumers; marked with a comment pointing at the removal-tracking issue.
- `__all__` updated to include both names during the deprecation window.

### 3.2 `src/observability/__init__.py`

- Created if absent. Empty (or a single-line docstring). No re-exports — callers import from `src.observability.log` directly, matching the existing `src/utils/log.py` convention.

### 3.3 `src/utils/log.py` (deprecation shim)

- Replaces the moved file (the rename leaves this path empty; we re-create it as a shim).
- Re-exports everything public from `src.observability.log` via explicit `__all__`.
- Emits a `DeprecationWarning` at module-import time.
- Adds `__getattr__` that emits a more specific warning when `Logger` is accessed by name.

### 3.4 In-repo callers

- Every `from src.utils.log import ...` → `from src.observability.log import ...`.
- Every reference to `Logger` (the class, not stdlib `logging.Logger`) → `StructuredLogger`.
- Includes test files.

### 3.5 Docs / README

- Search docs (`docs/`, `README.md`, any `*.md` in repo) for `src.utils.log` and `from src.utils import log`. Update snippets to the new path and class name.

### 3.6 Test coverage for the deprecation behavior

- One new test asserting that `import src.utils.log` raises `DeprecationWarning` exactly once.
- One new test asserting that `from src.utils.log import Logger` (or `src.utils.log.Logger` attribute access) raises a `DeprecationWarning` mentioning `StructuredLogger`.
- Both use `pytest.warns(DeprecationWarning)` and `warnings.catch_warnings()` to isolate.

## 4. Implementer guide

### Step 1 — Branch and inventory

- `git checkout -b refactor/log-to-observability` from `main`.
- Grep for all callers so you know the blast radius before you start moving files:
  - `rg -l "src\.utils\.log|from src\.utils import log" --type py`
  - `rg -l "\bLogger\b" --type py` — then filter to ones that are *our* `Logger`, not `logging.Logger`. Save the list somewhere scratch.

Checkpoint: you have a written list of every file that imports the old path and every file that references the old class name.

### Step 2 — Move the file with `git mv`

Rationale: `git mv` (not delete + create) preserves rename history so `git log --follow` keeps working on the moved file.

- `mkdir -p src/observability` (if missing).
- `touch src/observability/__init__.py` (if missing).
- `git mv src/utils/log.py src/observability/log.py`.

Checkpoint: `git status` shows `renamed: src/utils/log.py -> src/observability/log.py` (not `deleted` + `new file`).

### Step 3 — Rename the class in the new file

In `src/observability/log.py`:

- Find `class Logger` and rename to `class StructuredLogger`.
- Update any internal self-references (`Logger.something` inside the module).
- Add the deprecation alias at the bottom of the module:

```python
# Backwards-compat alias for the old class name. Remove in the release
# after this one — tracked in issue/follow-up: "Remove Logger alias and
# src/utils/log.py shim".
Logger = StructuredLogger
```

- If the module has `__all__`, include both names: `__all__ = [..., "StructuredLogger", "Logger"]`.

Checkpoint: `python -c "from src.observability.log import StructuredLogger, Logger; assert Logger is StructuredLogger"` exits 0.

### Step 4 — Create the deprecation shim at the old path

Rationale: this lands after Step 3 because the shim re-exports from the new module and references the new class name in its warning text — the new module needs to exist first.

Create `src/utils/log.py` with exactly this content (adjust `__all__` to match what the new module actually exports):

```python
"""Deprecated import path. Use src.observability.log instead.

This shim re-exports the public surface of src.observability.log and emits
a DeprecationWarning on import. It will be removed in the next release.
"""
import warnings as _warnings

from src.observability.log import *  # noqa: F401,F403  re-export public surface
from src.observability.log import __all__ as _new_all
from src.observability.log import StructuredLogger as _StructuredLogger

__all__ = list(_new_all)

_warnings.warn(
    "src.utils.log is deprecated; import from src.observability.log instead. "
    "This shim will be removed in the next release.",
    DeprecationWarning,
    stacklevel=2,
)


def __getattr__(name):
    # PEP 562: per-attribute deprecation for the old class name.
    if name == "Logger":
        _warnings.warn(
            "src.utils.log.Logger is deprecated; use "
            "src.observability.log.StructuredLogger instead.",
            DeprecationWarning,
            stacklevel=2,
        )
        return _StructuredLogger
    raise AttributeError(f"module 'src.utils.log' has no attribute {name!r}")
```

Notes:

- `stacklevel=2` on both warnings is deliberate — it makes the warning point at the **caller's import / attribute access line**, not at the shim itself. Without it the warning is useless for the user trying to find where to fix their code.
- The `from src.observability.log import *` line is what makes `from src.utils.log import StructuredLogger` keep working transparently. The `__getattr__` only fires for `Logger` because `*`-import already populated `StructuredLogger` at module scope.

Checkpoint:

```
python -W error::DeprecationWarning -c "import src.utils.log"
```

should raise. Then:

```
python -c "import warnings; warnings.simplefilter('always'); import src.utils.log; from src.utils.log import Logger; print(Logger)"
```

should print two warnings (one for the import, one for the `Logger` attribute) and the class object.

### Step 5 — Update in-repo callers

Walk the list from Step 1.

- For each file: replace `from src.utils.log import ...` with `from src.observability.log import ...`.
- Replace `Logger` with `StructuredLogger` where it refers to our class. Be careful not to rename `logging.Logger` references — those are stdlib and unrelated.
- If a file does `import src.utils.log as log`, change to `import src.observability.log as log`.

Checkpoint: `rg "src\.utils\.log|from src\.utils import log" --type py` returns only `src/utils/log.py` itself (the shim).

### Step 6 — Add tests for the deprecation behavior

Add a new test file (e.g. `tests/test_log_deprecation.py`) with two cases:

```python
import importlib
import warnings

import pytest


def test_old_module_import_warns():
    # Force a fresh import so the module-level warning fires.
    import sys
    sys.modules.pop("src.utils.log", None)
    with pytest.warns(DeprecationWarning, match="src.observability.log"):
        importlib.import_module("src.utils.log")


def test_old_class_name_warns_and_returns_structured_logger():
    import sys
    sys.modules.pop("src.utils.log", None)
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        mod = importlib.import_module("src.utils.log")
        cls = mod.Logger
    from src.observability.log import StructuredLogger
    assert cls is StructuredLogger
    assert any(
        issubclass(w.category, DeprecationWarning)
        and "StructuredLogger" in str(w.message)
        for w in caught
    )
```

Checkpoint: `pytest tests/test_log_deprecation.py -W error::DeprecationWarning` — both tests pass (the `pytest.warns` and `catch_warnings` blocks consume the warnings, so `-W error` doesn't trip the test runner itself).

### Step 7 — Update docs

- `rg "src\.utils\.log|from src\.utils import log" docs/ README.md` (and any other `*.md`).
- Replace import snippets and any mention of the `Logger` class with the new path and `StructuredLogger`.
- If there's a CHANGELOG, add an entry under the next release noting: moved path, renamed class, both old surfaces deprecated.

Checkpoint: `rg "src\.utils\.log|from src\.utils import log"` across the whole repo returns only the shim file and (optionally) the CHANGELOG entry describing the deprecation.

### Step 8 — Full test run, commit, PR

- `pytest` clean.
- Run the project's linter / type-checker; some projects flag `import *` in the shim — if so, the `# noqa: F401,F403` in the shim should cover it; otherwise add the project's local suppression.
- Single commit message along the lines of: `refactor(observability): move log module to src/observability and rename Logger → StructuredLogger (deprecate old surface for one release)`.
- Open PR. Body should call out:
  - the new import path,
  - the deprecation window length (one release),
  - the follow-up issue for removing the shim and alias.

Checkpoint: CI green; PR description names the follow-up tracking issue for shim removal.

## 5. Open questions for you

- **Which release is "next"?** The deprecation message currently says "the next release." If you want a concrete version (e.g. "removed in v2.0"), tell me and I'll edit the shim's warning text and the CHANGELOG entry.
- **Is `src.` the actual import root?** I've assumed `src/` is on `sys.path` (common with `src`-layout projects) so imports read `from src.observability.log import ...`. If the project uses a flat layout or a package name like `myproject/`, the import paths in the shim and callers should use that instead — point me at `pyproject.toml` / `setup.cfg` and I'll adjust.
- **Is there an issue tracker convention?** The OUT-scope items reference a "follow-up issue" for shim removal. If you want me to draft the issue body too, say so; otherwise I'll leave the PR description naming a placeholder that you fill in.
