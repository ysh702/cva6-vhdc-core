<#
.SYNOPSIS
Compatibility redirect for the retired VV33 phase-lifetime probe.

.DESCRIPTION
The former probe depended on the rejected vv33_fg_* sidecar signals.  This
entry point now delegates to the maintained fixed-workload smoke comparison.
#>

[CmdletBinding()]
param(
    [string]$Seed,
    [string]$VectorDir,
    [string]$OutRoot,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$replacementRunner = Join-Path $scriptDir "run_vv33_fixed_workload.ps1"
$replacementArgs = @{
    Suite = "smoke"
    Mode = "compare"
    VivadoBin = $VivadoBin
}
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $replacementArgs.Seed = $Seed
}
if (-not [string]::IsNullOrWhiteSpace($VectorDir)) {
    $replacementArgs.VectorDir = $VectorDir
}
if (-not [string]::IsNullOrWhiteSpace($OutRoot)) {
    $replacementArgs.OutRoot = $OutRoot
}
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    $replacementArgs.PythonExe = $PythonExe
}

Write-Warning (
    "VV33 phase_lifetime is retired because its vv33_fg_* signals were " +
    "removed. Delegating to fixed_workload smoke compare."
)
& $replacementRunner @replacementArgs
$replacementExit = $LASTEXITCODE
Write-Host (
    "[VV33:phase_lifetime_contract] RETIRED " +
    "replacement=fixed_workload_smoke status=$replacementExit"
)
exit $replacementExit
