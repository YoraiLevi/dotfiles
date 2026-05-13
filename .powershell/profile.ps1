# Pre-warm $ENV:GITHUB_TOKEN from the gh CLI so any chezmoi invocation launched
# from this shell inherits an authenticated GitHub token. Without it, the 60
# req/hour anonymous limit on the shared NAT IP is exhausted almost instantly
# and `.chezmoiexternals/*.toml.tmpl` templates that call
# gitHubLatestReleaseAssetURL fail with "API rate limit exceeded". chezmoi
# recognises $GITHUB_TOKEN / $GITHUB_ACCESS_TOKEN / $CHEZMOI_GITHUB_ACCESS_TOKEN.
# See https://chezmoi.io/reference/templates/github-functions/.
# Runs BEFORE the $ENV:CHEZMOI guard so chezmoi-spawned shells also export it
# to any deeper subprocesses, and skips when an outer process already set one.
if (-not $ENV:GITHUB_TOKEN) {
    $__ghPath = (Get-Command gh.exe -ErrorAction SilentlyContinue).Source
    if (-not $__ghPath -and (Test-Path -LiteralPath 'C:/Program Files/GitHub CLI/gh.exe')) {
        $__ghPath = 'C:/Program Files/GitHub CLI/gh.exe'
    }
    if ($__ghPath) {
        try {
            $__ghToken = (& $__ghPath auth token 2>$null | Out-String).Trim()
            if ($__ghToken) { $ENV:GITHUB_TOKEN = $__ghToken }
        }
        catch { }
        Remove-Variable -Name __ghToken -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name __ghPath -ErrorAction SilentlyContinue
}

function dotfiles { git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" @args }
function dotfiles-timer { pwsh "$HOME\.dotfiles\dotfiles-timer.ps1" @args }

# chezmoi also has a conflict with git-posh after vscode exit only if the editor field is defined in chezmoi.toml !!! the bug is that typing breaks and half the characters dont apply
# if (($ENV:CHEZMOI -eq 1)) {
#     # don't load the profile if chezmoi is active
#     # why would you edit with chezmoi active anyway?
#     return
# }


function global:Set-MyPrompt {
    try {
        Import-Module posh-git -ErrorAction Stop
        # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
        # https://github.com/dahlbyk/posh-git?tab=readme-ov-file#customizing-the-posh-git-prompt
        $Global:GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true
        # cwd: xterm 256-color index 12 — same as printf '\e[38;5;12m' / zsh %F{12} with 256 colors.
        # posh-git maps [byte]n to ESC[38;5;nm (see Get-VirtualTerminalSequence in AnsiUtils.ps1); [ConsoleColor]::Blue uses SGR 94m instead.
        $Global:GitPromptSettings.DefaultPromptPath.ForegroundColor = [byte]12
        function global:PromptWriteErrorInfo() {
            $status = if ($global:GitPromptValues.DollarQuestion) {
                "`e[32mOK`e[0m" 
            }
            else {
                if ($global:GitPromptValues.LastExitCode) {
                    "`e[31mERROR: " + $global:GitPromptValues.LastExitCode + "`e[0m"
                }
                else {
                    "`e[31m!!! `e[0m"
                }
            }
            $durationInfo = if ($he = Get-History -Count 1) {
                # Use a '0.00s' format: duration in *seconds*, with two decimal places.
                ' {0:N2}s' -f $he.Duration.TotalSeconds
            }
            return "[$status$durationInfo]"
        }
        $Global:GitPromptSettings.DefaultPromptWriteStatusFirst = $true
        $Global:GitPromptSettings.DefaultPromptBeforeSuffix.Text = '`n`e[90m$([DateTime]::now.ToString("MM-dd HH:mm:ss"))`e[0m $(PromptWriteErrorInfo)'
        # $Global:GitPromptSettings.DefaultPromptSuffix = ' $((Get-History -Count 1).id + 1)$(">" * ($nestedPromptLevel + 1)) '
    }
    catch {
        Write-Error "posh-git isn't available"
    }
}
# Register a one-shot idle event to load posh-git after the first prompt renders
if ((Get-Process -Id $PID).CommandLine -match '\s-(Command|File|EncodedCommand|NoProfile)\b') {
    # cursor ide fucks up the prompt if it's lazy loaded
    Set-MyPrompt
}
else {

    $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        # https://learn-powershell.net/2013/01/30/powershell-and-events-engine-events/
        Set-MyPrompt
    }
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

Set-PSReadLineKeyHandler -Key 'Ctrl+c' -ScriptBlock {
    param($key, $arg)
    # Revert any in-progress edit (e.g. MenuComplete insertion), then cancel the line.
    [Microsoft.PowerShell.PSConsoleReadLine]::Undo()
    [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($key, $arg)
}
function Benchmark-Profile {
    $pwsh = (Get-Process -Id $PID).Path
    & $pwsh -NoProfile -command 'Measure-Script -Top 10 $profile.CurrentUserAllHosts'
}


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



function Refresh-Env {
    Remove-Alias -Name refreshenv -Scope Global
    Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1" -ErrorAction Stop
    refreshenv
}
Set-Alias -Name refreshenv -Value Refresh-Env -Scope Global

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
$ExecutionContext.InvokeCommand.LocationChangedAction = {
    # this is called when the location changes
    param($sender, $eventArgs)
    $items = Get-ChildItem
    if ($items.Count -lt 15) {
        $items | Out-Default
    }
    Set-Alias -Name touch -Value Touch-File -Scope Global -Force # pscx has a touch alias
    Set-Alias -Name Expand-Archive -Value Microsoft.PowerShell.Archive\Expand-Archive -Scope Global -Force # pscx has a Expand-Archive function
}
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
Set-Alias -Name touch -Value Touch-File -Scope Global -Force # pscx has a touch alias

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

function Import-DotEnv {
    # Read KEY=value lines from .env files into Env: for this process. Use -Path or pipe paths/FileInfo (e.g. Get-ChildItem ~/.auth -File).
    # Two ways to invoke: pass -Path (string), or pipe objects—parameter sets keep those modes mutually exclusive.
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        # Explicit file path (supports ~, relative paths, provider paths); used when nothing is piped in.
        [Parameter(ParameterSetName = 'Path', Position = 0, Mandatory = $true)]
        [string] $Path,

        # Each piped object becomes one file to load (FileInfo from dir listings, strings, or .FullName-bearing objects).
        [Parameter(ParameterSetName = 'Pipeline', Mandatory = $true, ValueFromPipeline = $true)]
        [object] $InputObject,

        # When set, missing files throw; otherwise they are skipped quietly.
        [switch] $Required
    )

    process {
        # --- Resolve to concrete filesystem path(s) for this invocation/pipeline object ---
        # Unary comma (,) wraps a single string so foreach always iterates paths, never characters.
        $resolvedPaths =
            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                ,($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
            } else {
                # Normalize pipeline input to a path string; directories yield nothing so they are skipped later.
                $raw =
                    if ($InputObject -is [System.IO.FileInfo]) { $InputObject.FullName }
                    elseif ($InputObject -is [System.IO.DirectoryInfo]) { $null }
                    elseif ($InputObject -is [string]) { $InputObject.Trim() }
                    else {
                        $fn = $InputObject.PSObject.Properties['FullName']
                        if ($null -ne $fn -and $fn.Value) { [string]$fn.Value } else { [string]$InputObject }
                    }
                if ([string]::IsNullOrWhiteSpace($raw)) { @() } else {
                    ,($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($raw))
                }
            }

        foreach ($resolved in $resolvedPaths) {
            # --- Guardrails before reading file contents ---
            if (-not (Test-Path -LiteralPath $resolved)) {
                if ($Required) { throw "Import-DotEnv: file not found: $resolved" }
                continue
            }

            # Only regular files: skip folders that appeared in directory listings without -File.
            $item = Get-Item -LiteralPath $resolved -ErrorAction SilentlyContinue
            if ($null -eq $item -or $item.PSIsContainer) { continue }

            # --- Parse line-by-line (streaming); subset of common .env rules ---
            switch -Regex -File $resolved {
                # Ignore empty lines and shell-style # comments.
                '^\s*(?:#.*)?$' { continue }
                default {
                    $line = $_.TrimEnd()
                    # Strip optional "export " prefix so Unix-style .env lines still work.
                    if ($line.StartsWith('export ')) { $line = $line.Substring(7).TrimStart() }
                    # Split only on the first "=" so values may contain "=" (URLs, secrets, etc.).
                    $eq = $line.IndexOf('=')
                    if ($eq -lt 1) { continue }
                    $name = $line.Substring(0, $eq).Trim()
                    if ([string]::IsNullOrWhiteSpace($name) -or $name[0] -eq '#') { continue }
                    $value = $line.Substring($eq + 1).Trim()
                    # Remove one matching pair of outer ' or " quotes if both ends agree (simple unquoting).
                    if ($value.Length -ge 2) {
                        $q = $value[0]
                        if (($q -eq '"' -or $q -eq "'") -and $value[-1] -eq $q) {
                            $value = $value.Substring(1, $value.Length - 2)
                        }
                    }
                    # Process-scoped env var: visible in this session and processes spawned from it.
                    Set-Item -LiteralPath "Env:$name" -Value $value
                }
            }
        }
    }
}

function Set-SymlinkRelative {
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Path
    )

    process {
        $item = Get-Item -Path $Path
        if ($null -eq $item.LinkType) {
            Write-Warning "'$Path' is not a symbolic link."
            return
        }

        # The current absolute target
        $target = $item.Target
        # Calculate path from the Link's Parent folder to the Target
        $relPath = Resolve-Path -Path $target -RelativeBasePath $item.DirectoryName -Relative

        # Re-create the link with the relative value
        # This preserves the File vs Directory type automatically because -Value is resolved during creation
        New-Item -ItemType SymbolicLink -Path $item.FullName -Value $relPath -Force
    }
}

function New-Symlink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Target,

        [switch]$AbsolutePath,
        
        [switch]$Force
    )

    # 1. Clean up existing item if Force is used
    if ($Force -and (Test-Path -Path $Path -ErrorAction SilentlyContinue)) {
        Write-Verbose "Force: Removing existing item at $Path"
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
    }

    # 2. Get Absolute paths for logic (without creating physical files)
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $fullTargetObj = Resolve-Path -Path $Target -ErrorAction Stop
    $fullTarget = $fullTargetObj.Path
    $isDir = Test-Path -Path $fullTarget -PathType Container

    # 3. Determine the string to store in the link
    if ($AbsolutePath) {
        $finalTarget = $fullTarget
    } else {
        $parentDir = Split-Path -Path $fullPath -Parent
        # Calculate relative jumps (../../) from Link Parent to Target
        $finalTarget = Resolve-Path -Path $fullTarget -RelativeBasePath $parentDir -Relative
    }

    # 4. Create the link based on Type
    if ($isDir) {
        # mklink /D is the only way to guarantee the Directory bit on Windows
        Write-Verbose "Creating Directory Symlink: $fullPath -> $finalTarget"
        cmd /c mklink /D "$fullPath" "$finalTarget"
    } else {
        Write-Verbose "Creating File Symlink: $fullPath -> $finalTarget"
        New-Item -ItemType SymbolicLink -Path $fullPath -Value $finalTarget -Force
    }
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
function Register-LazyArgumentCompleter {
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [scriptblock]$CompletionCodeFactory
    )

    Register-ArgumentCompleter -Native -CommandName $CommandName -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $completionCode = & $CompletionCodeFactory
        if (-not $completionCode) { return }

        # Register the real completer
        Invoke-Expression $completionCode

        # Retrieve it via reflection and invoke for this first Tab press
        $bindingFlags = [Reflection.BindingFlags]'NonPublic,Instance'
        $allFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
        $internalCtx = $ExecutionContext.GetType().GetField('_context', $bindingFlags).GetValue($ExecutionContext)
        $realCompleter = $internalCtx.GetType().GetProperty('NativeArgumentCompleters', $allFlags).GetValue($internalCtx)[$CommandName]

        if ($realCompleter) {
            & $realCompleter $wordToComplete $commandAst $cursorPosition
        }
    }.GetNewClosure()
}
function Show-NativeArgumentCompleters {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [string[]]$Key,

        [switch]$ShowScriptBlock,
        [switch]$InvokeAndPrintResults
    )
    begin {
        $bindingFlags = [Reflection.BindingFlags]'NonPublic,Instance'
        $allFlags = [Reflection.BindingFlags]'Public,NonPublic,Instance'
        $internalCtx = $ExecutionContext.GetType().GetField('_context', $bindingFlags).GetValue($ExecutionContext)
        $completers = $internalCtx.GetType().GetProperty('NativeArgumentCompleters', $allFlags).GetValue($internalCtx)

        if (-not $completers) {
            Write-Warning "No native argument completers found."
            return
        }

        # Build lookups for matching keys if given
        $keySet = @{}
        if ($Key) {
            foreach ($k in $Key) {
                if ($null -ne $k -and $k -ne '') {
                    $keySet[$k] = $true
                }
            }
        }
        $enumerator = $completers.GetEnumerator()
        $completerEntries = @()
        while ($enumerator.MoveNext()) {
            $completerEntries += [PSCustomObject]@{ Key = $enumerator.Key; Value = $enumerator.Value }
        }
    }
    process {
        # Accepts Key from pipeline and merges them to $keySet
        if ($PSBoundParameters.ContainsKey('Key')) {
            foreach ($k in $Key) {
                if ($null -ne $k -and $k -ne '') {
                    $keySet[$k] = $true
                }
            }
        }
    }
    end {
        $filteredEntries = if ($keySet.Count -gt 0) {
            $completerEntries | Where-Object { $keySet.ContainsKey($_.Key) }
        }
        else {
            $completerEntries
        }

        if (-not $filteredEntries -or $filteredEntries.Count -eq 0) {
            Write-Warning "No (matching) native argument completers found."
            return
        }

        foreach ($entry in $filteredEntries) {
            $key = $entry.Key
            $value = $entry.Value

            Write-Host "`n-----------------------------"
            Write-Host "Key          : $key"
            Write-Host "Type         : $($value.GetType().Name)"

            if ($ShowScriptBlock) {
                Write-Host "ScriptBlock  :"
                try {
                    if ($value -is [Delegate]) {
                        Write-Host ("  [Delegate] Target:      {0}" -f ($value.Target))
                        Write-Host ("  [Delegate] Method:      {0}" -f ($value.Method))
                        # Show Method Body if possible
                        if ($null -ne $value.Method) {
                            $methodScript = $value.Method.ToString()
                            Write-Host ("  [Delegate] MethodInfo:  {0}" -f $methodScript)
                        }
                    }
                    elseif ($value -is [ScriptBlock]) {
                        Write-Host ("  {0}" -f $value.ToString())
                    }
                    else {
                        Write-Host ("  <Not a ScriptBlock or Delegate>")
                    }
                }
                catch {
                    Write-Warning "Error printing script block or delegate: $_"
                }
            }

            if ($InvokeAndPrintResults) {
                # Invocation & pretty print results
                if ($null -eq $value) {
                    Write-Host "Value        : <null>"
                }
                else {
                    Write-Host "Value        : <exists>"
                    try {
                        $results = $null
                        # Note: these variables need to exist or can default here
                        $safeWord = if ($null -ne $wordToComplete) { $wordToComplete } else { "" }
                        $safeAst = if ($null -ne $commandAst) { $commandAst } else { $null }
                        $safePos = if ($null -ne $cursorPosition) { $cursorPosition } else { 0 }
                        if ($value -is [Delegate]) {
                            $results = $value.DynamicInvoke($safeWord, $safeAst, $safePos)
                        }
                        elseif ($value -is [ScriptBlock]) {
                            $results = & $value $safeWord $safeAst $safePos
                        }
                        else {
                            Write-Warning "Value is not invokable directly."
                        }
                        if ($null -ne $results) {
                            $results = @($results)
                            Write-Host "Result(s):"
                            foreach ($r in $results) {
                                if ($null -eq $r) {
                                    Write-Host "  <null>"
                                }
                                elseif ($r -is [System.Management.Automation.CompletionResult]) {
                                    Write-Host ("  Text     : {0}" -f $r.CompletionText)
                                    Write-Host ("  ListItem : {0}" -f $r.ListItemText)
                                    Write-Host ("  ResultTy : {0}" -f $r.ResultType)
                                    Write-Host ("  ToolTip  : {0}" -f $r.ToolTip)
                                    Write-Host "  ---"
                                }
                                else {
                                    Write-Host "  $r"
                                }
                            }
                        }
                        else {
                            Write-Host "Result       : <null or not invokable>"
                        }
                    }
                    catch {
                        Write-Warning "Exception occurred during invocation: $_"
                    }
                }
            }
            Write-Host "-----------------------------`n"
        }
    }
}

