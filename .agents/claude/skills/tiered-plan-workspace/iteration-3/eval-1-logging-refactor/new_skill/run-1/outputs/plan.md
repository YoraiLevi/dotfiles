# Plan — Relocate logging to `src/observability/`, rename `Logger` → `StructuredLogger`, one-release back-compat

## Goal & worthwhileness

### Problem

- `src/utils/log.py` lives in the catch-all `utils` package, which hides that logging is a first-class cross-cutting concern.
  - New observability work (metrics, tracing) has no obvious home and will end up scattered.
  - `utils` is a known dumping ground; anything left there accretes unrelated helpers around it.
- The exported class is named `Logger` but it actually emits structured (key/value) records.
  - The name misleads readers into expecting stdlib `logging.Logger` semantics.
  - Reviewers have to read the class body to learn what it does, every time.

### Why now

- We're about to add more observability code; doing it before that lands means new code is born in the right place.
- The rename is cheaper now than after more call sites accumulate.

### Success criteria

- `from observability.log import StructuredLogger` works and is the documented path.
- `from utils.log import Logger` still works for one release.
  - Emits a `DeprecationWarning` exactly once per process per deprecated name.
  - Warning points at the caller's import line, not at the shim.
- No first-party code imports from the old path or uses the old class name.
- Full test suite passes, including a new test that asserts the deprecation warning fires.
- Old path and old name are scheduled for removal in the next release, tracked in `CHANGELOG.md` / `ROADMAP.md`.

### Risk surface

- Missed call sites — a stray `from utils.log import Logger` in a rarely-exercised module silently keeps using the old name and never surfaces the warning in tests.
- Circular import — `observability/log.py` must not import anything from `utils/` that itself imports logging.
- Pickled/serialized `Logger` instances (if any) referencing the old fully-qualified class path would break; need to confirm none exist.
- Third-party consumers (if this is a library) get a one-release warning; that's the contract.

## Approach

- **Strategy**:
  - `git mv src/utils/log.py src/observability/log.py` so git tracks it as a rename and history is preserved.
  - Inside the moved file, rename `Logger` → `StructuredLogger`. Keep a module-level alias `Logger = StructuredLogger` *only* in the deprecation shim, not in the new module.
  - Replace `src/utils/log.py` with a thin re-export shim that imports from the new location and warns on access.
  - Sweep all first-party imports to the new path and new name in the same commit.
- **Why this approach**:
  - Single commit keeps the rename atomic for `git log --follow` and for bisect.
  - Shim-as-module (not as alias inside the new module) keeps the new module clean — no deprecated names leak into the canonical surface.
  - `__getattr__` at module level lets us warn on *attribute access*, which catches both `import Logger` and `from utils.log import StructuredLogger` styles uniformly.
- **Why not a hard cut**:
  - Even in a solo project, breaking imports in one commit means any in-flight branch or local script breaks silently. One release of warning is cheap insurance.
- **Why not symlink / `sys.modules` redirect**:
  - Symlinks don't survive packaging on Windows wheels.
  - `sys.modules` injection at import time hides the rename from static analyzers and IDE go-to-definition.
- **Scope IN**:
  - Move the file.
  - Rename the class.
  - Sweep first-party callers.
  - Add deprecation shim with one-shot warning.
  - Update `__init__.py` exports for both old and new packages.
  - Update tests (new path, new name, plus a warning-fires test).
  - Update docs / docstrings / `CHANGELOG.md`.
- **Scope OUT**:
  - Removing the shim — tracked in `ROADMAP.md` under "Next release: drop `utils.log` shim".
  - Refactoring `StructuredLogger`'s API surface — out; rename only, no signature changes.
  - Migrating to a third-party structured logger (structlog, loguru) — separate decision, not bundled here.
  - Adding metrics/tracing modules to `observability/` — follow-up; this PR only establishes the package.
- **Delivery**: one PR, one commit, one branch. Solo.
- **Done when**: `pytest` is green, `grep -r "utils.log" src/ tests/` returns only the shim itself, and a fresh `python -c "from utils.log import Logger"` prints exactly one `DeprecationWarning`.

## Per-change overview

### Change 1: New canonical module at `src/observability/log.py`

- Contains the renamed `StructuredLogger` class and any module-level factory functions it currently exposes.
- New package `src/observability/__init__.py` re-exports `StructuredLogger` for ergonomic `from observability import StructuredLogger`.
- **Why this matters for the goal**: gives logging a named home aligned with what it does, and seeds the package that the next observability work will land in.

### Change 2: Deprecation shim at `src/utils/log.py`

