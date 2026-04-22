<#
.SYNOPSIS
    Runner for the chezmoi re-add Pester suite.

.DESCRIPTION
    Discovers and runs the test files alongside this script.

    By default only the unit tests (Sweep.Tests.ps1, PreHook.Tests.ps1) run
    because they have zero side effects. Pass -IncludeIntegration to also run
    Integration.Tests.ps1, which touches $HOME and produces git commits on
    origin/master.

.PARAMETER IncludeIntegration
    Include the 'Integration' tag tests (real chezmoi, real git commits).

.PARAMETER Output
    Pester output verbosity. Defaults to Detailed.

.EXAMPLE
    # Unit tests only (safe, no side effects):
    pwsh -NoProfile -File .\Invoke-PesterSuite.ps1

.EXAMPLE
    # Full suite including integration:
    pwsh -NoProfile -File .\Invoke-PesterSuite.ps1 -IncludeIntegration
#>
[CmdletBinding()]
param(
    [switch]$IncludeIntegration,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed'
)

$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path              = $PSScriptRoot
$config.Output.Verbosity      = $Output
$config.Run.PassThru          = $true
$config.Should.ErrorAction    = 'Stop'

if (-not $IncludeIntegration) {
    $config.Filter.ExcludeTag = @('Integration')
}

$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0) {
    exit 1
}
exit 0