# Register-LazyArgumentCompleter -CommandName 'chezmoi' -CompletionCodeFactory {
#     if (-not (Get-Command chezmoi.exe -ErrorAction SilentlyContinue)) { return }
#     # this needs to stay in the global scope, probably should report the error to the developer
#     return (& chezmoi completion powershell) | Out-String
# }

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

Register-LazyArgumentCompleter -CommandName 'uv' -CompletionCodeFactory {
    if (-not (Get-Command 'uv.exe')) { return }
    (& uv generate-shell-completion powershell) | Out-String
}
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
function Update-Uv {
    Remove-Alias -Name uv -Scope Global
    if (which 'uv.exe') {
        & uv self update
    }
    else {
        Write-Error "uv isn't available on the system, execute:`npowershell -ExecutionPolicy ByPass -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    }
}

Register-LazyArgumentCompleter -CommandName 'uvx' -CompletionCodeFactory {
    if (-not (Get-Command 'uvx.exe')) { return }
    (& uvx --generate-shell-completion powershell) | Out-String
}
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

# Lazy init for conda — only generated on first Tab press
Register-LazyArgumentCompleter -CommandName 'conda' -CompletionCodeFactory {
    if (-not (Test-Path 'C:\tools\miniforge3\Scripts\conda.exe')) { return }
    # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
    Set-MyPrompt
    (& 'C:\tools\miniforge3\Scripts\conda.exe' 'shell.powershell' 'hook') | Out-String | Where-Object { $_ } | Invoke-Expression
    Get-Command -Name Register-ArgumentCompleter -CommandType Cmdlet
    Register-ArgumentCompleter -Native -CommandName conda -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
    } return $null
    return $null
}
function Invoke-Conda {
    # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
    Set-MyPrompt
    Remove-Alias -Name conda -Scope Global
    if (Test-Path 'C:\tools\miniforge3\Scripts\conda.exe') {
        (& 'C:\tools\miniforge3\Scripts\conda.exe' 'shell.powershell' 'hook') | Out-String | Where-Object { $_ } | Invoke-Expression
    }
    conda @args
}
Set-Alias -Name conda -Value Invoke-Conda -Scope Global

