#!/usr/bin/env pwsh
#Requires -Version 7

$raw  = $input | Out-String
$data = $raw | ConvertFrom-Json

# '{"session_id":"85d6534a-7dcf-4627-bd0a-e2c0915fb82f","session_name":"Test Session","transcript_path":"C:/Users/devic/.claude/projects/C--Users-devic-source-test/85d6534a-7dcf-4627-bd0a-e2c0915fb82f.jsonl","model":{"id":"claude-sonnet-4-6","display_name":"Sonnet"},"agent":{"name":"security-reviewer"},"effort":{"level":"xhigh"},"thinking":{"enabled":true},"context_window":{"total_input_tokens":15234,"total_output_tokens":4521,"context_window_size":200000,"used_percentage":8},"exceeds_200k_tokens":false,"cost":{"total_cost_usd":0.0123,"total_lines_added":156,"total_lines_removed":23},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":9999999999},"seven_day":{"used_percentage":41.2,"resets_at":9999999999}},"workspace":{"project_dir":"C:/Users/devic/source/test","current_dir":"C:/Users/devic/source/test/src","git_worktree":"feature-xyz","added_dirs":["C:/Users/devic/extra"]},"version":"2.1.90","output_style":{"name":"Explanatory"}}' | pwsh -NoProfile -File "$env:USERPROFILE\.claude\statusline.ps1"

function Get-TerminalWidth {
    # COLUMNS env var is set by Windows Terminal and inherited through the process chain
    # Claude Code spawns statusLine with no console (piped I/O), so console APIs are unreliable
    $c = [int]($env:COLUMNS ?? 0);             if ($c -gt 0) { return $c }
    # Console APIs work when stdout is NOT redirected (e.g. manual test runs)
    try { $w = [Console]::WindowWidth;          if ($w -gt 0) { return $w } } catch {}
    try { $w = [Console]::BufferWidth;          if ($w -gt 0) { return $w } } catch {}
    # RawUI returns 120 in headless mode — only trust it if it exceeds that known default
    try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -gt 120) { return $w } } catch {}
    return 120
}
$COLS = Get-TerminalWidth

$R      = "`e[0m"
$DIM    = "`e[2m"
$GREEN  = "`e[32m"
$RED    = "`e[31m"
$YELLOW = "`e[33m"
$CYAN   = "`e[36m"
$BOLD   = "`e[1m"

function Strip-Ansi([string]$s)       { $s -replace "\x1b\[[0-9;]*[mGKHFJ]", "" }
function Vis-Len([string]$s)          { (Strip-Ansi $s).Length }

function Trunc-Clean([string]$s, [int]$max) {
    # Strip ANSI, truncate to max visible chars
    $clean = Strip-Ansi $s
    if ($clean.Length -le $max) { return $clean }
    return $clean.Substring(0, [math]::Max(0, $max - 1)) + "…"
}

function Padded-Line([string]$l, [string]$r) {
    $ll  = Vis-Len $l
    $rl  = Vis-Len $r
    $gap = $COLS - $ll - $rl
    if ($gap -ge 1) { return "$l$(' ' * $gap)$r" }
    # Narrow: drop colors from right, truncate to fit
    $avail = $COLS - $ll - 1
    if ($avail -le 0) { return (Trunc-Clean $l $COLS) }
    return "$l $(Trunc-Clean $r $avail)"
}

function Right-Align([string]$s) {
    $vl  = Vis-Len $s
    $pad = $COLS - $vl
    if ($pad -ge 0) { return "$(' ' * $pad)$s" }
    return Trunc-Clean $s $COLS
}

function Fmt-K([long]$n)   { if ($n -ge 10000) { "{0:F1}k" -f ($n/1000.0) } else { "$n" } }
function Fmt-Ctx([long]$n) { if ($n -ge 1000000) { "$($n/1000000)M" } else { "$($n/1000)k" } }

function Fmt-Time([long]$ts) {
    if ($ts -le 0) { return "" }
    $diff = $ts - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($diff -le 0) { return "now" }
    $h = [math]::Floor($diff / 3600)
    $m = [math]::Floor(($diff % 3600) / 60)
    if ($h -ge 24) { return "$([math]::Floor($h/24))d $($h % 24)h" }
    return "${h}h $($m.ToString('00'))m"
}

function Pct-Color([double]$p) {
    if ($p -ge 90) { return $RED }
    if ($p -ge 70) { return $YELLOW }
    return $GREEN
}

