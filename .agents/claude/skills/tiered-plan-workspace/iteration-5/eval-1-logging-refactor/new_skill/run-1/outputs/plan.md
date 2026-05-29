# Plan: Move logging module to `src/observability/`, rename `Logger` to `StructuredLogger`, keep old import path warning for one release

## 1. Objective

- Relocate the logging module from `src/utils/log.py` to `src/observability/log.py` so logging lives with the observability concern instead of the general-purpose utils grab-bag.
- Rename the misnamed `Logger` class to `StructuredLogger` — its actual behavior — so call sites read truthfully and don't collide visually with `logging.Logger`.
- Preserve `from src.utils.log import ...` for exactly one release with a `DeprecationWarning`, so downstream callers (and any vendored consumers) get a migration window instead of an `ImportError`.

**Definition of Done**:
- `src/observability/log.py` exists and is the canonical module; it exports `StructuredLogger` (and any previously public names).
- `src/observability/__init__.py` exists (package is importable).
- `src/utils/log.py` still imports cleanly and re-exports the same public surface, but emits a `DeprecationWarning` on import pointing at the new path.
- Importing the old name `Logger` from either path still works and also emits a `DeprecationWarning` naming `StructuredLogger` as the replacement.
- Every in-repo caller has been updated to use `src.observability.log` and `StructuredLogger` — `grep` for the old import path and the old class name returns zero hits in `src/` and `tests/` outside the shim file itself.
- Test suite passes; the shim's deprecation warning is asserted by at least one test (`pytest.warns(DeprecationWarning)`).
- `CHANGELOG.md` (or equivalent release-notes file) has a "Deprecated" entry naming the old path and old class name, and a "Removed in next release" pointer.

