<#
.SYNOPSIS
    Create a fake chezmoi executable that records every invocation.

.DESCRIPTION
    Returns an object with:
        - Path     : absolute path to the fake chezmoi (a .cmd shim around a .ps1)
        - LogPath  : path where each invocation appends a JSON line
        - FailPath : path that, when present, makes the next `add` invocation
                     fail with the BoltDB lock-timeout message and then deletes
                     itself. Tests can create it via `New-Item $mock.FailPath`.
        - PermFailPath : path that, when present, makes every `add` exit 2 with a
                         non-lock error (tests permanent failure).
        - FailCountPath : path that, when present, holds an integer; each `add`
                          decrements with lock-timeout exit 1 until zero, then succeeds.
        - GetCalls : scriptblock that returns every recorded invocation as an
                     array of objects (timestamp, command, argv, source, dest)
        - Reset    : scriptblock that clears the log

    The shim honours these commands:
        source-path  -> prints $ENV:CHEZMOI_SOURCE_DIR and exits 0
        target-path  -> prints $ENV:CHEZMOI_DEST_DIR and exits 0
        forget       -> logs, prints a short message, exits 0
        add          -> predicate order: PermFailPath (exit 2) > FailCountPath
                        (lock-timeout retries) > FailPath (one-shot lock timeout)
                        > success. Otherwise exits 0.
        anything else-> logs and exits 0

    A file-based latch (FailPath) is used instead of an environment variable
    so the mock process can "consume" the flag: env-var changes made in the
    mock (child) process are invisible to the parent, and the sweep would
    otherwise fail its retry on every attempt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

$logPath       = Join-Path $Root 'mock-chezmoi.log'
$failPath      = Join-Path $Root 'fail-next-add.flag'
$permFailPath  = Join-Path $Root 'perm-fail-add.flag'
$failCountPath = Join-Path $Root 'fail-add-count.txt'
$psPath        = Join-Path $Root 'chezmoi.ps1'
$cmdPath       = Join-Path $Root 'chezmoi.cmd'

@"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Argv)
`$ErrorActionPreference = 'Stop'
`$logPath       = '$($logPath       -replace "'", "''")'
`$failPath      = '$($failPath      -replace "'", "''")'
`$permFailPath  = '$($permFailPath  -replace "'", "''")'
`$failCountPath = '$($failCountPath -replace "'", "''")'
`$cmd = if (`$Argv.Count -gt 0) { `$Argv[0] } else { '' }
`$entry = [pscustomobject]@{
    timestamp = (Get-Date -Format o)
    command   = `$cmd
    argv      = `$Argv
    source    = `$ENV:CHEZMOI_SOURCE_DIR
    dest      = `$ENV:CHEZMOI_DEST_DIR
}
Add-Content -LiteralPath `$logPath -Value (`$entry | ConvertTo-Json -Compress -Depth 5)

switch (`$cmd) {
    'source-path' {
        Write-Output `$ENV:CHEZMOI_SOURCE_DIR
        exit 0
    }
    'target-path' {
        Write-Output `$ENV:CHEZMOI_DEST_DIR
        exit 0
    }
    'forget' {
        Write-Output "mock chezmoi: forget `$(`$Argv.Count - 1) target(s)"
        exit 0
    }
    'add' {
        if (Test-Path -LiteralPath `$permFailPath) {
            [Console]::Error.WriteLine('chezmoi: synthetic permanent failure for tests')
            exit 2
        }
        if (Test-Path -LiteralPath `$failCountPath) {
            `$remaining = [int](Get-Content `$failCountPath)
            if (`$remaining -gt 0) {
                (`$remaining - 1) | Set-Content `$failCountPath
                [Console]::Error.WriteLine('chezmoi: timeout obtaining persistent state lock, is another instance of chezmoi running?')
                exit 1
            }
        }
        if (Test-Path -LiteralPath `$failPath) {
            Remove-Item -LiteralPath `$failPath -Force -ErrorAction SilentlyContinue
            [Console]::Error.WriteLine('chezmoi: timeout obtaining persistent state lock, is another instance of chezmoi running?')
            exit 1
        }
        Write-Output "mock chezmoi: add `$(`$Argv.Count - 1) target(s)"
        exit 0
    }
    default {
        Write-Output "mock chezmoi: `$cmd"
        exit 0
    }
}
"@ | Set-Content -LiteralPath $psPath -Encoding UTF8

$pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = 'pwsh.exe' }
$shim = "@echo off`r`n`"$pwshExe`" -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -File `"$psPath`" %*`r`n"
Set-Content -LiteralPath $cmdPath -Value $shim -Encoding Ascii -NoNewline

[pscustomobject]@{
    Path          = $cmdPath
    PsPath        = $psPath
    LogPath       = $logPath
    FailPath      = $failPath
    PermFailPath  = $permFailPath
    FailCountPath = $failCountPath
    Reset         = { if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force } }.GetNewClosure()
    GetCalls = {
        if (-not (Test-Path -LiteralPath $logPath)) { return @() }
        Get-Content -LiteralPath $logPath | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }
    }.GetNewClosure()
}