# Capture the value of $_EDITOR at registration time so the event handler uses its value statically
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    if (Get-Module -ListAvailable -Name Pscx) {
        Import-Module Pscx -ErrorAction SilentlyContinue
        $EDITOR = @('cursor', 'code-insiders') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        $Pscx:Preferences['TextEditor'] = $(which $EDITOR)
        Set-Alias -Name touch -Value Touch-File -Scope Global -Force # pscx has a touch alias
        Set-Alias -Name Expand-Archive -Value Microsoft.PowerShell.Archive\Expand-Archive -Scope Global -Force # pscx has a Expand-Archive function
        Set-Alias -Name edp -Value Edit-Profile -Scope Global
    }
    else {
        Write-Error "Pscx isn't available on the system, execute:`nInstall-Module Pscx -Scope CurrentUser -Force"
    }
}


# https://stackoverflow.com/a/38882348/12603110 capture process stdout and stderr in the correct ordering
# the printout is partial compared to the original process because the speed output is in stderr
# --- Background runspace pre-loads module assemblies ---
# $script:_lazyRunspace = [RunspaceFactory]::CreateRunspace()
# $script:_lazyPwsh = [PowerShell]::Create()
# $script:_lazyPwsh.Runspace = $script:_lazyRunspace
# $script:_lazyRunspace.Open()

