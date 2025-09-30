param()
Write-Host $PSCommandPath -ForegroundColor Green
# Get-ChildItem Env: | Where-Object { $_.Name -like 'CHEZMOI*' } | ForEach-Object { Write-Host $_.Name, $_.Value -ForegroundColor Green }

# CHEZMOI 1
# CHEZMOI_a 1
# CHEZMOI_ARCH amd64
# CHEZMOI_ARGS C:\Users\Yorai/.local/bin\chezmoi.exe re-add
# CHEZMOI_CACHE_DIR C:/Users/Yorai/.cache/chezmoi
# CHEZMOI_COMMAND re-add
# CHEZMOI_COMMAND_DIR C:/Users/Yorai/.local/share/chezmoi
# CHEZMOI_CONFIG_FILE C:/Users/Yorai/.config/chezmoi/chezmoi.yaml
# CHEZMOI_DEST_DIR C:/Users/Yorai
# CHEZMOI_EXECUTABLE C:/Users/Yorai/.local/bin/chezmoi.exe
# CHEZMOI_FQDN_HOSTNAME DESKTOP-FFSUH9G
# CHEZMOI_GID S-1-5-21-3726588303-2376105255-2108496670-513
# CHEZMOI_GROUP
# CHEZMOI_HOME_DIR C:/Users/Yorai
# CHEZMOI_HOSTNAME DESKTOP-FFSUH9G
# CHEZMOI_OS windows
# CHEZMOI_SOURCE_DIR C:/Users/Yorai/.local/share/chezmoi
# CHEZMOI_UID S-1-5-21-3726588303-2376105255-2108496670-1001
# CHEZMOI_USERNAME DESKTOP-FFSUH9G\Yorai
# CHEZMOI_VERSION_BUILT_BY goreleaser
# CHEZMOI_VERSION_COMMIT ca8fe5bfcb148741d2763d93ce0d562e04fa3ae3
# CHEZMOI_VERSION_DATE 2025-02-07T22:13:25Z
# CHEZMOI_VERSION_VERSION 2.59.1
# CHEZMOI_WINDOWS_VERSION_CURRENT_BUILD 26100
# CHEZMOI_WINDOWS_VERSION_CURRENT_MAJOR_VERSION_NUMBER %!s(uint64=10)
# CHEZMOI_WINDOWS_VERSION_CURRENT_MINOR_VERSION_NUMBER %!s(uint64=0)
# CHEZMOI_WINDOWS_VERSION_CURRENT_VERSION 6.3
# CHEZMOI_WINDOWS_VERSION_DISPLAY_VERSION 24H2
# CHEZMOI_WINDOWS_VERSION_EDITION_ID Professional
# CHEZMOI_WINDOWS_VERSION_PRODUCT_NAME Windows 10 Pro


# CHEZMOI_WORKING_TREE C:/Users/Yorai/.local/share/chezmoi

# $ENV:CHEZMOI_WORKING_TREE


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
            $result += $attributes[$remaining[0]]
            if ("literal_" -eq $remaining[0]) {
                Write-Debug "literal_ found"
                break
            }
            if ($null -eq $attributes[$remaining[0]]) {
                Write-Debug "`$attributes[$remaining[0]] is null"
                $result += $remaining[0]
                break
            }
            $remaining = $remaining[1..($remaining.Length - 1)]
        }
        $result += $remaining[1..($remaining.Length - 1)] -join ""

        return $result
    }
}
$dirPaths = Get-ChildItem -Path $ENV:CHEZMOI_WORKING_TREE -Filter '.re-add-recursive' -Recurse -Force -File | ForEach-Object {
    $dirPath = Join-Path $ENV:CHEZMOI_DEST_DIR $_.Directory.Name
    if (Test-Path $dirPath) {
        $dirPath
    }
} 
Write-Debug "Waiting for chezmoi.exe to finish..."
foreach ($dirPath in $dirPaths) {
    Write-Debug "Invoking chezmoi.exe for $dirPath"
    Write-Host "Invoking chezmoi.exe for $dirPath"
    & $ENV:CHEZMOI_EXECUTABLE add $dirPath
    Write-Debug "chezmoi.exe finished for $dirPath"
}
Write-Debug "chezmoi.exe finished..."
sleep 10