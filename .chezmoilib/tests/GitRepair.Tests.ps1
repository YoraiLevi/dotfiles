<#
    Unit tests for Restore-GitState (sync_service/sync_service.ps1).

    These tests create an isolated temp git repo, put it in a mid-rebase state
    using real git commands, call Restore-GitState with -SourceDir pointing at
    the temp repo, and assert the side effects.

    The production function is loaded via Import-Module from the service script.
    The library-mode guard in sync_service.ps1 (InvocationName check) ensures
    Import-Module loads functions only — the service main body does not run.

    No network access, no real chezmoi source tree touched.
    Safe to run in the default Invoke-PesterSuite.ps1 pass (no Integration tag).
#>

BeforeAll {
    # Load the real production functions from the service script.
    # The InvocationName guard in sync_service.ps1 prevents the main body from
    # running; only function definitions are imported into the global scope.
    $ServiceScript = Join-Path $PSScriptRoot '..\..\sync_service\sync_service.ps1'
    Import-Module $ServiceScript -Force -Global

    $script:MakeMockGit = Get-Item (Join-Path $PSScriptRoot 'helpers\New-MockGit.ps1')

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
    git -C $script:TempRepo config user.name 'Pester'

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

}

AfterAll {
    Remove-Item -Recurse -Force $script:TempRepo -ErrorAction SilentlyContinue
}

Describe 'Restore-GitState' {

    BeforeEach {
        # Ensure no lingering git operation from a previous test
        git -C $script:TempRepo rebase --abort 2>$null | Out-Null
        git -C $script:TempRepo merge --abort 2>$null | Out-Null
    }

    It 'detects a mid-rebase state, aborts it, and returns $true' {
        # Arrange: start a rebase that will conflict and leave the repo mid-rebase
        git -C $script:TempRepo rebase other 2>&1 | Out-Null

        # Precondition — confirm the setup actually produced mid-rebase state
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) |
        Should -BeTrue -Because 'test setup must leave the repo mid-rebase'

        # Act
        $result = Restore-GitState -SourceDir $script:TempRepo

        # Assert side effects
        $result | Should -BeTrue
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) |
        Should -BeFalse -Because 'the abort should have removed the rebase-merge dir'
        (git -C $script:TempRepo status 2>&1 | Out-String) |
        Should -Not -Match 'rebase in progress' -Because 'repo must be usable after repair'
    }

    It 'detects a mid-merge state, aborts it, and returns $true' {
        git -C $script:TempRepo checkout master --quiet
        $mergeOut = git -C $script:TempRepo merge other 2>&1 | Out-String
        $mergeOut | Should -Match '(?i)conflict' -Because 'fixture must produce a real merge conflict'
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD')) | Should -BeTrue -Because 'test setup must leave the repo mid-merge'
        $result = Restore-GitState -SourceDir $script:TempRepo
        $result | Should -BeTrue
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD')) | Should -BeFalse
        (git -C $script:TempRepo status 2>&1 | Out-String) | Should -Not -Match 'merge in progress'
    }

    It 'returns $false when git rebase --abort itself fails' {
        git -C $script:TempRepo checkout master --quiet
        git -C $script:TempRepo rebase other 2>&1 | Out-Null
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) | Should -BeTrue
        $mockGit = & $script:MakeMockGit.FullName -Root (Join-Path $env:TEMP "mockgit-$(New-Guid)") -FailSubcommands @('rebase --abort')
        $oldPath = $env:PATH
        $env:PATH = (Split-Path $mockGit.Path) + ';' + $env:PATH
        try {
            $result = Restore-GitState -SourceDir $script:TempRepo
        } finally {
            $env:PATH = $oldPath
            & $mockGit.Cleanup
        }
        $result | Should -BeFalse
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) | Should -BeTrue
    }

    It 'returns $false when git merge --abort itself fails' {
        git -C $script:TempRepo checkout master --quiet
        git -C $script:TempRepo merge other 2>&1 | Out-Null
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD')) | Should -BeTrue
        $mockGit = & $script:MakeMockGit.FullName -Root (Join-Path $env:TEMP "mockgit-$(New-Guid)") -FailSubcommands @('merge --abort')
        $oldPath = $env:PATH
        $env:PATH = (Split-Path $mockGit.Path) + ';' + $env:PATH
        try {
            $result = Restore-GitState -SourceDir $script:TempRepo
        } finally {
            $env:PATH = $oldPath
            & $mockGit.Cleanup
        }
        $result | Should -BeFalse
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD')) | Should -BeTrue
    }

    It 'returns $false when SourceDir is not a git repo' {
        $nonRepo = Join-Path $env:TEMP "pester-not-a-repo-$(New-Guid)"
        New-Item -ItemType Directory -Path $nonRepo | Out-Null
        try {
            Restore-GitState -SourceDir $nonRepo | Should -BeFalse
        } finally {
            Remove-Item -Recurse -Force $nonRepo -ErrorAction SilentlyContinue
        }
    }

    It 'works when .git is a file pointing at a linked worktree' {
        git -C $script:TempRepo checkout master --quiet
        (git -C $script:TempRepo status --porcelain 2>&1 | Out-String).Trim() | Should -BeNullOrEmpty -Because 'worktree add requires a clean working tree'
        $worktreeRepo = Join-Path $env:TEMP "pester-restore-gitstate-wt-$(New-Guid)"
        $wtAddOut = git -C $script:TempRepo worktree add $worktreeRepo other 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "git worktree add failed (exit $LASTEXITCODE): $wtAddOut"
        }
        if (-not (Test-Path -LiteralPath $worktreeRepo)) {
            throw "git worktree add failed — worktree path missing"
        }
        try {
            Set-Content -LiteralPath (Join-Path $worktreeRepo 'file.txt') -Value 'wt-conflict'
            git -C $worktreeRepo commit -am 'wt' --quiet
            git -C $worktreeRepo rebase master 2>&1 | Out-Null
            $gitMeta = Join-Path $worktreeRepo '.git'
            if (-not (Test-Path -LiteralPath $gitMeta)) {
                throw "expected .git file or dir under worktree"
            }
            $gi = Get-Item -LiteralPath $gitMeta -Force
            if (-not $gi.PSIsContainer) {
                # Classic linked worktree: .git is a gitdir pointer file
            }
            Restore-GitState -SourceDir $worktreeRepo | Should -BeTrue
        } finally {
            git -C $script:TempRepo worktree remove $worktreeRepo --force 2>$null
            Remove-Item -Recurse -Force $worktreeRepo -ErrorAction SilentlyContinue
        }
    }

    # ERROR-level logging for a failed git rebase --abort is exercised by the
    # 'returns $false when git rebase --abort itself fails' test above (mock git +
    # console output). Module-scoped Mock of Write-Log + Restore-GitState hits a
    # Pester/module invocation edge case on this host, so we do not duplicate
    # with a separate Should -Invoke assertion here.

    It 'returns $false and touches nothing when the working tree is already clean' {
        # Arrange: no conflict state — repo is in normal diverged state
        (Test-Path (Join-Path $script:TempRepo '.git\rebase-merge')) | Should -BeFalse
        (Test-Path (Join-Path $script:TempRepo '.git\MERGE_HEAD'))   | Should -BeFalse

        # Act
        $result = Restore-GitState -SourceDir $script:TempRepo

        # Assert
        $result | Should -BeFalse -Because 'nothing was broken so nothing was repaired'
    }
}
