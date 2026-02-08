# chezmoi also has a conflict with git-posh after vscode exit only if the editor field is defined in chezmoi.toml !!! the bug is that typing breaks and half the characters dont apply
# if (($ENV:CHEZMOI -eq 1)) {
#     # don't load the profile if chezmoi is active
#     # why would you edit with chezmoi active anyway?
#     return
# }
try {
    # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
    Import-Module posh-git -ErrorAction Stop
}
catch {
    Write-Error "posh-git isn't available on the system, execute:"
    Write-Error 'PowerShellGet\Install-Module posh-git -Scope CurrentUser -Force'
}
if (Get-Command chezmoi.exe -ErrorAction SilentlyContinue) {
    # this needs to stay in the global scope, probably should report the error to the developer
    (& chezmoi completion powershell) | Out-String | Invoke-Expression
}
else {
    Write-Error "chezmoi isn't available on the system, How??"
}
$existingVariables = Get-Variable # Some setup may not work if the variables are not removed, keep that in mind

$_EDITOR = @('cursor', 'code-insiders') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
Set-Alias -Name code -Value $_EDITOR
Set-Alias -Name vscode -Value $_EDITOR
$ENV:EDITOR = "$_EDITOR -w -n" # Edit-Profile of PSCX
Set-Alias -Name sudo -Value gsudo

# https://github.com/ChrisTitusTech/powershell-profile/blob/e89e9b0f968fa2224c8a9400d2023770362fb278/Microsoft.PowerShell_profile.ps1#L446
# Enhanced PSReadLine Configuration
$PSReadLineOptions = @{
    EditMode  = 'Windows'
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
    $choco_list = choco list --lo --limit-output --exact $PackageName | ConvertFrom-Csv -Delimiter "|" -Header Id, Version
    return $choco_list
}
function Select-Zip {
    # https://stackoverflow.com/a/44055098/12603110
    [CmdletBinding()]
    param(
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
        $winget_list = winget list --exact $PackageName --source $Source | Select-Object -Last 3
    }
    else {
        $winget_list = winget list --exact $PackageName | Select-Object -Last 3
    }
    if ($winget_list[1] -notmatch '^-+$') {
        # The list has returned too many rows, the header is not present, this is a bug in the intent of the function.
        Write-Error "The list has returned too many rows, the header is not present, this is a bug in the intent of the function."
        return
    }
    $m = $winget_list[0] | Select-String '(\w+(?:\s+?|$))' -AllMatches | Select-Object -ExpandProperty Matches
    $columns = $m | Select-Object -ExpandProperty Value
    
    $indexes = $winget_list[0] | Select-String '(\w+(?:\s+?|$))' -AllMatches | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Index 
    $indexes += @($winget_list[0].length + 1)         
    
    $text = $indexes | ForEach-Object -Begin { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'i')]$i = 0 } -Process {
        if ($i -lt ($indexes.Length - 1)) {
            $i++
            return @{ Index = $_; Length = $indexes[$i] - $_ }
        }
    } | ForEach-Object { $winget_list[2].substring($_.Index, $_.Length) }  
    $winget_out = @{}
    for ($i = 0; $i -lt $columns.Length; $i++) {
        $winget_out[$columns[$i].Trim()] = $text[$i].Trim()
    }
    return $winget_out
}

# https://stackoverflow.com/a/34800670/12603110 - PowerShell equivalent of LINQ Any()?
function Invoke-YesNoPrompt {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    # https://stackoverflow.com/a/60101530/12603110 - Prompt for yes or no - without repeating on new line if wrong input
    $Cursor = [System.Console]::CursorTop
    do {
        [System.Console]::CursorTop = $Cursor
        $Answer = Read-Host -Prompt "$Prompt (y/n)"
    }
    until ($Answer -eq 'y' -or $Answer -eq 'n')
    if ($Answer -eq 'y') {
        & $Action
    }
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

# function Edit-Setup([switch]$PromptApplyChanges = $false) {
#     chezmoi edit
#     if ($PromptApplyChanges) {
#         Invoke-YesNoPrompt -Prompt 'Apply changes?' -Action { 
#             chezmoi update --init --apply &
#         }
#     }
#     else {
#         chezmoi update --init --apply &
#     }
# }
# Set-Alias -Name eds -Value Edit-Setup



function Find-Command {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$name)
    
    # will print location or source code
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd.CommandType -eq 'Alias') {
        Write-Debug "Command type is Alias: $($cmd.Name)"
        Write-Host "Alias: $($cmd.Name) -> $($cmd.Definition)" -ForegroundColor Cyan
        return & $MyInvocation.MyCommand.Name $cmd.Definition
    }
    if ($cmd.CommandType -eq 'ApplicationInfo') {
        Write-Debug "Command type is ApplicationInfo: $($cmd.Name)"
        return $cmd.Definition
    }
    if ($cmd.CommandType -eq 'Application') {
        Write-Debug "Command type is Application: $($cmd.Name)"
        return $cmd.Path
    }
    if ($cmd.CommandType -eq 'Cmdlet') {
        Write-Debug "Command type is Cmdlet: $($cmd.Name)"
        return $cmd
    }
    if ($cmd.CommandType -eq 'Function') {
        Write-Debug "Command type is Function: $($cmd.Name)"
        Write-Host "function $($cmd | Select-Object -ExpandProperty Name) {`n    $($cmd | Select-Object -ExpandProperty Definition)`n}" -ForegroundColor Cyan
        return $cmd
    }
    Write-Debug "Command type is other or null: $($cmd.CommandType)"
    return $cmd
}
Set-Alias -Name which -Value Find-Command

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
function Set-LocationHome { Set-Location -Path $HOME }
Set-Alias -Name ~/ -Value Set-LocationHome

