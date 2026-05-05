# ~/.config/zellij/launcher.ps1
# Pick a Windows Terminal profile (fzf) and run it in a new Zellij tab.
#
# Strategy: write a small .cmd in %TEMP% with `set` for profile env, then the same commandline
# string WT would pass to CreateProcess. Zellij only gets `cmd /c <path>` (short argv, no
# backslash-mangling in long -Command lines). Process-agnostic: any exe, any args.

$lock = "$env:TEMP\zellij-launcher.lock"

if (Test-Path $lock) {
    $existingPid = Get-Content $lock -ErrorAction SilentlyContinue
    if ($existingPid) {
        $proc = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -match 'pwsh') {
            Stop-Process -Id ([int]$existingPid) -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item $lock -ErrorAction SilentlyContinue
}

$PID | Set-Content $lock

try {
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

    $i = 1
    $numberedNames = $profiles.name | ForEach-Object {
        $label = if ($i -le 9) { "$i" } elseif ($i -eq 10) { "0" } else { " " }
        $i++
        "$label  $_"
    }
    $pickedLine = $numberedNames | fzf `
        --prompt='Terminal Profile > ' `
        --header='Select a Windows Terminal profile to launch in a new tab' `
        --border=rounded --no-info --nth='2..' `
        --bind='esc:abort' --bind='ctrl-c:abort' `
        --bind='1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept,4:pos(4)+accept,5:pos(5)+accept,6:pos(6)+accept,7:pos(7)+accept,8:pos(8)+accept,9:pos(9)+accept,0:pos(10)+accept'
    if (-not $pickedLine) { exit 0 }
    $picked = $pickedLine -replace '^.\s{2}', ''

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
    'if errorlevel 1 pause' | Out-File -FilePath $cmdFile -Append
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
} finally {
    Remove-Item $lock -ErrorAction SilentlyContinue
}
