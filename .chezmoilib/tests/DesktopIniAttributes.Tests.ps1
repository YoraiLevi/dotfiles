<#
    Unit tests for .chezmoilib/DesktopIniAttributes.psm1 and the desktop.ini
    pre/post scripts (minimal script smoke).

    - Cross-platform: module exports, validation throws before attrib.
    - Windows only: real attrib + optional symlink dual-pass (skipped if symlink
      creation is not permitted).

    "Unhappy path" cases assert the module *rejects* bad input (Should -Throw);
    those tests are expected to pass — the suite fails if validation regresses.

    Optional: Describe 'DesktopIniAttributes — negative cases (deliberately red)'
    contains inverted assertions; keep -Skip:$true in CI. See # comments on each
    Describe/It for what is being exercised.
#>
BeforeAll {
    # Paths: tests/ -> .chezmoilib/ (module) and repo root (scripts under .chezmoiscripts/).
    $script:ModuleRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:DesktopIniModule = Join-Path $script:ModuleRoot 'DesktopIniAttributes.psm1'
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:RunAfter010 = Join-Path $script:RepoRoot '.chezmoiscripts\pre_post_setup\run_after_010_setperm_desktopini.ps1'
    $script:RunBefore010 = Join-Path $script:RepoRoot '.chezmoiscripts\pre_post_setup\run_before_010_unsetperm_desktopini.ps1'

    # Reload module per test; required because Pester 5 scopes isolate Describe blocks.
    function script:Import-DesktopIniModule {
        Import-Module $script:DesktopIniModule -Force
    }

    # Minimal folder + desktop.ini under %TEMP% for attrib experiments; returns Root/Parent/Ini paths.
    function script:New-TempIniFixture {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('pester-ini-' + [guid]::NewGuid().ToString('n'))
        $parent = Join-Path $root 'folder'
        $ini = Join-Path $parent 'desktop.ini'
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Set-Content -LiteralPath $ini -Value '[.ShellClassInfo]' -Encoding utf8
        [pscustomobject]@{
            Root   = $root
            Parent = $parent
            Ini    = $ini
        }
    }

    # Recursive delete of a temp fixture root (best-effort).
    function script:Remove-TempIniFixture {
        param([string]$Root)
        if ($Root -and (Test-Path -LiteralPath $Root)) {
            Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # True if $Attributes includes the given filesystem flag (Hidden, System, ReadOnly, ...).
    function script:Test-HasFlag {
        param(
            [System.IO.FileAttributes]$Attributes,
            [System.IO.FileAttributes]$Flag
        )
        [bool]($Attributes -band $Flag)
    }

    # One-shot probe: symlink tests run only if OS allows creating a file symlink without elevation.
    $script:CanSymlink = $false
    if ($IsWindows) {
        $t = Join-Path ([IO.Path]::GetTempPath()) ('pester-ini-sl-' + [guid]::NewGuid().ToString('n'))
        try {
            New-Item -ItemType Directory -Path $t -Force | Out-Null
            $tgt = Join-Path $t 'target.ini'
            'x' | Set-Content -LiteralPath $tgt
            $lnk = Join-Path $t 'link.ini'
            New-Item -ItemType SymbolicLink -LiteralPath $lnk -Target $tgt -Force | Out-Null
            $script:CanSymlink = $true
        }
        catch {
            $script:CanSymlink = $false
        }
        finally {
            if (Test-Path -LiteralPath $t) {
                Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Inverted assertions: enabled only when you set -Skip:$false. The example expects no throw on a bad
# leaf; production code throws, so this It *fails* — proving validation still works. Do not enable in CI.
Describe 'DesktopIniAttributes — negative cases (deliberately red)' -Skip:$true {

    BeforeEach { script:Import-DesktopIniModule }
    AfterEach {
        Remove-Module DesktopIniAttributes -Force -ErrorAction SilentlyContinue
    }

    # Tests the wrong hypothesis (Should -Not -Throw). With correct Assert-LocalDesktopIniLeaf, this fails.
    It 'WRONG: must throw — Set-DesktopIniAttributesAtLocalPath on readme.txt' {
        $readme = Join-Path ([IO.Path]::GetTempPath()) 'readme.txt'
        Set-Content -LiteralPath $readme -Value 'x'
        try {
            { Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $readme } | Should -Not -Throw
        }
        finally {
            Remove-Item -LiteralPath $readme -Force -ErrorAction SilentlyContinue
        }
    }
}

# Public API contract: Export-ModuleMember must match what scripts and callers may rely on.
Describe 'DesktopIniAttributes module exports' {

    BeforeEach { Import-DesktopIniModule }
    AfterEach {
        Remove-Module DesktopIniAttributes -Force -ErrorAction SilentlyContinue
    }

    # Guards against accidental export churn (rename/remove) on the five supported cmdlets.
    It 'exposes only the intended public commands' {
        $names = @(
            (Get-Command -Module DesktopIniAttributes).Name | Sort-Object
        )
        $names | Should -Be @(
            'Remove-DesktopIniAttributes',
            'Remove-DesktopIniAttributesAtLocalPath',
            'Resolve-FinalPathForAttrib',
            'Set-DesktopIniAttributes',
            'Set-DesktopIniAttributesAtLocalPath'
        )
    }

    # Internal helpers must stay private so sessions do not depend on undocumented commands.
    It 'does not export private helpers' {
        $m = Get-Module DesktopIniAttributes
        $m.ExportedFunctions.ContainsKey('Assert-LocalDesktopIniLeaf') | Should -BeFalse
        $m.ExportedFunctions.ContainsKey('Test-ChezmoiEnvVars') | Should -BeFalse
    }
}

# Cross-platform: Assert-LocalDesktopIniLeaf and Get-Item behavior; no attrib involved.
Describe 'DesktopIniAttributes unhappy paths (validation & missing files)' {

    BeforeEach { Import-DesktopIniModule }
    AfterEach {
        Remove-Module DesktopIniAttributes -Force -ErrorAction SilentlyContinue
    }

    # *-AtLocalPath must reject any path whose filename is not exactly desktop.ini (case-insensitive).
    It 'Set-DesktopIniAttributesAtLocalPath rejects a non-desktop.ini leaf' {
        $bad = Join-Path ([IO.Path]::GetTempPath()) 'not-desktop-ini.txt'
        { Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $bad } |
            Should -Throw '*desktop.ini*'
    }

    # Same rule for remove; "Desktop.INI.bak" is not a valid desktop.ini leaf.
    It 'Remove-DesktopIniAttributesAtLocalPath rejects wrong leaf case-insensitively' {
        $bad = Join-Path ([IO.Path]::GetTempPath()) 'Desktop.INI.bak'
        { Remove-DesktopIniAttributesAtLocalPath -DesktopIniPath $bad } |
            Should -Throw '*desktop.ini*'
    }

    # After leaf validation, Get-Item must fail for a non-existent directory/file (terminating error).
    It 'Set-DesktopIniAttributesAtLocalPath throws when the path does not exist (leaf is valid)' {
        $missing = Join-Path ([IO.Path]::GetTempPath()) ('ghost-' + [guid]::NewGuid().ToString('n'))
        $missingIni = Join-Path $missing 'desktop.ini'
        { Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $missingIni } |
            Should -Throw
    }

    # Resolve-FinalPathForAttrib short-circuits when Test-Path is false: returns GetFullPath string only.
    It 'Resolve-FinalPathForAttrib returns normalized path without throwing when file is missing' {
        $missingIni = Join-Path ([IO.Path]::GetTempPath()) ('no-dir-' + [guid]::NewGuid().ToString('n'))
        $missingIni = Join-Path $missingIni 'desktop.ini'
        { Resolve-FinalPathForAttrib -DesktopIniPath $missingIni } | Should -Not -Throw
        $out = Resolve-FinalPathForAttrib -DesktopIniPath $missingIni
        $out | Should -Be ([IO.Path]::GetFullPath($missingIni))
    }
}

# Real attrib.exe on Windows: verifies Explorer-oriented flags on a normal file (no symlink).
Describe 'DesktopIniAttributes Windows attrib' -Skip:(-not $IsWindows) {

    BeforeEach { Import-DesktopIniModule }
    AfterEach {
        Remove-Module DesktopIniAttributes -Force -ErrorAction SilentlyContinue
    }

    # Set recipe: parent directory ReadOnly + not Hidden; file Hidden + System (dual attrib in one pass).
    It 'Set-DesktopIniAttributesAtLocalPath applies +h +s to file and +r -h on parent' {
        $fx = New-TempIniFixture
        try {
            Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $fx.Ini -ErrorAction Stop
            $f = Get-Item -LiteralPath $fx.Ini -Force
            $p = Get-Item -LiteralPath $fx.Parent -Force
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::Hidden) | Should -BeTrue
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::System) | Should -BeTrue
            Test-HasFlag $p.Attributes ([IO.FileAttributes]::ReadOnly) | Should -BeTrue
            Test-HasFlag $p.Attributes ([IO.FileAttributes]::Hidden) | Should -BeFalse
        }
        finally {
            attrib -r -h $fx.Parent 2>$null
            attrib -s -h $fx.Ini 2>$null
            Remove-TempIniFixture $fx.Root
        }
    }

    # Remove recipe: only clears System/Hidden on the file (parent untouched by this test’s assertions).
    It 'Remove-DesktopIniAttributesAtLocalPath clears system and hidden on file' {
        $fx = New-TempIniFixture
        try {
            attrib +h +s $fx.Ini 2>$null
            Remove-DesktopIniAttributesAtLocalPath -DesktopIniPath $fx.Ini -ErrorAction Stop
            $f = Get-Item -LiteralPath $fx.Ini -Force
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::Hidden) | Should -BeFalse
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::System) | Should -BeFalse
        }
        finally {
            attrib -s -h $fx.Ini 2>$null
            Remove-TempIniFixture $fx.Root
        }
    }

    # Symlink resolution: output must equal the target file’s full path (not the link path).
    It 'Resolve-FinalPathForAttrib follows a symlink to the target file' -Skip:(-not $script:CanSymlink) {
        $fx = New-TempIniFixture
        try {
            Remove-Item -LiteralPath $fx.Ini -Force
            $targetIni = Join-Path $fx.Parent 'target.ini'
            Set-Content -LiteralPath $targetIni -Value 't' -Encoding utf8
            $linkIni = Join-Path $fx.Parent 'link.ini'
            New-Item -ItemType SymbolicLink -LiteralPath $linkIni -Target $targetIni -Force | Out-Null
            $term = Resolve-FinalPathForAttrib -DesktopIniPath $linkIni
            [IO.Path]::GetFullPath($term) | Should -Be ([IO.Path]::GetFullPath($targetIni))
        }
        finally {
            Remove-TempIniFixture $fx.Root
        }
    }

    # Dual-pass: profile-style link at ...\folder\desktop.ini -> ...\real\desktop.ini; both get H+S after Set.
    It 'dual-pass Set applies attrib to symlink path and terminal when they differ' -Skip:(-not $script:CanSymlink) {
        $fx = New-TempIniFixture
        try {
            Remove-Item -LiteralPath $fx.Ini -Force
            $realDir = Join-Path $fx.Root 'real'
            New-Item -ItemType Directory -Path $realDir -Force | Out-Null
            $targetIni = Join-Path $realDir 'desktop.ini'
            Set-Content -LiteralPath $targetIni -Value 't' -Encoding utf8
            $linkIni = Join-Path $fx.Parent 'desktop.ini'
            New-Item -ItemType SymbolicLink -LiteralPath $linkIni -Target $targetIni -Force | Out-Null

            Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $linkIni -ErrorAction Stop

            $tFile = Get-Item -LiteralPath $targetIni -Force
            $lFile = Get-Item -LiteralPath $linkIni -Force
            Test-HasFlag $tFile.Attributes ([IO.FileAttributes]::Hidden) | Should -BeTrue
            Test-HasFlag $tFile.Attributes ([IO.FileAttributes]::System) | Should -BeTrue
            Test-HasFlag $lFile.Attributes ([IO.FileAttributes]::Hidden) | Should -BeTrue
            Test-HasFlag $lFile.Attributes ([IO.FileAttributes]::System) | Should -BeTrue
        }
        finally {
            attrib -r -h $fx.Parent 2>$null
            attrib -r -h (Join-Path $fx.Root 'real') 2>$null
            attrib -s -h (Join-Path $fx.Parent 'desktop.ini') 2>$null
            attrib -s -h (Join-Path $fx.Root 'real\desktop.ini') 2>$null
            Remove-TempIniFixture $fx.Root
        }
    }
}

# Set-/Remove-DesktopIniAttributes: chezmoi source paths, ConvertTo-LocalPath, then *-AtLocalPath on dest.
Describe 'DesktopIniAttributes chezmoi-path entry points (Windows)' -Skip:(-not $IsWindows) {

    BeforeEach { Import-DesktopIniModule }
    AfterEach {
        Remove-Module DesktopIniAttributes -Force -ErrorAction SilentlyContinue
    }

    # Name check uses Convert-ChezmoiAttributeString on the leaf; notes.txt must throw before ConvertTo-LocalPath.
    It 'Remove-DesktopIniAttributes throws when the source name is not desktop.ini' {
        $src = Join-Path ([IO.Path]::GetTempPath()) ('czm-rm-' + [guid]::NewGuid().ToString('n'))
        $dst = Join-Path ([IO.Path]::GetTempPath()) ('czm-rmd-' + [guid]::NewGuid().ToString('n'))
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedDest = $env:CHEZMOI_DEST_DIR
        try {
            New-Item -ItemType Directory -Path $src, $dst -Force | Out-Null
            $other = Join-Path $src 'notes.txt'
            Set-Content -LiteralPath $other -Value 'x'
            $env:CHEZMOI_SOURCE_DIR = $src
            $env:CHEZMOI_DEST_DIR = $dst
            { Remove-DesktopIniAttributes -chezmoiPath $other } | Should -Throw '*desktop.ini*'
        }
        finally {
            Remove-TempIniFixture $src
            Remove-TempIniFixture $dst
            $env:CHEZMOI_SOURCE_DIR = $savedSource
            $env:CHEZMOI_DEST_DIR = $savedDest
        }
    }

    # Same name gate as Remove; Set-DesktopIniAttributes must not run attrib on non-desktop.ini leaves.
    It 'Set-DesktopIniAttributes throws when the source name is not desktop.ini' {
        $src = Join-Path ([IO.Path]::GetTempPath()) ('czm-src-' + [guid]::NewGuid().ToString('n'))
        $dst = Join-Path ([IO.Path]::GetTempPath()) ('czm-dst-' + [guid]::NewGuid().ToString('n'))
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedDest = $env:CHEZMOI_DEST_DIR
        try {
            New-Item -ItemType Directory -Path $src, $dst -Force | Out-Null
            $other = Join-Path $src 'notes.txt'
            Set-Content -LiteralPath $other -Value 'x'
            $env:CHEZMOI_SOURCE_DIR = $src
            $env:CHEZMOI_DEST_DIR = $dst
            { Set-DesktopIniAttributes -chezmoiPath $other } | Should -Throw '*desktop.ini*'
        }
        finally {
            Remove-TempIniFixture $src
            Remove-TempIniFixture $dst
            $env:CHEZMOI_SOURCE_DIR = $savedSource
            $env:CHEZMOI_DEST_DIR = $savedDest
        }
    }

    # End-to-end: source tree desktop.ini -> mapped dest path receives +h +s via Set-DesktopIniAttributes.
    It 'Set-DesktopIniAttributes maps source desktop.ini to dest and applies attrib' {
        $src = Join-Path ([IO.Path]::GetTempPath()) ('czm-src-' + [guid]::NewGuid().ToString('n'))
        $dst = Join-Path ([IO.Path]::GetTempPath()) ('czm-dst-' + [guid]::NewGuid().ToString('n'))
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedDest = $env:CHEZMOI_DEST_DIR
        try {
            New-Item -ItemType Directory -Path $src, $dst -Force | Out-Null
            $srcIni = Join-Path $src 'desktop.ini'
            $dstIni = Join-Path $dst 'desktop.ini'
            Set-Content -LiteralPath $srcIni -Value '[]' -Encoding utf8
            Set-Content -LiteralPath $dstIni -Value '[]' -Encoding utf8
            $env:CHEZMOI_SOURCE_DIR = $src
            $env:CHEZMOI_DEST_DIR = $dst
            Set-DesktopIniAttributes -chezmoiPath $srcIni -ErrorAction Stop
            $f = Get-Item -LiteralPath $dstIni -Force
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::Hidden) | Should -BeTrue
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::System) | Should -BeTrue
        }
        finally {
            attrib -r -h $dst 2>$null
            attrib -s -h (Join-Path $dst 'desktop.ini') 2>$null
            Remove-TempIniFixture $src
            Remove-TempIniFixture $dst
            $env:CHEZMOI_SOURCE_DIR = $savedSource
            $env:CHEZMOI_DEST_DIR = $savedDest
        }
    }
}

