<#
.SYNOPSIS
Runs the VV33 one-K, per-bank HSIM interleaving integration test.

.DESCRIPTION
The runner first checks the simulation-only RTL event contract required by the
testbench.  It then creates exactly one new legal sect233k1 scalar through the
VV31 CSPRNG vector generator and runs Vivado Simulator 2024.2.  There is no
replay input in this focused runner: every successful invocation uses a newly
generated seed and K.
#>

[CmdletBinding()]
param(
    [string]$OutRoot,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot `
        "tmp\hdec_logs\vv33\bank_hsim_interleave_$timestamp"
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

function Write-RunManifest {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Manifest
    )
    $manifestPath = Join-Path $OutRoot "run_manifest.json"
    $Manifest | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8
    return $manifestPath
}

$hdecTopPath = Join-Path $repoRoot "core\hdec\rtl\hdec_top.sv"
$testbenchPath = Join-Path $repoRoot `
    "verif\hdec\vv33\integration\tb_vv33_bank_hsim_interleave.sv"
if (-not (Test-Path -LiteralPath $hdecTopPath)) {
    throw "hdec_top.sv is missing: $hdecTopPath"
}
if (-not (Test-Path -LiteralPath $testbenchPath)) {
    throw "VV33 bank-HSIM testbench is missing: $testbenchPath"
}

# These are simulation-only observations.  They carry only narrow tags,
# 64-bit words already consumed by the existing HDC datapath, and counters.
# They are not an authorization to add a second datapath or wide scheduler.
$eventContract = [ordered]@{
    vv33_bank_hsim_accept_fire = "logic"
    vv33_bank_hsim_src0_read_fire = "logic"
    vv33_bank_hsim_src0_read_word_id = "logic [3:0]"
    vv33_bank_hsim_src1_read_fire = "logic"
    vv33_bank_hsim_src1_read_word_id = "logic [3:0]"
    vv33_bank_hsim_src0_return_fire = "logic"
    vv33_bank_hsim_src0_return_word_id = "logic [3:0]"
    vv33_bank_hsim_src1_return_fire = "logic"
    vv33_bank_hsim_src1_return_word_id = "logic [3:0]"
    vv33_bank_hsim_compute_fire = "logic"
    vv33_bank_hsim_compute_word_id = "logic [3:0]"
    vv33_bank_hsim_compute_src0_word = "logic [63:0]"
    vv33_bank_hsim_compute_src1_word = "logic [63:0]"
    vv33_bank_hsim_word_popcount = "logic [6:0]"
    vv33_bank_hsim_accum_fire = "logic"
    vv33_bank_hsim_accum_word_id = "logic [3:0]"
    vv33_bank_hsim_partial_sum = "logic [10:0]"
    vv33_bank_hsim_done_fire = "logic"
    vv33_bank_hsim_response_fire = "logic"
    vv33_bank_hsim_vrf_read_conflict = "logic"
    vv33_bank_hsim_matrix_conflict = "logic"
    vv33_bank_hsim_popcount_conflict = "logic"
    vv33_bank_hsim_payload_conflict = "logic"
}
$rtlText = Get-Content -LiteralPath $hdecTopPath -Raw
$missingEvents = @(
    $eventContract.Keys | Where-Object {
        $rtlText -notmatch ("\b" + [regex]::Escape($_) + "\b")
    }
)

$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
$gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null |
    Out-String).Trim()
$gitStatus = @(& git -C $repoRoot status --short 2>$null)
$rtlStartHash = Get-Sha256 -Path $hdecTopPath

