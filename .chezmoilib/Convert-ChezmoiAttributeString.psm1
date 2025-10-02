# Usage: 
# Import-Module (Join-Path $ENV:CHEZMOI_WORKING_TREE .chezmoilib\Convert-ChezmoiAttributeString.psm1)

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
            Write-Debug "While Loop iteration starts"
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