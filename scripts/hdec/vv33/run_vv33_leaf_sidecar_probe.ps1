<#
.SYNOPSIS
Runs the bounded VV33 final-leaf sidecar probe with one fresh random K.

.DESCRIPTION
The probe verifies two no-wide-state foreground operations while a K-233 PMUL
continues in the background:

* HCNTCLR writes the sixteen accumulator rows in compatible 1R1W cycles.
* HBIND advances one 256-bit chunk at each safe final-leaf boundary and reuses
  the existing VRF, hdc_src0_q, vec_payload_q, and XOR0 path.

Supplying -Seed or -VectorDir replays an earlier vector bundle.  The runner
requires Vivado Simulator 2024.2 and accepts a run only when the tool status,
PASS marker, PMUL cycle contract, lifecycle counts, conflict count, and unknown
write count all agree.
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
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv33\leaf_sidecar_probe_$timestamp"
}
$OutRoot = [System.IO.Path]::GetFullPath($OutRoot)
if (Test-Path -LiteralPath (Join-Path $OutRoot "run_manifest.json")) {
    throw "VV33 output already contains a completed run: $OutRoot"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Convert-MetricFields {
    param([Parameter(Mandatory = $true)][string]$Line)
    $fields = [ordered]@{}
    foreach ($match in [regex]::Matches($Line, "([A-Za-z0-9_]+)=([^\s]+)")) {
        $fields[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return $fields
}

$requiredTools = @("vivado.bat", "xvlog.bat", "xelab.bat", "xsim.bat")
foreach ($toolName in $requiredTools) {
    $toolPath = Join-Path $VivadoBin $toolName
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Required Vivado 2024.2 tool is missing: $toolPath"
    }
}
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$vivadoVersion = (& $xvlog --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $vivadoVersion -notmatch "v2024\.2") {
    throw "VV33 requires Vivado Simulator v2024.2. Detected: $vivadoVersion"
}

$generatedVectors = $false
if ([string]::IsNullOrWhiteSpace($VectorDir)) {
    $vectorRun = Join-Path $OutRoot "vector_run"
    $vv31Runner = Join-Path $repoRoot "scripts\hdec\vv31\run_vv31_regression.ps1"
    $vectorArgs = @{
        Suite = "quick"
        VectorsOnly = $true
        OutRoot = $vectorRun
    }
    if (-not [string]::IsNullOrWhiteSpace($Seed)) {
        $vectorArgs.Seed = $Seed
    }
    if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
        $vectorArgs.PythonExe = $PythonExe
    }
    & $vv31Runner @vectorArgs
    if ($LASTEXITCODE -ne 0) {
        throw "VV31 vector generation failed with exit code $LASTEXITCODE"
    }
    $VectorDir = Join-Path $vectorRun "vectors"
    $generatedVectors = $true
} else {
    $VectorDir = (Resolve-Path -LiteralPath $VectorDir).Path
}

$requiredVectors = @(
    "master_seed.mem", "scalar_count.mem", "pmul_scalars.mem",
    "pmul_point_x.mem", "pmul_point_y.mem", "pmul_expected_x.mem",
    "pmul_expected_y.mem", "hdc_episode_count.mem",
    "hdc_train_samples.mem", "hdc_role_vectors.mem",
    "hdc_role_rotations.mem", "hdc_permuted_roles_expected.mem",
    "hdc_bound_expected.mem", "hdc_prototypes_expected.mem",
    "hdc_query_vectors.mem", "hdc_hsim_expected.mem",
    "hdc_hmatch_expected.mem", "vector_manifest.json"
)
foreach ($name in $requiredVectors) {
    $path = Join-Path $VectorDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required VV33 vector file is missing: $path"
    }
}
$scalarCountText = (
    Get-Content -LiteralPath (Join-Path $VectorDir "scalar_count.mem") -Raw
).Trim()
$scalarCount = [Convert]::ToUInt32($scalarCountText, 16)
if ($scalarCount -ne 1) {
    throw "VV33 leaf-sidecar probe requires exactly one random K, got $scalarCount"
}

