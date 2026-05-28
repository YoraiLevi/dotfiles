# Plan — Relocate logging into an observability module and rename Logger to its real shape

> Read top-down. Tier 1 is the manager's "should we do this?" — Tier 2 is the decider's "is the approach sound?" — Tier 3 is the reviewer's per-change dig-in — Tier 4 is the implementer's grounded step-by-step.

---

## Tier 1 — Objective & worthwhileness

- **Problem**: The logging module lives under `src/utils/` alongside unrelated helpers, so it has no discoverable home for the observability concerns that are accruing around it (structured fields, future tracing/metrics hooks). On top of that, the class is named `Logger` but does structured logging — the name lies about the behavior, which causes readers to either underuse it (treating it as plain stdlib logging) or wrap it redundantly.
- **Why now**: Both issues compound every time a new caller imports the module: another grep for "logging" misses it under `utils`, another reader has to rediscover that `Logger` is structured. Fixing it later means fixing it across more call sites. There is no external deadline — the urgency is purely "the longer we wait, the more callers we drag along."
- **Success criteria**: `src/observability/log.py` exists and exposes `StructuredLogger`; every in-tree caller imports from the new path; importing the old `src.utils.log` path still works for one release but emits a `DeprecationWarning` pointing at the new path; the test suite passes; `grep -r "from src.utils.log"` in non-shim code returns zero hits; `grep -r "\bLogger\b" src/` returns zero hits to the old class name in non-shim code.
- **Risk surface**: (1) A caller imported `Logger` by name and is now silently using a shim re-export that no longer matches a type annotation or `isinstance` check. (2) The deprecation warning fires inside a hot path during tests and either spams output or gets swallowed by a warning filter, making the deprecation invisible.
- **Alternatives considered**: Rename in place under `src/utils/log.py` without moving. Dismissed — solves the misleading name but not the discoverability problem, and we'd repeat half this work the next time observability grows.

---

## Tier 2 — Approach & shape

- **Approach**: Create `src/observability/` as the new home, move the module's real contents there with the class renamed to `StructuredLogger`, and convert `src/utils/log.py` into a thin compatibility shim that re-exports from the new location and emits a `DeprecationWarning` on import.
- **Why this approach**: The shim is the only mechanism that lets external callers (and any in-tree code we miss) keep working for one release while still being loudly told to migrate. Moving the file and leaving nothing behind would break consumers we don't control; renaming without moving would leave the discoverability problem unsolved.
- **Why not a wildcard `from .observability.log import *` shim**: Wildcard re-exports lose the explicit alias from `Logger` → `StructuredLogger`. We need the old name to keep resolving in the shim, which requires an explicit alias line, not a star import.
- **Scope IN**:
  - New module `src/observability/__init__.py` + `src/observability/log.py` with renamed class.
  - Shim at `src/utils/log.py` that re-exports `StructuredLogger` and aliases it as `Logger`, raising `DeprecationWarning` on module import.
  - Update every in-tree caller to import from `src.observability.log` and use `StructuredLogger`.
  - Update tests to assert the new import path works AND that the shim emits the deprecation warning.
  - Update any developer-facing docs / README snippets that show the import path.
- **Scope OUT**:
  - Removing the shim. Tracked: follow-up issue tagged "remove-utils-log-shim" scheduled for the release after next.
  - Broader `src/observability/` design (tracing, metrics, exporters). Tracked: deferred, no ticket yet — call it out in the new `src/observability/__init__.py` docstring so the next contributor sees the open lane.
  - Refactoring the internals of `StructuredLogger` itself (field schema, sink configuration). Tracked: deferred — this PR is move + rename only.
- **Delivery**: One PR, one commit on a `refactor/observability-log-move` branch. Solo dev.
- **Done when**: `pytest` passes; `python -c "import warnings; warnings.simplefilter('error'); import src.utils.log"` raises `DeprecationWarning`; `python -c "from src.observability.log import StructuredLogger; print(StructuredLogger)"` prints the class; ripgrep for the old class name and old import path in non-shim code returns empty.

---

## Tier 3 — Per-change overview

### Change 1: Create `src/observability/` as the new home

