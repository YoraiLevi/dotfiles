# chezmoi also has a conflict with git-posh after vscode exit only if the editor field is defined in chezmoi.toml !!! the bug is that typing breaks and half the characters dont apply
if (($ENV:CHEZMOI -eq 1)) {
    # don't load the profile if chezmoi is active
    # why would you edit with chezmoi active anyway?
    return
}

function global:Set-MyPrompt {
    try {
        Import-Module posh-git -ErrorAction Stop
        # https://stackoverflow.com/a/70527216/12603110 - Conda environment name hides git branch after conda init in Powershell
        # https://github.com/dahlbyk/posh-git?tab=readme-ov-file#customizing-the-posh-git-prompt
        $Global:GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true
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
$ExecutionContext.InvokeCommand.LocationChangedAction = {
    # this is called when the location changes
    param($sender, $eventArgs)
    $items = Get-ChildItem
    if ($items.Count -lt 15) {
        $items | Out-Default
    }
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

Register-LazyArgumentCompleter -CommandName 'chezmoi' -CompletionCodeFactory {
    if (-not (Get-Command chezmoi.exe -ErrorAction SilentlyContinue)) { return }
    # this needs to stay in the global scope, probably should report the error to the developer
    return (& chezmoi completion powershell) | Out-String
}

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
        Set-Alias -Name touch -Value Touch-File # pscx has a touch alias
        Set-Alias -Name Expand-Archive -Value Microsoft.PowerShell.Archive\Expand-Archive -Scope Global -Force # pscx has a Expand-Archive function
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

Get-Variable | Where-Object Name -NotIn $existingVariables.Name | Remove-Variable # Some setup may not work if the variables are not removed, keep that in mind