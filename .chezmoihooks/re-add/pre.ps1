param()
# Why is the forget/add logic in re-add.pre instead of re-add.post:
#
#   chezmoi acquires its BoltDB persistent-state lock between the pre and post
#   hooks. Anything that shells out to `chezmoi forget`/`chezmoi add` from the
#   post hook will race the parent and time out with:
#     "chezmoi: timeout obtaining persistent state lock, is another instance of
#      chezmoi running?"
#   The pre hook runs before the lock is taken, so nested chezmoi calls are
#   safe. Do not move this back to post.ps1.
Write-Host $PSCommandPath -ForegroundColor Green
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $ENV:CHEZMOI_SOURCE_DIR .chezmoilib\ConvertTo-LocalPath.psm1)

# $ENV:CHEZMOI_ARGS is a single space-joined string (System.String), not an
# array. Splitting on whitespace and using -contains is the only way to
# reliably detect flags like --dry-run. The previous "-in $ENV:CHEZMOI_ARGS"
# check was a silent no-op because -in treats the string as a single element.
$chezmoiArgv = @()
if ($ENV:CHEZMOI_ARGS) {
    $chezmoiArgv = $ENV:CHEZMOI_ARGS -split '\s+' | Where-Object { $_ }
}

$params = @()
if (($chezmoiArgv -contains '--debug') -or ($chezmoiArgv -contains '-d')) {
    $params += '--debug'
}
if (($chezmoiArgv -contains '--verbose') -or ($chezmoiArgv -contains '-v')) {
    $params += '--verbose'
}
$IsDryRun = ($chezmoiArgv -contains '--dry-run') -or ($chezmoiArgv -contains '-n')
if ($IsDryRun) {
    $params += '--dry-run'
}

# Guardrail: fail fast if the source tree contains a directory or file whose
# chezmoi attribute prefixes are in non-canonical order. See:
#   https://www.chezmoi.io/reference/source-state-attributes/
# The canonical order is
#   encrypted_ / private_ / readonly_ / empty_ / executable_ / remove_ /
#   create_ / modify_ / run_ / symlink_ / dot_ / literal_
# so a name that begins with `dot_<one of those other prefixes>_` means the
# user (or a previous tool) rearranged the prefixes and chezmoi is now
# silently managing a bogus target. An earlier incident of this in this
# repository produced phantom ~/.readonly_powershell, ~/.readonly_vscode, and
# ~/.readonly_wsl2 directories and doubled source dirs.
$badOrderPattern = '^dot_(?:encrypted|private|readonly|empty|executable|remove|create|modify|run|symlink)_'
$badOrder = Get-ChildItem -Path $ENV:CHEZMOI_SOURCE_DIR -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $badOrderPattern }
if ($badOrder) {
    Write-Warning "Non-canonical chezmoi attribute ordering detected in source tree:"
    foreach ($bad in $badOrder) {
        Write-Warning "  $($bad.FullName)"
    }
    throw "Refusing to run re-add hook: rename the above entries so prefixes are in canonical order (e.g. readonly_dot_powershell, not dot_readonly_powershell)."
}

$SPECIAL_FILE_NAME_REGEX = '.chezmoi-re-add*'
$FORGET_PROPERTY_REGEX = '*.forget*'
$FORGET_RECURSIVE_PROPERTY_REGEX = '*.recursive-forget*'
$RECURSIVE_PROPERTY_REGEX = '*.recursive-add*'

$recursiveFiles = Get-ChildItem -Path "$ENV:CHEZMOI_SOURCE_DIR" -Filter $SPECIAL_FILE_NAME_REGEX -Recurse -Force -File
foreach ($recursiveFile in $recursiveFiles) {
    $chezmoiTrackedDir = $recursiveFile.Directory
    # Skip if the target dir does not exist on this machine.
    try {
        $localDirPath = ConvertTo-LocalPath $chezmoiTrackedDir.FullName -ErrorAction Stop
        $null = Get-Item -Path $localDirPath -ErrorAction Stop
    }
    catch {
        Write-Debug "Skipping $($chezmoiTrackedDir.FullName): local dir not found"
        continue
    }

    $do_recursive_forget = $recursiveFile.Name -like $FORGET_RECURSIVE_PROPERTY_REGEX
    $do_forget = ($recursiveFile.Name -like $FORGET_PROPERTY_REGEX) -or $do_recursive_forget
    $do_recursive_add = $recursiveFile.Name -like $RECURSIVE_PROPERTY_REGEX

    if ($do_forget) {
        $forget_params = $params.Clone()
        $chezmoiManagedFiles = Get-ChildItem -Path $chezmoiTrackedDir -Force -Recurse:$do_recursive_forget
        $filteredManagedFiles = $chezmoiManagedFiles | Where-Object {
            $_.Length -gt 0 -and
            -not $_.Name.EndsWith('.tmpl') -and
            -not ($_.Name -like $SPECIAL_FILE_NAME_REGEX)
        }
        Write-Debug "Found $($filteredManagedFiles.Count) managed files under $($chezmoiTrackedDir.FullName)"
        foreach ($managedFile in $filteredManagedFiles) {
            try {
                $localFilePath = ConvertTo-LocalPath $managedFile.FullName -ErrorAction Stop
            }
            catch {
                Write-Debug "Failed to convert $($managedFile.FullName) to a local path; skipping"
                Write-Warning $_
                continue
            }
            if (Test-Path -LiteralPath $localFilePath) {
                Write-Debug "Keep: $localFilePath still exists"
                continue
            }
            Write-Debug "Forget: $localFilePath no longer exists"
            & $ENV:CHEZMOI_EXECUTABLE forget $localFilePath @forget_params --force
        }
    }

    $add_params = $params.Clone()
    if ($do_recursive_add) {
        $add_params += '--recursive=true'
    }
    else {
        # Adds the directory entry only (not its children). This preserves the
        # chezmoi-managed directory metadata without pulling in new files
        # (important for dirs like ~/.local/bin where we explicitly do *not*
        # want auto-add -- see also .chezmoiignore.tmpl for externals).
        $add_params += '--recursive=false'
    }

    try {
        Write-Debug "chezmoi add $localDirPath $($add_params -join ' ')"
        & $ENV:CHEZMOI_EXECUTABLE add $localDirPath @add_params
    }
    catch {
        Write-Warning $_
    }
}