function Up {
    param([int]$Levels = 1)
    $path = Get-Location
    for ($i = 0; $i -lt $Levels; $i++) {
        $path = Split-Path $path -Parent
    }
    Set-Location $path
}
function Up1 { Up 1 }
function Up2 { Up 2 }
function Up3 { Up 3 }

Set-Alias -Name '..' -Value Up1
Set-Alias -Name '...' -Value Up2
Set-Alias -Name '....' -Value Up3

# Enhanced Listing
$PSDefaultParameterValues = @{'Format-Table:Autosize' = $true }
function ll { param($Path = '') Get-ChildItem -Path $Path -Force }

# https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm4va8o/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
function Touch-File {
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
    if ($file -eq $null) {
        throw 'No filename supplied'
    }
    if (Test-Path -Path $file) {
        (Get-ChildItem -Path $file).LastWriteTime = Get-Date
    }
    else {
        Write-Output -InputObject $null > $file
    }
}
Set-Alias -Name touch -Value Touch-File

function Restart-WSL {
    wsl --shutdown && wsl exit
}
Set-Alias -Name Restart-WSL2 -Value Restart-WSL

function Extract-Archive {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "'$Path' is not a valid file!"
        return
    }
    
    $extension = [System.IO.Path]::GetExtension($Path).ToLower()
    $directory = [System.IO.Path]::GetDirectoryName($Path)
    
    switch ($extension) {
        '.zip' { Expand-Archive -Path $Path -DestinationPath $directory }
        '.7z' { & 7z x $Path -o"$directory" }
        '.rar' { & winrar x $Path $directory }
        '.tar' { tar -xf $Path -C $directory }
        '.gz' { 
            if ($Path -like '*.tar.gz') { tar -xzf $Path -C $directory }
            else { gzip -d $Path }
        }
        default { Write-Error "Don't know how to extract '$Path'..." }
    }
}
Set-Alias -Name extract -Value Extract-Archive


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

function Get-Type {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [object]$Object
    )
    process {
        $Object.GetType()
    }
}

# https://stackoverflow.com/a/51956864/12603110 - powershell - Remove all variables
# This can make gitposh fail
# $existingVariables = Get-Variable
# try {
#     # your script here
# } finally {
#     Get-Variable | Where-Object Name -notin $existingVariables.Name | Remove-Variable
# }

# https://github.com/giggio/posh-alias
# Add-Alias ls 'ls -force'

# https://www.reddit.com/r/PowerShell/comments/fsv3kt/comment/fm4fi89/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
# Set-ExecutionPolicy Bypass -Scope Process
# Update-FormatData -PrependPath "$PSScriptRoot\Format.ps1xml"

function Invoke-Fnm {
    Remove-Alias -Name fnm -Scope Global
    if (which 'fnm.exe') {
        fnm env --use-on-cd | Out-String | Invoke-Expression
    }
    else {
        Write-Error "fnm isn't available on the system, execute:`nchoco install fnm"
    }
    fnm @args
}
Set-Alias -Name fnm -Value Invoke-Fnm -Scope Global

function Invoke-Uv {
    Remove-Alias -Name uv -Scope Global
    if (which 'uv.exe') {
        (& uv generate-shell-completion powershell) | Out-String | Invoke-Expression
    }
    else {
        # powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        Write-Error "uv isn't available on the system, execute:`npowershell -ExecutionPolicy ByPass -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    }
    uv @args
}
Set-Alias -Name uv -Value Invoke-Uv -Scope Global

function Invoke-Uvx {
    Remove-Alias -Name uvx -Scope Global
    if (which 'uv.exe') {
        (& uvx --generate-shell-completion powershell) | Out-String | Invoke-Expression
    }
    else {
        # powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        Write-Error "uv isn't available on the system, execute:`npowershell -ExecutionPolicy ByPass -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    }
    uvx @args
}
Set-Alias -Name uvx -Value Invoke-Uvx -Scope Global

# I don't like the public oh my posh themes
# use oh my posh here

function Invoke-Conda {
    Remove-Alias -Name conda -Scope Global
    if (Test-Path 'C:\tools\miniforge3\Scripts\conda.exe') {
        (& 'C:\tools\miniforge3\Scripts\conda.exe' 'shell.powershell' 'hook') | Out-String | Where-Object { $_ } | Invoke-Expression
    }
    conda @args
}
Set-Alias -Name conda -Value Invoke-Conda -Scope Global

if (Get-Module -ListAvailable -Name Pscx) {
    Import-Module Pscx -ErrorAction SilentlyContinue
    $Pscx:Preferences['TextEditor'] = $(which $_EDITOR)
    Set-Alias -Name touch -Value Touch-File # pscx has a touch alias
    Set-Alias -Name Expand-Archive -Value Microsoft.PowerShell.Archive\Expand-Archive -Scope Global -Force # pscx has a Expand-Archive function
}
else {
    Write-Error "Pscx isn't available on the system, execute:`nInstall-Module Pscx -Scope CurrentUser -Force"
}

# https://stackoverflow.com/a/38882348/12603110 capture process stdout and stderr in the correct ordering
# the printout is partial compared to the original process because the speed output is in stderr
# $c = $chezmoi_process.StandardOutput.Read()
# if ($null -ne $c -and $c -ne -1 ) {
#     do {
#         write-host "$([char]$c)" -NoNewline
#         $c = $chezmoi_process.StandardOutput.Read()
#     } while ($null -ne $c -and $c -ne -1)
#     $chezmoi_process | Wait-Process
# }

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

# Remove-Variable -Name chezmoi_process
# Remove-Variable -Name _EDITOR
Get-Variable | Where-Object Name -NotIn $existingVariables.Name | Remove-Variable # Some setup may not work if the variables are not removed, keep that in mind
