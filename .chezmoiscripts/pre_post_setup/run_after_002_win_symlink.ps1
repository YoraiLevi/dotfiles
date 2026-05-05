# run_after_002_win_symlink.ps1 — Windows: symlink live paths → %USERPROFILE%\.win (after apply)
#
# Canonical files under %USERPROFILE%\.win\USERPROFILE\** → symlinks under %USERPROFILE% (same relative path).
# Only files are linked (not directories). Existing non-symlink link paths are moved aside as *.bak.

if (-not $IsWindows) {
    exit 0
}

if (-not $env:USERPROFILE) {
    exit 0
}

# Returns the path of $FullPath relative to $Root (e.g. Documents\foo.txt), or $null if $FullPath is not under $Root.
# Used so each file under .win\USERPROFILE can be mirrored at the same relative path under %USERPROFILE%.
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

# For every file under $StoreRoot, creates a symlink at $SymlinkRoot\<same relative path> pointing at the file in the store.
# Skips when the desired path is already a symlink; backs up an existing regular file/dir to *.bak before replacing.
function Invoke-WinSymlinkFromWinStore {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,
        [Parameter(Mandatory)]
        [string]$SymlinkRoot
    )

    if (-not (Test-Path -LiteralPath $StoreRoot)) {
        return
    }

    Get-ChildItem -LiteralPath $StoreRoot -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = Get-RelativePathFromRoot -Root $StoreRoot -FullPath $_.FullName
        if ([string]::IsNullOrEmpty($rel)) {
            return
        }

        $linkPath = Join-Path $SymlinkRoot $rel
        $linkTarget = $_.FullName

        # Verbose line per file (same idea as echo "$rel" in run_after_001_wsl2_symlink.sh); use / for stable logs.
        Write-Output ($rel -replace '\\', '/')

        $null = New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($linkPath)) -Force -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $linkPath) {
            $item = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                return
            }
            Move-Item -LiteralPath $linkPath -Destination "$linkPath.bak" -Force
        }

        try {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $linkTarget -Force | Out-Null
        }
        catch {
            Write-Warning "could not link '$linkPath' → '$linkTarget': $_"
        }
    }
}

# Mirror canonical profile files from the store into the live profile tree.
$winRoot = Join-Path $env:USERPROFILE '.win'
Invoke-WinSymlinkFromWinStore -StoreRoot (Join-Path $winRoot 'USERPROFILE') -SymlinkRoot $env:USERPROFILE
