<#
    Unit tests for .chezmoihooks/re-add/pre.ps1.

    The hook:
        1. Enforces canonical chezmoi attribute ordering on the source tree.
        2. Delegates the forget/add sweep to .chezmoilib/Invoke-ChezmoiReAddSweep.ps1.

    We substitute a trivial stub sweep script into the temp source tree and run
    the hook with controlled $ENV:CHEZMOI_SOURCE_DIR / CHEZMOI_DEST_DIR /
    CHEZMOI_EXECUTABLE / CHEZMOI_ARGS. Then we inspect the stub's log to
    assert that the hook passed the correct arguments.
#>
BeforeAll {
    $script:MakeSourceTree = Get-Item (Join-Path $PSScriptRoot 'helpers\New-TestSourceTree.ps1')
    $script:RepoPreHook    = (Resolve-Path (Join-Path $PSScriptRoot '..\..\.chezmoihooks\re-add\pre.ps1')).Path
}

Describe 're-add pre-hook' {

    BeforeEach {
        $script:tree = & $script:MakeSourceTree.FullName
        # Drop a stub sweep on top of the real one so we can observe the call
        # without running the real (heavy) implementation. The stub writes its
        # arguments and environment snapshot to a predictable log path.
        $script:stubLog = Join-Path $script:tree.Root 'sweep-stub.log'
        $sweepStub = @"
param(
    [string]`$ChezmoiPath,
    [string]`$SourceDir,
    [string]`$DestDir,
    [switch]`$DryRun
)
`$entry = [pscustomobject]@{
    ChezmoiPath = `$ChezmoiPath
    SourceDir   = `$SourceDir
    DestDir     = `$DestDir
    DryRun      = [bool]`$DryRun
}
Add-Content -LiteralPath '$($script:stubLog -replace "'", "''")' -Value (`$entry | ConvertTo-Json -Compress -Depth 5)
"@
        Set-Content -LiteralPath (Join-Path $script:tree.SourceDir '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1') `
                    -Value $sweepStub -Encoding UTF8
    }

    AfterEach {
        if ($script:tree) { & $script:tree.Cleanup }
        Remove-Item Env:\CHEZMOI_SOURCE_DIR -ErrorAction SilentlyContinue
        Remove-Item Env:\CHEZMOI_DEST_DIR   -ErrorAction SilentlyContinue
        Remove-Item Env:\CHEZMOI_EXECUTABLE -ErrorAction SilentlyContinue
        Remove-Item Env:\CHEZMOI_ARGS      -ErrorAction SilentlyContinue
    }

    It 'invokes the sweep script with env-populated source/dest/executable' {
        $ENV:CHEZMOI_SOURCE_DIR = $script:tree.SourceDir
        $ENV:CHEZMOI_DEST_DIR   = $script:tree.DestDir
        $ENV:CHEZMOI_EXECUTABLE = 'C:\fake\chezmoi.exe'
        $ENV:CHEZMOI_ARGS       = 'chezmoi re-add'

        & $script:RepoPreHook

        Test-Path -LiteralPath $script:stubLog | Should -BeTrue
        $call = (Get-Content -LiteralPath $script:stubLog | Select-Object -First 1) | ConvertFrom-Json
        $call.ChezmoiPath | Should -Be 'C:\fake\chezmoi.exe'
        $call.SourceDir   | Should -Be $script:tree.SourceDir
        $call.DestDir     | Should -Be $script:tree.DestDir
        $call.DryRun      | Should -Be $false
    }

    It 'forwards --dry-run from CHEZMOI_ARGS to the sweep' {
        $ENV:CHEZMOI_SOURCE_DIR = $script:tree.SourceDir
        $ENV:CHEZMOI_DEST_DIR   = $script:tree.DestDir
        $ENV:CHEZMOI_EXECUTABLE = 'C:\fake\chezmoi.exe'
        $ENV:CHEZMOI_ARGS       = 'chezmoi --dry-run re-add'

        & $script:RepoPreHook

        $call = (Get-Content -LiteralPath $script:stubLog | Select-Object -First 1) | ConvertFrom-Json
        $call.DryRun | Should -Be $true
    }

    It 'throws on non-canonical attribute ordering (dot_readonly_*)' {
        $ENV:CHEZMOI_SOURCE_DIR = $script:tree.SourceDir
        $ENV:CHEZMOI_DEST_DIR   = $script:tree.DestDir
        $ENV:CHEZMOI_EXECUTABLE = 'C:\fake\chezmoi.exe'
        $ENV:CHEZMOI_ARGS       = 'chezmoi re-add'

        New-Item -ItemType Directory -Path (Join-Path $script:tree.SourceDir 'dot_readonly_bogus') -Force | Out-Null

        { & $script:RepoPreHook } | Should -Throw -ExpectedMessage '*canonical order*'

        Test-Path -LiteralPath $script:stubLog | Should -BeFalse
    }

    It 'warns (but does not throw) if the sweep script is missing' {
        $ENV:CHEZMOI_SOURCE_DIR = $script:tree.SourceDir
        $ENV:CHEZMOI_DEST_DIR   = $script:tree.DestDir
        $ENV:CHEZMOI_EXECUTABLE = 'C:\fake\chezmoi.exe'
        $ENV:CHEZMOI_ARGS       = 'chezmoi re-add'
        Remove-Item -LiteralPath (Join-Path $script:tree.SourceDir '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1') -Force

        { & $script:RepoPreHook 3>&1 } | Should -Not -Throw
    }
}
