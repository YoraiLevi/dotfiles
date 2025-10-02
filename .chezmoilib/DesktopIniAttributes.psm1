Import-Module (Join-Path $PSScriptRoot ConvertTo-LocalPath.psm1)
Import-Module (Join-Path $PSScriptRoot Convert-ChezmoiAttributeString.psm1)

$ErrorActionPreference = "Stop"

function Test-ChezmoiEnvVars {
    if (($null -eq $ENV:CHEZMOI_WORKING_TREE) -or ($null -eq $ENV:CHEZMOI_DEST_DIR)) {
        throw "CHEZMOI_WORKING_TREE and CHEZMOI_DEST_DIR environment variables must be set"
    }
}
function Remove-DesktopIniAttributes {
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$chezmoiPath
    )
    $chezmoiItem = Get-Item -Path $chezmoiPath -Force -ErrorAction Stop
    if ((Convert-ChezmoiAttributeString $chezmoiItem.Name) -ne "desktop.ini") {
        throw "File $chezmoiPath is not a desktop.ini file"
    }
    $localFilePath = ConvertTo-LocalPath $chezmoiPath
    try {
        $localFile = Get-item -path $localFilePath -force -ErrorAction Stop
        attrib -s -h ($localFile.FullName)
    }
    catch {
        Write-Error $_
    }
}

function Set-DesktopIniAttributes {
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$chezmoiPath
    )
    $chezmoiItem = Get-Item -Path $chezmoiPath -Force -ErrorAction Stop
    if ((Convert-ChezmoiAttributeString $chezmoiItem.Name) -ne "desktop.ini") {
        throw "File $chezmoiPath is not a desktop.ini file"
    }
    $localFilePath = ConvertTo-LocalPath $chezmoiPath
    try {
        $localFile = Get-item -path $localFilePath -force -ErrorAction Stop
        attrib +r -h ($localFile.Directory.FullName)
    }
    catch {
        Write-Error $_
    }
    attrib +h +s ($localFile.FullName)
}