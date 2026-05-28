# Plan — Move logging to `src/observability/`, rename `Logger` → `StructuredLogger`, ship one-release back-compat shim

> Layered by reader depth. Tier 1 is the 60-second read. Tier 2 is the reviewer's dig-in. Tier 3 is the implementer's reference.

---

## Tier 1 — Summary (30-60 second read)

- **What ships**: logging module relocated to `src/observability/log.py`, the misnamed `Logger` class renamed to `StructuredLogger`, and a thin back-compat shim left at `src/utils/log.py` that re-exports from the new location and emits a `DeprecationWarning`.
- **What moves**: `src/utils/log.py` → `src/observability/log.py` via `git mv` so history follows; a new `src/observability/__init__.py` is added; the old path becomes a 5-10 line shim, not a deletion.
- **What gets renamed**: class `Logger` → `StructuredLogger` at the new location; a module-level alias `Logger = StructuredLogger` is kept (with deprecation warning on attribute access via `__getattr__`) for one release.
- **What gets fixed**: the name now matches behavior — the class produces structured (key=value / JSON) records, not plain log lines, so "Logger" was misleading every caller who read it.
- **What changes for users**: `from src.utils.log import Logger` still works for one release but warns; the recommended import becomes `from src.observability.log import StructuredLogger`; no runtime behavior changes, no log format changes, no config surface changes.
- **What's still paused / deferred**: removing the shim and the `Logger` alias is a follow-up scheduled for the release *after* this one; tracked in `ROADMAP.md` (or a `DEPRECATIONS.md` entry created by this PR).
- **Delivery**: solo dev, single PR, single commit on a branch named `refactor/observability-logging`.
- **Done when**: `pytest` is green, `python -c "from src.utils.log import Logger; Logger()"` prints a `DeprecationWarning`, and `python -c "from src.observability.log import StructuredLogger; StructuredLogger()"` runs clean.

---

## Tier 2 — High-level overview

### Change 1: Move the module to `src/observability/log.py`

- New package `src/observability/` is created with an `__init__.py` that re-exports `StructuredLogger` (and any other public names) so `from src.observability import StructuredLogger` also works.
- The file move uses `git mv src/utils/log.py src/observability/log.py` so blame and history follow — this matters for a module that's likely to be touched again.
- All first-party callers are updated in the same commit to import from the new path; the shim exists for third-party callers and any code outside the repo, not as an excuse to leave first-party callers stale.
- Rationale: `utils/` is a junk drawer; `observability/` names the concern. Future additions (metrics, tracing) land next to logging instead of scattering across `utils/`.

### Change 2: Rename `Logger` → `StructuredLogger`

- The class is renamed at the definition site in `src/observability/log.py`.
- A module-level `Logger = StructuredLogger` alias is kept at the new location too, but emits a `DeprecationWarning` when accessed (via module `__getattr__`) — this catches callers who imported `Logger` directly from the new path during the transition.
- All first-party usages of `Logger(` and `: Logger` and `-> Logger` are updated to `StructuredLogger` in the same commit.
- Rationale: the class emits structured records; calling it `Logger` collides with `logging.Logger` and misleads every reader. The rename is cheap now and gets cheaper the sooner it lands.

### Change 3: Back-compat shim at the old path

- `src/utils/log.py` is rewritten to a ~10-line shim that re-exports everything from `src.observability.log` and emits a single `DeprecationWarning` on module import.
- The warning message names both the old path and the new path and states the removal release (e.g. "remove in vNEXT+1").
- A `DEPRECATIONS.md` entry (or a `ROADMAP.md` bullet) records the removal milestone so the shim doesn't become permanent.
- Rationale: external callers (notebooks, sibling repos, anyone pinning to a tag) get one release to migrate without breakage. One release, not forever.

### Scope decisions (what's explicitly in vs out)

- IN: file move, class rename, first-party caller updates, shim at old path, deprecation warning on both old-path import and old-name access, deprecation entry in `DEPRECATIONS.md` / `ROADMAP.md`, tests updated to import from new path.
- IN: a single test that asserts the shim still works *and* emits `DeprecationWarning` — this is the contract for the back-compat promise.
- OUT: removing the shim — that's the follow-up release; tracked as a `DEPRECATIONS.md` row with a target version.
- OUT: changing log format, log level handling, sinks, or config schema — pure refactor, behavior unchanged.
- OUT: introducing `metrics/` or `tracing/` modules alongside — `observability/` is created with just `log.py` for now; expansion is a future PR.
- OUT: updating downstream repos / notebooks — they get the shim and a deprecation warning; their owners migrate on their own clock.

### Counts anchoring scale

- 1 file moved (`src/utils/log.py` → `src/observability/log.py`).
- 1 file added (`src/observability/__init__.py`).
- 1 file rewritten as shim (`src/utils/log.py`).
- 1 class renamed (`Logger` → `StructuredLogger`), with one alias kept at each location.
- N caller files updated (grep `from src.utils.log` and `Logger\b` in `src/` and `tests/` to get exact count before starting — expect 5-30 in a typical project).
- 1 docs entry added (`DEPRECATIONS.md` row or `ROADMAP.md` bullet).
- 1 test added (shim still works + emits warning).

