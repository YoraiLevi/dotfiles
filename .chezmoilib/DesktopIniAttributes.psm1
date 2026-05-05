<#
.SYNOPSIS
  Windows desktop.ini attribute helpers for chezmoi-managed folders.

.INTENT
  Explorer expects customized folders to use a hidden+system desktop.ini and a
  read-only, non-hidden parent directory. We apply that with attrib.

.WHY TWO ENTRY STYLES
  - Set-DesktopIniAttributes / Remove-DesktopIniAttributes: paths under the
    chezmoi source tree (names may use chezmoi attribute prefixes).
  - *-AtLocalPath: already-resolved Windows paths (e.g. under %USERPROFILE%).

.WHY DUAL ATTRIB PASS
  Live profile desktop.ini may be a symlink into %USERPROFILE%\.win\USERPROFILE.
  attrib must be applied consistently on the path you open and on the symlink
  terminal when that differs.

.SEE ALSO
  run_after_010_setperm_desktopini.ps1, run_before_010_unsetperm_desktopini.ps1,
  run_after_002_win_symlink.ps1 (mirrors .win\USERPROFILE into the profile).
#>
Import-Module (Join-Path $PSScriptRoot ConvertTo-LocalPath.psm1)
Import-Module (Join-Path $PSScriptRoot Convert-ChezmoiAttributeString.psm1)

$ErrorActionPreference = "Stop"

# Guard for callers that require CHEZMOI_* (message text may predate env renames).
function Test-ChezmoiEnvVars {
    if (($null -eq $ENV:CHEZMOI_SOURCE_DIR) -or ($null -eq $ENV:CHEZMOI_DEST_DIR)) {
        throw "CHEZMOI_WORKING_TREE and CHEZMOI_DEST_DIR environment variables must be set"
    }
}

# Ensures *-AtLocalPath is only used with a desktop.ini leaf (case-insensitive).
function Assert-LocalDesktopIniLeaf {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $leaf = [IO.Path]::GetFileName($Path)
    if (-not $leaf.Equals('desktop.ini', [StringComparison]::OrdinalIgnoreCase)) {
        throw "File '$Path' is not a desktop.ini file"
    }
}

# Returns the final filesystem path after following file symlinks (reparse points).
# Uses ResolveLinkTarget when available, else walks .Target with a depth cap.
function Resolve-FinalPathForAttrib {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('FullName')]
        [string]$DesktopIniPath
    )
    process {
        $current = [IO.Path]::GetFullPath($DesktopIniPath)
        if (-not (Test-Path -LiteralPath $current)) {
            return $current
        }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item -is [IO.FileInfo] -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            try {
                $resolved = $item.ResolveLinkTarget($true)
                if ($null -ne $resolved) {
                    return [IO.Path]::GetFullPath($resolved.FullName)
                }
            }
            catch {
                # Fall through to Target walk
            }
        }
        $guard = 0
        while ($guard++ -lt 64) {
            $i = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (-not ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return [IO.Path]::GetFullPath($i.FullName)
            }
            $tgt = $i.Target
            if ($null -eq $tgt) {
                return [IO.Path]::GetFullPath($i.FullName)
            }
            $next = if ($tgt -is [string[]]) { $tgt[0] } else { $tgt }
            if ([string]::IsNullOrEmpty($next)) {
                return [IO.Path]::GetFullPath($i.FullName)
            }
            if (-not [IO.Path]::IsPathRooted($next)) {
                $next = Join-Path $i.DirectoryName $next
            }
            $current = [IO.Path]::GetFullPath($next)
        }
        throw "Resolve-FinalPathForAttrib: symlink depth or cycle exceeded for '$DesktopIniPath'"
    }
}

# Set recipe per path pass: parent attrib +r -h, file +h +s. Runs on the literal
# path then again on Resolve-FinalPathForAttrib when different (both attrib lines
# stay in the same try/catch per pass).
function Set-DesktopIniAttributesAtLocalPath {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('FullName')]
        [string]$DesktopIniPath
    )
    process {
        Assert-LocalDesktopIniLeaf $DesktopIniPath
        $applyPass = {
            param([string]$FileFullPath)
            try {
                $localFile = Get-Item -LiteralPath $FileFullPath -Force -ErrorAction Stop
                attrib +r -h ($localFile.Directory.FullName)
                attrib +h +s ($localFile.FullName)
            }
            catch {
                Write-Error $_
            }
        }
        $firstItem = Get-Item -LiteralPath $DesktopIniPath -Force -ErrorAction Stop
        $first = [IO.Path]::GetFullPath($firstItem.FullName)
        & $applyPass $first
        $terminal = [IO.Path]::GetFullPath((Resolve-FinalPathForAttrib -DesktopIniPath $first))
        if (-not $first.Equals($terminal, [StringComparison]::OrdinalIgnoreCase)) {
            & $applyPass $terminal
        }
    }
}

# Remove recipe: file attrib -s -h only; dual pass when symlink terminal differs.
function Remove-DesktopIniAttributesAtLocalPath {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('FullName')]
        [string]$DesktopIniPath
    )
    process {
        Assert-LocalDesktopIniLeaf $DesktopIniPath
        $applyPass = {
            param([string]$FileFullPath)
            try {
                $localFile = Get-Item -LiteralPath $FileFullPath -Force -ErrorAction Stop
                attrib -s -h ($localFile.FullName)
            }
            catch {
                Write-Error $_
            }
        }
        $firstItem = Get-Item -LiteralPath $DesktopIniPath -Force -ErrorAction Stop
        $first = [IO.Path]::GetFullPath($firstItem.FullName)
        & $applyPass $first
        $terminal = [IO.Path]::GetFullPath((Resolve-FinalPathForAttrib -DesktopIniPath $first))
        if (-not $first.Equals($terminal, [StringComparison]::OrdinalIgnoreCase)) {
            & $applyPass $terminal
        }
    }
}

# Chezmoi source path: validate desktop.ini name, ConvertTo-LocalPath, then Remove-*AtLocalPath.
function Remove-DesktopIniAttributes {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$chezmoiPath
    )
    process {
        $chezmoiItem = Get-Item -Path $chezmoiPath -Force -ErrorAction Stop
        if ((Convert-ChezmoiAttributeString $chezmoiItem.Name) -ne "desktop.ini") {
            throw "File $chezmoiPath is not a desktop.ini file"
        }
        $localFilePath = ConvertTo-LocalPath $chezmoiPath
        Remove-DesktopIniAttributesAtLocalPath -DesktopIniPath $localFilePath
    }
}

# Chezmoi source path: validate desktop.ini name, ConvertTo-LocalPath, then Set-*AtLocalPath.
function Set-DesktopIniAttributes {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$chezmoiPath
    )
    process {
        $chezmoiItem = Get-Item -Path $chezmoiPath -Force -ErrorAction Stop
        if ((Convert-ChezmoiAttributeString $chezmoiItem.Name) -ne "desktop.ini") {
            throw "File $chezmoiPath is not a desktop.ini file"
        }
        $localFilePath = ConvertTo-LocalPath $chezmoiPath
        Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $localFilePath
    }
}

# Public API surface for scripts and reviewers (avoid implicit export-all).
Export-ModuleMember -Function @(
    'Resolve-FinalPathForAttrib',
    'Set-DesktopIniAttributesAtLocalPath',
    'Remove-DesktopIniAttributesAtLocalPath',
    'Set-DesktopIniAttributes',
    'Remove-DesktopIniAttributes'
)
