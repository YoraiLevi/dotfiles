#Requires -Version 7.0
<#
.SYNOPSIS
  Shared Git hook runner (PowerShell). Git invokes one stub per hook name; each stub calls:
    pwsh -File .../Run-GitHook.ps1 <hook-name> <git's args...>

.DESCRIPTION
  Design (same idea as the bash version in the referenced notes):
  1. dispatch — single switch on HookName routes to one Invoke-Hook_* function.
  2. Invoke-Hook_* — one function per Git hook; start with Write-GitHookLog and add checks.
     Exit non-zero from hooks that may block the operation (when Git allows --no-verify).
  3. Invoke-Hook_Default — safety net for unknown hook names.

  Log line goes to stderr so it does not interfere with hooks that use stdout (e.g. fsmonitor).
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$HookName,

  [Parameter(ValueFromRemainingArguments = $true)]
  [object[]]$GitArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-GitHookLog {
  [Console]::Error.WriteLine("[githook] $HookName")
}

function Invoke-Hook_Default {
  Write-GitHookLog
}

# --- applypatch / am ---------------------------------------------------------

function Invoke-Hook_applypatch_msg {
  # Args: $1 = path to proposed commit message file
  Write-GitHookLog
}

function Invoke-Hook_pre_applypatch {
  Write-GitHookLog
}

function Invoke-Hook_post_applypatch {
  Write-GitHookLog
}

# --- commit ------------------------------------------------------------------

function Invoke-Hook_pre_commit {
  Write-GitHookLog
}

function Invoke-Hook_pre_merge_commit {
  Write-GitHookLog
}

function Invoke-Hook_prepare_commit_msg {
  # Args: $1 = message file, $2 = source (message|template|merge|squash|commit)
  Write-GitHookLog
}

function Invoke-Hook_commit_msg {
  # Args: $1 = path to proposed commit message
  Write-GitHookLog
}

function Invoke-Hook_post_commit {
  Write-GitHookLog
}

# --- branch / merge / rebase -------------------------------------------------

function Invoke-Hook_pre_rebase {
  # Args: upstream [, branch]
  Write-GitHookLog
}

function Invoke-Hook_post_checkout {
  # Args: $1 = previous HEAD, $2 = new HEAD, $3 = 1 (branch) or 0 (file)
  Write-GitHookLog
}

function Invoke-Hook_post_merge {
  # Args: $1 = squash flag
  Write-GitHookLog
}

function Invoke-Hook_post_rewrite {
  # Args: $1 = amend | rebase; rewritten pairs on stdin
  Write-GitHookLog
}

# --- remote ------------------------------------------------------------------

function Invoke-Hook_pre_push {
  # Args: $1 = remote name, $2 = remote URL; ref updates on stdin
  Write-GitHookLog
}

function Invoke-Hook_pre_receive {
  # Stdin: lines "<old> <new> <ref>"
  Write-GitHookLog
}

function Invoke-Hook_update {
  # Args: $1 = ref name, $2 = old sha, $3 = new sha
  Write-GitHookLog
}

function Invoke-Hook_post_receive {
  Write-GitHookLog
}

function Invoke-Hook_post_update {
  # Args: updated ref names
  Write-GitHookLog
}

function Invoke-Hook_reference_transaction {
  # Args: $1 = preparing|prepared|committed|aborted; updates on stdin
  Write-GitHookLog
}

function Invoke-Hook_push_to_checkout {
  # Args: $1 = proposed new HEAD commit
  Write-GitHookLog
}

# --- maintenance / misc ------------------------------------------------------

function Invoke-Hook_pre_auto_gc {
  Write-GitHookLog
}

function Invoke-Hook_sendemail_validate {
  # Args: $1 = email body file, $2 = headers file
  Write-GitHookLog
}

function Invoke-Hook_post_index_change {
  # Args: $1 = working dir updated (0|1), $2 = skip-worktree may have changed
  Write-GitHookLog
}

# --- git-p4 ------------------------------------------------------------------

function Invoke-Hook_p4_changelist {
  # Args: $1 = changelist message file
  Write-GitHookLog
}

function Invoke-Hook_p4_prepare_changelist {
  Write-GitHookLog
}

function Invoke-Hook_p4_post_changelist {
  Write-GitHookLog
}

function Invoke-Hook_p4_pre_submit {
  Write-GitHookLog
}

# --- dispatch ----------------------------------------------------------------

function Invoke-GitHookDispatch {
  switch ($HookName) {
    'applypatch-msg' { Invoke-Hook_applypatch_msg @GitArguments; break }
    'pre-applypatch' { Invoke-Hook_pre_applypatch @GitArguments; break }
    'post-applypatch' { Invoke-Hook_post_applypatch @GitArguments; break }
    'pre-commit' { Invoke-Hook_pre_commit @GitArguments; break }
    'pre-merge-commit' { Invoke-Hook_pre_merge_commit @GitArguments; break }
    'prepare-commit-msg' { Invoke-Hook_prepare_commit_msg @GitArguments; break }
    'commit-msg' { Invoke-Hook_commit_msg @GitArguments; break }
    'post-commit' { Invoke-Hook_post_commit @GitArguments; break }
    'pre-rebase' { Invoke-Hook_pre_rebase @GitArguments; break }
    'post-checkout' { Invoke-Hook_post_checkout @GitArguments; break }
    'post-merge' { Invoke-Hook_post_merge @GitArguments; break }
    'pre-push' { Invoke-Hook_pre_push @GitArguments; break }
    'pre-receive' { Invoke-Hook_pre_receive @GitArguments; break }
    'update' { Invoke-Hook_update @GitArguments; break }
    'post-receive' { Invoke-Hook_post_receive @GitArguments; break }
    'post-update' { Invoke-Hook_post_update @GitArguments; break }
    'reference-transaction' { Invoke-Hook_reference_transaction @GitArguments; break }
    'push-to-checkout' { Invoke-Hook_push_to_checkout @GitArguments; break }
    'pre-auto-gc' { Invoke-Hook_pre_auto_gc @GitArguments; break }
    'post-rewrite' { Invoke-Hook_post_rewrite @GitArguments; break }
    'sendemail-validate' { Invoke-Hook_sendemail_validate @GitArguments; break }
    'post-index-change' { Invoke-Hook_post_index_change @GitArguments; break }
    'p4-changelist' { Invoke-Hook_p4_changelist @GitArguments; break }
    'p4-prepare-changelist' { Invoke-Hook_p4_prepare_changelist @GitArguments; break }
    'p4-post-changelist' { Invoke-Hook_p4_post_changelist @GitArguments; break }
    'p4-pre-submit' { Invoke-Hook_p4_pre_submit @GitArguments; break }
    default { Invoke-Hook_Default @GitArguments; break }
  }
}

Invoke-GitHookDispatch