**Open questions** (planner can't decide without you):
- **What is "one release" concretely?** The shim's removal target needs a version string in the warning message and the changelog (e.g. "removed in v2.0", "removed in 0.14"). What's the next version, and is removal in the *immediately* next release or the one after?
- **Is there a public/external surface for this package?** If `src/utils/log.py` is exposed to downstream consumers (PyPI package, vendored copy in another repo), the shim must stay for the full deprecation window. If it's purely internal, we could shorten the window. Which is it?
- **Project Python floor?** The shim uses module-level `__getattr__` for the lazy `Logger` -> `StructuredLogger` alias warning; that requires Python >= 3.7 (PEP 562). Confirm the project's minimum supported Python.

## 2. Approach

**Strategy: move the implementation to `src/observability/log.py` as the canonical module; rewrite `src/utils/log.py` as a thin re-export shim that emits a `DeprecationWarning` on import and on access to the old `Logger` name.**

Why this shape:
- One source of truth (the new path) avoids drift between two copies of the implementation during the deprecation window.
- A shim-only old path means the deprecation can be deleted by removing one file in the follow-up release — no spelunking through the new module to strip warning code.

Mechanics that matter:
- **`git mv src/utils/log.py src/observability/log.py`** to preserve file history (blame, log follow). Do the move in a dedicated commit *before* renaming the class, so the rename diff is reviewable as a pure rename.
- **Class rename: `Logger` -> `StructuredLogger`** inside the new module. Keep a module-level alias `Logger = StructuredLogger` in the new module *only if* the new path needs to accept the old name during the window (it does — see below).
- **Shim at old path** (`src/utils/log.py`): `from src.observability.log import *` plus an explicit `__all__` re-export, then `warnings.warn(...)` at import time. Use **`stacklevel=2`** so the warning points at the caller's `import` line, not at the shim. Category: `DeprecationWarning`.
- **Lazy `Logger` alias with per-name warning**: use a module-level **`__getattr__`** (PEP 562) in *both* `src/observability/log.py` and `src/utils/log.py` so that accessing the bare name `Logger` triggers a `DeprecationWarning` naming `StructuredLogger`, without paying the warning cost for callers who already migrated. This lets us warn on the class name independently of the path.
- **Warning suppression in our own tests**: any test that intentionally exercises the shim wraps the import in `pytest.warns(DeprecationWarning)`; everything else imports the new path and stays warning-free, so CI doesn't drown in noise.
- **Changelog entry** under "Deprecated" with the removal version embedded in the warning message text (so users grep-searching their logs find the same string in the changelog).

**Scope IN**:
- New module at `src/observability/log.py` with `StructuredLogger`.
- New `src/observability/__init__.py` (empty or re-exporting `StructuredLogger` for convenience).
- Shim at `src/utils/log.py` with import-time `DeprecationWarning` and lazy `Logger` alias warning.
- Update all in-repo callers in `src/` and `tests/` to the new path and new class name.
- One test asserting the shim warns.
- Changelog "Deprecated" entry naming the removal version.

**Scope OUT**:
- Actually removing the shim — out because the user explicitly asked for one release of backwards-compat; the removal is the follow-up -> tracked in changelog "Removed in vX" entry + a follow-up issue/TODO referencing this PR.
- Restructuring `src/utils/` beyond moving `log.py` out — out because other utils modules aren't part of this request; surface area creep risks reviewer churn -> deferred, no tracker needed unless raised.
- Restructuring the logger's internal API (format, sinks, levels) — out because rename + move is already two concerns; behavior changes would muddy the diff -> deferred to a separate ticket if/when a need surfaces.
- Adding `__init__.py` re-exports that promote `StructuredLogger` to `src.observability` top-level beyond a single convenience export — out because doing more than the minimum invites bikeshed during review -> can be added later without breaking callers.
- Migrating to `structlog` or any third-party structured-logging library — out because the request is rename-and-move, not re-implement -> separate evaluation if proposed.

**Delivery**: one PR, one branch `refactor/observability-log-move`, ideally two commits (commit 1: pure `git mv` + caller updates for path; commit 2: class rename + shim + changelog). Solo.

## 3. Per-change overview

### 3.1 `src/observability/__init__.py` (new)

- Create empty file, or single-line `from .log import StructuredLogger` if the project's import style favors short paths.
- Pick whichever matches existing sibling packages in `src/` for consistency.

### 3.2 `src/observability/log.py` (moved from `src/utils/log.py`)

- File moved via `git mv` to preserve history.
- Class `Logger` renamed to `StructuredLogger` throughout.
- Module-level `__getattr__` added so `from src.observability.log import Logger` still works but warns.
- Public surface (`__all__`) updated to list `StructuredLogger`; the old `Logger` name is reachable via `__getattr__` but excluded from `__all__` so `from … import *` doesn't pull the deprecated alias.

### 3.3 `src/utils/log.py` (rewritten as shim)

- Replaced with a thin shim: re-exports `StructuredLogger` (and any other public names) from `src.observability.log`.
- Emits `DeprecationWarning` at import time with `stacklevel=2` naming both the new path and the removal version.
- Has its own module-level `__getattr__` so accessing `Logger` via the old path warns about both the path *and* the class name.

### 3.4 All callers in `src/` and `tests/` (excluding the shim)

- Replace `from src.utils.log import …` -> `from src.observability.log import …`.
- Replace `Logger` -> `StructuredLogger` at every call site, type annotation, and isinstance check.
- Run `grep` for both the old import path and the bare identifier `Logger` to confirm no stragglers (other than the shim itself and any unrelated `logging.Logger` references).

### 3.5 `tests/test_log_shim_deprecation.py` (new, small)

- One test that imports `src.utils.log` and asserts `DeprecationWarning` is raised, with the warning message containing the removal version string.
- One test that accesses `src.observability.log.Logger` and asserts `DeprecationWarning` naming `StructuredLogger`.

### 3.6 `CHANGELOG.md`

- "Deprecated" section entry: old import path + old class name + removal version + link to PR.

## 4. Implementer guide

### Step 1 — Branch and answer open questions

- `git checkout -b refactor/observability-log-move` off `main`.
- Resolve the open questions in section 1 — pick the removal version string (will be referenced literally below as `VNEXT`); confirm Python floor >= 3.7 for `__getattr__`.

Checkpoint: branch exists; `VNEXT` is a known string (e.g. `"v2.0"`).

### Step 2 — Move the file with history preserved, do nothing else

This commit must be a pure move — no edits to contents yet — so reviewers can see `git log --follow` works.

- `mkdir -p src/observability`
- `git mv src/utils/log.py src/observability/log.py`
- Create `src/observability/__init__.py`. Use the empty-file form if siblings under `src/` use empty `__init__.py`; use the re-export form below if siblings re-export:

```python
from .log import StructuredLogger

__all__ = ["StructuredLogger"]
```

(Note: at this commit the class is still named `Logger`; the re-export will be edited in Step 4. If using the empty form, skip the file contents.)

- Commit: `refactor(observability): move log module from utils to observability (pure move)`.

Checkpoint: `git log --follow src/observability/log.py` shows the file's history from when it was at `src/utils/log.py`.

### Step 3 — Update all in-repo callers to the new path (still old class name)

Doing the path update before the class rename keeps each commit small enough to read in one sitting.

- Find call sites: `grep -rn "from src.utils.log" src/ tests/` and `grep -rn "import src.utils.log" src/ tests/`.
- For each hit, rewrite the import to `from src.observability.log import …` (still using `Logger`, not `StructuredLogger` — class rename is next step).
- Run the test suite to confirm nothing broke from the path change alone.

Checkpoint: `grep -rn "src.utils.log" src/ tests/` returns no hits; tests pass.

### Step 4 — Rename `Logger` -> `StructuredLogger` in the new module and at all call sites

- In `src/observability/log.py`: rename the class definition and every internal self-reference. Update docstrings.
- In every caller under `src/` and `tests/`: replace `Logger` -> `StructuredLogger`. Be surgical — do not rewrite unrelated identifiers, and do not touch references to `logging.Logger` from the stdlib.
- If `src/observability/__init__.py` re-exports, confirm it names `StructuredLogger`.

Checkpoint: `grep -rwn "Logger" src/observability/log.py src/ tests/` shows only intentional `logging.Logger` references and the to-be-added `__getattr__` alias (next step).

### Step 5 — Add the lazy `Logger` alias in the new module

The point of this alias is to keep the old class name reachable via the new path for one release, but with a warning. PEP 562 module-level `__getattr__` is the mechanism.

Append to `src/observability/log.py`:

```python
import warnings as _warnings


def __getattr__(name):
    if name == "Logger":
        _warnings.warn(
            "`Logger` is deprecated; use `StructuredLogger` instead. "
            "The alias will be removed in VNEXT.",
            DeprecationWarning,
            stacklevel=2,
        )
        return StructuredLogger
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

Replace `VNEXT` literally with the version chosen in Step 1.

Checkpoint: in a Python REPL, `from src.observability.log import Logger` emits a `DeprecationWarning` and returns the `StructuredLogger` class.

### Step 6 — Write the shim at the old path

Create `src/utils/log.py` (it was moved away in Step 2 — this is a fresh file at the old location):

```python
"""Deprecated shim. The logging module moved to `src.observability.log`.

This shim will be removed in VNEXT.
"""
import warnings as _warnings

from src.observability.log import StructuredLogger  # re-export

__all__ = ["StructuredLogger"]

_warnings.warn(
    "`src.utils.log` is deprecated; import from `src.observability.log` instead. "
    "This shim will be removed in VNEXT.",
    DeprecationWarning,
    stacklevel=2,
)


def __getattr__(name):
    if name == "Logger":
        _warnings.warn(
            "`Logger` is deprecated; use `StructuredLogger` instead. "
            "The alias will be removed in VNEXT.",
            DeprecationWarning,
            stacklevel=2,
        )
        return StructuredLogger
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
```

Replace `VNEXT` literally. If the original module had other public names beyond `Logger`/`StructuredLogger`, re-export them in the `from … import …` line and `__all__`.

Checkpoint: `python -W error::DeprecationWarning -c "import src.utils.log"` raises (proving the warning fires); without `-W error`, it imports and prints the deprecation notice.

### Step 7 — Add the shim deprecation test

Create `tests/test_log_shim_deprecation.py`:

```python
import importlib
import sys

import pytest


def test_old_import_path_warns():
    sys.modules.pop("src.utils.log", None)
    with pytest.warns(DeprecationWarning, match="src.observability.log"):
        importlib.import_module("src.utils.log")


def test_old_class_name_warns_on_new_path():
    import src.observability.log as new_log
    with pytest.warns(DeprecationWarning, match="StructuredLogger"):
        _ = new_log.Logger


def test_old_class_name_warns_on_old_path():
    sys.modules.pop("src.utils.log", None)
    with pytest.warns(DeprecationWarning):
        old_log = importlib.import_module("src.utils.log")
    with pytest.warns(DeprecationWarning, match="StructuredLogger"):
        _ = old_log.Logger
```

The `sys.modules.pop` is needed because import-time warnings only fire on first import; without it, a previous test run in the same pytest session would have cached the module and suppressed the warning.

Checkpoint: `pytest tests/test_log_shim_deprecation.py -v` — all three tests pass.

### Step 8 — Changelog entry

Add to `CHANGELOG.md` under the next-release section (create a "Deprecated" subsection if it doesn't exist):

```markdown
### Deprecated
- `src.utils.log` module path — import from `src.observability.log` instead. The shim will be removed in VNEXT.
- `Logger` class name — use `StructuredLogger`. The alias will be removed in VNEXT.
```

Checkpoint: changelog renders; version string matches the warning messages exactly.

### Step 9 — Full sweep and PR

- Run the full test suite: `pytest`.
- Run any linters/type-checkers the project uses (e.g. `ruff`, `mypy`).
- Final grep sweep: `grep -rn "src.utils.log" src/ tests/` should match only `src/utils/log.py` itself and the shim test. `grep -rwn "Logger" src/ tests/` should match only stdlib `logging.Logger` references, the `__getattr__` blocks, and the shim test.
- Open PR off `refactor/observability-log-move`. Title: `refactor(observability): move log module out of utils and rename Logger -> StructuredLogger`. PR description points at this plan and the changelog entry.

Checkpoint: CI green; no `DeprecationWarning` noise in test output other than the three targeted tests (the rest of the suite imports the new path).