# Script integration: imports module from $env:CHEZMOI_SOURCE_DIR\.chezmoilib; exercises Path A + env restore.
Describe 'run_before_010_unsetperm_desktopini.ps1 smoke (Windows)' -Skip:(-not $IsWindows) {

    # Path A only: GCI source for desktop.ini -> Remove on dest; we pre-tag dest +h+s and assert they clear.
    It 'runs Path A and clears system/hidden on dest desktop.ini' {
        $src = Join-Path ([IO.Path]::GetTempPath()) ('czm-rb10-' + [guid]::NewGuid().ToString('n'))
        $dst = Join-Path ([IO.Path]::GetTempPath()) ('czm-rb10d-' + [guid]::NewGuid().ToString('n'))
        $dstIni = Join-Path $dst 'sub\desktop.ini'
        $lib = Join-Path $src '.chezmoilib'
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedDest = $env:CHEZMOI_DEST_DIR
        try {
            New-Item -ItemType Directory -Path $lib -Force | Out-Null
            foreach ($fn in @(
                    'DesktopIniAttributes.psm1',
                    'ConvertTo-LocalPath.psm1',
                    'Convert-ChezmoiAttributeString.psm1'
                )) {
                Copy-Item -LiteralPath (Join-Path $script:ModuleRoot $fn) -Destination (Join-Path $lib $fn)
            }
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            $srcIni = Join-Path $src 'sub\desktop.ini'
            New-Item -ItemType Directory -Path (Split-Path $srcIni) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path $dstIni) -Force | Out-Null
            Set-Content -LiteralPath $srcIni -Value '[]' -Encoding utf8
            Set-Content -LiteralPath $dstIni -Value '[]' -Encoding utf8
            attrib +h +s $dstIni 2>$null
            $env:CHEZMOI_SOURCE_DIR = $src
            $env:CHEZMOI_DEST_DIR = $dst
            & $script:RunBefore010
            $f = Get-Item -LiteralPath $dstIni -Force
            script:Test-HasFlag $f.Attributes ([IO.FileAttributes]::Hidden) | Should -BeFalse
            script:Test-HasFlag $f.Attributes ([IO.FileAttributes]::System) | Should -BeFalse
        }
        finally {
            attrib -s -h $dstIni 2>$null
            script:Remove-TempIniFixture $src
            script:Remove-TempIniFixture $dst
            $env:CHEZMOI_SOURCE_DIR = $savedSource
            $env:CHEZMOI_DEST_DIR = $savedDest
        }
    }

    # Import-Module line targets missing module path; with $ErrorActionPreference Stop the script must throw.
    It 'fails fast when CHEZMOI_SOURCE_DIR has no .chezmoilib (unhappy path)' {
        $badSrc = Join-Path ([IO.Path]::GetTempPath()) ('czm-badb-' + [guid]::NewGuid().ToString('n'))
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedEa = $ErrorActionPreference
        try {
            New-Item -ItemType Directory -Path $badSrc -Force | Out-Null
            $env:CHEZMOI_SOURCE_DIR = $badSrc
            {
                $ErrorActionPreference = 'Stop'
                & $script:RunBefore010
            } | Should -Throw
        }
        finally {
            $ErrorActionPreference = $savedEa
            script:Remove-TempIniFixture $badSrc
            $env:CHEZMOI_SOURCE_DIR = $savedSource
        }
    }
}

