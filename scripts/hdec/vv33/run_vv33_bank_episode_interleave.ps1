<#
.SYNOPSIS
Runs the VV33 one-K repeated-inference interleaving performance contract.

.DESCRIPTION
The test constructs and verifies the HDC prototypes once, then measures a
standalone sect233k1 PMUL and one standalone four-class highest-overlap search.
It repeats that same inference while one PMUL runs in the background.  The
matched-prefix comparison counts only complete searches retired before the
PMUL-done edge.  Any partial search is reported and excluded from serial, ideal,
and gap-closure arithmetic.

This focused runner accepts no seed or vector replay input.  Every executable
run generates exactly one fresh legal K through the VV31 CSPRNG vector flow.
#>

[CmdletBinding()]
param(
    [switch]$StaticOnly,
    [switch]$FullInference,
    [string]$OutRoot,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $runStem = if ($FullInference) {
        "full_inference_interleave_$timestamp"
    } else {
        "bank_episode_interleave_$timestamp"
    }
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv33\$runStem"
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
$testbenchRelative = if ($FullInference) {
    "verif\hdec\vv33\integration\tb_vv33_full_inference_interleave.sv"
} else {
    "verif\hdec\vv33\integration\tb_vv33_bank_episode_interleave.sv"
}
$testbenchPath = Join-Path $repoRoot $testbenchRelative
if (-not (Test-Path -LiteralPath $hdecTopPath)) {
    throw "hdec_top.sv is missing: $hdecTopPath"
}
if (-not (Test-Path -LiteralPath $testbenchPath)) {
    throw "VV33 bank-episode testbench is missing: $testbenchPath"
}

# The performance test depends on maintained generic resource events, the
# accepted paired-HMATCH sidecar handshakes, and minimal top-level progress
# state.  It does not depend on the rejected per-bank HSIM probe.
$observationContract = [ordered]@{
    vv31_evt_hdc_matrix = "logic"
    vv31_evt_ecc_matrix = "logic"
    vv31_evt_hdc_xor0 = "logic"
    vv31_evt_ecc_xor0 = "logic"
    vv31_evt_ecc_square = "logic"
    vv31_evt_ecc_vrf_prefetch = "logic"
    vv31_evt_hdc_vrf_read = "logic"
    vv31_evt_ecc_control_progress = "logic"
    vv31_evt_vrf_write = "logic"
    vv31_evt_vrf_read_owner = "logic [2:0]"
    vv31_evt_vrf_write_owner = "logic [2:0]"
    vv33_sq_read_fire = "logic"
    vv33_sq_write_fire = "logic"
    vv33_pair_accept = "logic"
    vv33_pair_product_fire = "logic"
    vv33_pair_pop_fire = "logic"
    vv33_pair_resp_q = "logic"
    ecc_job_done_q = "logic"
    vrf_we_direct = "logic [3:0]"
}
$rtlText = Get-Content -LiteralPath $hdecTopPath -Raw
$missingObservations = @(
    $observationContract.Keys | Where-Object {
        $rtlText -notmatch ("\b" + [regex]::Escape($_) + "\b")
    }
)

$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
$gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null |
    Out-String).Trim()
$gitStatus = @(& git -C $repoRoot status --short 2>$null)
$rtlStartHash = Get-Sha256 -Path $hdecTopPath

