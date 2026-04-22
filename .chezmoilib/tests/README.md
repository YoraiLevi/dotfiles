# chezmoi re-add Pester suite

Tests that the custom `re-add` pipeline (pre-hook + sweep) behaves correctly
both when invoked interactively by a user shell and when invoked as a
subprocess (as the `ChezmoiSync` Windows service does).

## Layout

```
.chezmoilib/tests/
    Invoke-PesterSuite.ps1        # runner
    Sweep.Tests.ps1               # unit tests for Invoke-ChezmoiReAddSweep.ps1
    PreHook.Tests.ps1             # unit tests for .chezmoihooks/re-add/pre.ps1
    Integration.Tests.ps1         # end-to-end tests (real chezmoi, real git)
    helpers/
        New-MockChezmoi.ps1       # fake chezmoi shim that records calls
        New-TestSourceTree.ps1    # ephemeral temp source + dest pair
    README.md
```

## Running

### Unit tests only (default, no side effects)

```powershell
pwsh -NoProfile -File .\Invoke-PesterSuite.ps1
```

The unit tests do not call the real `chezmoi.exe` and do not touch
`$HOME`. They build a temp source tree with the canonical `.chezmoilib/`
modules, stub out `chezmoi.exe` with a mock that records every invocation, and
assert on the mock log.

### Full suite including integration tests

```powershell
pwsh -NoProfile -File .\Invoke-PesterSuite.ps1 -IncludeIntegration
```

Integration tests call the real `chezmoi re-add` against the real source
tree and `$HOME`. Each test case briefly creates a `_pester_*.ps1` file
under `~/.powershell/`, pulls it into source via `chezmoi re-add`, deletes
it, and pulls the deletion back into source again. Net effect in the source
tree: zero. Net effect in git history: one add commit + one remove commit
per test, pushed to `origin/master` because `git.autoAdd/autoCommit/autoPush`
are on.

If you don't want those commits, run only the unit tests.

### Running a single file or test

```powershell
Invoke-Pester -Path .\Sweep.Tests.ps1
Invoke-Pester -Path .\Integration.Tests.ps1 -Tag Integration
```

## What each test file covers

| File                   | Scope                                                      |
|------------------------|------------------------------------------------------------|
| `Sweep.Tests.ps1`      | `Invoke-ChezmoiReAddSweep.ps1` - the marker-file logic: forget missing files, add new files, routing to recursive vs non-recursive add, retry-on-lock-timeout, canonical attribute-ordering guardrail |
| `PreHook.Tests.ps1`    | `.chezmoihooks/re-add/pre.ps1` - guardrail, `--dry-run` propagation, sweep invocation with correct env-populated parameters |
| `Integration.Tests.ps1`| Real `chezmoi re-add` round-trip (add + forget) in both the interactive shell and a service-style subprocess; idempotence (a second re-add with no changes produces no commits) |

## Adding a test

- Write helpers in `helpers/` and dot-source or invoke them from tests.
- Unit tests should build their world inside the temp tree produced by
  `New-TestSourceTree.ps1` and assert against the mock chezmoi log from
  `New-MockChezmoi.ps1`.
- Integration tests should always use the `New-PesterFixture` /
  `Remove-PesterLeftovers` helpers in `Integration.Tests.ps1` so cleanup
  survives failures, and should be tagged `Integration`.

## Prerequisites

- Pester 5.0 or later (`Install-Module Pester -Scope CurrentUser`).
- `pwsh.exe` on `PATH` (PowerShell 7+).
- Real chezmoi on `PATH` or at `C:\Users\devic\.local\bin\chezmoi.exe`
  (only required for the integration tests).
