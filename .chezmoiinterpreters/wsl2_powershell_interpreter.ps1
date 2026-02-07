param()
$ENV:CHEZMOI_DATA = (chezmoi data --format json | Out-String | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 100)
$ENV:CHEZMOI_WSL2 = 1
<#
  Explanation of $slashFlags and the different WSLENV suffixes
  Reference: https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/

  The value of $slashFlags is a hashtable mapping CHEZMOI_* environment variable names
  to their corresponding WSLENV flags, used when sharing environment variables from Windows to WSL.

  In WSLENV values, after the variable name, suffix flags may be specified to control propagation:

    /p - Path translation: When set, the value of the variable will be translated between WSL (Linux) paths and Win32 (Windows) paths as appropriate. For example, when reading the variable in WSL it will be a Linux-style path; in Windows, it will appear as a Windows-style path.

    /l - List of paths: Indicates the variable contains a list of paths. In WSL this is a colon-delimited list, while in Win32 this is a semicolon-delimited list. This flag converts between delimiters appropriately.

    /u - Up (Windows → WSL): Variable is propagated only when invoking WSL from Win32. For example, set in Windows and visible in WSL.

    /w - Down (WSL → Windows): Variable is propagated only when invoking Win32 from WSL. For example, set in WSL and visible in Windows.

    /d - Downward propagation: The variable value should be propagated from WSL into Windows.

    /c - Path list conversion (legacy): Variable contains a list of paths and should be converted between ':' (Linux) and ';' (Windows) separators (usually replaced with /l in modern usage).

  In this script, "/up" is used for all variables, which means:
    - /u: The variable is available inside WSL when launched from Windows.
    - /p: The variable is also propagated from the parent environment (default behavior).

  No path (/p) or list (/l) translation is used for these variables, so their values are passed as-is, without format conversion, unless the appropriate flag is added.

  The $env:WSLENV variable defines which variables are propagated into WSL and with what transformation flags.
   For example, appending CHEZMOI_CACHE_DIR/up to $WSLENV allows that environment variable to be accessible inside WSL according to the up propagation behavior.
#>
$slashFlags = [hashtable]@{
    "CHEZMOI_CACHE_DIR"    = "/up"
    "CHEZMOI_COMMAND_DIR"  = "/up"
    "CHEZMOI_CONFIG_FILE"  = "/up"
    "CHEZMOI_DEST_DIR"     = "/up"
    "CHEZMOI_EXECUTABLE"   = "/up"
    "CHEZMOI_HOME_DIR"     = "/up"
    "CHEZMOI_SOURCE_DIR"   = "/up"
    "CHEZMOI_WORKING_TREE" = "/up"
    "CHEZMOI_ARGS"         = "/up"
}
$envArgs = Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' }
$env:WSLENV = $env:WSLENV + ":" + ( ($envArgs | ForEach-Object { "$($_.Name)$($slashFlags[$_.Name])" }) -join ':')
wsl bash --noprofile --norc "$(wsl wslpath $args.replace('\','/'))"