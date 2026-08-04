param(
    [string]$RepoRoot = "E:\HDEC\cva6-vhdc-core\tmp\hdec_vv35_global_ppa_worktree",
    [string]$OutRoot,
    [double]$PeriodNs = 5.0,
    [string]$RunLabel = "vv35_postroute",
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin"
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado launcher not found: $vivado"
}

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutRoot = Join-Path $repo "reports\hdec\vv35_eval_impl_$stamp"
}

$out = [System.IO.Path]::GetFullPath($OutRoot)
New-Item -ItemType Directory -Force -Path $out | Out-Null

$script = Join-Path $repo "scripts\hdec\vv35_eval\vv35_impl_route.tcl"
$log = Join-Path $out "vivado_impl.log"
$journal = Join-Path $out "vivado_impl.jou"

& $vivado -mode batch -notrace -log $log -journal $journal `
    -source $script -tclargs $repo $out $PeriodNs $RunLabel
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "VV35 implementation failed with exit code $exitCode. See $log"
}

$summary = Join-Path $out "reports\run_summary.txt"
if (-not (Test-Path -LiteralPath $summary)) {
    throw "Implementation completed without run_summary.txt. See $log"
}

Get-Content -LiteralPath $summary
Write-Host "VV35 implementation output: $out"