# [void]$script:_lazyPwsh.AddScript({
#     Import-Module posh-git
# })
# [void]$script:_lazyPwsh.BeginInvoke()

# $null = Register-ObjectEvent -InputObject $script:_lazyPwsh -EventName InvocationStateChanged -Action {
#     # Only act when background work completes
#     if ($script:_lazyPwsh.InvocationStateInfo.State -ne 'Completed') { return }

#     # These are fast now — assemblies already cached in the AppDomain
#     try {
#         Import-Module posh-git
#     } catch {
#     }

#     # Cleanup
#     $script:_lazyPwsh.Dispose()
#     $script:_lazyRunspace.Close()
#     $script:_lazyRunspace.Dispose()
# }

Set-Alias -Name ssh -Value tssh -Scope Global
function Invoke-Claude {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $Args
    )
    # Compose the claude command with required flags and pass all arguments
    # If current folder is home, cd to tmp/claude-tmp before running claude.exe
    $homePath = [Environment]::GetFolderPath("UserProfile")
    $currentPath = (Get-Location).ProviderPath
    if ($currentPath -eq $homePath -or $currentPath -eq "~") {
        $tmpDir = Join-Path $ENV:TEMP "claude-tmp"
   
        if (-not (Test-Path $tmpDir)) {
            New-Item -ItemType Directory -Path $tmpDir | Out-Null
        }
        Set-Location $tmpDir
    }
    $ENV:CLAUDE_CODE_BLOCKING_LIMIT_OVERRIDE = 10 * 1024 * 1024
    & claude.exe --enable-auto-mode --allow-dangerously-skip-permissions --strict-mcp-config @Args
    Set-Location $currentPath
}
Set-Alias -Name claude -Value Invoke-Claude -Scope Global

