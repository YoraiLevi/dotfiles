# Run after timer install + unit tests. Exercises auto-commit message shapes; prints subject/body to CI logs.
$ErrorActionPreference = 'Stop'

$g = Join-Path $env:USERPROFILE '.dotfiles'
$wt = $env:USERPROFILE
$ac = Join-Path $g '.auto-commit.ps1'

function Dump-Msg([string]$Title) {
    Write-Host "::group::$Title"
    Write-Host '--- subject (git log -1 --pretty=%s) ---'
    git --git-dir="$g" --work-tree="$wt" log -1 --pretty=%s
    Write-Host '--- body (git log -1 --pretty=%b) ---'
    git --git-dir="$g" --work-tree="$wt" log -1 --pretty=%b
    Write-Host '::endgroup::'
}

Write-Host "ci-commit-message-demos.ps1: auto-commit script=$ac"

# --- modified only ---
Add-Content (Join-Path $wt 'README.md') "`npatch-demo-pwsh"
& $ac
Dump-Msg 'Sample A: modified tracked file (mod)'

# --- new tracked file ---
$added = Join-Path $wt '.ci-demo-added.txt'
'ci-demo-added' | Out-File -FilePath $added -Encoding utf8
git --git-dir="$g" --work-tree="$wt" add -- $added
& $ac
Dump-Msg 'Sample B: new tracked file (add)'

# --- deletion ---
Remove-Item -Force -ErrorAction SilentlyContinue $added
& $ac
Dump-Msg 'Sample C: deleted file (del)'

# --- rename ---
Set-Location $wt
git --git-dir="$g" --work-tree="$wt" mv -- README.md README.ci-demo-renamed.md
& $ac
Dump-Msg 'Sample D: rename (ren)'

# --- many paths ---
1..35 | ForEach-Object {
    $i = '{0:D2}' -f $_
    $p = Join-Path $wt ".ci-long-$i.txt"
    "long-$i" | Out-File -FilePath $p -Encoding utf8
}
Get-ChildItem -Path $wt -Filter '.ci-long-*.txt' | ForEach-Object {
    git --git-dir="$g" --work-tree="$wt" add -- $_.FullName
}
& $ac
Dump-Msg 'Sample E: many adds (truncated subject when >160 chars)'

# --- combined ---
Add-Content (Join-Path $wt 'README.ci-demo-renamed.md') "`ncombo-edit"
$newCombo = Join-Path $wt '.ci-combo-new.txt'
'combo-new' | Out-File -FilePath $newCombo -Encoding utf8
git --git-dir="$g" --work-tree="$wt" add -- $newCombo
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $wt '.ci-long-01.txt')
& $ac
Dump-Msg 'Sample F: add + mod + del together'

Write-Host 'ci-commit-message-demos.ps1: finished'
