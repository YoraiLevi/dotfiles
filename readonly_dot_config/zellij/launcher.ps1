# ~/.config/zellij/launcher.ps1
# Pick a Windows Terminal profile (fzf) and run it in a new Zellij tab.
#
# Strategy: write a small .cmd in %TEMP% with `set` for profile env, then the same commandline
# string WT would pass to CreateProcess. Zellij only gets `cmd /c <path>` (short argv, no
# backslash-mangling in long -Command lines). Process-agnostic: any exe, any args.

# --- Zellij UI workaround ----------------------------------------------------
Start-Sleep -Milliseconds 150
zellij action show-floating-panes 2>$null

$settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Error "Windows Terminal settings not found at $settingsPath"
    exit 1
}

if (-not $env:ZELLIJ_SESSION_NAME) {
    Write-Warning 'ZELLIJ_SESSION_NAME is not set. Pass --session when starting zellij, or this may fail.'
}

$wtRoot = (Get-Content $settingsPath -Raw | ConvertFrom-Json).profiles
$profiles = $wtRoot.list | Where-Object { $_.commandline -and -not $_.hidden }

$picked = $profiles.name | fzf `
    --prompt='Terminal Profile > ' `
    --header='Select a Windows Terminal profile to launch in a new tab' `
    --border=rounded --no-info `
    --bind='esc:abort' --bind='ctrl-c:abort'
if (-not $picked) { exit 0 }

$wtProfile = $profiles | Where-Object name -EQ $picked | Select-Object -First 1
if (-not $wtProfile) { exit 0 }

# Merge environment: defaults, then profile (profile wins). Expand %VAR% in each value.
$wtEnv = [ordered]@{}
foreach ($src in @(
        $(if ($wtRoot.defaults) { $wtRoot.defaults.environment }),
        $wtProfile.environment)) {
    if ($null -eq $src) { continue }
    foreach ($prop in $src.psobject.properties) {
        $wtEnv[$prop.Name] = [Environment]::ExpandEnvironmentVariables([string]$prop.Value)
    }
}

# Same commandline WT would use, with %...% expanded (path-friendly for the .cmd file).
$expandedCmd = [Environment]::ExpandEnvironmentVariables($wtProfile.commandline)

# Build %TEMP%\zellij-launcher.cmd — run the profile like cmd.exe would (one line = one process command line).
$cmdFile = Join-Path $env:TEMP 'zellij-launcher.cmd'
$lines = [System.Collections.Generic.List[string]]::new()
[void]$lines.Add('@echo off')
foreach ($kv in $wtEnv.GetEnumerator()) {
    $v = ([string]$kv.Value) -replace '"', '""'
    [void]$lines.Add(('set "{0}={1}"' -f $kv.Key, $v))
}
[void]$lines.Add($expandedCmd)
# OEM (CP437) is what cmd.exe expects for batch files on typical Windows installs.
$lines | Set-Content -Path $cmdFile -Encoding OEM

$zellij = (Get-Command zellij -ErrorAction SilentlyContinue).Source
if (-not $zellij) { $zellij = 'zellij' }

$comspec = $env:ComSpec
if (-not $comspec) { $comspec = "$env:SystemRoot\System32\cmd.exe" }

try {
    & $zellij @(
        '--session', $env:ZELLIJ_SESSION_NAME
        'action', 'new-tab', '--close-on-exit', '--cwd', $PWD.Path
        '--', $comspec, '/c', $cmdFile
    )
}
catch {
    Write-Error $_
    exit 1
}
