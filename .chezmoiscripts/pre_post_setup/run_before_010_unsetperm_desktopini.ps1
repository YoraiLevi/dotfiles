<#
.SYNOPSIS
  Pre-apply: clear system/hidden on desktop.ini so chezmoi can replace them.

.DESCRIPTION
  Path A — CHEZMOI_SOURCE_DIR: Remove-DesktopIniAttributes per file
  (-ErrorAction Continue for best-effort).

  Path B — Same as run_after_010_setperm_desktopini.ps1: for each desktop.ini
  under %USERPROFILE%\.win\USERPROFILE, clear attributes on the matching path
  under %USERPROFILE% when it exists (Remove-DesktopIniAttributesAtLocalPath).
#>
Import-Module (Join-Path $ENV:CHEZMOI_SOURCE_DIR .chezmoilib\DesktopIniAttributes.psm1)

# Path A: chezmoi source tree
Get-ChildItem -Path $ENV:CHEZMOI_SOURCE_DIR -Filter desktop.ini -Recurse | ForEach-Object {
    Remove-DesktopIniAttributes $_.FullName -ErrorAction Continue
}

# Path B: profile tree (see run_after_010 header)
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
                Remove-DesktopIniAttributesAtLocalPath -DesktopIniPath $profileIni -ErrorAction Continue
            }
        }
    }
}
