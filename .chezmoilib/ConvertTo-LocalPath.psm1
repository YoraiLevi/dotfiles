# Usage:
# Import-Module (Join-Path $ENV:CHEZMOI_SOURCE_DIR .chezmoilib\ConvertTo-LocalPath.psm1)
# ConvertTo-LocalPath c:\Users\Yorai\.local\share\chezmoi\dot_conda\desktop.ini      
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot Convert-ChezmoiAttributeString.psm1)
function Test-ChezmoiEnvVars {
    if (($null -eq $ENV:CHEZMOI_SOURCE_DIR) -or ($null -eq $ENV:CHEZMOI_DEST_DIR)) {
        throw "CHEZMOI_WORKING_TREE and CHEZMOI_DEST_DIR environment variables must be set"
    }
}

function ConvertTo-LocalPath {
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$InputString
    )
    Test-ChezmoiEnvVars
    $managedFile = Get-Item -Path $InputString -Force -ErrorAction Stop

    # Check if $ENV:CHEZMOI_SOURCE_DIR is an ancestor of $managedFile.FullName
    $workingTree = [System.IO.Path]::GetFullPath($ENV:CHEZMOI_SOURCE_DIR)
    $filePath = [System.IO.Path]::GetFullPath($managedFile.FullName)
    if (-not ($filePath.StartsWith($workingTree, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "The file '$filePath' is not under the CHEZMOI_WORKING_TREE directory '$workingTree'."
    }
    if (-not (Test-Path $managedFile.FullName)) {
        Write-Debug "File managed file found at $managedFile doesn't exist"
        return
    }
    try {
        $resolvedItem = Resolve-Path -LiteralPath $managedFile.FullName -RelativeBasePath $ENV:CHEZMOI_SOURCE_DIR -Relative -ErrorAction Stop
    }
    catch {
        Write-Debug "Failed to resolve path for $managedFile"
        Write-Error $_
    }
    $l = (($resolvedItem -replace '/', '\') -split '\\' | ForEach-Object { Convert-ChezmoiAttributeString $_ })
    $localFilePath = Join-Path $ENV:CHEZMOI_DEST_DIR @l
    return $localFilePath

}