<#
.SYNOPSIS
    Sweep chezmoi-managed marker directories and forget files that disappeared from the
    destination or add files that appeared in it, then return.

.DESCRIPTION
    This is the shared implementation of the `.chezmoi-re-add.*` marker protocol.
    The protocol lets a directory under the chezmoi source tree ship a zero-byte file named
    `.chezmoi-re-add.<properties>` to declare how the sync service (and the chezmoi re-add
    pre-hook) should keep that directory in sync with the corresponding destination directory:

        .chezmoi-re-add.forget                          -> forget missing files (non-recursive)
        .chezmoi-re-add.recursive-forget                -> forget missing files (recursive)
        .chezmoi-re-add.recursive-add                   -> add the directory recursively
        .chezmoi-re-add.recursive-forget.recursive-add  -> both (full two-way sync)

    The sweep produces at most three top-level chezmoi invocations:
        chezmoi forget <missing-paths> --force
        chezmoi add <dirs> --recursive=true
        chezmoi add <dirs> --recursive=false

    Because each invocation is top-level (not nested inside another chezmoi process), it
    acquires and releases the BoltDB persistent-state lock cleanly, avoiding the
    "timeout obtaining persistent state lock" failures that plague nested chezmoi calls.

    The same logic used to live inside .chezmoihooks/re-add/pre.ps1 as nested chezmoi
    invocations. That happened to work from an interactive shell by timing luck but
    reliably failed under the Windows service (ChezmoiSync), because chezmoi opens its
    persistent state lazily and a parent chezmoi that happens to touch state before the
    hook runs starves every nested child. See
    https://github.com/twpayne/chezmoi/issues/433 and
    https://chezmoi.io/user-guide/frequently-asked-questions/troubleshooting/.

.PARAMETER ChezmoiPath
    Path to chezmoi.exe. Required because the sweep intentionally does not assume it
    is being invoked inside a chezmoi hook (so $ENV:CHEZMOI_EXECUTABLE may be unset).

.PARAMETER SourceDir
    Chezmoi source directory. Defaults to `chezmoi source-path`.

