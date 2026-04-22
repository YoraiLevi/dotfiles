<#
    End-to-end integration tests for the re-add pipeline.

    These tests invoke the REAL chezmoi binary against the REAL chezmoi source
    tree and destination ($HOME), exactly as users and the ChezmoiSync service
    invoke it. They therefore:
        - touch files in the user's $HOME briefly
        - produce one pair of git commits per test case (one add, one remove)
        - push those commits to origin (because git.autoAdd/autoCommit/autoPush
          are enabled in the normal chezmoi config)

    They self-clean: each test creates a unique `_pester_*` file inside a
    chezmoi-managed marker directory, runs a re-add to pull it into source,
    asserts, then deletes it and runs another re-add to forget it. AfterEach
    sweeps any leftover files from both locations on failure.

    Tagged 'Integration' - skip with `-ExcludeTag Integration` if you don't
    want the git side effects.
#>
BeforeAll {
    $script:ChezmoiExe = (Get-Command chezmoi.exe -ErrorAction SilentlyContinue).Source
    if (-not $script:ChezmoiExe) { $script:ChezmoiExe = 'C:\Users\devic\.local\bin\chezmoi.exe' }
    $script:SourceDir = (& $script:ChezmoiExe source-path | Out-String).Trim()
    # Destination is the chezmoi default (the user's home) - we use a child of
    # ~/.powershell because it is covered by a recursive-forget.recursive-add
    # marker in the real source tree, so re-add will actually pick up files
    # dropped there.
    $script:DestMarkerDir   = Join-Path $HOME '.powershell'
    $script:SourceMarkerDir = Join-Path $script:SourceDir 'readonly_dot_powershell'
    if (-not (Test-Path -LiteralPath $script:DestMarkerDir))   { throw "Expected marker destination $script:DestMarkerDir to exist." }
    if (-not (Test-Path -LiteralPath $script:SourceMarkerDir)) { throw "Expected marker source $script:SourceMarkerDir to exist." }

    # Pester 5 scopes function definitions inside BeforeAll to the describe so
    # they are reachable from It and AfterEach. Defining them at script-top
    # level is NOT enough because Pester 5 re-parses the file in a fresh
    # runspace per container.
    function script:New-PesterFixture {
        $ts   = Get-Date -Format 'yyyyMMddHHmmssfff'
        $name = "_pester_${ts}.ps1"
        [pscustomobject]@{
            Name     = $name
            DestPath = Join-Path $script:DestMarkerDir $name
            SrcPath  = Join-Path $script:SourceMarkerDir $name
        }
    }

    function script:Remove-PesterLeftovers {
        Get-ChildItem -LiteralPath $script:DestMarkerDir   -Filter '_pester_*.ps1' -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $script:SourceMarkerDir -Filter '_pester_*.ps1' -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Describe 'chezmoi re-add end-to-end' -Tag Integration {

    AfterEach {
        # Defensive cleanup in case the test failed partway through. A final
        # chezmoi re-add will catch any source-side leftovers as forgets.
        Remove-PesterLeftovers
        & $script:ChezmoiExe re-add 2>&1 | Out-Null
        Remove-PesterLeftovers
    }

    Context 'interactive invocation (this shell)' {

        It 'round-trips a NEW file from destination into source via `chezmoi re-add`' {
            $fx = New-PesterFixture
            Set-Content -LiteralPath $fx.DestPath -Value "# pester $(Get-Date -Format o)" -Encoding UTF8

            & $script:ChezmoiExe re-add 2>&1 | Out-Null

            Test-Path -LiteralPath $fx.SrcPath | Should -BeTrue -Because 're-add should pull the new destination file into source state'
        }

        It 'round-trips a DELETED destination file out of source (forget) via `chezmoi re-add`' {
            $fx = New-PesterFixture
            Set-Content -LiteralPath $fx.DestPath -Value "# pester $(Get-Date -Format o)" -Encoding UTF8
            & $script:ChezmoiExe re-add 2>&1 | Out-Null
            Test-Path -LiteralPath $fx.SrcPath | Should -BeTrue

            Remove-Item -LiteralPath $fx.DestPath -Force
            & $script:ChezmoiExe re-add 2>&1 | Out-Null

            Test-Path -LiteralPath $fx.SrcPath  | Should -BeFalse -Because 're-add should forget the missing destination file from source'
            Test-Path -LiteralPath $fx.DestPath | Should -BeFalse
        }
    }

    Context 'service-style subprocess (pwsh -NoProfile -NonInteractive)' {

        It 'round-trips a new file via a subprocess that mimics the ChezmoiSync service' {
            $fx = New-PesterFixture
            Set-Content -LiteralPath $fx.DestPath -Value "# pester-service $(Get-Date -Format o)" -Encoding UTF8

            $pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
            if (-not $pwshExe) { $pwshExe = 'pwsh.exe' }
            & $pwshExe -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -Command "& '$script:ChezmoiExe' re-add" 2>&1 | Out-Null

            Test-Path -LiteralPath $fx.SrcPath | Should -BeTrue
        }

        It 'forgets a file via a subprocess that mimics the ChezmoiSync service' {
            $fx = New-PesterFixture
            Set-Content -LiteralPath $fx.DestPath -Value "# pester-service $(Get-Date -Format o)" -Encoding UTF8

            $pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
            if (-not $pwshExe) { $pwshExe = 'pwsh.exe' }
            & $pwshExe -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -Command "& '$script:ChezmoiExe' re-add" 2>&1 | Out-Null
            Test-Path -LiteralPath $fx.SrcPath | Should -BeTrue

            Remove-Item -LiteralPath $fx.DestPath -Force
            & $pwshExe -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -Command "& '$script:ChezmoiExe' re-add" 2>&1 | Out-Null

            Test-Path -LiteralPath $fx.SrcPath  | Should -BeFalse
            Test-Path -LiteralPath $fx.DestPath | Should -BeFalse
        }
    }

    Context 'idempotence' {

        It 'running chezmoi re-add twice with no changes leaves the source tree clean' {
            & $script:ChezmoiExe re-add 2>&1 | Out-Null
            $before = (& $script:ChezmoiExe git -- rev-parse HEAD | Out-String).Trim()

            & $script:ChezmoiExe re-add 2>&1 | Out-Null
            $after  = (& $script:ChezmoiExe git -- rev-parse HEAD | Out-String).Trim()

            $after | Should -Be $before -Because 'a second re-add with no filesystem changes must not create new commits'
        }
    }
}
