$ENV:_EDITOR = @('cursor', 'code-insiders', 'code') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
Set-Alias -Name code -Value $ENV:_EDITOR
Set-Alias -Name vscode -Value $ENV:_EDITOR
$ENV:EDITOR = "$ENV:_EDITOR -w -n" # chezmoi compatibility... exec: "code" executable file not found in %PATH%
# if (-not ($ENV:CHEZMOI -eq 1)){ # chezmoi also has a conflict with git-posh after vscode exit only if the editor field is defined in chezmoi.toml !!! the bug is that typing breaks and half the characters dont apply
# }
try {
    # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
    Import-Module posh-git -ErrorAction Stop
}
catch {
    Write-Error "posh-git isn't available on the system, execute:"
    Write-Error 'PowerShellGet\Install-Module posh-git -Scope CurrentUser -Force'
}

Set-Alias -Name sudo -Value gsudo

# https://github.com/ChrisTitusTech/powershell-profile/blob/e89e9b0f968fa2224c8a9400d2023770362fb278/Microsoft.PowerShell_profile.ps1#L446
# Enhanced PSReadLine Configuration
$PSReadLineOptions = @{
    EditMode = 'Windows'
#     HistoryNoDuplicates = $true
#     HistorySearchCursorMovesToEnd = $true
    BellStyle = 'None'
}
Set-PSReadLineOption @PSReadLineOptions
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

function Get-ChocoPackage {
    # https://stackoverflow.com/a/76556486/12603110
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )
    $choco_list = choco list --lo --limit-output --exact $PackageName | ConvertFrom-Csv -delimiter "|" -Header Id, Version
    return $choco_list
}
function Select-Zip {
    # https://stackoverflow.com/a/44055098/12603110
    [CmdletBinding()]
    Param(
        $First,
        $Second,
        $ResultSelector = { , $args }
    )
    return [System.Linq.Enumerable]::Zip($First, $Second, [Func[Object, Object, Object[]]]$ResultSelector)
}

