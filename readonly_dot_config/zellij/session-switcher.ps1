$lock = "$env:TEMP\zellij-session-switcher.lock"

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
    while ($true) {
        $sessions = @(zellij ls --no-formatting 2>$null)
        if (-not $sessions) { break }
        Clear-Host
        $sessionNames = $sessions | ForEach-Object { ($_ -split '\s+')[0] }
        $timeDir = "$env:TEMP\zellij-session-times"
        if (Test-Path $timeDir) {
            Get-ChildItem $timeDir |
                Where-Object { $_.Name -notin $sessionNames } |
                Remove-Item -ErrorAction SilentlyContinue
        }
        $sessions = @($sessions | Sort-Object {
            $name = ($_ -split '\s+')[0]
            if ($name -eq $env:ZELLIJ_SESSION_NAME) {
                [long]::MaxValue
            } else {
                $timeFile = Join-Path $timeDir $name
                if (Test-Path $timeFile) {
                    $t = Get-Content $timeFile -Raw -ErrorAction SilentlyContinue
                    if ($t) { -[long]$t.Trim() } else { [long]::MaxValue - 1 }
                } else {
                    [long]::MaxValue - 1
                }
            }
        })
        $clientData = $sessions | ForEach-Object -Parallel {
            $name = ($_ -split '\s+')[0]
            $lines = @(zellij --session $name action list-clients 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\S' })
            [pscustomobject]@{ Name = $name; Count = $lines.Count }
        } -ThrottleLimit 20
        $clientCounts = @{}
        foreach ($item in $clientData) { $clientCounts[$item.Name] = $item.Count }
        $sessions = $sessions | ForEach-Object {
            $name = ($_ -split '\s+')[0]
            $count = $clientCounts[$name]
            $timeFile = Join-Path $timeDir $name
            $lastUsed = if (Test-Path $timeFile) {
                $t = Get-Content $timeFile -Raw -ErrorAction SilentlyContinue
                if ($t) {
                    $elapsed = [TimeSpan]::FromTicks([DateTime]::UtcNow.Ticks - [long]$t.Trim())
                    if     ($elapsed.TotalSeconds -lt 60) { "$([int]$elapsed.TotalSeconds)s" }
                    elseif ($elapsed.TotalMinutes -lt 60) { "$([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s" }
                    elseif ($elapsed.TotalHours   -lt 24) { "$([int]$elapsed.TotalHours)h$($elapsed.Minutes)m" }
                    else                                  { "$([int]$elapsed.TotalDays)d$($elapsed.Hours)h" }
                } else { 'never' }
            } else { 'never' }
            $current = if ($name -eq $env:ZELLIJ_SESSION_NAME) { ' (current)' } else { '' }
            "$name ($count attached) [$lastUsed]$current"
        }
        $i = 1
        $numbered = $sessions | ForEach-Object {
            $label = if ($i -le 9) { "$i" } elseif ($i -eq 10) { "0" } else { " " }
            $i++
            "$label  $_"
        }
        $result = @($numbered | fzf --expect "ctrl-d,ctrl-n" --nth "2.." --header "enter:switch  ctrl-d:delete  ctrl-n:new  esc:close" --bind "1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept,4:pos(4)+accept,5:pos(5)+accept,6:pos(6)+accept,7:pos(7)+accept,8:pos(8)+accept,9:pos(9)+accept,0:pos(10)+accept")
        if (-not $result -or $result.Count -lt 1) { break }
        $key = $result[0]

        if ($key -eq 'ctrl-n') {
            $newName = Read-Host "New session name"
            if ($newName) {
                zellij action switch-session $newName
                break
            }
        } else {
            if (-not $result[1]) { break }
            $name = ($result[1] -split '\s+')[1]
            if ($key -eq 'ctrl-d') {
                if ($name -eq $env:ZELLIJ_SESSION_NAME) {
                    Read-Host "Cannot delete the current session. Press Enter to continue"
                } else {
                    zellij delete-session $name 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "Session '$name' is active. Kill it? [y/N] " -NoNewline
                        $confirm = Read-Host
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            zellij kill-session $name 2>$null
                        }
                    }
                }
            } else {
                zellij action switch-session $name
                break
            }
        }
    }
} finally {
    Remove-Item $lock -ErrorAction SilentlyContinue
}
