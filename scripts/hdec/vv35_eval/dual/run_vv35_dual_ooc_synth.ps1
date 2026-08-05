param(
    [string]$RepoRoot = "E:\HDEC\cva6-vhdc-core\tmp\hdec_vv35_ecc_area_worktree",
    [Parameter(Mandatory = $true)]
    [string]$OutRoot,
    [double]$PeriodNs = 5.0,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$out = [System.IO.Path]::GetFullPath($OutRoot)
$vivado = Join-Path $VivadoBin "vivado.bat"
$tcl = Join-Path $repo "scripts\hdec\vv35_eval\dual\vv35_dual_ooc_synth.tcl"
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado not found: $vivado" }
if (Test-Path -LiteralPath $out) {
    if (Get-ChildItem -LiteralPath $out -Force | Select-Object -First 1) {
        throw "Output directory is not empty: $out"
    }
} else {
    New-Item -ItemType Directory -Path $out -Force | Out-Null
}

$version = & $vivado -version 2>&1
if (($version -join "`n") -notmatch 'v2024\.2') { throw "Vivado 2024.2 is required" }

$trackedInputs = @(
    (Join-Path $repo "core\hdec\rtl\hdec_top.sv"),
    (Join-Path $repo "verif\hdec\vv35_eval\dual\vv35_dual_accel_core_top.sv"),
    (Join-Path $repo "verif\hdec\vv35_eval\dual\vv35_dual_ooc_ip_wrappers.sv"),
    (Join-Path $repo "verif\hdec\vv35_eval\dual\vv35_dual_ooc_ip_stubs.sv"),
    $tcl
)
$before = foreach ($path in $trackedInputs) {
    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    [pscustomobject]@{ path=$item.FullName; bytes=$item.Length; sha256=$hash.Hash.ToLowerInvariant() }
}
$before | Export-Csv -LiteralPath (Join-Path $out "input_hashes_before.csv") -NoTypeInformation -Encoding UTF8

$periodText = $PeriodNs.ToString("0.############", [System.Globalization.CultureInfo]::InvariantCulture)
& $vivado -mode batch -notrace `
    -log (Join-Path $out "vivado_ooc.log") `
    -journal (Join-Path $out "vivado_ooc.jou") `
    -source $tcl -tclargs $repo $out $periodText
if ($LASTEXITCODE -ne 0) { throw "OOC dual synthesis failed; see $out\vivado_ooc.log" }

$after = foreach ($path in $trackedInputs) {
    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    [pscustomobject]@{ path=$item.FullName; bytes=$item.Length; sha256=$hash.Hash.ToLowerInvariant() }
}
$after | Export-Csv -LiteralPath (Join-Path $out "input_hashes_after.csv") -NoTypeInformation -Encoding UTF8
if (Compare-Object $before $after -Property path,bytes,sha256) {
    throw "Source files changed during synthesis"
}

Get-Content -LiteralPath (Join-Path $out "reports\run_summary.txt")
Write-Host "VV35 independent HDC+ECC accelerator output: $out"