if ($missingObservations.Count -ne 0) {
    $blockedManifest = [ordered]@{
        schema = "hdec-vv33-bank-episode-run-v1"
        status = "BLOCKED_RTL_EVENTS"
        reason = (
            "The complete-episode performance contract is ready, but one or " +
            "more maintained generic resource observations are unavailable. " +
            "RTL was not changed and no long simulation ran."
        )
        branch = $gitBranch
        commit = $gitCommit
        git_status = $gitStatus
        hdec_top_sha256 = $rtlStartHash
        testbench_sha256 = Get-Sha256 -Path $testbenchPath
        runner_sha256 = Get-Sha256 -Path $MyInvocation.MyCommand.Path
        generated_vectors = $false
        performance_contract = [ordered]@{
            foreground_work = (
                "repeat one four-class highest-overlap prototype search " +
                "until the background PMUL done edge"
            )
            completed_work = (
                "only complete searches retired before PMUL done"
            )
            partial_work = (
                "unfinished search reported but excluded from gap arithmetic"
            )
            serial = "standalone PMUL + completed searches * standalone search"
            ideal = "max(standalone PMUL, completed search work)"
            gap_closure = "(serial - mixed wall) / (serial - ideal)"
        }
        observation_contract = $observationContract
        missing_observations = $missingObservations
    }
    $manifestPath = Write-RunManifest -Manifest $blockedManifest
    Write-Host "[VV33:BANK_EPISODE_RUN] BLOCKED_RTL_EVENTS"
    foreach ($name in $missingObservations) {
        Write-Host (
            "[VV33:BANK_EPISODE_REQUIRED] h.dut.$name " +
            "$($observationContract[$name])"
        )
    }
    Write-Host "[VV33:BANK_EPISODE_RUN] manifest=$manifestPath"
    exit 2
}

if ($StaticOnly) {
    $staticManifest = [ordered]@{
        schema = "hdec-vv33-bank-episode-run-v1"
        status = "STATIC_READY"
        reason = (
            "PowerShell parsing, file presence, and RTL event-name checks " +
            "passed. Vector generation and simulation were intentionally skipped."
        )
        branch = $gitBranch
        commit = $gitCommit
        git_status = $gitStatus
        hdec_top_sha256 = $rtlStartHash
        testbench_sha256 = Get-Sha256 -Path $testbenchPath
        runner_sha256 = Get-Sha256 -Path $MyInvocation.MyCommand.Path
        generated_vectors = $false
        simulation_started = $false
        performance_contract = [ordered]@{
            foreground_work = (
                "repeat one four-class highest-overlap prototype search " +
                "until the background PMUL done edge"
            )
            completed_work = "searches retired before PMUL done"
            partial_work = "reported but excluded from gap arithmetic"
            serial = "standalone PMUL + completed searches * standalone search"
            ideal = "max(standalone PMUL, completed search work)"
            gap_closure = "(serial - mixed wall) / (serial - ideal)"
        }
        observation_contract = $observationContract
        missing_observations = @()
    }
    $manifestPath = Write-RunManifest -Manifest $staticManifest
    Write-Host (
        "[VV33:BANK_EPISODE_RUN] STATIC_READY simulation_started=0 " +
        "manifest=$manifestPath"
    )
    exit 0
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
    throw "VV33 bank-episode test requires one random K, got $scalarCount"
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
    ($scalarValue -eq 3) -or
    (($scalarValue -shr 233) -ne 0)) {
    throw "Generated scalar is not a legal nontrivial sect233k1 K: $scalarHex"
}

