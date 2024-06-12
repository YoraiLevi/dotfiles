# conda and git posh have conflict, this works tho
try {
    Import-Module posh-git
}
catch {
    Write-Error "posh-git isn't available on the system, execute:"
    Write-Error "PowerShellGet\Install-Module posh-git -Scope CurrentUser -Force"
}

function Update-PowerShell {
    Write-Host "Checking for internet connection... " -ForegroundColor Cyan  -NoNewline
    $canConnectToGitHub = Test-Connection github.com -Count 1 -Quiet -TimeoutSeconds 1
    if (-not $canConnectToGitHub) {
        Write-Host "Skipping profile update check due to GitHub.com not responding within 1 second." -ForegroundColor Yellow
        return
    }
    try {
        Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan
        $updateNeeded = $false
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
        if ($currentVersion -lt $latestVersion) {
            Write-Host "Updating PowerShell..." -ForegroundColor Yellow
            winget upgrade "Microsoft.PowerShell" --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell has been updated. Please restart your shell to reflect changes" -ForegroundColor Magenta
        }
    } catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

# daily update check
if ($(try{Get-Date -Date (Get-Content "$PSScriptRoot/date.tmp" -ErrorAction SilentlyContinue)}catch{}) -lt $(Get-Date)){
    (Get-Date).Date.AddDays(1).DateTime > "$PSScriptRoot/date.tmp"
    Update-PowerShell
}

# # PSReadLine option to add a matching closing bracket for (, [ and { - cannot copy paste it adds brackets in terminal
# # https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm44e6i/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
# Set-PSReadLineKeyHandler -Key '(', '{', '[' `
#     -BriefDescription InsertPairedBraces `
#     -LongDescription "Insert matching braces" `
#     -ScriptBlock {
#     param($key, $arg)

#     $closeChar = switch ($key.KeyChar) {
#         '(' { [char]')'; break }
#         '{' { [char]'}'; break }
#         '[' { [char]']'; break }
#     }

#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
#     $line = $null
#     $cursor = $null
#     [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
#     [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor - 1)
# }

# Set-PSReadLineKeyHandler -Key ')', ']', '}' `
#     -BriefDescription SmartCloseBraces `
#     -LongDescription "Insert closing brace or skip" `
#     -ScriptBlock {
#     param($key, $arg)

#     $line = $null
#     $cursor = $null
#     [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

#     if ($line[$cursor] -eq $key.KeyChar) {
#         [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
#     }
#     else {
#         [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
#     }
# }

Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 # refreshenv

# https://github.com/ChrisTitusTech/powershell-profile/blob/main/Microsoft.PowerShell_profile.ps1
function Invoke-Profile {
    @(
        $Profile.AllUsersAllHosts,
        $Profile.AllUsersCurrentHost,
        $Profile.CurrentUserAllHosts,
        $Profile.CurrentUserCurrentHost
    ) | % {
        if(Test-Path $_){
            Write-Verbose "Running $_"
            . $_
        }
    }
}
Set-Alias -Name "Reload-Profile" -Value Invoke-Profile
# Quick Access to Editing the Profile
function ep { code --wait $Profile.CurrentUserAllHosts } # todo maybe add variable "profile type"

function which($name) {
    # will print location or source code
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd.CommandType -eq "Alias"){
        return which($cmd.Definition)
    }
    return $cmd.Definition
}

function export($name, $value) {
    set-item -force -path "env:$name" -value $value;
}

function pkill($name) {
    Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10)
  Get-Content $Path -Tail $n
}

# Navigation Shortcuts
function home { Set-Location -Path $HOME }
Set-Alias -Name user -Value home

function docs { Set-Location -Path $HOME\Documents }
Set-Alias -Name documents -Value docs

function source { Set-Location -Path $HOME\Documents\source }
Set-Alias -Name sources -Value source

function dtop { Set-Location -Path $HOME\Desktop }
Set-Alias -Name desktop -Value dtop

# Enhanced Listing
$PSDefaultParameterValues = @{"Format-Table:Autosize"=$true}
function ll { ls -Force }

# https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm4va8o/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
Function Touch-File {
    <#
      .SYNOPSIS
      Creates an empty file
      .DESCRIPTION
      Creates an empty file
      .PARAMETER <full path and name of file with extension>
      Define the file to make
      .EXAMPLE
      Touch "C:\down\test.txt"
    #>
    $file = $args[0]
    If ($file -eq $null){
        Throw 'No filename supplied'
    }
    If (Test-Path -Path $file){
        (Get-ChildItem -Path $file).LastWriteTime = Get-Date
    } else {
        Write-Output -InputObject $null > $file
    }
}
Set-Alias -Name touch -Value Touch-File


# https://stackoverflow.com/a/51956864/12603110 - powershell - Remove all variables
$existingVariables = Get-Variable
try {
    # your script here
    $vscode = if ($null -ne (Get-Command code-insiders -ErrorAction SilentlyContinue)) { 'code-insiders' } else { 'code' }
    Set-Alias -Name code -Value $vscode
    Set-Alias -Name vscode -Value $vscode
    # Set-Alias -Name code-insiders -Value $vscode
} finally {
    Get-Variable |
        Where-Object Name -notin $existingVariables.Name |
        Remove-Variable
}

# https://github.com/giggio/posh-alias
# Add-Alias ls 'ls -force'

# https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm4fi89/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
# Set-ExecutionPolicy Bypass -Scope Process
# Update-FormatData -PrependPath "$PSScriptRoot\Format.ps1xml"

if ("C:\ProgramData\chocolatey\bin\fnm.exe"){
    fnm env --use-on-cd | Out-String | Invoke-Expression
}
else {
    Write-Error "fnm isn't available on the system, execute:"
    Write-Error "choco install fnm"
}

# I don't like the public oh my posh themes
# use oh my posh here

#region conda initialize
# !! Contents within this block are managed by 'conda init' !!
If (Test-Path "C:\tools\miniforge3\Scripts\conda.exe") {
    (& "C:\tools\miniforge3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | ?{$_} | Invoke-Expression
}
#endregion