# Script integration: post-apply attrib; same temp .chezmoilib bundle pattern as run_before.
Describe 'run_after_010_setperm_desktopini.ps1 smoke (Windows)' -Skip:(-not $IsWindows) {

    # Path A: Set-DesktopIniAttributes on source ini -> dest sub\desktop.ini gets H+S (and parent +r -h).
    It 'runs Path A against a temp CHEZMOI_SOURCE_DIR with bundled .chezmoilib copies' {
        $src = Join-Path ([IO.Path]::GetTempPath()) ('czm-ra10-' + [guid]::NewGuid().ToString('n'))
        $dst = Join-Path ([IO.Path]::GetTempPath()) ('czm-ra10d-' + [guid]::NewGuid().ToString('n'))
        $dstIni = Join-Path $dst 'sub\desktop.ini'
        $lib = Join-Path $src '.chezmoilib'
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedDest = $env:CHEZMOI_DEST_DIR
        try {
            New-Item -ItemType Directory -Path $lib -Force | Out-Null
            foreach ($fn in @(
                    'DesktopIniAttributes.psm1',
                    'ConvertTo-LocalPath.psm1',
                    'Convert-ChezmoiAttributeString.psm1'
                )) {
                Copy-Item -LiteralPath (Join-Path $script:ModuleRoot $fn) -Destination (Join-Path $lib $fn)
            }
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
            $srcIni = Join-Path $src 'sub\desktop.ini'
            New-Item -ItemType Directory -Path (Split-Path $srcIni) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path $dstIni) -Force | Out-Null
            Set-Content -LiteralPath $srcIni -Value '[]' -Encoding utf8
            Set-Content -LiteralPath $dstIni -Value '[]' -Encoding utf8
            $env:CHEZMOI_SOURCE_DIR = $src
            $env:CHEZMOI_DEST_DIR = $dst
            & $script:RunAfter010
            $f = Get-Item -LiteralPath $dstIni -Force
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::Hidden) | Should -BeTrue
            Test-HasFlag $f.Attributes ([IO.FileAttributes]::System) | Should -BeTrue
        }
        finally {
            attrib -r -h (Split-Path $dstIni) 2>$null
            attrib -s -h $dstIni 2>$null
            Remove-TempIniFixture $src
            Remove-TempIniFixture $dst
            $env:CHEZMOI_SOURCE_DIR = $savedSource
            $env:CHEZMOI_DEST_DIR = $savedDest
        }
    }

    # Same as run_before unhappy test: missing .chezmoilib under CHEZMOI_SOURCE_DIR must surface as failure.
    It 'fails fast when CHEZMOI_SOURCE_DIR has no .chezmoilib (unhappy path)' {
        $badSrc = Join-Path ([IO.Path]::GetTempPath()) ('czm-bad-' + [guid]::NewGuid().ToString('n'))
        $savedSource = $env:CHEZMOI_SOURCE_DIR
        $savedEa = $ErrorActionPreference
        try {
            New-Item -ItemType Directory -Path $badSrc -Force | Out-Null
            $env:CHEZMOI_SOURCE_DIR = $badSrc
            {
                $ErrorActionPreference = 'Stop'
                & $script:RunAfter010
            } | Should -Throw
        }
        finally {
            $ErrorActionPreference = $savedEa
            script:Remove-TempIniFixture $badSrc
            $env:CHEZMOI_SOURCE_DIR = $savedSource
        }
    }
}
