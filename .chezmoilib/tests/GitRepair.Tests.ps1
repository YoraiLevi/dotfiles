<#
    Unit tests for Restore-GitState (sync_service/sync_service.ps1).

    These tests are fully self-contained: they create an isolated temp git repo,
    put it in a mid-rebase state using real git commands, call Restore-GitState
    with -SourceDir pointing at the temp repo, and assert the side effects.

    No network access, no real chezmoi source tree touched, no dot-sourcing of
    the service script. Restore-GitState is defined inline in BeforeAll because
    it has no service coupling — it is a pure git utility that only needs git.

    Safe to run in the default Invoke-PesterSuite.ps1 pass (no Integration tag).
#>

BeforeAll {
    # -------------------------------------------------------------------------
    # Function under test — exact body from sync_service.ps1, defined inline
    # so this test has no coupling to the service script's main body.
    # If the production function changes, update this copy and the test.
    # -------------------------------------------------------------------------
    function script:Restore-GitState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$ChezmoiPath,
            [string]$SourceDir = ''
        )
        if (-not $SourceDir) {
            $SourceDir = (& $ChezmoiPath source-path 2>$null | Out-String).Trim()
        }
        $gitDir   = Join-Path $SourceDir '.git'
        $inRebase = (Test-Path (Join-Path $gitDir 'rebase-merge')) -or
                    (Test-Path (Join-Path $gitDir 'rebase-apply'))
        $inMerge  = Test-Path (Join-Path $gitDir 'MERGE_HEAD')

        if ($inRebase) {
            git -C $SourceDir rebase --abort 2>&1 | Out-Null
            return $true
        }
        if ($inMerge) {
            git -C $SourceDir merge --abort 2>&1 | Out-Null
            return $true
        }
        return $false
    }

    # -------------------------------------------------------------------------
    # Temp git repo with a guaranteed conflict:
    #
    #   base: file.txt = "base"
    #          |
    #     ┌────┴────┐
    #   master    other
    #   "local"  "remote"   ← same file, different content
    # -------------------------------------------------------------------------
    $script:TempRepo = Join-Path $env:TEMP "pester-restore-gitstate-$(New-Guid)"
    git init $script:TempRepo --quiet
    git -C $script:TempRepo config user.email 'pester@test.local'
    git -C $script:TempRepo config user.name  'Pester'

    'base' | Set-Content (Join-Path $script:TempRepo 'file.txt')
    git -C $script:TempRepo add .
    git -C $script:TempRepo commit -m 'base' --quiet

    git -C $script:TempRepo checkout -b other --quiet
    'remote content' | Set-Content (Join-Path $script:TempRepo 'file.txt')
    git -C $script:TempRepo add .
    git -C $script:TempRepo commit -m 'other' --quiet

    git -C $script:TempRepo checkout master --quiet
    'local content' | Set-Content (Join-Path $script:TempRepo 'file.txt')
    git -C $script:TempRepo add .
    git -C $script:TempRepo commit -m 'local' --quiet

    $script:ChezmoiExe = (Get-Command chezmoi.exe -ErrorAction SilentlyContinue).Source
    if (-not $script:ChezmoiExe) { $script:ChezmoiExe = 'C:\Users\devic\.local\bin\chezmoi.exe' }
}

AfterAll {
    Remove-Item -Recurse -Force $script:TempRepo -ErrorAction SilentlyContinue
}

Describe 'Restore-GitState' {

    BeforeEach {
        # Ensure no lingering git operation from a previous test
        git -C $script:TempRepo rebase --abort 2>$null | Out-Null
        git -C $script:TempRepo merge  --abort 2>$null | Out-Null
    }

    It 'detects a mid-rebase state, aborts it, and returns $true' {
        # Arrange: start a rebase that will conflict and leave the repo mid-rebase
        git -C $script:TempRepo rebase other 2>&1 | Out-Null

        # Precondition — confirm the setup actually produced mid-rebase state
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) |
            Should -BeTrue -Because 'test setup must leave the repo mid-rebase'

        # Act
        $result = Restore-GitState -ChezmoiPath $script:ChezmoiExe -SourceDir $script:TempRepo

        # Assert side effects
        $result | Should -BeTrue
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) |
            Should -BeFalse -Because 'the abort should have removed the rebase-merge dir'
        (git -C $script:TempRepo status 2>&1 | Out-String) |
            Should -Not -Match 'rebase in progress' -Because 'repo must be usable after repair'
    }

    It 'returns $false and touches nothing when the working tree is already clean' {
        # Arrange: no conflict state — repo is in normal diverged state
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) | Should -BeFalse
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD'))   | Should -BeFalse

        # Act
        $result = Restore-GitState -ChezmoiPath $script:ChezmoiExe -SourceDir $script:TempRepo

        # Assert
        $result | Should -BeFalse -Because 'nothing was broken so nothing was repaired'
    }
}