function Get-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,
        [string]$Source
    )
    if ($Source) {
        $winget_list = winget list --exact $PackageName --source $Source | Select -Last 3
    }
    else {
        $winget_list = winget list --exact $PackageName | Select -Last 3
    }
    if ($winget_list[1] -notmatch '^-+$') {
        # The list has returned too many rows, the header is not present, this is a bug in the intent of the function.
        Write-Error "The list has returned too many rows, the header is not present, this is a bug in the intent of the function."
        return
    }
    $m = $winget_list[0] | Select-String '(\w+(?:\s+?|$))' -AllMatches | Select -ExpandProperty Matches
    $columns = $m | Select-Object -ExpandProperty Value
    
    $indexes = $winget_list[0] | Select-String '(\w+(?:\s+?|$))' -AllMatches | Select -ExpandProperty Matches | Select -ExpandProperty Index 
    $indexes += @($winget_list[0].length + 1)         
    $text = $indexes | ForEach-Object -Begin { $i = 0 } -Process {
        if ($i -lt ($indexes.Length - 1)) {
            $i++
            return @{ Index = $_; Length = $indexes[$i] - $_ }
        }
    } | % { $winget_list[2].substring($_.Index, $_.Length) }  
    $winget_out = @{}
    for ($i = 0; $i -lt $columns.Length; $i++) {
        $winget_out[$columns[$i].Trim()] = $text[$i].Trim()
    }
    return $winget_out
}
function Update-PowerShell {
    Write-Host 'Checking for internet connection... ' -ForegroundColor Cyan -NoNewline
    $canConnectToGitHub = Test-Connection github.com -Count 1 -Quiet -TimeoutSeconds 1
    if (-not $canConnectToGitHub) {
        Write-Host 'Skipping profile update check due to GitHub.com not responding within 1 second.' -ForegroundColor Yellow
        return
    }
    try {
        Write-Host 'Checking for PowerShell updates...' -ForegroundColor Cyan
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $gitHubApiUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
        $latestReleaseInfo = Invoke-RestMethod -Uri $gitHubApiUrl
        $latestVersion = $latestReleaseInfo.tag_name.Trim('v')
        if ($currentVersion -lt $latestVersion) {
            Write-Host 'Updating PowerShell...' -ForegroundColor Yellow
            if (Get-ChocoPackage 'pwsh') {
                sudo choco upgrade pwsh -y
            }
            else {
                winget upgrade 'Microsoft.PowerShell' --accept-source-agreements --accept-package-agreements
            }
            if ($?) {
                Write-Host 'PowerShell has been updated. Please restart your shell to reflect changes' -ForegroundColor Magenta
            }
        }
    }
    catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

function Invoke-YesNoPrompt {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    # https://stackoverflow.com/a/60101530/12603110 - Prompt for yes or no - without repeating on new line if wrong input
    $Cursor = [System.Console]::CursorTop
    Do {
        [System.Console]::CursorTop = $Cursor
        $Answer = Read-Host -Prompt "$Prompt (y/n)"
    }
    Until ($Answer -eq 'y' -or $Answer -eq 'n')
    if ($Answer -eq 'y') {
        & $Action
    }
}
# Update local changes to chezmoi repo
&$ENV:_EDITOR --list-extensions > $ENV:USERPROFILE\.vscode\extensions.txt
$null = (chezmoi re-add)
# weekly update check
if ($(try { Get-Date -Date (Get-Content "$PSScriptRoot/date.tmp" -ErrorAction SilentlyContinue) }catch {}) -lt $(Get-Date)) {
    (Get-Date).Date.AddDays(7).DateTime > "$PSScriptRoot/date.tmp"
    if ($ENV:CHEZMOI -ne 1) {
        $Chezmoi_diff = $(chezmoi git pull -- --autostash --rebase ; chezmoi diff) | Out-String
        $NoChanges = 'Current branch master is up to date.', 'Already up to date.'
        if (-not (([string]$Chezmoi_diff).trim() -in $NoChanges)) {
            # https://www.chezmoi.io/user-guide/daily-operations/#pull-the-latest-changes-from-your-repo-and-see-what-would-change-without-actually-applying-the-changes
            chezmoi diff
            Invoke-YesNoPrompt -Prompt 'Chezmoi changes detected! Install them now?' -Action { 
                chezmoi update --init --apply &
            }
        }
    }
    # fetch latest changes from chezmoi repo
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

# Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 # refreshenv

function Edit-Setup([switch]$PromptApplyChanges = $false) {
    chezmoi edit
    if ($PromptApplyChanges) {
        Invoke-YesNoPrompt -Prompt 'Apply changes?' -Action { 
            chezmoi update --init --apply &
        }
    }
    else {
        chezmoi update --init --apply &
    }
}
Set-Alias -Name eds -Value Edit-Setup

function which([Parameter(Mandatory = $true)][string]$name) {
    # will print location or source code
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd.CommandType -eq 'Alias') {
        Write-Host "Alias: $($cmd.Name) -> $($cmd.Definition)" -ForegroundColor Cyan
        return which($cmd.Definition)
    }
    if ($cmd.CommandType -eq 'ApplicationInfo') {
        return $cmd.Definition
    }
    if ($cmd.CommandType -eq 'Application') {
        return $cmd.Path
    }
    if ($cmd.CommandType -eq 'Cmdlet') {
        return $cmd
    }
    if ($cmd.CommandType -eq 'Function') {
        Write-Host "function $($cmd | Select-Object -ExpandProperty Name) {`n    $($cmd | Select-Object -ExpandProperty Definition)`n}" -ForegroundColor Cyan
        return $cmd
    }
    return $cmd
}

function export($name, $value) {
    Set-Item -Force -Path "env:$name" -Value $value
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
$PSDefaultParameterValues = @{'Format-Table:Autosize' = $true }
function ll { param($Path = '') Get-ChildItem -Path $Path -Force }

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
    If ($file -eq $null) {
        Throw 'No filename supplied'
    }
    If (Test-Path -Path $file) {
        (Get-ChildItem -Path $file).LastWriteTime = Get-Date
    }
    else {
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
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User    = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        if ($persistedPaths -notcontains $Path) {
            $persistedPaths = $persistedPaths + $Path | Where-Object { $_ }
            [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
        }
    }

    $envPaths = $env:Path -split ';'
    if ($envPaths -notcontains $Path) {
        $envPaths = $envPaths + $Path | Where-Object { $_ }
        $env:Path = $envPaths -join ';'
    }
}

function Add-EnvPathFirst {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User    = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        if ($persistedPaths -notcontains $Path) {
            $persistedPaths = , $Path + $persistedPaths | Where-Object { $_ }
            [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
        }
    }

    $envPaths = $env:Path -split ';'
    if ($envPaths -notcontains $Path) {
        $envPaths = , $Path + $envPaths | Where-Object { $_ }
        $env:Path = $envPaths -join ';'
    }
}

function Remove-EnvPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User    = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        $persistedPaths = $persistedPaths | Where-Object { $_ -and $_ -notlike $Path }
        [Environment]::SetEnvironmentVariable('Path', $persistedPaths -join ';', $containerType)
    }

    $envPaths = $env:Path -split ';'
    # filter out the possible wildcard path
    $envPaths = $envPaths | Where-Object { $_ -and $_ -notlike $Path }
    $env:Path = $envPaths -join ';'
}

