param()
Write-Host $PSCommandPath -ForegroundColor Green

Import-Module (Join-Path $ENV:CHEZMOI_WORKING_TREE .chezmoilib\ConvertTo-LocalPath.psm1)

# Uncomment to assist with debugging
# Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' } | ForEach-Object { Write-Debug $_.Name, $_.Value -ForegroundColor Yellow }

# https://www.chezmoi.io/reference/command-line-flags/global/
# --cache directory
# --color value
# -c, --config filename
# --config-format format
# -D, --destination directory
# -n, --dry-run
# --force
# --interactive
# -k, --keep-going
# --mode file | symlink
# --no-pager
# --no-tty
# -o, --output filename
# --persistent-state filename
# --progress value
# -S, --source directory
# --source-path
# # -R, --refresh-externals [value]
# # --use-builtin-age [bool]
# # --use-builtin-diff [bool]
# # --use-builtin-git [bool]
# -v, --verbose
# --version
# -w, --working-tree directory

# https://www.chezmoi.io/reference/command-line-flags/common/
# --age-recipient recipient
# --age-recipient-file recipient-file
# -x, --exclude types
# -f, --format json|yaml
# -h, --help
# -i, --include types
# --init
# -P, --parent-dirs
# -p, --path-style style
# -r, --recursive
# --tree

# https://www.chezmoi.io/reference/commands/re-add/
# Common flags
# -x, --exclude types
# -i, --include types
# -r, --recursive


$params = @()
if (("--debug" -in $ENV:CHEZMOI_ARGS) -or ("-d" -in $ENV:CHEZMOI_ARGS)) {
    $params += "--debug"
    # $DebugPreference = 'Continue' # these don't work in a file?
}
if (("--verbose" -in $ENV:CHEZMOI_ARGS) -or ("-v" -in $ENV:CHEZMOI_ARGS)) {
    $params += "--verbose"
}
if (("--dry-run" -in $ENV:CHEZMOI_ARGS) -or ("-n" -in $ENV:CHEZMOI_ARGS)) {
    $params += "--dry-run"
}

$SPECIAL_FILE_NAME_REGEX = '.chezmoi-re-add*'
$FORGET_PROPERTY_REGEX = '*.forget*'
$FORGET_RECURSIVE_PROPERTY_REGEX = '*.recursive-forget*'
$RECURSIVE_PROPERTY_REGEX = '*.recursive-add*'

$recursiveFiles = Get-ChildItem -Path "$ENV:CHEZMOI_WORKING_TREE" -Filter $SPECIAL_FILE_NAME_REGEX -Recurse -Force -File
foreach ($recursiveFile in $recursiveFiles) {
    $chezmoiTrackedDir = $recursiveFile.Directory
    # Verify that the local directory exists, else skip, we don't have anything to re-add or forget
    try {
        $localDirPath = Join-Path $ENV:CHEZMOI_DEST_DIR (Convert-ChezmoiAttributeString $chezmoiTrackedDir.Name)
        $null = Get-Item -Path $localDirPath -ErrorAction Stop
    }
    catch {
        Write-Debug "Failed to get directory path for $localDirPath"
        Write-Warning $_
        continue
    }
    $do_recursive_forget = $recursiveFile.Name -like $FORGET_RECURSIVE_PROPERTY_REGEX
    $do_forget = ($recursiveFile.Name -like $FORGET_PROPERTY_REGEX) -or $do_recursive_forget

    if ($do_forget) {
        $forget_params = $params.clone()

        $chezmoiManagedFiles = Get-ChildItem -Path $chezmoiTrackedDir -Force -Recurse:$do_recursive_forget # attempt recursive forget
        
        $filteredManagedFiles = $chezmoiManagedFiles | Where-Object { $_.Length -gt 0 -and -not $_.Name.EndsWith('.tmpl') -and -not ($_.Name -like $SPECIAL_FILE_NAME_REGEX) }
        Write-Debug "Found $($filteredManagedFiles.Count) managed files"
        foreach ($managedFile in $filteredManagedFiles) {
            try {
                $localFilePath = ConvertTo-LocalPath $managedFile.FullName -ErrorAction Stop
            }
            catch {
                Write-Debug "Failed to convert $($managedFile.FullName) to local path"
                Write-Warning $_
                continue
            }
            try {
                $localFile = Get-Item -Path $localFilePath -Force -ErrorAction Stop
                Write-Debug "File $localFilePath exists, no need to forget it"
                continue
            }
            catch {
                Write-Debug "File $localFilePath doesn't exist, need to forget it"
                Write-Debug "forgetting $localFilePath with chezmoi.exe"
                # https://www.chezmoi.io/reference/commands/forget/
                & $ENV:CHEZMOI_EXECUTABLE forget $localFilePath @forget_params --force
                Write-Debug "chezmoi.exe finished forgetting $localFilePath"
            }
        }
    }

    # https://www.chezmoi.io/reference/commands/add/
    # -a, --autotemplate
    # --create
    # --encrypt
    # --exact
    # --follow
    # -p, --prompt
    # -q, --quiet
    # --secrets ignore | warning | error
    # -T, --template
    # --template-symlinks
    # Common flags
    # -x, --exclude types
    # -f, --force
    # -i, --include types
    # -r, --recursive
    $add_params = $params.clone()
    if ($recursiveFile.Name -like $RECURSIVE_PROPERTY_REGEX) {
        # recursive re-add
        $add_params += "--recursive=true"
    }
    else {
        $add_params += "--recursive=false" # this adds the folder without any files, a directory with .keep
    }

    # "Re-add" the directory, adds newly created files and directories (if recursive is true)
    try {
        Write-Debug "Adding $localDirPath with chezmoi.exe"
        & $ENV:CHEZMOI_EXECUTABLE add $localDirPath @add_params
        Write-Debug "chezmoi.exe finished adding $localDirPath"
    }
    catch {
        Write-Warning $_
    }
}