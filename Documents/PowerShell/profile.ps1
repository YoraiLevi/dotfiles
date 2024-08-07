$ENV:EDITOR = if ($null -ne (Get-Command code-insiders -ErrorAction SilentlyContinue)) { 'code-insiders' } else { 'code' }
Set-Alias -Name code -Value $ENV:EDITOR
Set-Alias -Name vscode -Value $ENV:EDITOR
$ENV:EDITOR = "$ENV:EDITOR -w -n" # chezmoi compatibility... exec: "code" executable file not found in %PATH%
# if (-not ($ENV:CHEZMOI -eq 1)){ # chezmoi also has a conflict with git-posh after vscode exit only if the editor field is defined in chezmoi.toml !!! the bug is that typing breaks and half the characters dont apply
# }
try {
    # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
    Import-Module posh-git -ErrorAction Stop
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
    if($ENV:CHEZMOI -ne 1){
        $Chezmoi_diff = $(chezmoi git pull -- --autostash --rebase ; chezmoi diff) | Out-String
        $NoChanges = "Current branch master is up to date.", "Already up to date."
        if (-not (([string]$Chezmoi_diff).trim() -in $NoChanges)){
            # https://www.chezmoi.io/user-guide/daily-operations/#pull-the-latest-changes-from-your-repo-and-see-what-would-change-without-actually-applying-the-changes
            chezmoi diff
            # https://stackoverflow.com/a/60101530/12603110 - Prompt for yes or no - without repeating on new line if wrong input
            $Cursor = [System.Console]::CursorTop
            Do {
                [System.Console]::CursorTop = $Cursor
                $Answer = Read-Host -Prompt 'Chezmoi changes detecter! Install them now? (y/n)'
            }
            Until ($Answer -eq 'y' -or $Answer -eq 'n')
            if($Answer -eq 'y'){
                (chezmoi update) -and (chezmoi init) -and (chezmoi apply)
            }
        }
    }
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
    # "bug", doesn't update function defenitions aka doesn't reload functions 
    # https://stackoverflow.com/a/27721496/12603110 - maybe make these utility function into modules
    @(
        $Profile.AllUsersAllHosts,
        $Profile.AllUsersCurrentHost,
        $Profile.CurrentUserAllHosts,
        $Profile.CurrentUserCurrentHost
    ) | % {
        if(Test-Path $_){
            Write-Verbose "Running $_"
            Import-Module $_ -Force
        }
    }
}
Set-Alias -Name "Reload-Profile" -Value Invoke-Profile
# Quick Access to Editing the Profile
function Edit-Profile([switch]$Reload = $True, [switch]$EditChezmoi = $True, [string]$PowerShellProfile = $Profile.CurrentUserAllHosts){
    # todo add check one of available profiles
    # todo if it doesn't exist, create it? throw error?
    if($EditChezmoi){
        $applyFlag = " -a " # --apply
        iex "chezmoi edit $applyFlag $PowerShellProfile" # invoke editing with chezmoi and apply changes immidietly
    }
    else {
        iex ($ENV:EDITOR + " " + $PowerShellProfile) # invoke vscode on profile
    }
    if ($Reload){
        Invoke-Profile
    }
}
Set-Alias -Name edp -Value Edit-Profile

function Edit-ChezmoiConfig([switch]$EditChezmoi = $True,[switch]$Template = $True, [switch]$Push = $True){
    if($EditChezmoi){
        if($Template){
            (chezmoi edit-config-template) -and (chezmoi init)
            chezmoi git push
        }
        else{
            chezmoi edit-config
            chezmoi git push 
        }
    }
    else{
        if($Template){
            $chezmoi_template_path = "$HOME/.local/share/chezmoi/.chezmoi.toml.tmpl"
            $chezmoi_init = "; chezmoi init"
        }
        else {
            $chezmoi_template_path = "$HOME/.config/chezmoi/chezmoi.toml" 
        }
        iex ($ENV:EDITOR + " " + $chezmoi_template_path + " " + $chezmoi_init)
    }
}

function Edit-Setup(){
    code $(chezmoi source-path)
}

function which($name) {
    # will print location or source code
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd.CommandType -eq "Alias"){
        return which($cmd.Definition)
    }
    if ($cmd.CommandType -eq "ApplicationInfo"){
        return $cmd.Definition
    }
    if ($cmd.CommandType -eq "Cmdlet"){
        return $cmd
    }
    if ($cmd.CommandType -eq "Function"){
        Write-Output $cmd
        return $cmd.Definition
    }
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
function ll {param($Path='') ls -Path $Path -Force }

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

function Get-Env {
    Get-ChildItem env:
}

# https://gist.github.com/jaw/4d1d858b87a5c208fbe42fd4d4aa97a4 - EnvPaths.psm1
function Add-EnvPathLast {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        if ($persistedPaths -notcontains $Path) {
            $persistedPaths = $persistedPaths + $Path | where { $_ }
            [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
        }
    }

    $envPaths = $env:Path -split ';'
    if ($envPaths -notcontains $Path) {
        $envPaths = $envPaths + $Path | where { $_ }
        $env:Path = $envPaths -join ';'
    }
}

function Add-EnvPathFirst {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        if ($persistedPaths -notcontains $Path) {
            $persistedPaths = ,$Path + $persistedPaths | where { $_ }
            [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
        }
    }

    $envPaths = $env:Path -split ';'
    if ($envPaths -notcontains $Path) {
        $envPaths = ,$Path + $envPaths | where { $_ }
        $env:Path = $envPaths -join ';'
    }
}

function Remove-EnvPath {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        $persistedPaths = $persistedPaths | where { $_ -and $_ -notlike $Path }
        [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
    }

    $envPaths = $env:Path -split ';'
    # filter out the possible wildcard path
    $envPaths = $envPaths | where { $_ -and $_ -notlike $Path }
    $env:Path = $envPaths -join ';'
}

function Get-EnvPath {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Machine', 'User')]
        [string] $Container
    )

    $containerMapping = @{
        Machine = [EnvironmentVariableTarget]::Machine
        User = [EnvironmentVariableTarget]::User
    }
    $containerType = $containerMapping[$Container]

    [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';' |
        where { $_ }
}

function Find-EnvPath {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        $persistedPaths = $persistedPaths | where { $_ -and $_ -like $Path }

        return $persistedPaths -ne $null
    }

    $envPaths = $env:Path -split ';'
    # filter out the possible wildcard path
    $envPaths = $envPaths | where { $_ -and $_ -like $Path }
    return $envPaths -ne $null
}

# https://stackoverflow.com/a/51956864/12603110 - powershell - Remove all variables
# $existingVariables = Get-Variable
# try {
#     # your script here
# } finally {
#     Get-Variable |
#         Where-Object Name -notin $existingVariables.Name |
#         Remove-Variable
# }

# https://github.com/giggio/posh-alias
# Add-Alias ls 'ls -force'

# https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm4fi89/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
# Set-ExecutionPolicy Bypass -Scope Process
# Update-FormatData -PrependPath "$PSScriptRoot\Format.ps1xml"

if (which "fnm.exe"){
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