- A short module that re-exports `StructuredLogger` under both names (`Logger` and `StructuredLogger`) via `__getattr__`.
- Uses `warnings.warn(..., DeprecationWarning, stacklevel=2)` on access.
- Caches "already warned" per-name in a module-level set so callers see one warning per name per process.
- **Why this matters for the goal**: lets existing code keep running for one release while making the deprecation visible to anyone running tests with `-W error::DeprecationWarning` or watching CI output.

### Change 3: First-party caller sweep

- Replace `from utils.log import Logger` → `from observability.log import StructuredLogger`.
- Replace bare `Logger(...)` constructions → `StructuredLogger(...)`.
- Update any type hints (`: Logger`, `-> Logger`) accordingly.
- **Why this matters for the goal**: the deprecation warning is only useful if first-party code isn't itself generating it; otherwise CI is noisy and real consumers' warnings get drowned out.

### Change 4: Test updates

- Existing tests that import from `utils.log` → switch to `observability.log`.
- Add one new test: `test_deprecation_shim.py` asserting that importing `Logger` from the old path raises `DeprecationWarning` exactly once.
- **Why this matters for the goal**: locks in the back-compat contract so we don't accidentally remove the shim early or accidentally make it silent.

### Change 5: Docs and changelog

- `CHANGELOG.md`: new entry under Unreleased — "Moved logging to `observability.log`; renamed `Logger` → `StructuredLogger`; old path deprecated, removed next release."
- `ROADMAP.md` (or follow-up issue): "Remove `utils.log` shim in vX+1."
- Any README / docstring example using the old import path.
- **Why this matters for the goal**: a deprecation that isn't documented is a trap; readers need to know both that it changed and when the old path stops working.

## Implementation

### Step 1: `git mv` the file before editing it

This step lands first because moving the file before editing it lets git's rename-detection link old history to new path; editing first then moving fragments `git log --follow`.

- `mkdir src/observability` if it doesn't exist.
- `touch src/observability/__init__.py`.
- `git mv src/utils/log.py src/observability/log.py`.
- Do not edit the contents yet — keep the move and the rename as separable hunks within the single commit for reviewability, because mixing a move with content edits makes the diff look like a rewrite.

Checkpoint: `git status` shows `renamed: src/utils/log.py -> src/observability/log.py` with no content changes.

### Step 2: Rename `Logger` → `StructuredLogger` inside the moved file

This step lands here because the new module should expose its canonical name before any other code starts importing from it.

- In `src/observability/log.py`, rename the class declaration `class Logger:` → `class StructuredLogger:`.
- Update internal self-references (factory functions, `__repr__` strings, docstrings) to `StructuredLogger`.
- Do NOT add a `Logger = StructuredLogger` alias in this file, because the new module should not carry deprecated names; that's the shim's job.
- Update `src/observability/__init__.py` to `from .log import StructuredLogger` and set `__all__ = ["StructuredLogger"]`, because exposing it at the package root makes `from observability import StructuredLogger` work for the common case.

Checkpoint: `python -c "from observability.log import StructuredLogger; print(StructuredLogger)"` prints the class repr without error.

### Step 3: Write the deprecation shim at `src/utils/log.py`

This step lands here because the shim depends on the new module existing and being importable; doing it earlier would create a circular reference window.

- Re-create `src/utils/log.py` (the file was moved away in Step 1) as a thin module:
  - Imports `StructuredLogger` from `observability.log`.
  - Defines a module-level `__getattr__(name)` that handles both `"Logger"` and `"StructuredLogger"`.
  - Maintains a module-level `_warned: set[str] = set()` to dedupe warnings per name per process, because firing on every access would flood logs in any loop that constructs loggers.
  - Calls `warnings.warn(...)` with `stacklevel=2`, because we want the warning to point at the caller's import line, not at the shim itself — otherwise the warning is unactionable.
  - Maps `"Logger"` → `StructuredLogger` (both deprecated path AND deprecated name), with a warning message naming both: e.g. `"utils.log.Logger is deprecated; use observability.log.StructuredLogger (will be removed in next release)"`.
  - Maps `"StructuredLogger"` → `StructuredLogger` (deprecated path only), with a path-only warning.
  - Raises `AttributeError` for any other name, because returning `None` would mask typos.
- Do NOT add `__all__` to the shim, because `from utils.log import *` should not be a supported path during deprecation.

Checkpoint: in a fresh interpreter, `python -W default -c "from utils.log import Logger; Logger"` prints one `DeprecationWarning` whose file pointer is `<string>`, not `utils/log.py`.