function Get-EnvPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Machine', 'User')]
        [string] $Container
    )

    $containerMapping = @{
        Machine = [EnvironmentVariableTarget]::Machine
        User    = [EnvironmentVariableTarget]::User
    }
    $containerType = $containerMapping[$Container]

    [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';' |
    Where-Object { $_ }
}

function Find-EnvPath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [ValidateSet('Machine', 'User', 'Session')]
        [string] $Container = 'Session'
    )

    if ($Container -ne 'Session') {
        $containerMapping = @{
            Machine = [EnvironmentVariableTarget]::Machine
            User    = [EnvironmentVariableTarget]::User
        }
        $containerType = $containerMapping[$Container]

        $persistedPaths = [Environment]::GetEnvironmentVariable('Path', $containerType) -split ';'
        $persistedPaths = $persistedPaths | Where-Object { $_ -and $_ -like $Path }

        return $persistedPaths -ne $null
    }

    $envPaths = $env:Path -split ';'
    # filter out the possible wildcard path
    $envPaths = $envPaths | Where-Object { $_ -and $_ -like $Path }
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

if (which 'fnm.exe') {
    fnm env --use-on-cd | Out-String | Invoke-Expression
}
else {
    Write-Error "fnm isn't available on the system, execute:`nchoco install fnm"
}

if (which 'uv.exe') {
    (& uv generate-shell-completion powershell) | Out-String | Invoke-Expression
    (& uvx --generate-shell-completion powershell) | Out-String | Invoke-Expression
}
else {
    # powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    Write-Error "uv isn't available on the system, execute:`npowershell -ExecutionPolicy ByPass -c `"irm https://astral.sh/uv/install.ps1 | iex`""
}

# I don't like the public oh my posh themes
# use oh my posh here

function Invoke-Conda {
    Remove-Alias -Name conda -Scope Global
    If (Test-Path 'C:\tools\miniforge3\Scripts\conda.exe') {
    (& 'C:\tools\miniforge3\Scripts\conda.exe' 'shell.powershell' 'hook') | Out-String | Where-Object { $_ } | Invoke-Expression
    }
    conda @args
}
Set-Alias -Name conda -Value Invoke-Conda -Scope Global

if(which 'chezmoi.exe') {
    chezmoi completion powershell | Out-String | Invoke-Expression
}
else{
    Write-Error "chezmoi isn't available on the system, How??"
}


# $LazyLoadProfileRunspace = [RunspaceFactory]::CreateRunspace()
# $LazyLoadProfile = [PowerShell]::Create()
# $LazyLoadProfile.Runspace = $LazyLoadProfileRunspace
# $LazyLoadProfileRunspace.Open()
# [void]$LazyLoadProfile.AddScript({Import-Module posh-git}) # (1)
# [void]$LazyLoadProfile.BeginInvoke()
# $null = Register-ObjectEvent -InputObject $LazyLoadProfile -EventName InvocationStateChanged -Action {
#     Import-Module -Name posh-git # (2)
#     $global:GitPromptSettings.DefaultPromptPrefix.Text = 'PS '
#     $global:GitPromptSettings.DefaultPromptBeforeSuffix.Text = '`n'
#     $LazyLoadProfile.Dispose()
#     $LazyLoadProfileRunspace.Close()
#     $LazyLoadProfileRunspace.Dispose()
# }