Get-Variable | Where-Object Name -NotIn $existingVariables.Name | Remove-Variable # Some setup may not work if the variables are not removed, keep that in mind

if ($ENV:TERM_PROGRAM -eq "vscode" -or $ENV:VSCODE_INJECTION -eq 1) {
    # Cursor/VSCode terminal
    return
}

if (($ENV:VSCODE_CLI -eq 1) -or ($ENV:CURSOR_AGENT -eq 1) -or ($null -ne $ENV:VSCODE_PID)) {
    # Cursor AI agent terminal
    return
}

Get-ChildItem "~/.auth/*.env" | Import-DotEnv

# $null = zellij da -y # delete dead sessions
$ENV:SHELL = 'pwsh'
if (-not $ENV:ZELLIJ) {
    $env:TERM = 'xterm-256color'
    if ($ENV:SSH_CONNECTION) {
        zellij attach main -c
    }
}

if ($env:ZELLIJ_SESSION_NAME) {
    $null = New-Item -ItemType Directory -Force "$env:TEMP\zellij-session-times" -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
        try {
            [System.IO.File]::WriteAllText(
                "$env:TEMP\zellij-session-times\$env:ZELLIJ_SESSION_NAME",
                [DateTime]::UtcNow.Ticks.ToString()
            )
        }
        catch {}
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}