.PARAMETER DestDir
    Chezmoi destination directory. Defaults to $env:USERPROFILE (chezmoi's Windows default).

.PARAMETER DryRun
    Pass --dry-run to nested chezmoi commands.

.PARAMETER Debug
    Pass --debug to nested chezmoi commands (inherited from CmdletBinding).

.PARAMETER Verbose
    Pass --verbose to nested chezmoi commands (inherited from CmdletBinding).

.EXAMPLE
    & '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1' -ChezmoiPath 'C:\Users\devic\.local\bin\chezmoi.exe'

.EXAMPLE
    # From the re-add pre-hook (interactive users only; the service bypasses the hook):
    & (Join-Path $ENV:CHEZMOI_SOURCE_DIR '.chezmoilib\Invoke-ChezmoiReAddSweep.ps1') `
        -ChezmoiPath $ENV:CHEZMOI_EXECUTABLE -DryRun:$IsDryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ChezmoiPath,

    [string]$SourceDir,

    [string]$DestDir,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ChezmoiPath -PathType Leaf)) {
    throw "ChezmoiPath '$ChezmoiPath' does not exist."
}

if (-not $SourceDir) { # TODO, don't use in script directly, used for intialization only
    $SourceDir = (& $ChezmoiPath source-path | Out-String).Trim()
}
if (-not $DestDir) { # TODO, don't use in script directly, used for intialization only
    $DestDir = $env:USERPROFILE # TODO get from chezmoi
}
# ConvertTo-LocalPath reads these two env vars directly.
# TODO, don't assign it if it's already set
$ENV:CHEZMOI_SOURCE_DIR = $SourceDir
$ENV:CHEZMOI_DEST_DIR = $DestDir

if (-not (Test-Path -LiteralPath $SourceDir)) {
    throw "SourceDir '$SourceDir' does not exist."
}
if (-not (Test-Path -LiteralPath $DestDir)) {
    throw "DestDir '$DestDir' does not exist."
}

Import-Module (Join-Path $SourceDir '.chezmoilib\ConvertTo-LocalPath.psm1') -Force

# Guardrail: fail fast if the source tree contains a directory or file whose chezmoi
# attribute prefixes are in non-canonical order. See
# https://www.chezmoi.io/reference/source-state-attributes/.
# An earlier incident produced phantom ~/.readonly_powershell etc. and doubled dirs.
$badOrderPattern = '^dot_(?:encrypted|private|readonly|empty|executable|remove|create|modify|run|symlink)_'
$badOrder = Get-ChildItem -Path $SourceDir -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $badOrderPattern }
if ($badOrder) {
    Write-Warning "Non-canonical chezmoi attribute ordering detected in source tree:"
    foreach ($bad in $badOrder) {
        Write-Warning "  $($bad.FullName)"
    }
    throw "Refusing to run re-add sweep: rename the above entries so prefixes are in canonical order (e.g. readonly_dot_powershell, not dot_readonly_powershell)."
}

$SPECIAL_FILE_NAME_REGEX = '.chezmoi-re-add*'
$FORGET_PROPERTY_REGEX = '*.forget*'
$FORGET_RECURSIVE_PROPERTY_REGEX = '*.recursive-forget*'
$RECURSIVE_PROPERTY_REGEX = '*.recursive-add*'

$filesToForget = [System.Collections.Generic.List[string]]::new()
$dirsToAddRecursive = [System.Collections.Generic.List[string]]::new()
$dirsToAddNonRecursive = [System.Collections.Generic.List[string]]::new()

$recursiveFiles = Get-ChildItem -Path $SourceDir -Filter $SPECIAL_FILE_NAME_REGEX -Recurse -Force -File
foreach ($recursiveFile in $recursiveFiles) {
    $chezmoiTrackedDir = $recursiveFile.Directory
    try {
        $localDirPath = ConvertTo-LocalPath $chezmoiTrackedDir.FullName -ErrorAction Stop
        $null = Get-Item -Path $localDirPath -ErrorAction Stop
    }
    catch {
        Write-Verbose "Skipping $($chezmoiTrackedDir.FullName): local dir not found"
        continue
    }

    $do_recursive_forget = $recursiveFile.Name -like $FORGET_RECURSIVE_PROPERTY_REGEX
    $do_forget = ($recursiveFile.Name -like $FORGET_PROPERTY_REGEX) -or $do_recursive_forget
    $do_recursive_add = $recursiveFile.Name -like $RECURSIVE_PROPERTY_REGEX

    if ($do_forget) {
        $chezmoiManagedFiles = Get-ChildItem -Path $chezmoiTrackedDir -Force -Recurse:$do_recursive_forget
        # Skip source-only metadata that never maps to a chezmoi target:
        #   * zero-byte placeholders (e.g. .keep, our .chezmoi-re-add markers)
        #   * template fragments (*.tmpl)
        #   * literal-dotfile metadata like .gitignore/.gitattributes (all target-mapped
        #     entries use attribute prefixes dot_/private_dot_/etc., so any entry
        #     starting with '.' is source-only and forget would print "not managed").
        $filteredManagedFiles = $chezmoiManagedFiles | Where-Object {
            $_.Length -gt 0 -and
            -not $_.Name.EndsWith('.tmpl') -and
            -not ($_.Name -like $SPECIAL_FILE_NAME_REGEX) -and
            -not $_.Name.StartsWith('.')
        }
        foreach ($managedFile in $filteredManagedFiles) {
            try {
                $localFilePath = ConvertTo-LocalPath $managedFile.FullName -ErrorAction Stop
            }
            catch {
                Write-Verbose "Failed to convert $($managedFile.FullName) to a local path; skipping"
                continue
            }
            if (Test-Path -LiteralPath $localFilePath) {
                continue
            }
            $filesToForget.Add($localFilePath)
        }
    }

    if ($do_recursive_add) {
        $dirsToAddRecursive.Add($localDirPath)
    }
    else {
        $dirsToAddNonRecursive.Add($localDirPath)
    }
}

$commonArgs = @()
if ($DryRun) { $commonArgs += '--dry-run' }
if ($PSBoundParameters.ContainsKey('Debug')) { $commonArgs += '--debug' }
if ($PSBoundParameters.ContainsKey('Verbose')) { $commonArgs += '--verbose' }

# Invoke a top-level chezmoi command with a small retry loop. BoltDB occasionally
# reports "timeout obtaining persistent state lock" on Windows because the lock file
# is briefly held by a stale chezmoi process, an AV scanner, or a filesystem indexer.
# Retrying is safe here because every chezmoi operation in this sweep (forget / add)
# is idempotent with respect to the destination state: if the first attempt partially
# succeeded, a retry re-checks the destination and only does what is still needed.
function Invoke-ChezmoiWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$MaxAttempts = 3,
        [int]$InitialDelaySeconds = 2
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $output = & $Action 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = ($output | Out-String)
        if ($outputText) { Write-Host $outputText.TrimEnd() }
        $isLockTimeout = $outputText -match 'timeout obtaining persistent state lock'
        if ($exitCode -eq 0 -and -not $isLockTimeout) {
            return
        }
        if ($attempt -lt $MaxAttempts -and $isLockTimeout) {
            $delay = $InitialDelaySeconds * [math]::Pow(2, $attempt - 1)
            Write-Warning ("{0}: lock contention on attempt {1}/{2}; retrying in {3}s" -f $Label, $attempt, $MaxAttempts, $delay)
            Start-Sleep -Seconds $delay
            continue
        }
        if ($exitCode -ne 0) {
            Write-Warning ("{0}: chezmoi exited with code {1} after {2} attempt(s)" -f $Label, $exitCode, $attempt)
        }
        return
    }
}

# Execute the batched operations. Each block is guarded so a failure in one (e.g. a
# transient lock contention from some other chezmoi invocation) does not prevent the
# others from running.
if ($filesToForget.Count -gt 0) {
    Write-Host ("Invoke-ChezmoiReAddSweep: forget {0} file(s)" -f $filesToForget.Count) -ForegroundColor Cyan
    Invoke-ChezmoiWithRetry -Label 'chezmoi forget' -Action {
        & $ChezmoiPath forget @filesToForget @commonArgs --force
    }
}

if ($dirsToAddRecursive.Count -gt 0) {
    Write-Host ("Invoke-ChezmoiReAddSweep: add --recursive=true {0} dir(s)" -f $dirsToAddRecursive.Count) -ForegroundColor Cyan
    Invoke-ChezmoiWithRetry -Label 'chezmoi add --recursive=true' -Action {
        & $ChezmoiPath add @dirsToAddRecursive @commonArgs --recursive=true
    }
}

if ($dirsToAddNonRecursive.Count -gt 0) {
    Write-Host ("Invoke-ChezmoiReAddSweep: add --recursive=false {0} dir(s)" -f $dirsToAddNonRecursive.Count) -ForegroundColor Cyan
    Invoke-ChezmoiWithRetry -Label 'chezmoi add --recursive=false' -Action {
        & $ChezmoiPath add @dirsToAddNonRecursive @commonArgs --recursive=false
    }
}
