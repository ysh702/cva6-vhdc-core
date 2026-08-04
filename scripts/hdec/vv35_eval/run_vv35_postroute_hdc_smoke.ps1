[CmdletBinding()]
param(
    [string]$Checkpoint,
    [string]$OutRoot,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe = "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
if ([string]::IsNullOrWhiteSpace($Checkpoint)) {
    $Checkpoint = Join-Path $repoRoot "reports\hdec\vv35_eval_postroute_repair_20260803\dcp\02_postroute_repaired.dcp"
}
$Checkpoint = [System.IO.Path]::GetFullPath($Checkpoint)
if (-not (Test-Path -LiteralPath $Checkpoint)) {
    throw "Checkpoint not found: $Checkpoint"
}
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv35_eval\postroute_hdc_$stamp"
}
$OutRoot = [System.IO.Path]::GetFullPath($OutRoot)
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$vivado = Join-Path $VivadoBin "vivado.bat"
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($vivado, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required Vivado tool not found: $tool"
    }
}

$exportDir = Join-Path $OutRoot "export"
$runDir = Join-Path $OutRoot "sim"
New-Item -ItemType Directory -Force -Path $exportDir, $runDir | Out-Null
$exportTcl = Join-Path $scriptDir "vv35_export_postroute_sim.tcl"
& $vivado -mode batch -nolog -nojournal -notrace -source $exportTcl `
    -tclargs $Checkpoint $exportDir 2>&1 |
    Tee-Object -LiteralPath (Join-Path $OutRoot "export.log") |
    ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    throw "Post-route netlist export failed with exit code $LASTEXITCODE"
}

$netlist = Join-Path $exportDir "hdec_top_postroute_timesim.v"
$sdfRaw = Join-Path $exportDir "hdec_top_postroute_max.sdf"
$sdf = Join-Path $exportDir "hdec_top_postroute_delay_only.sdf"
$stripSdf = Join-Path $scriptDir "strip_sdf_timingchecks.py"
if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Python runtime not found: $PythonExe"
}
& $PythonExe $stripSdf $sdfRaw $sdf 2>&1 |
    Tee-Object -LiteralPath (Join-Path $OutRoot "strip_sdf.log") |
    ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    throw "SDF timing-check stripping failed with exit code $LASTEXITCODE"
}
$pkg = Join-Path $repoRoot "core\hdec\rtl\hdec_pkg.sv"
$tb = Join-Path $repoRoot "verif\hdec\tb_hdec_hdc_full_flow_v20.sv"
$glbl = "E:\Vivado\Vivado\2024.2\data\verilog\src\glbl.v"

Push-Location $runDir
try {
    & $xvlog -sv $pkg $netlist $tb $glbl 2>&1 |
        Tee-Object -LiteralPath (Join-Path $runDir "xvlog_console.log") |
        ForEach-Object { Write-Host $_ }
    $xvlogExit = $LASTEXITCODE
    if ($xvlogExit -ne 0) { throw "xvlog failed: $xvlogExit" }

    $sdfArg = "/tb_hdec_hdc_full_flow_v20/dut=$($sdf.Replace('\', '/'))"
    # Windows PowerShell 5 splits a native argument containing '=' when it is
    # passed directly. A response file preserves the required root=file SDF
    # token byte-for-byte for xelab.
    $xelabArgs = Join-Path $runDir "xelab_args.f"
    @(
        "tb_hdec_hdc_full_flow_v20",
        "glbl",
        "-L", "simprims_ver",
        "--timescale", "1ns/1ps",
        "--maxdelay",
        "--sdfmax", $sdfArg,
        "-s", "tb_vv35_postroute_hdc"
    ) | Set-Content -LiteralPath $xelabArgs -Encoding ascii
    & $xelab -f $xelabArgs 2>&1 |
        Tee-Object -LiteralPath (Join-Path $runDir "xelab_console.log") |
        ForEach-Object { Write-Host $_ }
    $xelabExit = $LASTEXITCODE
    if ($xelabExit -ne 0) { throw "xelab failed: $xelabExit" }

    $runTcl = Join-Path $runDir "run_all.tcl"
    @("run all", "quit") | Set-Content -LiteralPath $runTcl -Encoding ascii
    $runTclForXsim = $runTcl.Replace('\', '/')
    & $xsim tb_vv35_postroute_hdc -tclbatch $runTclForXsim `
        -log (Join-Path $runDir "xsim.log") 2>&1 |
        Tee-Object -LiteralPath (Join-Path $runDir "xsim_console.log") |
        ForEach-Object { Write-Host $_ }
    $xsimExit = $LASTEXITCODE
    if ($xsimExit -ne 0) { throw "xsim failed: $xsimExit" }
}
finally {
    Pop-Location
}

$xsimLog = Join-Path $runDir "xsim.log"
$text = Get-Content -LiteralPath $xsimLog -Raw
$passMarker = "[HDEC_HDC_FULL_FLOW_V20] PASS"
$passCount = [regex]::Matches($text, [regex]::Escape($passMarker)).Count
$failed = [regex]::IsMatch($text, "(?im)(^\s*ERROR:|\bFAIL(?:ED)?\b|\*\*\s*(Error|Fatal):)")
$status = if (($passCount -eq 1) -and (-not $failed)) { "PASS" } else { "FAIL" }
$manifest = [ordered]@{
    schema = "hdec-vv35-postroute-hdc-smoke-v1"
    status = $status
    git_commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    checkpoint = $Checkpoint
    checkpoint_sha256 = (Get-FileHash -LiteralPath $Checkpoint -Algorithm SHA256).Hash.ToLower()
    netlist_sha256 = (Get-FileHash -LiteralPath $netlist -Algorithm SHA256).Hash.ToLower()
    sdf_sha256 = (Get-FileHash -LiteralPath $sdf -Algorithm SHA256).Hash.ToLower()
    source_sdf_sha256 = (Get-FileHash -LiteralPath $sdfRaw -Algorithm SHA256).Hash.ToLower()
    timing_checks = "SDF TIMINGCHECK groups removed; routed STA is authoritative; routed path and interconnect delays remain annotated"
    testbench = $tb
    testbench_sha256 = (Get-FileHash -LiteralPath $tb -Algorithm SHA256).Hash.ToLower()
    runner_sha256 = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLower()
    sdf_filter_sha256 = (Get-FileHash -LiteralPath $stripSdf -Algorithm SHA256).Hash.ToLower()
    pass_marker = $passMarker
    pass_marker_count = $passCount
    failure_marker_found = $failed
    xsim_log = $xsimLog
    completed_at = (Get-Date).ToString("o")
}
$manifest | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $OutRoot "run_manifest.json") -Encoding UTF8
Write-Host "[VV35:POSTROUTE_HDC] $status output=$OutRoot"
if ($status -ne "PASS") { exit 1 }
exit 0
