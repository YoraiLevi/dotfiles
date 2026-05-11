# Run after timer install + unit tests. Exercises auto-commit message shapes; prints subject/body to CI logs.
$ErrorActionPreference = 'Stop'

# Same as README “The dotfiles command”
function dotfiles { git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" @args }

# Surface native (non-.NET) failures: $ErrorActionPreference=Stop doesn't catch git exit codes.
function Invoke-Native([string]$Description) {
    if ($LASTEXITCODE -ne 0) {
        throw "ci-commit-message-demos.ps1: $Description failed (exit $LASTEXITCODE)"
    }
}

$wt = $env:USERPROFILE
$ac = Join-Path $HOME '.dotfiles\.auto-commit.ps1'

function Dump-Msg([string]$Title) {
    Write-Host "::group::$Title"
    Write-Host '--- subject (git log -1 --pretty=%s) ---'
    dotfiles log -1 --pretty=%s
    Write-Host '--- body (git log -1 --pretty=%b) ---'
    dotfiles log -1 --pretty=%b
    Write-Host '::endgroup::'
}

Write-Host "ci-commit-message-demos.ps1: auto-commit script=$ac"

# Pathspecs are CWD-relative; cd to $HOME so demo paths resolve at the work-tree root.
Set-Location $wt

# Prep: extend the (restrictive) .gitignore to permit demo paths, then seed a tracked target.
Write-Host "ci-commit-message-demos.ps1: prep — unignore demo paths and seed .demo-target.txt"
@'

# ci-demo: allow demo paths
!/.demo-*
!/.ci-*
'@ | Add-Content -Path (Join-Path $wt '.gitignore')
'demo initial content' | Out-File -FilePath (Join-Path $wt '.demo-target.txt') -Encoding utf8
dotfiles add -- (Join-Path $wt '.gitignore') (Join-Path $wt '.demo-target.txt'); Invoke-Native 'dotfiles add (prep)'
dotfiles commit -m "ci-demo: seed demo target & allow demo paths"; Invoke-Native 'dotfiles commit (prep)'

# --- modified only ---
Add-Content (Join-Path $wt '.demo-target.txt') "`npatch-demo-pwsh"
& $ac
Dump-Msg 'Sample A: modified tracked file (mod)'

# --- new tracked file ---
$added = Join-Path $wt '.ci-demo-added.txt'
'ci-demo-added' | Out-File -FilePath $added -Encoding utf8
dotfiles add -- $added; Invoke-Native 'dotfiles add (sample B)'
& $ac
Dump-Msg 'Sample B: new tracked file (add)'

# --- deletion ---
Remove-Item -Force -ErrorAction SilentlyContinue $added
& $ac
Dump-Msg 'Sample C: deleted file (del)'

# --- rename ---
dotfiles mv -- .demo-target.txt .demo-renamed.txt; Invoke-Native 'dotfiles mv (sample D)'
& $ac
Dump-Msg 'Sample D: rename (ren)'

# --- many paths ---
1..35 | ForEach-Object {
    $i = '{0:D2}' -f $_
    $p = Join-Path $wt ".ci-long-$i.txt"
    "long-$i" | Out-File -FilePath $p -Encoding utf8
}
Get-ChildItem -Path $wt -Filter '.ci-long-*.txt' | ForEach-Object {
    dotfiles add -- $_.FullName; Invoke-Native "dotfiles add $($_.Name)"
}
& $ac
Dump-Msg 'Sample E: many adds (truncated subject when >160 chars)'

# --- combined ---
Add-Content (Join-Path $wt '.demo-renamed.txt') "`ncombo-edit"
$newCombo = Join-Path $wt '.ci-combo-new.txt'
'combo-new' | Out-File -FilePath $newCombo -Encoding utf8
dotfiles add -- $newCombo; Invoke-Native 'dotfiles add (sample F)'
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $wt '.ci-long-01.txt')
& $ac
Dump-Msg 'Sample F: add + mod + del together'

Write-Host 'ci-commit-message-demos.ps1: finished'
