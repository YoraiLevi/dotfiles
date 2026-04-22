<#
.SYNOPSIS
    Build a minimal chezmoi-looking source tree in a temp directory.

.DESCRIPTION
    Returns an object describing the temp source + destination pair:
        - SourceDir : temp dir containing a copy of the real .chezmoilib/ modules
                      plus any test-supplied marker directories.
        - DestDir   : temp dir that represents a fake $HOME for the sweep to
                      diff against.
        - Cleanup() : recursively removes both directories.

    The real .chezmoilib/ modules (Invoke-ChezmoiReAddSweep.ps1,
    ConvertTo-LocalPath.psm1, Convert-ChezmoiAttributeString.psm1) are copied
    into SourceDir so the sweep can Import-Module them from its relative path.

    SourceDir is created with the canonical layout:

        <SourceDir>/.chezmoilib/
            Invoke-ChezmoiReAddSweep.ps1
            ConvertTo-LocalPath.psm1
            Convert-ChezmoiAttributeString.psm1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = [IO.Path]::Combine([IO.Path]::GetTempPath(), "chezmoi-tests-$([guid]::NewGuid().ToString('N'))")
$src  = Join-Path $root 'source'
$dest = Join-Path $root 'dest'
$lib  = Join-Path $src '.chezmoilib'
New-Item -ItemType Directory -Path $src, $dest, $lib -Force | Out-Null

$repoLib = Join-Path $PSScriptRoot '..' '..'
$repoLib = (Resolve-Path $repoLib).Path
foreach ($name in @(
        'Invoke-ChezmoiReAddSweep.ps1',
        'ConvertTo-LocalPath.psm1',
        'Convert-ChezmoiAttributeString.psm1'
    )) {
    Copy-Item -LiteralPath (Join-Path $repoLib $name) -Destination (Join-Path $lib $name) -Force
}

[pscustomobject]@{
    Root      = $root
    SourceDir = $src
    DestDir   = $dest
    Cleanup   = {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }.GetNewClosure()
}