### Why one PR (not three)

- Solo dev. No external reviewer queue to amortize across multiple PRs.
- The three changes are tightly coupled: moving without renaming leaves the misleading name in the new home; renaming without the shim breaks external callers; the shim only makes sense after the move. Splitting them would force the same context-switch three times.
- The diff is mechanical (one move, one rename, N import updates, one shim) — small enough to review in one sitting.

---

## Tier 3 — Implementer guide

### Step 1: Inventory the blast radius

[Do this before touching anything so Step 4 has a concrete checklist.]

- Run `grep -rn "from src.utils.log" src/ tests/` and save the file list.
- Run `grep -rn "import src.utils.log" src/ tests/` and append.
- Run `grep -rnE "\bLogger\b" src/ tests/` and filter out unrelated `logging.Logger` references; save the list of files that reference the project's `Logger`.
- Note: the union of these three lists is the caller set. Expect overlap.

Checkpoint: you have a written list of every file that needs an import update or a name update. If the list is empty, abort — something is wrong with the search.

### Step 2: Create the new package and move the file

[Move first, edit second — keeps history clean and the rename diff isolated.]

- Create `src/observability/__init__.py` with a single re-export: `from src.observability.log import StructuredLogger` (plus any other public names the old module exposed — check `__all__` if present, otherwise check what callers actually import).
- Run `git mv src/utils/log.py src/observability/log.py`. Do not `cp` + `rm` — that loses history.
- Commit nothing yet; this is one commit at the end.

Checkpoint: `git status` shows the rename as a rename (not as delete + add), and `src/observability/__init__.py` exists.

### Step 3: Rename the class at its new home

[Class rename lives in the moved file; do it now while the file is the only thing open.]

- In `src/observability/log.py`, rename `class Logger` to `class StructuredLogger`.
- At the bottom of the file, add the deprecation hook for the old name:
  - Define `_DEPRECATED_NAMES = {"Logger": "StructuredLogger"}`.
  - Define `def __getattr__(name): ...` that checks `_DEPRECATED_NAMES`, emits `warnings.warn(f"{name} is deprecated; use {new}", DeprecationWarning, stacklevel=2)`, and returns the new symbol. Raise `AttributeError` otherwise so unrelated typos still fail loudly.
- Inside `src/observability/log.py` itself, update any internal self-references (e.g. `cls: Logger`, `-> Logger`, `Logger.__init__`) to `StructuredLogger`.

Checkpoint: `python -c "from src.observability.log import StructuredLogger; print(StructuredLogger)"` runs clean; `python -W error::DeprecationWarning -c "from src.observability.log import Logger"` raises (proving the warning fires).

### Step 4: Update first-party callers

[Now that the new module is stable, sweep callers in one pass using the Step 1 inventory.]

- For each file in the Step 1 inventory:
  - Replace `from src.utils.log import Logger` with `from src.observability.log import StructuredLogger`.
  - Replace `from src.utils.log import ...` with `from src.observability.log import ...` for any other imported names.
  - Replace bare `Logger(` constructor calls, `: Logger` annotations, and `-> Logger` return types with `StructuredLogger`.
  - Leave any reference to `logging.Logger` (stdlib) alone.
- If the project uses `ruff` or `isort`, run it across the touched files so import order doesn't drift.

Checkpoint: `grep -rn "from src.utils.log" src/ tests/` returns nothing (callers all migrated); `grep -rnE "\bLogger\b" src/ tests/` returns only references to `logging.Logger` or to the deprecated alias inside the shim.

### Step 5: Write the back-compat shim at the old path

[Recreate `src/utils/log.py` as a shim — the `git mv` removed it, this step re-adds it as a different file.]

- Create `src/utils/log.py` with this exact shape (literal contents will look like):
  - A module docstring stating "Deprecated location; import from `src.observability.log` instead. Removal scheduled for vNEXT+1."
  - `import warnings`
  - `warnings.warn("src.utils.log is deprecated; import from src.observability.log instead. This shim will be removed in vNEXT+1.", DeprecationWarning, stacklevel=2)`
  - `from src.observability.log import *  # noqa: F401,F403`
  - Explicit `from src.observability.log import StructuredLogger` and the deprecation alias `Logger = StructuredLogger` so star-import isn't load-bearing.
- Pick the actual removal version (e.g. "v2.0.0" or "the release after this one") and put it in both the docstring and the warning message — vague deprecations get ignored.

Checkpoint: `python -W default -c "from src.utils.log import Logger; print(Logger.__name__)"` prints `StructuredLogger` and the deprecation warning is visible on stderr.

### Step 6: Record the deprecation

[Without a removal pointer, the shim becomes permanent.]

