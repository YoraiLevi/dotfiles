<#
.SYNOPSIS
  Post-apply: set Windows attributes on every managed desktop.ini.

.DESCRIPTION
  Path A — CHEZMOI_SOURCE_DIR: recurse desktop.ini, Set-DesktopIniAttributes
  (chezmoi path -> ConvertTo-LocalPath -> attrib; handles symlink terminal).

  Path B — Windows only, if %USERPROFILE%\.win\USERPROFILE exists: recurse
  desktop.ini in that store, map each to the same relative path under
  %USERPROFILE%, and Set-DesktopIniAttributesAtLocalPath when that live file
  exists. Pairs with run_after_002_win_symlink.ps1 (symlinks store -> profile).

  Relative path: prefer [IO.Path]::GetRelativePath; on older runtimes fall back
  to Get-RelativePathFromRoot (same prefix rule as run_after_002_win_symlink).
#>
Import-Module (Join-Path $ENV:CHEZMOI_SOURCE_DIR .chezmoilib\DesktopIniAttributes.psm1)

# Path A: chezmoi source tree
Get-ChildItem -Path $ENV:CHEZMOI_SOURCE_DIR -Filter desktop.ini -Recurse | ForEach-Object {
    Set-DesktopIniAttributes $_.FullName
}

# Path B: profile copies mirrored from .win\USERPROFILE (literal desktop.ini scan; no chezmoi name conversion)
if ($IsWindows -and $env:USERPROFILE) {
    $storeRoot = Join-Path $env:USERPROFILE '.win\USERPROFILE'
    if (Test-Path -LiteralPath $storeRoot) {
        # Fallback when [IO.Path]::GetRelativePath is missing; same root-prefix rule as run_after_002_win_symlink.ps1
        function Get-RelativePathFromRoot {
            param(
                [Parameter(Mandatory)]
                [string]$Root,
                [Parameter(Mandatory)]
                [string]$FullPath
            )
            $r = [System.IO.Path]::GetFullPath($Root.TrimEnd('\') + '\')
            $f = [System.IO.Path]::GetFullPath($FullPath)
            if (-not $f.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
                return $null
            }
            return $f.Substring($r.Length).TrimStart('\')
        }

        Get-ChildItem -LiteralPath $storeRoot -Filter desktop.ini -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $null
            try {
                $rel = [IO.Path]::GetRelativePath($storeRoot, $_.FullName)
            }
            catch {
                $rel = Get-RelativePathFromRoot -Root $storeRoot -FullPath $_.FullName
            }
            if ([string]::IsNullOrEmpty($rel)) {
                return
            }
            $profileIni = Join-Path $env:USERPROFILE $rel
            if (Test-Path -LiteralPath $profileIni) {
                Set-DesktopIniAttributesAtLocalPath -DesktopIniPath $profileIni
            }
        }
    }
}
