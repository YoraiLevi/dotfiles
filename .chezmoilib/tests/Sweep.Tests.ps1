<#
    Unit tests for .chezmoilib/Invoke-ChezmoiReAddSweep.ps1.

    No real chezmoi invocations: a mock chezmoi (see helpers/New-MockChezmoi.ps1)
    records every call and returns deterministic output. No files are ever
    created in the real $HOME.

    The sweep translates chezmoi-style source paths (e.g. readonly_dot_foo)
    into destination paths (e.g. ~/.foo) to decide what to forget and what to
    re-add. We feed it a temp source tree with canonical markers, a matching
    temp destination tree, and assert it calls the mock with the expected
    arguments.
#>
BeforeAll {
    $helpers = Join-Path $PSScriptRoot 'helpers'
    $script:MakeMockChezmoi = Get-Item (Join-Path $helpers 'New-MockChezmoi.ps1')
    $script:MakeSourceTree  = Get-Item (Join-Path $helpers 'New-TestSourceTree.ps1')
}

Describe 'Invoke-ChezmoiReAddSweep' {

    BeforeEach {
        $script:tree  = & $script:MakeSourceTree.FullName
        $script:mock  = & $script:MakeMockChezmoi.FullName -Root (Join-Path $script:tree.Root 'bin')
        $script:sweep = Join-Path $script:tree.SourceDir '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1'
    }

    AfterEach {
        if ($script:tree) { & $script:tree.Cleanup }
    }

    Context 'recursive-forget.recursive-add marker' {
        It 'forgets managed files that vanished from the destination and adds the dir recursively' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_testdir'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-forget.recursive-add') -Value '' -NoNewline
            'content1' | Set-Content -LiteralPath (Join-Path $markerDir 'keep.txt')
            'content2' | Set-Content -LiteralPath (Join-Path $markerDir 'gone.txt')

            $destSub = Join-Path $script:tree.DestDir '.testdir'
            New-Item -ItemType Directory -Path $destSub -Force | Out-Null
            'content1' | Set-Content -LiteralPath (Join-Path $destSub 'keep.txt')
            # gone.txt intentionally missing from destination

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls = & $script:mock.GetCalls
            $forgets = @($calls | Where-Object { $_.command -eq 'forget' })
            $adds    = @($calls | Where-Object { $_.command -eq 'add'    })

            $forgets.Count | Should -Be 1
            ($forgets[0].argv -join ' ') | Should -Match 'gone\.txt'
            ($forgets[0].argv -join ' ') | Should -Match '--force'
            ($forgets[0].argv -join ' ') | Should -Not -Match 'keep\.txt'

            $adds.Count | Should -Be 1
            ($adds[0].argv -join ' ') | Should -Match '--recursive=true'
            ($adds[0].argv -join ' ') | Should -Match '\.testdir'
        }
    }

    Context 'recursive-add marker without forget' {
        It 'does not forget anything, adds the dir recursively' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_addonly'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-add') -Value '' -NoNewline
            'x' | Set-Content -LiteralPath (Join-Path $markerDir 'x.txt')

            New-Item -ItemType Directory -Path (Join-Path $script:tree.DestDir '.addonly') -Force | Out-Null
            # no files in destination - should not forget anything because there is
            # nothing in source that needs forgetting, and should still queue the
            # dir for a recursive add so new files are detected.

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls = & $script:mock.GetCalls
            $forgets = @($calls | Where-Object { $_.command -eq 'forget' })
            $adds    = @($calls | Where-Object { $_.command -eq 'add'    })

            $forgets.Count | Should -Be 0
            $adds.Count    | Should -Be 1
            ($adds[0].argv -join ' ') | Should -Match '--recursive=true'
        }
    }

    Context 'forget-only marker (recursive-forget, no recursive-add)' {
        It 'forgets missing files and does NOT queue any add for the directory' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_forgetonly'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-forget') -Value '' -NoNewline
            'content' | Set-Content -LiteralPath (Join-Path $markerDir 'gone.txt')

            $destSub = Join-Path $script:tree.DestDir '.forgetonly'
            New-Item -ItemType Directory -Path $destSub -Force | Out-Null
            # gone.txt intentionally absent from destination - should be forgotten

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls   = & $script:mock.GetCalls
            $forgets = @($calls | Where-Object { $_.command -eq 'forget' })
            $adds    = @($calls | Where-Object { $_.command -eq 'add'    })

            $forgets.Count | Should -Be 1 -Because 'the missing file must be forgotten'
            ($forgets[0].argv -join ' ') | Should -Match 'gone\.txt'
            $adds.Count | Should -Be 0 -Because 'a forget-only marker must never trigger a chezmoi add'
        }
    }

    Context 'marker dir whose destination does not exist' {
        It 'is skipped entirely (no forget, no add)' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_nonexistent'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-forget.recursive-add') -Value '' -NoNewline
            'x' | Set-Content -LiteralPath (Join-Path $markerDir 'only-in-source.txt')
            # intentionally no dest dir

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls = & $script:mock.GetCalls
            $calls | Where-Object { $_.command -in 'forget', 'add' } | Should -BeNullOrEmpty
        }
    }

    Context 'retry on transient BoltDB lock timeout' {
        It 'retries the add call once and succeeds when the second attempt is clean' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_retry'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-add') -Value '' -NoNewline
            New-Item -ItemType Directory -Path (Join-Path $script:tree.DestDir '.retry') -Force | Out-Null

            # Touch the file-based latch; the mock chezmoi will fail its next
            # `add` with a BoltDB lock-timeout message and then delete the
            # latch, so the sweep's second attempt succeeds.
            New-Item -ItemType File -Path $script:mock.FailPath -Force | Out-Null

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls = & $script:mock.GetCalls
            $adds  = @($calls | Where-Object { $_.command -eq 'add' })
            $adds.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'canonical attribute-ordering guardrail' {
        It 'throws when the source tree contains a dot_readonly_* directory' {
            New-Item -ItemType Directory -Path (Join-Path $script:tree.SourceDir 'dot_readonly_bogus') -Force | Out-Null

            { & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir } |
                Should -Throw -ExpectedMessage '*canonical order*'
        }
    }

    Context 'source-only files are not considered for forget' {
        It 'ignores zero-byte markers, *.tmpl files, and dotfiles' {
            $markerDir = Join-Path $script:tree.SourceDir 'readonly_dot_filtered'
            New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $markerDir '.chezmoi-re-add.recursive-forget.recursive-add') -Value '' -NoNewline
            New-Item -ItemType File -Path (Join-Path $markerDir '.keep') -Force | Out-Null
            'template' | Set-Content -LiteralPath (Join-Path $markerDir 'something.tmpl')
            '' | Set-Content -LiteralPath (Join-Path $markerDir '.gitignore')

            New-Item -ItemType Directory -Path (Join-Path $script:tree.DestDir '.filtered') -Force | Out-Null

            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls   = & $script:mock.GetCalls
            $forgets = @($calls | Where-Object { $_.command -eq 'forget' })
            $forgets.Count | Should -Be 0
        }
    }

    Context 'no markers anywhere' {
        It 'makes zero chezmoi invocations (aside from source-path probes if any)' {
            & $script:sweep -ChezmoiPath $script:mock.Path -SourceDir $script:tree.SourceDir -DestDir $script:tree.DestDir

            $calls = & $script:mock.GetCalls
            $calls | Where-Object { $_.command -in 'forget', 'add' } | Should -BeNullOrEmpty
        }
    }
}