- Add `src/observability/__init__.py` (empty or with a one-line module docstring naming the package's intent).
- Add `src/observability/log.py` containing the real implementation moved from `src/utils/log.py`.
- The `__init__.py` docstring acknowledges that observability is intentionally broader than logging today — leaves a marker for future tracing/metrics work without committing to it.
- **Why this matters for the objective**: A new package directory is the discoverable home the objective demands; without it, the rename alone wouldn't fix the "where does logging live" question.

### Change 2: Move the module via `git mv` and rename `Logger` → `StructuredLogger`

- Use `git mv src/utils/log.py src/observability/log.py` so history follows the file, then edit in place.
- Rename the class to `StructuredLogger` at the definition site and at every internal self-reference (factory functions, type hints, `__repr__`, docstrings).
- Update any module-level `__all__` if present.
- **Why this matters for the objective**: The rename is the half of the objective that fixes the lying name; doing it in the same move-commit keeps the diff coherent (reviewers see "moved + renamed" as one intent, not two scattered changes).

### Change 3: Convert `src/utils/log.py` into a deprecation shim

- New file contents: an explicit `from src.observability.log import StructuredLogger`, an alias line `Logger = StructuredLogger`, and a `warnings.warn(..., DeprecationWarning, stacklevel=2)` call at import time.
- The warning message names both the old path and the new path so a developer reading their test output gets a copy-pasteable fix.
- Shim has a top-of-file comment stating it exists for one release and pointing at the removal ticket.
- **Why this matters for the objective**: The shim is what lets us claim "backwards-compat for one release." Without the alias line for `Logger`, callers that imported by name break immediately; without the warning, the deprecation is silent and callers never migrate.

### Change 4: Update in-tree callers

- Every `from src.utils.log import Logger` (or `import src.utils.log`) becomes `from src.observability.log import StructuredLogger`.
- Every constructor call site `Logger(...)` becomes `StructuredLogger(...)`.
- Type hints referencing `Logger` follow the same rename.
- **Why this matters for the objective**: If we leave in-tree callers on the shim, our own test suite will emit the deprecation warning we just added — drowning the signal we want external callers to receive.

### Change 5: Tests for both the new path and the shim

- Existing tests update their import path to the new module.
- One new test asserts `from src.observability.log import StructuredLogger` succeeds and the class behaves identically to the pre-move class (a smoke-level instantiation + one log call is enough).
- One new test asserts that importing `src.utils.log` (in a fresh subprocess or with `importlib.reload` under `warnings.catch_warnings(record=True)`) emits exactly one `DeprecationWarning` whose message names the new path.
- **Why this matters for the objective**: The deprecation contract is load-bearing — if it silently stops firing in a future refactor, downstream callers will discover the breakage at removal time instead of now. The test pins the contract.

### Change 6: Docs / README sweep

- Update any code snippets in `README.md`, `docs/`, or developer-onboarding material that show `from src.utils.log import Logger`.
- If a CHANGELOG exists, add a "Deprecated" entry naming `src.utils.log` and the new path.
- **Why this matters for the objective**: Docs that still teach the old path will keep producing new callers on the deprecated import, defeating the migration.

### Counts / math anchoring scale

- Expected file touches: 1 new package dir (`src/observability/`), 1 moved-and-edited file (`src/observability/log.py`), 1 rewritten shim (`src/utils/log.py`), N caller files (count to be determined by a single ripgrep — see Tier 4 step 4), 1-2 test files, 1-3 doc files. Total typically 5-15 files in a generic project; if the ripgrep returns dozens, that itself is a useful signal that the rename is overdue.

### Honest debt

- The shim adds a file that exists solely to be deleted in one release. That's intentional debt, tracked at the OUT list above. The risk of forgetting to delete it is mitigated by the top-of-file comment plus the follow-up issue.
- We are NOT taking the opportunity to clean up the internals of `StructuredLogger` while we're in there. That's deliberate — mixing internal refactor into a move + rename muddies the diff. Tracked as deferred in Tier 2 OUT.

---

## Tier 4 — Implementer guide

### Step 1: Inventory the blast radius before touching anything

This step lands here because the size of the caller update (Change 4) and the doc sweep (Change 6) are both unknown until we measure them, and committing to a one-commit delivery requires knowing the diff size up front.

- Run `rg -n "from src\.utils\.log|import src\.utils\.log" src/ tests/` and save the file list — this is the Change 4 worklist.
- Run `rg -n "\bLogger\b" src/ tests/` and skim — most hits will be the class we're renaming, but flag any unrelated `Logger` (e.g. from a third-party library) so we don't accidentally rename them, because the rename is a literal text substitution and false positives would corrupt unrelated code.
- Run `rg -n "src\.utils\.log|from src/utils/log" README.md docs/ 2>/dev/null` to scope the doc sweep.
- Note the count of caller files; if it exceeds ~20, reconsider whether this still fits one commit or whether a "move + shim" commit followed by a "migrate callers" commit reads better, because a single 30-file diff can hide a regression in the move itself.

Checkpoint: a written list (in your scratchpad, not committed) of every file Change 4 and Change 6 will touch.

### Step 2: Create the new package skeleton

This step lands here because the move in Step 3 needs a destination directory that already exists; doing it as a separate logical action keeps the `git mv` in Step 3 visibly clean.

- Create `src/observability/__init__.py` with a one-line docstring along the lines of `"""Observability primitives. Currently houses structured logging; tracing/metrics are intentional future neighbors, not committed scope."""`.
- Do NOT pre-create `src/observability/log.py` as an empty file — the `git mv` in the next step needs the destination path to be absent so git records a rename rather than a delete+add, because git's rename detection is path-based at the destination.

Checkpoint: `ls src/observability/` shows only `__init__.py`.

### Step 3: Move and rename in one editing pass

This step lands here because doing the move and the class rename in the same editing pass produces one coherent "moved + renamed" diff, which is what reviewers actually need to verify intent.

- Run `git mv src/utils/log.py src/observability/log.py`. Do this with `git mv` specifically, not a copy, because reviewers and `git log --follow` rely on the rename being recorded.
- Open `src/observability/log.py` and rename `class Logger` to `class StructuredLogger`. Use a find-and-replace scoped to that file only — global rename would clobber unrelated `Logger` occurrences from Step 1's inventory.
- Update every self-reference inside the file: factory functions returning `Logger`, type hints (`-> Logger`, `: Logger`), `__repr__` output, docstrings, any `__all__` entry.
- Verify no leftover `Logger` token remains in `src/observability/log.py` by running `rg -n "\bLogger\b" src/observability/log.py` — expect zero hits, because any survivor is either a bug or unrelated code that shouldn't have been in this file.

Checkpoint: `python -c "from src.observability.log import StructuredLogger; StructuredLogger.__name__ == 'StructuredLogger' or exit(1)"` succeeds.

### Step 4: Write the deprecation shim at the old path

This step lands here because the shim must exist before the test suite runs against the new layout — otherwise any caller we haven't migrated yet will hard-fail with `ModuleNotFoundError` and we lose the ability to validate incrementally.

- Create a new `src/utils/log.py` with this shape (illustrative, not literal): a top-of-file comment stating the shim's purpose and removal target, an explicit `from src.observability.log import StructuredLogger`, an alias `Logger = StructuredLogger`, and a `warnings.warn(...)` call.
- Use `stacklevel=2` on the `warnings.warn` call, because `stacklevel=1` points at the warning's own line inside the shim, which is useless for the caller debugging which import to fix.
- Use `DeprecationWarning` specifically (not `FutureWarning` or a custom subclass), because `DeprecationWarning` is what Python's default warning filters and most CI configurations recognize as the standard "migrate by next release" signal.
- Warning message should name BOTH the old path AND the new path verbatim, e.g. `"src.utils.log is deprecated; import from src.observability.log instead. The shim will be removed in the next release."`, because a developer reading the warning in their test output should be able to copy-paste the fix without going to look up our docs.

Checkpoint: `python -W error::DeprecationWarning -c "import src.utils.log"` exits non-zero with a `DeprecationWarning` mentioning `src.observability.log`.

### Step 5: Migrate in-tree callers off the shim

This step lands here because we want OUR test suite running on the new path — if internal callers stay on the shim, every test run floods stdout with the deprecation warning we created for external callers.

- For each file in the Step 1 inventory, rewrite the import: `from src.utils.log import Logger` → `from src.observability.log import StructuredLogger`.
- For each `Logger(...)` constructor call and each `Logger` type hint in those files, rename to `StructuredLogger`. Scope each rename to the file currently being edited, because the project-wide `Logger` token may include unrelated matches per the Step 1 inventory.
- After editing all caller files, run `rg -n "from src\.utils\.log" src/ tests/` and expect zero hits outside `src/utils/log.py` itself, because any survivor will trigger the deprecation warning in CI.
- Run `rg -n "\bLogger\b" src/ tests/` and confirm every remaining hit is either (a) the alias line inside the shim, or (b) a flagged-as-unrelated hit from Step 1.

Checkpoint: `pytest -W error::DeprecationWarning` passes — the `-W error` flag promotes the deprecation warning to a failure, so any missed caller surfaces immediately.

### Step 6: Add the two contract tests

This step lands here because the deprecation contract is the riskiest invisible piece — without a test, a future refactor could silence the warning and we'd never notice until removal day.

- Add a test that imports `from src.observability.log import StructuredLogger`, instantiates it, and exercises one log call. This is a smoke test, not a behavioral re-verification — the behavioral tests already exist and were migrated in Step 5.
- Add a test that asserts importing `src.utils.log` emits exactly one `DeprecationWarning` whose message contains the string `src.observability.log`. Run the import in a subprocess OR use `importlib.reload` inside `warnings.catch_warnings(record=True)`, because Python caches module imports and a plain second import won't re-fire the warning.
- The shim test should assert the warning's `category is DeprecationWarning` specifically, because asserting on message text alone allows a future refactor to silently downgrade the warning class.

Checkpoint: `pytest tests/` passes including the two new tests; deliberately deleting the `warnings.warn` line in the shim causes the shim test to fail (validate this locally, then restore the line).

### Step 7: Sweep docs and changelog

This step lands here because docs that still teach `from src.utils.log import Logger` will keep producing new callers on the deprecated import — defeating the whole migration. It happens last because earlier steps may have surfaced doc references that weren't in the Step 1 inventory.

- Update import snippets in `README.md`, anything under `docs/`, and any docstrings in unrelated modules that name the old path or the old class.
- If `CHANGELOG.md` exists, add a `Deprecated` entry naming `src.utils.log` (deprecated, removal next release) and a `Changed` entry naming the rename `Logger` → `StructuredLogger`.
- Re-run the Step 1 ripgrep commands one final time across the whole repo (not just `src/` and `tests/`) to catch any straggler in scripts, examples, or notebooks.

Checkpoint: `rg "src\.utils\.log|class Logger\b|import Logger\b" -g '!src/utils/log.py'` returns empty.

### Critical files (patterns repeat; representative paths only)

- New: `src/observability/__init__.py`, `src/observability/log.py`.
- Shim: `src/utils/log.py` (rewritten in place).
- Callers: every file matching `rg -l "from src\.utils\.log|\bLogger\b" src/ tests/` from Step 1 — pattern-based, not enumerated.
- Tests: existing logging tests (import path update) plus one new file (or new cases in an existing file) for the two contract tests.
- Docs: `README.md`, `docs/**`, `CHANGELOG.md` if present.

### Reusable utilities (referenced, not reinvented)

- `warnings.warn` from the stdlib for the deprecation signal — do not roll a custom warning class.
- `warnings.catch_warnings(record=True)` + `warnings.simplefilter("always")` from the stdlib for the contract test — standard pattern for asserting on emitted warnings.
- `git mv` for the file relocation — not `mv` + `git add`, because git's rename detection is what makes `git log --follow` work for future readers.

### Hygiene constraints

- Use `git mv` for the relocation. A plain filesystem `mv` followed by `git add` records as delete + add and breaks history-following tools.
- One commit, on `refactor/observability-log-move`. Solo dev — no multi-PR ceremony.
- Commit message: name both the move AND the rename in the subject line (e.g. `refactor: move logging to src/observability and rename Logger -> StructuredLogger`) so the rename is visible in `git log --oneline` without expanding the diff.
- No AI co-author attribution in the commit message.
- Do NOT amend earlier commits to fold this in — keep the move/rename as its own commit so it's bisectable.