- If `DEPRECATIONS.md` exists, add a row: old path + old name → new path + new name, with the target removal version.
- If not, add a bullet under a "Deprecations" heading in `ROADMAP.md` (or `CHANGELOG.md`'s Unreleased section) with the same info.
- The entry must name the *version* the shim is removed in, not a date.

Checkpoint: `grep -rn "src.utils.log" DEPRECATIONS.md ROADMAP.md CHANGELOG.md 2>/dev/null` finds the entry.

### Step 7: Add a test that locks in the back-compat contract

[The shim's whole job is to keep working *and* warn. Test both halves.]

- Add `tests/test_observability_log_shim.py` (or wherever the project keeps tests) with two cases:
  - `test_old_import_still_works`: imports `Logger` from `src.utils.log`, asserts it's the same class object as `StructuredLogger` from `src.observability.log`.
  - `test_old_import_warns`: uses `pytest.warns(DeprecationWarning, match="src.observability.log")` to confirm the import emits the warning.
- Update any existing logging tests that imported from `src.utils.log` to import from `src.observability.log` (they should already be covered by Step 4, but double-check).

Checkpoint: `pytest tests/test_observability_log_shim.py -v` passes both cases; `pytest` full suite passes.

### Step 8: Commit and push

[One commit, declarative message.]

- Stage everything: `git add src/observability/ src/utils/log.py tests/ DEPRECATIONS.md ROADMAP.md` (adjust to what actually changed).
- Commit message (subject + body):
  - Subject: `refactor(observability): move log module, rename Logger -> StructuredLogger, ship deprecation shim`
  - Body bullets: what moved, what renamed, that the old path is a shim with a `DeprecationWarning`, the removal version, and a pointer to the `DEPRECATIONS.md` entry.
- Push to `refactor/observability-logging` and open the PR.

Checkpoint: `git log -1 --stat` shows the rename as a rename (not delete+add) and the shim as an added file.

### Critical files (patterns repeat; representative paths only)

- `src/observability/log.py` — moved module, holds `StructuredLogger` + module-level `__getattr__` deprecation hook.
- `src/observability/__init__.py` — re-exports the public names so `from src.observability import StructuredLogger` works.
- `src/utils/log.py` — the shim; ~10 lines, emits `DeprecationWarning` on import, re-exports from new location.
- Caller files — anywhere `grep -rn "from src.utils.log\|^import src.utils.log\|\bLogger\b" src/ tests/` matches; typical hotspots are `src/*/main.py`, `src/*/app.py`, request/middleware files, and CLI entrypoints.
- `tests/test_observability_log_shim.py` — locks the back-compat contract.
- `DEPRECATIONS.md` / `ROADMAP.md` / `CHANGELOG.md` — wherever the project tracks deprecations; pick the one that already exists, don't invent a new file.

### Reusable utilities (referenced, not reinvented)

- `warnings.warn(..., DeprecationWarning, stacklevel=2)` — stdlib; the `stacklevel=2` is important so the warning points at the caller, not at the shim itself.
- Module-level `__getattr__` (PEP 562, Python 3.7+) — the right tool for "deprecate a name within a module"; do not use a metaclass or import-time monkeypatch.
- `pytest.warns(DeprecationWarning, match=...)` — stdlib `warnings`-aware context manager pytest exposes; use this rather than rolling a `warnings.catch_warnings()` block by hand.
- `git mv` — required for history preservation; `cp` + `rm` defeats `git log --follow`.

### Commit hygiene notes

- One commit on this PR. If the inventory in Step 1 turns up surprises (50+ callers, a dynamic import via `importlib`, a vendored copy of the module), pause and re-scope before continuing rather than splitting the commit.
- Do not include AI co-author attribution in the commit trailer unless the project's existing log already does.
- The commit subject is the contract: `refactor(observability):` signals to future-you (or to a `git log --grep`) that this is the move/rename, not an unrelated logging change.

---

## Meta — prompt template for future tiered plans

Reusable across projects. Paste one of these into a future prompt to get this same three-tier format.

### Minimal trigger

- `Plan this as a tiered plan: Tier 1 summary, Tier 2 overview, Tier 3 implementer guide. Bullets only, no tables. Solo dev — one PR.`

### Full spec

- Three tiers, progressive disclosure: Tier 1 is a 60-second skim (5-7 bullets covering what ships / what moves / what gets fixed / what changes for users / what's deferred / delivery / done-when).
- Tier 2 is the reviewer's dig-in: one bulleted section per major change with shape + rationale, plus cross-cutting sections for scope (explicit IN/OUT with pointers for OUT items), counts anchoring scale, and a "why one PR" justification.
- Tier 3 is the implementer guide: numbered steps, each with a one-sentence ordering rationale, bulleted action items naming specific file paths, exact edits when non-obvious, and a Checkpoint line per step with the verification command.
- Plus in Tier 3: a "Critical files" pattern list (representative paths, not exhaustive), a "Reusable utilities" list (existing helpers/stdlib to call rather than reinvent), and any commit-hygiene constraints (e.g. `git mv` for history, AI co-author rules).
- Style: bullets only, no tables, no prose paragraphs longer than three sentences, declarative voice, honest about asymmetries, no multi-PR splits for solo devs, explicit scope discipline.