$runTcl = Join-Path $scriptDir "vv33_xsim_run.tcl"
$vivado = Join-Path $VivadoBin "vivado.bat"
$testName = if ($FullInference) {
    "full_inference_interleave"
} else {
    "bank_episode_interleave"
}
$testTop = if ($FullInference) {
    "tb_vv33_full_inference_interleave"
} else {
    "tb_vv33_bank_episode_interleave"
}
$testFile = $testbenchRelative.Replace("\", "/")
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
$metricPattern = if ($FullInference) {
    "(?m)^\[VV33:FULL_INFERENCE_METRIC\]\s+.*$"
} else {
    "(?m)^\[VV33:(?:INFERENCE_STREAM_METRIC|BANK_EPISODE_METRIC)\]\s+.*$"
}
$metricMatches = [regex]::Matches($logText, $metricPattern)
$partialMatches = [regex]::Matches(
    $logText,
    "(?m)^\[VV33:BANK_EPISODE_PARTIAL\]\s+.*$"
)
$passMarker = if ($FullInference) {
    "[VV33:full_inference_interleave] PASS"
} else {
    "[VV33:bank_episode_interleave] PASS"
}
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

if ($FullInference) {
    $requiredFields = @(
        "standalone_inference", "capacity_n_fit", "fixed_n",
        "standalone_hdc_batch", "standalone_pmul", "independent_dual",
        "interleaved_hdec", "serial_hdec", "serial_calc",
        "serial_transition", "saved_cycles", "serial_reduction_bp",
        "speedup_bp", "mixed_pmul", "mixed_pmul_stretch",
        "mixed_pmul_stretch_bp", "hperm_response", "hbind_response",
        "hmatch_response", "pair_accept", "pair_response",
        "pair_matrix", "pair_pop", "vrf_read_conflict",
        "matrix_conflict", "xor0_conflict", "payload_conflict",
        "unknown", "errors"
    )
    $hasAllFields = $true
    foreach ($fieldName in $requiredFields) {
        if (-not $fields.Contains($fieldName)) {
            $hasAllFields = $false
        }
    }

    $arithmeticOk = $false
    $methodEvidenceGate = "NOT_MET"
    if ($hasAllFields) {
        $standalonePmul = [long]$fields.standalone_pmul
        $standaloneHdc = [long]$fields.standalone_hdc_batch
        $independentDual = [long]$fields.independent_dual
        $interleavedHdec = [long]$fields.interleaved_hdec
        $serialHdec = [long]$fields.serial_hdec
        $serialCalc = [long]$fields.serial_calc
        $serialTransition = [long]$fields.serial_transition
        $savedCycles = [long]$fields.saved_cycles
        $reductionBp = [long]$fields.serial_reduction_bp
        $speedupBp = [long]$fields.speedup_bp
        $fixedN = [long]$fields.fixed_n
        $capacityN = [long]$fields.capacity_n_fit
        $mixedPmul = [long]$fields.mixed_pmul
        $mixedPmulStretch = [long]$fields.mixed_pmul_stretch
        $mixedPmulStretchBp = [long]$fields.mixed_pmul_stretch_bp
        $pairAccept = [long]$fields.pair_accept
        $pairResponse = [long]$fields.pair_response
        $pairMatrix = [long]$fields.pair_matrix
        $pairPop = [long]$fields.pair_pop
        $expectedIndependent = [Math]::Max($standalonePmul, $standaloneHdc)
        $expectedSerialCalc = $standalonePmul + $standaloneHdc
        $expectedSaved = $serialHdec - $interleavedHdec
        $expectedReductionBp = [long][Math]::Truncate(
            10000.0 * $expectedSaved / $serialHdec
        )
        $expectedSpeedupBp = [long][Math]::Truncate(
            10000.0 * $serialHdec / $interleavedHdec
        )
        $expectedStretch = $mixedPmul - $standalonePmul
        $expectedStretchBp = [long][Math]::Truncate(
            10000.0 * $expectedStretch / $standalonePmul
        )
        $arithmeticOk = ($fixedN -eq $capacityN) -and
                        ($independentDual -eq $expectedIndependent) -and
                        ($serialCalc -eq $expectedSerialCalc) -and
                        ($serialHdec -eq ($serialCalc + $serialTransition)) -and
                        ($savedCycles -eq $expectedSaved) -and
                        ($reductionBp -eq $expectedReductionBp) -and
                        ($speedupBp -eq $expectedSpeedupBp) -and
                        ($mixedPmulStretch -eq $expectedStretch) -and
                        ($mixedPmulStretchBp -eq $expectedStretchBp)
        $pairOk = ($pairResponse -gt 0) -and
                  ($pairAccept -eq $pairResponse) -and
                  ($pairMatrix -eq (12 * $pairResponse)) -and
                  ($pairPop -eq $pairMatrix)
        $operationOk = ([long]$fields.hperm_response -eq $fixedN) -and
                       ([long]$fields.hbind_response -eq $fixedN) -and
                       ([long]$fields.hmatch_response -eq $fixedN)
        $resourceOk = ($fields.vrf_read_conflict -eq "0") -and
                      ($fields.matrix_conflict -eq "0") -and
                      ($fields.xor0_conflict -eq "0") -and
                      ($fields.payload_conflict -eq "0") -and
                      ($fields.unknown -eq "0") -and
                      ($fields.errors -eq "0")
        $orderingOk = ($independentDual -le $interleavedHdec) -and
                      ($interleavedHdec -le $serialHdec)
        if ($arithmeticOk -and $pairOk -and $operationOk -and $resourceOk -and
            $orderingOk -and ($savedCycles -gt 0) -and ($fixedN -gt 0)) {
            $methodEvidenceGate = "MET"
        }
    }

    $contractOk = $hasAllFields -and $arithmeticOk -and
                  ($methodEvidenceGate -eq "MET")
    $passed = $toolOk -and ($passCount -eq 1) -and
              (-not $failureFound) -and $contractOk
    $rtlEndHash = Get-Sha256 -Path $hdecTopPath
    $rtlChangedDuringRun = $rtlStartHash -ne $rtlEndHash
    if ($rtlChangedDuringRun) {
        $passed = $false
    }

    $manifest = [ordered]@{
        schema = "hdec-vv33-full-inference-run-v1"
        status = if ($passed) { "PASS" } else { "FAIL" }
        random_policy = (
            "exactly one fresh OS-CSPRNG-derived legal sect233k1 K; " +
            "all standalone, capacity, serial and mixed runs replay it"
        )
        inference_contract = [ordered]@{
            input_boundary = "resident quantized binary input and role HV"
            query_encoding = "HPERM then HBIND"
            classification = "three-class highest AND-POPCOUNT overlap"
            model_loading = "outside all timed intervals"
            fixed_work = "one PMUL plus N complete HPERM-HBIND-HMATCH chains"
        }
        formulas = [ordered]@{
            independent_dual = "max(C_pmul, C_hdc_batch_N)"
            saved_cycles = "C_serial_measured - C_interleaved"
            serial_cycle_reduction = "saved_cycles / C_serial_measured"
            speedup = "C_serial_measured / C_interleaved"
        }
        scalar_count = $scalarCount
        scalar_hex = $scalarHex
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
        method_evidence_gate = $methodEvidenceGate
        arithmetic_recomputed_ok = $arithmeticOk
        tool_exit = $toolExit
        tool_status = $toolStatus
        pass_marker_count = $passCount
        metric_count = $metricMatches.Count
        failure_text_found = $failureFound
        metrics = $fields
        runner_log = $runnerLog
        xsim_log = $xsimLog
        log_sha256 = Get-Sha256 -Path $xsimLog
    }
    $manifestPath = Write-RunManifest -Manifest $manifest
    $reductionText = if ($hasAllFields) {
        ([long]$fields.serial_reduction_bp / 100.0).ToString(
            "0.00", [System.Globalization.CultureInfo]::InvariantCulture
        )
    } else { "NA" }
    Write-Host (
        "[VV33:FULL_INFERENCE_RUN] $($manifest.status) K=$scalarHex " +
        "evidence=$methodEvidenceGate reduction_pct=$reductionText " +
        "manifest=$manifestPath"
    )
    if (-not $passed) {
        exit 1
    }
    exit 0
}

$arithmeticOk = $false
$evidenceGate = "NOT_MET"
$gapClosurePercent = $null
$gapClosurePercentText = "NA"
$pairEvidenceOk = $false
$standaloneInference = 0
$completedInferences = 0
$prototypeConstruction = 0
$standaloneRepeatCount = 0
$standaloneRepeatMismatch = -1
$mixedPmulService = 0
$mixedPmulStretch = 0
$mixedForegroundOnly = 0
$gapClosureBp = 0
$pairMatrix = 0
$pairPop = 0
$pairAccept = 0
$pairResponse = 0
if ($metricMatches.Count -eq 1) {
    $standalonePmul = [long]$fields.standalone_pmul
    $prototypeConstruction = [long]$fields.prototype_construction
    $standaloneInference = if ($fields.Contains("standalone_inference")) {
        [long]$fields.standalone_inference
    } else {
        [long]$fields.standalone_episode
    }
    $completedInferences = if ($fields.Contains("completed_inferences")) {
        [long]$fields.completed_inferences
    } else {
        [long]$fields.completed_episodes
    }
    $completedWork = [long]$fields.completed_work
    $mixedWall = [long]$fields.mixed_wall
    $serialBaseline = [long]$fields.serial_baseline
    $idealDual = [long]$fields.ideal_dual
    $serialGap = [long]$fields.serial_gap
    $saved = [long]$fields.saved
    $gapClosureBp = [long]$fields.gap_closure_bp
    $standaloneRepeatCount = [long]$fields.standalone_repeat_count
    $standaloneRepeatMismatch = [long]$fields.standalone_repeat_mismatch
    $mixedPmulService = [long]$fields.mixed_pmul_service
    $mixedPmulStretch = [long]$fields.mixed_pmul_stretch
    $mixedForegroundOnly = [long]$fields.mixed_foreground_only
    $pairMatrix = [long]$fields.pair_matrix
    $pairPop = [long]$fields.pair_pop
    $pairAccept = [long]$fields.pair_accept
    $pairResponse = [long]$fields.pair_response

    $expectedWork = $completedInferences * $standaloneInference
    $expectedSerial = $standalonePmul + $expectedWork
    $expectedIdeal = [Math]::Max($standalonePmul, $expectedWork)
    $expectedGap = $expectedSerial - $expectedIdeal
    $expectedSaved = $expectedSerial - $mixedWall
    $expectedClosureBp = if ($expectedGap -ne 0) {
        [long][Math]::Truncate(10000.0 * $expectedSaved / $expectedGap)
    } else { 0 }
    $arithmeticOk = ($completedWork -eq $expectedWork) -and
                    ($serialBaseline -eq $expectedSerial) -and
                    ($idealDual -eq $expectedIdeal) -and
                    ($serialGap -eq $expectedGap) -and
                    ($saved -eq $expectedSaved) -and
                    ($gapClosureBp -eq $expectedClosureBp)
    $gapClosurePercent = $gapClosureBp / 100.0
    $gapClosurePercentText = $gapClosurePercent.ToString(
        "0.00",
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $pairEvidenceOk = ($pairResponse -gt 0) -and
                      ($pairAccept -eq $pairResponse) -and
                      ($pairMatrix -eq (16 * $pairResponse)) -and
                      ($pairPop -eq $pairMatrix)
    if (($completedInferences -gt 0) -and
        ([long]$fields.resource_pair -gt 0) -and
        $pairEvidenceOk -and
        ($saved -gt 0) -and
        ($gapClosureBp -gt 0)) {
        $evidenceGate = "MET"
    }
}

$contractOk = ($metricMatches.Count -eq 1) -and
              ($partialMatches.Count -eq 1) -and
              ([long]$fields.standalone_pmul -gt 0) -and
              ($prototypeConstruction -gt 0) -and
              ($standaloneInference -gt 0) -and
              ($standaloneRepeatCount -eq 4) -and
              ($standaloneRepeatMismatch -eq 0) -and
              ($mixedPmulService -gt 0) -and
              ($mixedForegroundOnly -ge 0) -and
              ([long]$fields.mixed_wall -gt 0) -and
              ([long]$fields.unfinished_stage -ge 0) -and
              ([long]$fields.unfinished_stage -le 16) -and
              ($fields.vrf_read_conflict -eq "0") -and
              ($fields.matrix_conflict -eq "0") -and
              ($fields.xor0_conflict -eq "0") -and
              ($fields.popcount_conflict -eq "0") -and
              ($fields.payload_conflict -eq "0") -and
              ($fields.unknown -eq "0") -and
              ($fields.errors -eq "0") -and
              $pairEvidenceOk -and
              $arithmeticOk
$passed = $toolOk -and ($passCount -eq 1) -and
          (-not $failureFound) -and $contractOk -and
          ($evidenceGate -eq "MET")

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
    method_evidence_gate = $evidenceGate
    gap_closure_percent = $gapClosurePercent
    gap_closure_basis_points = $gapClosureBp
    paired_hmatch_contract_ok = $pairEvidenceOk
    prototype_construction_cycles = $prototypeConstruction
    standalone_repeat_count = $standaloneRepeatCount
    standalone_repeat_mismatch = $standaloneRepeatMismatch
    mixed_pmul_service_cycles = $mixedPmulService
    mixed_pmul_stretch_cycles = $mixedPmulStretch
    mixed_foreground_only_cycles = $mixedForegroundOnly
    paired_events = [ordered]@{
        accept = $pairAccept
        response = $pairResponse
        matrix = $pairMatrix
        popcount = $pairPop
        matrix_per_response = if ($pairResponse -gt 0) {
            $pairMatrix / $pairResponse
        } else { $null }
    }
    partial_episode_excluded_from_gap_metric = $true
    arithmetic_recomputed_ok = $arithmeticOk
    tool_exit = $toolExit
    tool_status = $toolStatus
    pass_marker_count = $passCount
    metric_count = $metricMatches.Count
    partial_record_count = $partialMatches.Count
    contract_ok = $contractOk
    failure_text_found = $failureFound
    metrics = $fields
    runner_log = $runnerLog
    xsim_log = $xsimLog
    log_sha256 = Get-Sha256 -Path $xsimLog
}
$manifest = [ordered]@{
    schema = "hdec-vv33-bank-episode-run-v1"
    status = if ($passed) { "PASS" } else { "FAIL" }
    random_policy = (
        "exactly one fresh OS-CSPRNG-derived legal sect233k1 K; " +
        "the same K is used by standalone and mixed PMUL measurements"
    )
    performance_contract = [ordered]@{
        foreground_inference_operations = 1
        foreground_search = "four-class highest-overlap prototype search"
        completed_work = "searches retired before PMUL done"
        partial_work = "reported but excluded from matched-prefix arithmetic"
        serial_formula = "C_pmul + N_complete * C_inference"
        ideal_formula = "max(C_pmul, N_complete * C_inference)"
        gap_closure_formula = "(C_serial - C_mixed)/(C_serial - C_ideal)"
    }
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
    observation_contract = $observationContract
    evidence_summary = [ordered]@{
        xsim_exit_ok = ($toolStatus.xsim -eq 0)
        xsim_pass_marker_count = $passCount
        metric_count = $metricMatches.Count
        gap_closure_basis_points = $gapClosureBp
        gap_closure_percent = $gapClosurePercent
        pair_accept = $pairAccept
        pair_response = $pairResponse
        pair_matrix = $pairMatrix
        pair_popcount = $pairPop
        paired_hmatch_contract_ok = $pairEvidenceOk
        method_evidence_gate = $evidenceGate
    }
    test = $testResult
}
$manifestPath = Write-RunManifest -Manifest $manifest
Write-Host (
    "[VV33:BANK_EPISODE_RUN] $($manifest.status) K=$scalarHex " +
    "evidence=$evidenceGate gap_closure_bp=$gapClosureBp " +
    "gap_closure_pct=$gapClosurePercentText pair_matrix=$pairMatrix " +
    "pair_response=$pairResponse " +
    "manifest=$manifestPath"
)
if (-not $passed) {
    exit 1
}
exit 0