if ($missingEvents.Count -ne 0) {
    $blockedManifest = [ordered]@{
        schema = "hdec-vv33-bank-hsim-run-v1"
        status = "BLOCKED_RTL_EVENTS"
        reason = (
            "The integration test is ready, but hdec_top.sv does not yet " +
            "export the required simulation event contract. RTL was not changed."
        )
        branch = $gitBranch
        commit = $gitCommit
        git_status = $gitStatus
        hdec_top_sha256 = $rtlStartHash
        testbench_sha256 = Get-Sha256 -Path $testbenchPath
        runner_sha256 = Get-Sha256 -Path $MyInvocation.MyCommand.Path
        generated_vectors = $false
        event_contract = $eventContract
        missing_events = $missingEvents
    }
    $manifestPath = Write-RunManifest -Manifest $blockedManifest
    Write-Host "[VV33:BANK_HSIM_RUN] BLOCKED_RTL_EVENTS"
    foreach ($name in $missingEvents) {
        Write-Host (
            "[VV33:BANK_HSIM_REQUIRED] h.dut.$name " +
            "$($eventContract[$name])"
        )
    }
    Write-Host "[VV33:BANK_HSIM_RUN] manifest=$manifestPath"
    exit 2
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

# The focused test deliberately has no -Seed or -VectorDir parameter.  The
# VV31 quick profile obtains a fresh OS-CSPRNG seed and creates exactly one K.
$vectorRun = Join-Path $OutRoot "vector_run"
$vv31Runner = Join-Path $repoRoot `
    "scripts\hdec\vv31\run_vv31_regression.ps1"
$vectorArgs = @{
    Suite = "quick"
    VectorsOnly = $true
    OutRoot = $vectorRun
}
if (-not [string]::IsNullOrWhiteSpace($PythonExe)) {
    $vectorArgs.PythonExe = $PythonExe
}
& $vv31Runner @vectorArgs
if ($LASTEXITCODE -ne 0) {
    throw "VV31 vector generation failed with exit code $LASTEXITCODE"
}
$vectorDir = Join-Path $vectorRun "vectors"
$vectorManifestPath = Join-Path $vectorDir "vector_manifest.json"
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
    $path = Join-Path $vectorDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required VV33 vector file is missing: $path"
    }
}

$scalarCountHex = (
    Get-Content -LiteralPath (Join-Path $vectorDir "scalar_count.mem") -Raw
).Trim()
$scalarCount = [Convert]::ToUInt32($scalarCountHex, 16)
if ($scalarCount -ne 1) {
    throw "VV33 bank-HSIM test requires exactly one random K, got $scalarCount"
}
$scalarLines = @(
    Get-Content -LiteralPath (Join-Path $vectorDir "pmul_scalars.mem") |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($scalarLines.Count -ne 1) {
    throw "Expected one scalar line, got $($scalarLines.Count)"
}
$vectorManifest = Get-Content -LiteralPath $vectorManifestPath -Raw |
    ConvertFrom-Json
$scalarHex = $scalarLines[0].Trim()
$orderHex = ([string]$vectorManifest.sect233k1_order_hex).Trim()
$hexStyle = [System.Globalization.NumberStyles]::AllowHexSpecifier
$scalarValue = [System.Numerics.BigInteger]::Parse("0$scalarHex", $hexStyle)
$orderValue = [System.Numerics.BigInteger]::Parse("0$orderHex", $hexStyle)
if (($scalarValue -lt 1) -or
    ($scalarValue -ge $orderValue) -or
    ($scalarValue -eq 3)) {
    throw "Generated scalar is not a legal nontrivial sect233k1 K: $scalarHex"
}
if ($scalarHex.Length -gt 64 -or
    (($scalarValue -shr 233) -ne 0)) {
    throw "Generated scalar violates the 233-bit VRF contract: $scalarHex"
}

$runTcl = Join-Path $scriptDir "vv33_xsim_run.tcl"
$vivado = Join-Path $VivadoBin "vivado.bat"
$testName = "bank_hsim_interleave"
$testTop = "tb_vv33_bank_hsim_interleave"
$testFile = "verif/hdec/vv33/integration/tb_vv33_bank_hsim_interleave.sv"
$runnerLog = Join-Path $OutRoot "$testName.runner.log"
$toolExit = -1
$oldPath = $env:Path
try {
    $env:Path = "$VivadoBin;$oldPath"
    Push-Location $OutRoot
    try {
        & $vivado -mode batch -nolog -nojournal -notrace `
            -source $runTcl -tclargs `
            $repoRoot $repoRoot $OutRoot $testName `
            $testTop $testFile $vectorDir 2>&1 |
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
$toolStatus = Get-Content -LiteralPath $toolStatusPath -Raw |
    ConvertFrom-Json
$metricMatches = [regex]::Matches(
    $logText,
    "(?m)^\[VV33:BANK_HSIM_METRIC\]\s+.*$"
)
$passMarker = "[VV33:bank_hsim_interleave] PASS"
$passCount = [regex]::Matches(
    $logText,
    [regex]::Escape($passMarker)
).Count
$failureFound = [regex]::IsMatch(
    $logText,
    "(?im)(^\s*ERROR:|\bFAIL\b|\bFATAL\b|\*\*\s*Error:)"
)
$toolOk = ($toolExit -eq 0) -and
          ($toolStatus.xvlog -eq 0) -and
          ($toolStatus.xelab -eq 0) -and
          ($toolStatus.xsim -eq 0)
$fields = if ($metricMatches.Count -eq 1) {
    Convert-MetricFields -Line $metricMatches[0].Value
} else {
    [ordered]@{}
}
$contractOk = ($metricMatches.Count -eq 1) -and
              ($fields.accept -eq "1") -and
              ($fields.src0_read -eq "16") -and
              ($fields.src1_read -eq "16") -and
              ($fields.src0_return -eq "16") -and
              ($fields.src1_return -eq "16") -and
              ($fields.compute -eq "16") -and
              ($fields.accum -eq "16") -and
              ($fields.done -eq "1") -and
              ($fields.response -eq "1") -and
              ($fields.bus_response -eq "1") -and
              ($fields.src0_read_seen -eq "ffff") -and
              ($fields.src1_read_seen -eq "ffff") -and
              ($fields.src0_return_seen -eq "ffff") -and
              ($fields.src1_return_seen -eq "ffff") -and
              ($fields.compute_seen -eq "ffff") -and
              ($fields.accum_seen -eq "ffff") -and
              ($fields.vrf_read_conflict -eq "0") -and
              ($fields.matrix_conflict -eq "0") -and
              ($fields.popcount_conflict -eq "0") -and
              ($fields.payload_conflict -eq "0") -and
              ($fields.unknown -eq "0") -and
              ($fields.errors -eq "0")
$passed = $toolOk -and ($passCount -eq 1) -and
          (-not $failureFound) -and $contractOk

$rtlEndHash = Get-Sha256 -Path $hdecTopPath
$rtlChangedDuringRun = $rtlStartHash -ne $rtlEndHash
if ($rtlChangedDuringRun) {
    $passed = $false
    Write-Warning "hdec_top.sv changed during the run; evidence is invalid."
}

$testResult = [ordered]@{
    name = $testName
    top = $testTop
    status = if ($passed) { "PASS" } else { "FAIL" }
    tool_exit = $toolExit
    tool_status = $toolStatus
    pass_marker_count = $passCount
    metric_count = $metricMatches.Count
    contract_ok = $contractOk
    failure_text_found = $failureFound
    metrics = $fields
    runner_log = $runnerLog
    xsim_log = $xsimLog
    log_sha256 = Get-Sha256 -Path $xsimLog
}
$manifest = [ordered]@{
    schema = "hdec-vv33-bank-hsim-run-v1"
    status = if ($passed) { "PASS" } else { "FAIL" }
    random_policy = (
        "exactly one fresh OS-CSPRNG-derived legal sect233k1 K; " +
        "no fixed seed or vector replay input accepted by this runner"
    )
    scalar_count = $scalarCount
    scalar_hex = $scalarHex
    scalar_is_legal = $true
    seed_hex = [string]$vectorManifest.seed_hex
    vector_dir = $vectorDir
    vector_manifest_sha256 = Get-Sha256 -Path $vectorManifestPath
    branch = $gitBranch
    commit = $gitCommit
    git_status = $gitStatus
    hdec_top_sha256_start = $rtlStartHash
    hdec_top_sha256_end = $rtlEndHash
    rtl_changed_during_run = $rtlChangedDuringRun
    testbench_sha256 = Get-Sha256 -Path $testbenchPath
    runner_sha256 = Get-Sha256 -Path $MyInvocation.MyCommand.Path
    vivado_version = $vivadoVersion
    target_device = "xc7z020clg400-2"
    event_contract = $eventContract
    test = $testResult
}
$manifestPath = Write-RunManifest -Manifest $manifest
Write-Host (
    "[VV33:BANK_HSIM_RUN] $($manifest.status) K=$scalarHex " +
    "manifest=$manifestPath"
)
if (-not $passed) {
    exit 1
}
exit 0
