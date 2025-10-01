param()
Write-Host $PSCommandPath -ForegroundColor Green
# Uncomment to assist with debugging
# Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' } | ForEach-Object { Write-Debug $_.Name, $_.Value -ForegroundColor Yellow }

function Convert-ChezmoiAttributeString {
    <#
    .SYNOPSIS
        Converts a chezmoi attribute string (e.g., "dot_exact_literal_git") to the corresponding filename (e.g., ".git").
    
    .DESCRIPTION
        This function interprets attribute prefixes used by chezmoi (such as "dot_", "remove_", "external_", "exact_", "private_", "readonly_", and "literal_") and converts the attribute string to the intended filename. 
        - "dot_" is replaced with a leading dot (".").
        - "remove_", "external_", "exact_", "private_", and "readonly_" are ignored (removed).
        - "literal_" stops further attribute processing; the rest of the string is appended as-is.
        - If an unknown attribute is encountered, processing stops.
        Accepts input from the pipeline or as a parameter.
    
    .EXAMPLES
        Convert-ChezmoiAttributeString "dot_exact_literal_git"   # => ".git"
        "dot_literal_dot_git" | Convert-ChezmoiAttributeString   # => ".dot_git"
    
    .NOTES
        This function is intended to help convert chezmoi source file attribute names to their target filenames on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$InputString
    )

    process {
        # Define the attributes and their effects
        $attributes = [hashtable]@{
            "before_"     = ""
            "after_"      = ""
            "dot_"        = "."
            "empty_"      = ""
            "exact_"      = ""
            "executable_" = ""
            "external_"   = ""
            "once_"       = ""
            "onchange_"   = ""
            "private_"    = ""
            "readonly_"   = ""
            "create_"     = ""
            "encrypted_"  = ""
            "modify_"     = ""
            "remove_"     = ""
            "run_"        = ""
            "symlink_"    = ""
        }

        $result = ""
        $remaining = [regex]::Split($InputString.Trim(), '(?<=_)') | Where-Object { $_ -ne "" }
        while ($remaining.Length -gt 0) {
            Write-Debug "While Loop starts"
            Write-Debug "`$remaining[0]: $($remaining[0])"
            Write-Debug "`$attributes[`$remaining[0]]: $($attributes[$remaining[0]])"
            Write-Debug "`$result: $result"
            Write-Debug "`$remaining: $remaining"
            $token = $remaining[0]
            if (($remaining.Length - 1) -gt 0) {
                $remaining = $remaining[1..($remaining.Length - 1)]
            }
            else {
                $remaining = @()
            }

            if ("literal_" -eq $token) {
                Write-Debug "literal_ found"
                break
            }
            if ($null -eq $attributes[$token]) {
                Write-Debug "`$attributes[`$token] is null"
                $result += $token
                break
            }
            else {
                $result += $attributes[$token]
            }
        }
        $result += $remaining -join ""

        return $result
    }
}


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
            if (-not (Test-Path $managedFile.FullName)) {
                Write-Debug "File managed file found at $managedFile doesn't exist anymore (why?), no need to forget it"
                continue
            }
            try {
                $resolvedItem = Resolve-Path -LiteralPath $managedFile.FullName -RelativeBasePath $ENV:CHEZMOI_WORKING_TREE -Relative -ErrorAction Stop
            }
            catch {
                Write-Debug "Failed to resolve path for $managedFile"
                Write-Warning $_
                continue
            }
            $l = (($resolvedItem -replace '/', '\') -split '\\' | ForEach-Object { Convert-ChezmoiAttributeString $_ })
            $localFilePath = Join-Path $ENV:CHEZMOI_DEST_DIR @l
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