$runTcl = Join-Path $scriptDir "vv33_xsim_run.tcl"
$testName = "leaf_sidecar_probe"
$testTop = "tb_vv33_leaf_sidecar_probe"
$testFile = "verif/hdec/vv33/system/tb_vv33_leaf_sidecar_probe.sv"
$runnerLog = Join-Path $OutRoot "$testName.runner.log"
$vivado = Join-Path $VivadoBin "vivado.bat"
$hdecTopPath = Join-Path $repoRoot "core\hdec\rtl\hdec_top.sv"
$rtlStartHash = Get-Sha256 -Path $hdecTopPath
$toolExit = -1
$oldPath = $env:Path
try {
    $env:Path = "$VivadoBin;$oldPath"
    Push-Location $OutRoot
    try {
        & $vivado -mode batch -nolog -nojournal -notrace `
            -source $runTcl -tclargs `
            $repoRoot $repoRoot $OutRoot $testName `
            $testTop $testFile $VectorDir 2>&1 |
            Tee-Object -FilePath $runnerLog |
            ForEach-Object { Write-Host $_ }
        $toolExit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:Path = $oldPath
}
$rtlEndHash = Get-Sha256 -Path $hdecTopPath

$xsimDir = Join-Path $OutRoot "xsim_$testName"
$xsimLog = Join-Path $xsimDir "xsim.log"
$toolStatusPath = Join-Path $xsimDir "tool_status.json"
if (-not (Test-Path -LiteralPath $xsimLog)) {
    throw "VV33 XSim result log is missing: $xsimLog"
}
if (-not (Test-Path -LiteralPath $toolStatusPath)) {
    throw "VV33 tool-status file is missing: $toolStatusPath"
}
$logText = Get-Content -LiteralPath $xsimLog -Raw
$toolStatus = Get-Content -LiteralPath $toolStatusPath -Raw | ConvertFrom-Json
$metricMatches = [regex]::Matches(
    $logText,
    "(?m)^\[VV33:LEAF_SIDECAR\]\s+.*$"
)
$passCount = [regex]::Matches(
    $logText,
    [regex]::Escape("[VV33:leaf_sidecar_probe] PASS")
).Count
$failureFound = [regex]::IsMatch(
    $logText,
    "(?im)(^\s*ERROR:|\bFAIL\b|\bFATAL\b|\*\*\s*Error:)"
)
$fields = if ($metricMatches.Count -eq 1) {
    Convert-MetricFields -Line $metricMatches[0].Value
} else {
    [ordered]@{}
}
$toolOk = ($toolExit -eq 0) -and
          ($toolStatus.xvlog -eq 0) -and
          ($toolStatus.xelab -eq 0) -and
          ($toolStatus.xsim -eq 0)
$contractOk = ($metricMatches.Count -eq 1) -and
              ($fields.pmul -eq "146908") -and
              ($fields.accept -eq "2") -and
              ($fields.clear -eq "16") -and
              ($fields.bind_reads -eq "4/4") -and
              ($fields.bind_capture -eq "4") -and
              ($fields.bind_compute -eq "4") -and
              ($fields.bind_write -eq "4") -and
              ($fields.response -eq "2") -and
              ($fields.conflicts -eq "0") -and
              ($fields.unknown -eq "0") -and
              ($fields.errors -eq "0")
$rtlChangedDuringRun = $rtlStartHash -ne $rtlEndHash
$passed = $toolOk -and ($passCount -eq 1) -and
          (-not $failureFound) -and $contractOk -and
          (-not $rtlChangedDuringRun)

$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
$gitStatus = (& git -C $repoRoot status --short 2>$null | Out-String).Trim()
$manifest = [ordered]@{
    test = $testName
    status = if ($passed) { "PASS" } else { "FAIL" }
    start_policy = if ($generatedVectors) { "fresh-random-k" } else { "replay" }
    source_vector_dir = $VectorDir
    scalar_count = $scalarCount
    master_seed_sha256 = Get-Sha256 -Path (Join-Path $VectorDir "master_seed.mem")
    vector_manifest_sha256 = Get-Sha256 -Path (Join-Path $VectorDir "vector_manifest.json")
    vivado_version = $vivadoVersion
    tool_exit = $toolExit
    tool_status = $toolStatus
    pass_marker_count = $passCount
    metric_count = $metricMatches.Count
    contract_ok = $contractOk
    failure_text_found = $failureFound
    rtl_changed_during_run = $rtlChangedDuringRun
    metrics = $fields
    git_commit = $gitCommit
    git_dirty = -not [string]::IsNullOrWhiteSpace($gitStatus)
    hdec_top_sha256 = $rtlEndHash
    xsim_log = $xsimLog
    xsim_log_sha256 = Get-Sha256 -Path $xsimLog
    completed_at = (Get-Date).ToString("o")
}
$manifestPath = Join-Path $OutRoot "run_manifest.json"
$manifest | ConvertTo-Json -Depth 8 |
    Set-Content -Encoding utf8 -LiteralPath $manifestPath

Write-Host (
    "[VV33:leaf_sidecar_runner] status={0} pmul={1} clear={2} " +
    "bind_reads={3} conflicts={4} unknown={5} manifest={6}" -f
    $manifest.status, $fields.pmul, $fields.clear, $fields.bind_reads,
    $fields.conflicts, $fields.unknown, $manifestPath
)
if (-not $passed) {
    exit 1
}
exit 0