### Step 4: Sweep first-party callers

This step lands here because the canonical and shim paths now both work, so the sweep can land atomically without breaking intermediate states.

- Run `grep -rn "from utils.log" src/ tests/` and `grep -rn "utils\\.log" src/ tests/` to enumerate every caller.
- For each hit, rewrite:
  - `from utils.log import Logger` → `from observability.log import StructuredLogger`.
  - Any bare `Logger` reference → `StructuredLogger`.
  - Any `utils.log.Logger` fully-qualified reference → `observability.log.StructuredLogger`.
- Also grep for `: Logger`, `-> Logger`, and `isinstance(x, Logger)` patterns, because type hints and isinstance checks won't show up in import-line searches.
- Skip the shim itself (`src/utils/log.py`) — it is allowed to reference the old name.

Checkpoint: `grep -rn "utils.log\\|\\bLogger\\b" src/ tests/ --include="*.py"` returns only `src/utils/log.py` (the shim) and any genuinely unrelated `Logger` matches (e.g. third-party `logging.Logger`).

### Step 5: Update tests

This step lands here because callers have been updated; now tests need to match and we need a new test guarding the back-compat contract.

- Update any existing test imports to the new path/name (covered by Step 4's sweep — verify nothing was missed).
- Add `tests/test_deprecation_shim.py`:
  - Test 1: `pytest.warns(DeprecationWarning)` when accessing `utils.log.Logger`, because this locks in that the warning fires at all.
  - Test 2: Accessing the same name twice in the same process produces one warning, because this locks in the dedupe contract.
  - Test 3: The deprecated `Logger` and the canonical `StructuredLogger` are the same class object (`is` identity), because anything else would mean we accidentally created two parallel classes and `isinstance` checks would silently fail.
  - Use `importlib.reload(utils.log)` between tests if the dedupe set causes cross-test pollution, because pytest reuses module state across tests in the same process.

Checkpoint: `pytest tests/test_deprecation_shim.py -v` shows all three tests green.

### Step 6: Update docs and changelog

This step lands here because the code and tests are stable; docs should reflect what's actually shipping, not what we intended at the start.

- `CHANGELOG.md` under `## [Unreleased]`:
  - Added: `observability` package with `StructuredLogger`.
  - Deprecated: `utils.log.Logger` and the `utils.log` module — use `observability.log.StructuredLogger`; removal scheduled for next release.
- `ROADMAP.md` (or open a follow-up issue and link it here): "Remove `utils.log` deprecation shim — target: vNext."
- Search docs for old import examples: `grep -rn "utils.log\\|from utils import log" docs/ README.md` and rewrite to new path/name.
- Update the moved file's module docstring to describe `StructuredLogger`, because the old docstring likely still says "Logger".

Checkpoint: `grep -rn "utils.log\\|\\bLogger(" docs/ README.md` returns nothing (or only contextual mentions inside the deprecation note).

### Step 7: Full-suite verification

This step lands last because the prior steps each had a narrow checkpoint; this is the end-to-end gate before commit.

- Run `pytest -W error::DeprecationWarning` over the full suite, because if any first-party test still triggers the shim, this turns it into a hard failure and surfaces the miss. The new `test_deprecation_shim.py` must be exempted (it expects the warning) — use `pytest.warns` inside, which consumes the warning, so the global `-W error` won't trip on it.
- Run `python -c "import observability; import observability.log; print(observability.log.StructuredLogger)"` to confirm the canonical surface.
- Run `python -W default -c "from utils.log import Logger; from utils.log import Logger"` to confirm the shim warns exactly once per process even on repeated import.

Checkpoint: all three commands exit 0 with expected output; suite is green; warning count is 1 in the third command.

### Critical files

- `src/observability/__init__.py` — new package marker, re-exports `StructuredLogger`.
- `src/observability/log.py` — canonical module (moved + renamed).
- `src/utils/log.py` — deprecation shim (replaces moved file).
- `tests/test_deprecation_shim.py` — new, locks in back-compat contract.
- `CHANGELOG.md`, `ROADMAP.md` — deprecation announcement and removal tracking.

### Hygiene constraints

- Use `git mv`, not delete-and-create, so history follows.
- Single commit. Commit message names both the move and the rename, e.g. `refactor(logging): move utils.log → observability.log; rename Logger → StructuredLogger; shim utils.log for one release`.
- No AI co-author attribution in the commit trailer.
- `stacklevel=2` on every `warnings.warn` in the shim — non-negotiable; the warning is useless if it points at the shim.
- The shim file is the ONLY place the old name appears in first-party code post-sweep.
