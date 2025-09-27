$_EDITOR = @('cursor', 'code-insiders') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
Set-Alias -Name code -Value $_EDITOR
Set-Alias -Name vscode -Value $_EDITOR
$ENV:EDITOR = "$_EDITOR -w -n" # chezmoi compatibility... exec: "code" executable file not found in %PATH%
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


function Invoke-Process {
    <#
    .SYNOPSIS
    Starts a process with optional redirected stdout and stderr streams for better output handling.
    Allow to wait for the process to exit or forcefully kill it with timeout.
    
    .DESCRIPTION
    This function creates and starts a new process with optional standard output and error streams 
    redirected to enable capture and processing. It provides various waiting options
    including timeout and TimeSpan timeout support.
    
    .PARAMETER FilePath
    The path to the executable file to run.
    
    .PARAMETER ArgumentList
    Arguments to pass to the executable.
    
    .PARAMETER WorkingDirectory
    The working directory for the process.
    
    .PARAMETER Wait
    Wait for the process to exit without timeout.
    
    .PARAMETER Timeout
    Wait for the process to exit with a timeout in milliseconds.
    
    .PARAMETER TimeSpan
    Wait for the process to exit with a TimeSpan timeout.
    
    .PARAMETER TimeoutAction
    Action to take when wait operations timeout. Valid values are 'Continue', 'Inquire', 'SilentlyContinue', 'Stop'.
    
    .PARAMETER RedirectOutput
    Redirect stdout and stderr streams. When false, uses Start-Process for normal console output.
    It is Recommended to use the PassThru switch to access the redirected output through the returned process object
    You're welcome to think of a better solution to this.
    
    .PARAMETER PassThru
    Return the process object.
    
    .EXAMPLE
    # Basic usage without waiting - starts process and control returns immediately
    Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "10"

     .EXAMPLE
    # Basic usage with timeout - starts process and control returns immediately, the process is killed after 3 seconds
    Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "10" -Timeout 3
    
    .EXAMPLE
    # Wait for process to complete
    Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "4" -Wait
    
    .EXAMPLE
    # Wait with timeout (3 seconds), after 3 seconds the process is killed
    Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "10" -Wait -Timeout 3
    
    .EXAMPLE
    # Wait with TimeSpan timeout and custom timeout action, after 3 an inquire is shown asking what to do
    Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "10" -Wait -TimeSpan (New-TimeSpan -Seconds 3) -TimeoutAction Inquire
    
    .EXAMPLE
    # Redirect output and get process object
    $process = Invoke-Process -FilePath "ping.exe" -ArgumentList "google.com", "-n", "10" -TimeSpan (New-TimeSpan -Seconds 3) -TimeoutAction Stop -RedirectOutput -PassThru
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
   
    .LINK
    https://gist.github.com/YoraiLevi/d0d95011bed792dff57a301dbc2780ec
    .LINK
    https://stackoverflow.com/a/66700583/12603110
    .LINK
    https://stackoverflow.com/q/36933527/12603110
    .LINK
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.5#parameters
    .LINK
    https://github.com/PowerShell/PowerShell/blob/d8b1cc55332079d2be94cc266891c85e57d88c55/src/Microsoft.PowerShell.Commands.Management/commands/management/Process.cs#L1597
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'NoWait')]
    param
    (
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias('PSPath', 'Path')]
        [string]$FilePath,
        [Parameter(Position = 1)]
        [string[]]$ArgumentList = @(),
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,

        [Parameter(ParameterSetName = 'WithTimeout')]
        [Parameter(ParameterSetName = 'WithTimeSpan')]
        [Parameter(Mandatory, ParameterSetName = 'WaitExit')]
        [switch]$Wait,
        [Parameter(Mandatory, ParameterSetName = 'WithTimeout')]
        [int]$Timeout,
        [Parameter(Mandatory, ParameterSetName = 'WithTimeSpan')]
        [System.TimeSpan]$TimeSpan,
        [Parameter(ParameterSetName = 'WithTimeout')]
        [Parameter(ParameterSetName = 'WithTimeSpan')]
        [ValidateSet('Continue', 'Inquire', 'SilentlyContinue', 'Stop')]
        [string]$TimeoutAction = 'Stop',
        [switch]$RedirectOutput,
        [switch]$PassThru,
        # Consider adding support for the other Start-Process parameters and make this into a drop in replacement for Start-Process:
        # https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.5#parameters
        # partial eg:
        # [-Verb <string>]
        # [-WindowStyle <ProcessWindowStyle>]
        [hashtable]$Environment,
        [switch]$UseNewEnvironment
    )

    $ErrorActionPreference = 'Stop'

    $command = Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue
    $resolvedFilePath = if ($command) {
        $command.Source
    }
    else {
        $FilePath
    }

    $argumentString = if ($ArgumentList -and $ArgumentList.Count -gt 0) {
        " " + ($ArgumentList -join " ")
    }
    else {
        ""
    }
    
    $target = "$resolvedFilePath$argumentString"
    
    if ($PSCmdlet.ShouldProcess($target, $MyInvocation.MyCommand)) {
        if (($TimeoutAction -eq 'Inquire') -and -not $Wait) {
            throw "TimeoutAction 'Inquire' and 'Wait' switch are not compatible"
        }

        class Process : System.Diagnostics.Process {
            [void] WaitForExit() {
                $this.StandardOutput.ReadToEnd()
                $this.StandardError.ReadToEnd()
                ([System.Diagnostics.Process]$this).WaitForExit()
            }
        }
        function InvokeTimeoutAction {
            param(
                [string]$TimeoutAction,
                [System.Diagnostics.Process]$Process
            )
            
            switch ($TimeoutAction) {
                'Continue' {
                    Write-Debug "Waiting action: Continue"
                    Write-Warning "Process may still be running. Continuing..."
                }
                'Inquire' {
                    Write-Debug "Waiting action: Inquire"
                    $choice = Read-Host "Process is still running. What would you like to do? (K)ill, (W)ait"
                    switch ($choice.ToLower()) {
                        'k' { 
                            if (!$Process.HasExited) {
                                $Process.Kill()
                            }
                        }
                        'w' {
                            $Process.WaitForExit()
                        }
                        default {
                            Write-Warning "Invalid choice. Process will continue running."
                        }
                    }
                }
                'SilentlyContinue' {
                    Write-Debug "Waiting action: SilentlyContinue"
                    # No action - let process continue running
                }
                'Stop' {
                    Write-Debug "Waiting action: Stop"
                    if (!$Process.HasExited) {
                        $Process.Kill()
                    }
                }
                default {
                    Write-Debug "Waiting action: Default, should never happen"
                    # Unreachable code
                    Write-Error "Invalid wait action: $WaitAction"
                }
            }
        }
        $script_block = { param($Id, $Timeout)
            $function:InvokeTimeoutAction = $using:function:InvokeTimeoutAction;
            $TimeoutAction = $using:TimeoutAction;
            Write-Host "TimeoutAction: $TimeoutAction, Id: $Id, Timeout: $Timeout"
            $p = Wait-Process -Id $Id -Timeout $Timeout -PassThru;
            if ($TimeoutAction) {
                InvokeTimeoutAction -TimeoutAction $TimeoutAction -Process $p 
            } 
        }
        $p = $null
        if ($RedirectOutput) {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $FilePath
            $pinfo.RedirectStandardError = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.WindowStyle = 'Hidden'
            $pinfo.CreateNoWindow = $true
            $pinfo.Arguments = $ArgumentList
            if ($WorkingDirectory) {
                $pinfo.WorkingDirectory = $WorkingDirectory
            }
            function LoadEnvironmentVariable {
                # https://github.com/PowerShell/PowerShell/blob/d8b1cc55332079d2be94cc266891c85e57d88c55/src/Microsoft.PowerShell.Commands.Management/commands/management/Process.cs#L2231C24-L2231C335
                param(
                    [System.Diagnostics.ProcessStartInfo]$ProcessStartInfo,
                    [System.Collections.IDictionary]$EnvironmentVariables
                )
                
                $processEnvironment = $ProcessStartInfo.EnvironmentVariables
                foreach ($entry in $EnvironmentVariables.GetEnumerator()) {
                    if ($processEnvironment.ContainsKey($entry.Key)) {
                        $processEnvironment.Remove($entry.Key)
                    }
                    
                    if ($null -ne $entry.Value) {
                        if ($entry.Key -eq "PATH") {
                            if ($IsWindows) {
                                $machinePath = [System.Environment]::GetEnvironmentVariable($entry.Key, [System.EnvironmentVariableTarget]::Machine)
                                $userPath = [System.Environment]::GetEnvironmentVariable($entry.Key, [System.EnvironmentVariableTarget]::User)
                                $combinedPath = $entry.Value + [System.IO.Path]::PathSeparator + $machinePath + [System.IO.Path]::PathSeparator + $userPath
                                $processEnvironment.Add($entry.Key, $combinedPath)
                            }
                            else {
                                $processEnvironment.Add($entry.Key, $entry.Value)
                            }
                        }
                        else {
                            $processEnvironment.Add($entry.Key, $entry.Value)
                        }
                    }
                }
            }
            # https://github.com/PowerShell/PowerShell/blob/d8b1cc55332079d2be94cc266891c85e57d88c55/src/Microsoft.PowerShell.Commands.Management/commands/management/Process.cs#L1954
            if ($UseNewEnvironment) {
                $pinfo.EnvironmentVariables.Clear()
                LoadEnvironmentVariable -ProcessStartInfo $pinfo -EnvironmentVariables ([System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine))
                LoadEnvironmentVariable -ProcessStartInfo $pinfo -EnvironmentVariables ([System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::User))
            }

            if ($Environment) {
                LoadEnvironmentVariable -ProcessStartInfo $pinfo -EnvironmentVariables $Environment
            }
            $p = New-Object Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
        }
        else {
            $startProcessParams = @{
                FilePath     = $FilePath
                ArgumentList = $ArgumentList
                PassThru     = $true
                NoNewWindow  = $true
            }
            if ($WorkingDirectory) {
                $startProcessParams.WorkingDirectory = $WorkingDirectory
            }
            if ($Environment) {
                $startProcessParams.Environment = $Environment
            }
            if ($UseNewEnvironment) {
                $startProcessParams.UseNewEnvironment = $UseNewEnvironment
            }
            $p = Start-Process @startProcessParams -Confirm:$false
        }
        Write-Debug "Process started: $target"
        Write-Debug "Waiting Mode: $($PSCmdlet.ParameterSetName)"

        if ($Wait) {
            switch ($PSCmdlet.ParameterSetName) {
                'WaitExit' {
                    Write-Debug "Waiting for process to exit..."
                    $p.WaitForExit() | Out-Null
                }
                'WithTimeout' {
                    Write-Debug "Waiting for process to exit with timeout..."
                    $p.WaitForExit($Timeout * 1000) | Out-Null
                    InvokeTimeoutAction -TimeoutAction $TimeoutAction -Process $p
                }
                'WithTimeSpan' {
                    Write-Debug "Waiting for process to exit with timespan..."
                    $p.WaitForExit($TimeSpan) | Out-Null
                    InvokeTimeoutAction -TimeoutAction $TimeoutAction -Process $p
                }
                default {
                    Write-Error "Invalid parameter set: $($PSCmdlet.ParameterSetName)"
                }
            }
        }
        else {
            switch ($PSCmdlet.ParameterSetName) {
                'WithTimeout' {
                    Start-Job -ScriptBlock $script_block -ArgumentList $p.Id, $Timeout | Out-Null
                    Write-Debug "Letting process run in background with timeout..."
                }
                'WithTimeSpan' {
                    Start-Job -ScriptBlock $script_block -ArgumentList $p.Id, $TimeSpan.TotalSeconds | Out-Null
                    Write-Debug "Letting process run in background with timespan..."
                }
                'NoWait' {
                    Write-Debug "Letting process run in background..."
                }
                default {
                    Write-Error "Invalid parameter set: $($PSCmdlet.ParameterSetName)"
                }
            }
        }
    
        if ($PassThru) {
            Write-Debug "Returning process object"
            return $p
        }
    }
}



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
&$_EDITOR --list-extensions > $ENV:USERPROFILE\.vscode\$_EDITOR-extensions.txt
$chezmoi_process = Invoke-Process -FilePath "chezmoi" -ArgumentList "re-add" -PassThru -Timeout 10 -RedirectOutput -TimeoutAction Stop # this is a process object
# $chezmoi_process = chezmoi re-add & # this is a job and not a process object
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
Set-Alias -Name ~/ -Value home

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
    If (Test-Path 'C:\tools\miniforge3\Scripts\conda.exe') {
        (& 'C:\tools\miniforge3\Scripts\conda.exe' 'shell.powershell' 'hook') | Out-String | Where-Object { $_ } | Invoke-Expression
    }
    conda @args
}
Set-Alias -Name conda -Value Invoke-Conda -Scope Global

if (which 'chezmoi.exe') {
    # this needs to stay in the global scope, probably should report the error to the developer
    (& chezmoi completion powershell) | Out-String | Invoke-Expression
}
else {
    Write-Error "chezmoi isn't available on the system, How??"
}

# https://stackoverflow.com/a/38882348/12603110 capture process stdout and stderr in the correct ordering
# the printout is partial compared to the original process because the speed output is in stderr
$c = $chezmoi_process.StandardOutput.Read()
if ($null -ne $c -and $c -ne -1 ) {
    do {
        write-host "$([char]$c)" -NoNewline
        $c = $chezmoi_process.StandardOutput.Read()
    } while ($null -ne $c -and $c -ne -1)
    $chezmoi_process | Wait-Process
}
Remove-Variable -Name chezmoi_process
Remove-Variable -Name _EDITOR

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