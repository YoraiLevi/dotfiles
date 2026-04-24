<#
.SYNOPSIS
    Create a fake git executable that delegates to the real git except for configured fail patterns.

.DESCRIPTION
    Returns an object with:
        - Path    : absolute path to the fake git (a .cmd shim around a .ps1)
        - RealGit : path to the resolved real git.exe used for delegation
        - Cleanup : scriptblock that removes the shim directory

    The shim fails (exit 1, stderr) when the space-joined argument list contains any
    substring listed in -FailSubcommands. Otherwise it invokes RealGit with the same argv.

.PARAMETER Root
    Directory to place git.ps1 and git.cmd (created if missing).

.PARAMETER FailSubcommands
    Substrings matched against the space-joined argument list (e.g. 'rebase --abort').
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$FailSubcommands = @()
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

$rootResolved = (Resolve-Path -LiteralPath $Root).Path
$realGit = $null
foreach ($cmd in Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue) {
    $gitDir = Split-Path -Parent $cmd.Source
    if ($gitDir -and $gitDir -ne $rootResolved) {
        $realGit = $cmd.Source
        break
    }
}
if (-not $realGit) {
    throw "No real git.exe on PATH outside the shim dir '$Root'."
}

$jsonEscaped = if (-not $FailSubcommands -or $FailSubcommands.Count -eq 0) {
    '[]'
} else {
    ($FailSubcommands | ConvertTo-Json -Compress -Depth 5)
}

$psPath  = Join-Path $Root 'git.ps1'
$cmdPath = Join-Path $Root 'git.cmd'

@"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$Argv)
`$ErrorActionPreference = 'Stop'
`$realGit = '$($realGit -replace "'", "''")'
`$failJson = '$($jsonEscaped -replace "'", "''")'
`$failSet = `$failJson | ConvertFrom-Json
`$cmdJoined = (`$Argv | ForEach-Object { "`$_" }) -join ' '
foreach (`$pat in `$failSet) {
    `$likePat = '*' + `$pat + '*'
    if (`$cmdJoined -like `$likePat) {
        [Console]::Error.WriteLine("mock git: refusing `$cmdJoined")
        exit 1
    }
}
& `$realGit @Argv
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $psPath -Encoding UTF8

$pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = 'pwsh.exe' }
$shim = "@echo off`r`n`"$pwshExe`" -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -File `"$psPath`" %*`r`n"
Set-Content -LiteralPath $cmdPath -Value $shim -Encoding Ascii -NoNewline

[pscustomobject]@{
    Path    = $cmdPath
    RealGit = $realGit
    Cleanup = {
        if (Test-Path -LiteralPath $Root) {
            Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }.GetNewClosure()
}
