# Plan — Move log module to observability, rename Logger to StructuredLogger, ship one-release backwards-compat shim

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: logging module relocated from `src/utils/log.py` to `src/observability/log.py`, with `Logger` renamed to `StructuredLogger`, and a one-release deprecation shim left at the old path.
- **What moves**: `src/utils/log.py` -> `src/observability/log.py` (via `git mv` so history follows). New package `src/observability/` is created with an `__init__.py` that re-exports `StructuredLogger`.
- **What gets renamed**: class `Logger` -> `StructuredLogger` at the new location. The old name remains importable from the old path as an alias for one release, emitting a `DeprecationWarning`.
- **What changes for users**: callers update to `from src.observability.log import StructuredLogger`. Old imports keep working but warn. No behavioral change to logging output.
- **What's still paused / deferred**: removing the shim entirely (next release, tracked as a follow-up TODO in the shim file itself); any broader observability work (metrics, tracing) is explicitly out of scope.
- **Delivery**: solo dev, single PR, single commit (or two if the rename and shim warrant separation — implementer's call).
- **Done when**: `python -c "from src.utils.log import Logger; Logger()"` emits a `DeprecationWarning` and still works; `python -c "from src.observability.log import StructuredLogger; StructuredLogger()"` works silently; full test suite green; grep for `from src.utils.log` and `utils.log` in non-shim code returns zero hits.

---

## Tier 2 — High-level overview

### Change 1: Relocate the module

- Create `src/observability/` package with `__init__.py` that re-exports `StructuredLogger` (so `from src.observability import StructuredLogger` works at the package level too).
- Move file via `git mv src/utils/log.py src/observability/log.py` so blame and history follow the file.
- Update every non-shim caller's import path in the same commit as the move (a `git mv` keeps history; the import edits are mechanical).
- Rationale: `utils` is a junk drawer; `observability` is the real category. The move is cheap once and expensive forever-if-deferred.

### Change 2: Rename Logger to StructuredLogger

- Rename the class at its new location: `class Logger` -> `class StructuredLogger`.
- Update all in-repo references (instantiations, type hints, `isinstance` checks, docstrings) to the new name.
- Inside the new module, also add `Logger = StructuredLogger` as a module-level alias guarded by a `DeprecationWarning` accessor pattern (see Tier 3 step 3) so any stragglers continue to work but warn.
- Rationale: the name `Logger` collides with `logging.Logger` and undersells what the class does. Renaming alongside the move avoids two churning commits in two releases.

### Change 3: Backwards-compat shim at the old path

- Replace `src/utils/log.py` (now gone after `git mv`) by re-creating it as a thin shim file at the same path.
- The shim re-exports `StructuredLogger as Logger` and triggers a `DeprecationWarning` on import (using `warnings.warn` at module top level with `stacklevel=2` so the warning points at the caller).
- Shim file contains an inline TODO with the target removal release tag and a pointer to the follow-up issue / ROADMAP entry.
- Rationale: one-release grace period gives downstream code (or other branches / forks / staged callers) time to update without a flag-day break.

### Scope decisions (what's explicitly in vs out)

- IN: file move; class rename; one-release shim; all in-repo callers updated; tests updated; deprecation warning verified.
- IN: docstring + module docstring updated to reflect new home and new class name.
- OUT: removing the shim (tracked as inline TODO in the shim file, scheduled for next release).
- OUT: broader observability scaffolding (metrics, tracing, span propagation, OTel) — only the log module moves; the `src/observability/` package starts with just the one file.
- OUT: changing log output format, log levels, sinks, or any runtime behavior.
- OUT: renaming `Logger` to anything other than `StructuredLogger` — no bikeshedding mid-PR.

### Counts / math anchoring scale

- 1 file moved (`log.py`).
- 1 file created (`src/observability/__init__.py`).
- 1 file recreated as a shim (`src/utils/log.py`).
- 1 class renamed (`Logger` -> `StructuredLogger`).
- N caller files updated, where N is what `grep -r "from src.utils.log\|from src\.utils\.log\|utils\.log\|import.*Logger" src/ tests/` returns. Expect double-digit at most for a normal-sized project; if it's hundreds, that's a signal the rename should land in a separate codemod commit.

### Why one PR (not three)

- Solo dev — no external reviewers, no review-surface budget to amortize across multiple PRs.
- The move + rename + shim are tightly coupled: shipping any one without the others leaves the tree in a worse state (broken imports, or a rename without a shim, or a shim with nothing to defer to).
- Reverting is a single `git revert` if anything goes sideways in CI.

---

## Tier 3 — Implementer guide

### Step 1: Create the new package skeleton

Land the package directory before moving the file so `git mv` has a destination and the import path resolves on first run.

- Create `src/observability/__init__.py` with a single line: `from .log import StructuredLogger` (and an `__all__ = ["StructuredLogger"]` for hygiene).
- Do NOT pre-create `src/observability/log.py` — the next step's `git mv` creates it.

Checkpoint: `ls src/observability/` shows `__init__.py` only.

### Step 2: Move the file with history preserved

`git mv` keeps blame intact, which matters for the next person investigating a log-format bug.

- Run `git mv src/utils/log.py src/observability/log.py`.
- Do not edit the file's contents in this commit yet if you're splitting commits; if single-commit, proceed to step 3 in the same working tree.

Checkpoint: `git status` shows `renamed: src/utils/log.py -> src/observability/log.py`.

### Step 3: Rename the class at the new location

The class rename lands at the new home so the shim (created in step 5) has a clean target to alias.

- Open `src/observability/log.py`.
- Rename `class Logger:` -> `class StructuredLogger:` (or `class Logger(...)` -> `class StructuredLogger(...)` preserving bases).
- Update the module docstring to reflect the new home and new class name.
- Update any internal self-references (e.g., `__repr__` strings, factory functions like `def get_logger() -> "Logger"` -> `-> "StructuredLogger"`, classmethods that return `cls`-style annotated as `Logger`).
- At the bottom of `src/observability/log.py`, do NOT add a `Logger = StructuredLogger` alias — that alias lives in the shim only. Keeping the new module clean means callers who import from the new path get a single, unambiguous name.

Checkpoint: `python -c "from src.observability.log import StructuredLogger; print(StructuredLogger.__name__)"` prints `StructuredLogger` with no warning.

### Step 4: Update all in-repo callers

Mechanical sweep. Land before the shim so the shim's deprecation warning isn't being triggered by your own code in CI.

- Find callers: `grep -rn "from src.utils.log\|src\.utils\.log\| Logger(\|: Logger\|-> Logger\|isinstance.*Logger" src/ tests/` (adjust the `Logger` patterns to avoid `logging.Logger` false positives — inspect each hit).
- For each caller file:
  - Replace `from src.utils.log import Logger` with `from src.observability.log import StructuredLogger`.
  - Replace `Logger(` with `StructuredLogger(` at instantiation sites.
  - Replace type hints `Logger` -> `StructuredLogger` (including forward refs `"Logger"` -> `"StructuredLogger"`).
  - Replace `isinstance(x, Logger)` -> `isinstance(x, StructuredLogger)`.
- For docstrings or comments mentioning `Logger`, update to `StructuredLogger` where the reference is to this class (leave references to stdlib `logging.Logger` alone).

Checkpoint: `grep -rn "from src.utils.log" src/ tests/ | grep -v "src/utils/log.py"` returns zero lines; `pytest` passes (or whatever the project's test command is).

### Step 5: Re-create the old path as a deprecation shim

The shim is the deferral mechanism. It must warn on import, not on use, so callers see the warning even if they don't instantiate immediately.

- Create `src/utils/log.py` with content along these lines:

  ```python
  """Deprecated location for StructuredLogger.

  This module is a backwards-compatibility shim. Import from
  ``src.observability.log`` instead.

  TODO(<next-release-tag>): remove this shim. Tracked in ROADMAP / follow-up issue.
  """
  import warnings

  from src.observability.log import StructuredLogger
  from src.observability.log import StructuredLogger as Logger  # legacy alias

  warnings.warn(
      "src.utils.log is deprecated; import from src.observability.log instead. "
      "The old import path and the `Logger` alias will be removed in the next release.",
      DeprecationWarning,
      stacklevel=2,
  )

  __all__ = ["StructuredLogger", "Logger"]
  ```

- Confirm the file uses `stacklevel=2` so the warning's traceback points at the caller's import line, not at the shim itself.
- Replace `<next-release-tag>` with the actual target version string from the project's version file / changelog.

Checkpoint: `python -W error::DeprecationWarning -c "from src.utils.log import Logger"` raises `DeprecationWarning` (proving the warning fires); `python -W ignore -c "from src.utils.log import Logger; Logger()"` runs without error (proving the alias still works).

### Step 6: Add a regression test for the shim

The shim is load-bearing for one release. A test pins its behavior so a future cleanup doesn't accidentally rip the warning out while leaving the alias.

- Add `tests/observability/test_log_deprecation_shim.py` (create `tests/observability/` if absent) with two tests:
  - `test_old_import_path_still_works`: imports `Logger` from `src.utils.log`, instantiates it, asserts it's an instance of `StructuredLogger` from the new path.
  - `test_old_import_path_warns`: uses `pytest.warns(DeprecationWarning, match="src.utils.log is deprecated")` around a fresh import (use `importlib.reload` or a subprocess to defeat import caching).

Checkpoint: `pytest tests/observability/test_log_deprecation_shim.py -W default` passes both tests.

### Step 7: Update docs and CHANGELOG (if present)

Keeping the changelog in the same commit means future-you-debugging-an-import-error finds the migration note via `git log` on the file.

- If a `CHANGELOG.md` exists, add an entry under the unreleased / next-version section: "Moved `src/utils/log.py` to `src/observability/log.py`; renamed `Logger` to `StructuredLogger`. Old import path remains available with a `DeprecationWarning` for one release."
- If a `README.md` or `docs/` has any reference to `src.utils.log` or `Logger`, update those references to the new path and new class name.
- Run `grep -rn "src.utils.log\|src\.utils\.log\|\bLogger\b" docs/ README.md 2>/dev/null` to catch stragglers; review each hit (skip stdlib `logging.Logger` mentions).

Checkpoint: `grep -rn "src.utils.log" docs/ README.md 2>/dev/null` only matches text describing the deprecation, not active guidance to use the old path.

### Step 8: Final verification before commit

One pass to confirm Tier 1's "Done when" line.

- `pytest` — full suite green.
- `python -W error::DeprecationWarning -c "from src.observability.log import StructuredLogger; StructuredLogger()"` — runs without raising (no warning from the new path).
- `python -W error::DeprecationWarning -c "from src.utils.log import Logger"` — raises `DeprecationWarning` (shim warns as designed).
- `grep -rn "from src.utils.log" src/ tests/ | grep -v "src/utils/log.py"` — empty (no live callers on the old path).
- `git log --follow src/observability/log.py` — shows pre-move history (confirms `git mv` preserved blame).

Checkpoint: all four commands behave as expected; commit and push.

### Critical files (patterns repeat; representative paths only)

- `src/observability/__init__.py` — new package init; re-exports `StructuredLogger`.
- `src/observability/log.py` — the moved + renamed module; the new source of truth.
- `src/utils/log.py` — the deprecation shim; the one-release deferral mechanism.
- `tests/observability/test_log_deprecation_shim.py` — pins the shim's behavior.
- Caller files — pattern: anything matching `grep -rn "src.utils.log\|\bLogger\b" src/ tests/` minus stdlib false positives. Mechanical edits; no per-file design decisions.

### Reusable utilities (referenced, not reinvented)

- `warnings.warn(..., DeprecationWarning, stacklevel=2)` — stdlib; the `stacklevel=2` is the load-bearing detail so warnings point at the caller, not the shim.
- `pytest.warns(DeprecationWarning, match=...)` — stdlib pytest helper; the right tool for the shim regression test, not a hand-rolled warning catcher.
- `git mv` — preserves history; do not `rm` + `add`.

### Commit hygiene

- Use `git mv` (already called out above).
- One commit is the default; if the caller-update sweep is large enough to dominate the diff, split into two commits: (1) move + rename + shim + caller updates for code, (2) tests + docs + changelog. Both land in the same PR.
- Follow the project's normal commit message conventions; if there's a rule against AI co-author attribution, honor it.

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Produce a three-tier plan: Tier 1 is a 5-7 bullet summary readable in 60 seconds (what ships / what moves / what gets fixed / user-visible change / what's deferred / delivery shape / done-when).
- Tier 2 is one section per major change (3-5 bullets each, with rationale), plus cross-cutting sections for explicit IN/OUT scope, counts that anchor scale, and a one-bullet justification for single-PR delivery.
- Tier 3 is numbered implementer steps with file paths, exact edits where non-obvious, and a Checkpoint line per step describing the verification command. End with a Critical files list (patterns, not enumeration) and a Reusable utilities list (cited by path).
- Bullets only. No tables. No prose paragraphs longer than three sentences. Declarative voice. Honest about asymmetries. Default to solo-dev assumptions (one PR, one commit). Always include explicit IN/OUT scope lists. Link OUT items to their tracking (ROADMAP, follow-up issue, inline TODO).
- If using `git mv`, say so. If commit messages must follow a hygiene rule (no AI co-author, conventional commits, etc.), call it out.