function Short-Path([string]$p) {
    if (-not $p) { return "" }
    $h = ($HOME ?? $env:USERPROFILE).Replace('\', '/')
    $pNorm = $p.Replace('\', '/')
    if ($h -and $pNorm.StartsWith($h, [StringComparison]::OrdinalIgnoreCase)) {
        return "~" + $pNorm.Substring($h.Length)
    }
    return $p
}

# ── Parse ─────────────────────────────────────────────────────
$sessionId   = ($data.session_id ?? "").Substring(0, [math]::Min(8, ($data.session_id ?? "").Length))
$sessionName = $data.session_name ?? ""
$transcript  = Short-Path ($data.transcript_path ?? "")

$linesAdd = $data.cost?.total_lines_added   ?? 0
$linesRem = $data.cost?.total_lines_removed ?? 0

$agent    = $data.agent?.name    ?? ""
$modelId  = $data.model?.id      ?? ""
$effort   = $data.effort?.level  ?? ""
$thinking = $data.thinking?.enabled ?? $false

$totIn   = $data.context_window?.total_input_tokens   ?? 0
$totOut  = $data.context_window?.total_output_tokens  ?? 0
$usedPct = [double]($data.context_window?.used_percentage   ?? 0)
$ctxSize = $data.context_window?.context_window_size  ?? 200000
$exceeds = $data.exceeds_200k_tokens ?? $false

$cost    = "{0:F4}" -f ([double]($data.cost?.total_cost_usd ?? 0))

$fhPct   = $data.rate_limits?.five_hour?.used_percentage
$fhReset = [long]($data.rate_limits?.five_hour?.resets_at  ?? 0)
$sdPct   = $data.rate_limits?.seven_day?.used_percentage
$sdReset = [long]($data.rate_limits?.seven_day?.resets_at  ?? 0)

$project   = Short-Path ($data.workspace?.project_dir  ?? "")
$worktree  = $data.workspace?.git_worktree ?? ""
$cwd       = Short-Path ($data.workspace?.current_dir  ?? "")
$addedDirs = ($data.workspace?.added_dirs ?? @()) | ForEach-Object { Short-Path $_ }
$version   = $data.version ?? ""
$styleName = $data.output_style?.name ?? ""

# ── Line 1 (right-aligned): session_id  session_name  transcript ──
$L1 = "${DIM}${sessionId}${R}"
if ($sessionName) { $L1 += "  $sessionName" }
if ($transcript)  { $L1 += "  ${DIM}${transcript}${R}" }

# ── Line 2 left: [+] added  [-] removed ──────────────────────────
$L2L = "${GREEN}[+] $linesAdd${R}  ${RED}[-] $linesRem${R}"

# ── Line 2 right: agent  model  effort  thinking  tokens  ctx ────
$L2R = ""
if ($agent)  { $L2R += "$agent  " }
$L2R += $modelId
if ($effort) { $L2R += "  $effort" }
$L2R += if ($thinking) { "  ${CYAN}thinking ✓${R}" } else { "  ${DIM}thinking ✗${R}" }
$pctC = Pct-Color $usedPct
$L2R += "  $(Fmt-K $totIn)in + $(Fmt-K $totOut)out  ${pctC}${usedPct}%${R}/$(Fmt-Ctx $ctxSize)"
if ($exceeds) { $L2R += "  ${RED}${BOLD}⚠ EXCEEDS 200k${R}" }

# ── Line 3 left: project: dir ─────────────────────────────────────
$L3L = "project: $project"

# ── Line 3 right: cost  5h rate  7d rate ─────────────────────────
$L3R = "`$$cost"
if ($null -ne $fhPct) {
    $c = Pct-Color ([double]$fhPct); $t = Fmt-Time $fhReset
    $L3R += "  ${c}5h: ${fhPct}%${R} ($t)"
}
if ($null -ne $sdPct) {
    $c = Pct-Color ([double]$sdPct); $t = Fmt-Time $sdReset
    $L3R += "  ${c}7d: ${sdPct}%${R} ($t)"
}

# ── Line 4 left: [worktree] name  [cwd] dir ───────────────────────
$L4L = if ($worktree) { "[worktree] $worktree  " } else { "" }
$L4L += "[cwd] $cwd"

# ── Line 4 right: added_dirs  version  style ─────────────────────
$L4R = ""
if ($addedDirs) { $L4R = ($addedDirs -join "  ") + "  " }
$L4R += "v$version  $styleName"

# ── Output (LF-only line endings — CRLF breaks Claude Code's status bar rendering) ──
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::Write(
    "$(Right-Align $L1)`n$(Padded-Line $L2L $L2R)`n$(Padded-Line $L3L $L3R)`n$(Padded-Line $L4L $L4R)`n"
)
