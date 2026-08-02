<#
.SYNOPSIS
Runs the matched VV33 fixed-workload serial/interleaved comparison.

.DESCRIPTION
The full profile preserves the originally requested 46-episode workload.  The
equalized profile executes 168 episodes, the nearest integer normalization for
the measured 874-cycle episode and 146908-cycle PMUL.  Every run reports the
normalization again from its own measured standalone cycles.  Inputs are loaded
before the timed interval and their cycles are reported separately.  The smoke
profile uses the identical test and vector contract with two episodes.

Both serial and interleaved runs consume the same vector directory.  Supplying
-Seed or -VectorDir exactly replays a previous input bundle.
#>

[CmdletBinding()]
param(
    [ValidateSet("smoke", "full", "equalized")]
    [string]$Suite = "smoke",
    [ValidateSet("compare", "serial", "interleaved")]
    [string]$Mode = "compare",
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
$episodeCount = switch ($Suite) {
    "equalized" { 168 }
    "full"      { 46 }
    default     { 2 }
}

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv33\fixed_${Suite}_$timestamp"
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

function Invoke-FixedTest {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Top,
        [Parameter(Mandatory = $true)][string]$PassMarker,
        [Parameter(Mandatory = $true)][string]$OverlayVectorDir
    )

    $runTcl = Join-Path $scriptDir "vv33_xsim_run.tcl"
    $testFile = "verif/hdec/vv33/system/tb_vv33_fixed_workload.sv"
    $runnerLog = Join-Path $OutRoot "$Label.runner.log"
    $vivado = Join-Path $VivadoBin "vivado.bat"
    $toolExit = -1
    $oldPath = $env:Path
    try {
        $env:Path = "$VivadoBin;$oldPath"
        Push-Location $OutRoot
        try {
            & $vivado -mode batch -nolog -nojournal -notrace `
                -source $runTcl -tclargs `
                $repoRoot $repoRoot $OutRoot $Label `
                $Top $testFile $OverlayVectorDir 2>&1 |
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

    $xsimDir = Join-Path $OutRoot "xsim_$Label"
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
        "(?m)^\[VV33:FIXED_WORKLOAD\]\s+.*$"
    )
    $passCount = [regex]::Matches(
        $logText, [regex]::Escape($PassMarker)
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
                  ($fields.episodes -eq [string]$episodeCount) -and
                  ($fields.completed -eq [string]$episodeCount) -and
                  ($fields.matrix_conflict -eq "0") -and
                  ($fields.xor0_conflict -eq "0") -and
                  ($fields.payload_conflict -eq "0") -and
                  ($fields.vrf_read_conflict -eq "0") -and
                  ($fields.vrf_write_conflict -eq "0") -and
                  ($fields.unknown -eq "0") -and
                  ($fields.errors -eq "0")
    $passed = $toolOk -and ($passCount -eq 1) -and
              (-not $failureFound) -and $contractOk

    return [ordered]@{
        name = $Label
        top = $Top
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
    if (-not (Test-Path -LiteralPath (Join-Path $VectorDir $name))) {
        throw "Required VV33 vector file is missing: $(Join-Path $VectorDir $name)"
    }
}
$scalarCountText = (
    Get-Content -LiteralPath (Join-Path $VectorDir "scalar_count.mem") -Raw
).Trim()
$scalarCount = [Convert]::ToUInt32($scalarCountText, 16)
if ($scalarCount -ne 1) {
    throw "VV33 fixed workload requires exactly one random K, got $scalarCount"
}

$overlayVectorDir = Join-Path $OutRoot "vectors"
New-Item -ItemType Directory -Force -Path $overlayVectorDir | Out-Null
Get-ChildItem -LiteralPath $VectorDir -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $overlayVectorDir -Force
}
("{0:X8}" -f $episodeCount) | Set-Content -Encoding ascii -NoNewline `
    -LiteralPath (Join-Path $overlayVectorDir "vv33_episode_count.mem")

$hdecTopPath = Join-Path $repoRoot "core\hdec\rtl\hdec_top.sv"
$rtlStartHash = Get-Sha256 -Path $hdecTopPath
$tests = @()
if ($Mode -in @("compare", "serial")) {
    $tests += Invoke-FixedTest `
        -Label "fixed_workload_serial" `
        -Top "tb_vv33_fixed_workload_serial" `
        -PassMarker "[VV33:fixed_workload_serial] PASS" `
        -OverlayVectorDir $overlayVectorDir
}
if ($Mode -in @("compare", "interleaved")) {
    $tests += Invoke-FixedTest `
        -Label "fixed_workload_interleaved" `
        -Top "tb_vv33_fixed_workload_interleaved" `
        -PassMarker "[VV33:fixed_workload_interleaved] PASS" `
        -OverlayVectorDir $overlayVectorDir
}
$rtlEndHash = Get-Sha256 -Path $hdecTopPath
$rtlChangedDuringRun = $rtlStartHash -ne $rtlEndHash
if ($rtlChangedDuringRun) {
    Write-Warning (
        "hdec_top.sv changed while matched tests were running; " +
        "the comparison is invalid and the run will fail."
    )
}

$comparison = $null
if ($Mode -eq "compare") {
    $serialTest = @($tests | Where-Object { $_.name -eq "fixed_workload_serial" })[0]
    $interleavedTest = @($tests | Where-Object {
        $_.name -eq "fixed_workload_interleaved"
    })[0]
    if (($serialTest.status -eq "PASS") -and
        ($interleavedTest.status -eq "PASS")) {
        $serialWall = [long]$serialTest.metrics.mixed_wall
        $interleavedWall = [long]$interleavedTest.metrics.mixed_wall
        $pmulCycles = [long]$serialTest.metrics.pmul
        $interleavedPmulCycles = [long]$interleavedTest.metrics.pmul
        $serialPmulService = [long]$serialTest.metrics.pmul_service
        $interleavedPmulService = [long]$interleavedTest.metrics.pmul_service
        $hdcCycles = [long]$serialTest.metrics.standalone_hdc
        $interleavedHdcCycles = [long]$interleavedTest.metrics.standalone_hdc
        $cyclesPerEpisode = [double]$hdcCycles / [double]$episodeCount
        $nearestEqualizedCount = [int][Math]::Round(
            ([double]$pmulCycles / $cyclesPerEpisode),
            0,
            [MidpointRounding]::AwayFromZero
        )
        $equalizedHdcEstimate = $nearestEqualizedCount * $cyclesPerEpisode
        $normalizationError = $equalizedHdcEstimate - $pmulCycles
        $hdcToPmulRatio = [double]$hdcCycles / [double]$pmulCycles
        $serialComponentSum = $pmulCycles + $hdcCycles
        $idealWall = [Math]::Max($pmulCycles, $hdcCycles)
        $savedCycles = $serialWall - $interleavedWall
        $serialGap = $serialWall - $idealWall
        $serialControlOverhead = $serialWall - $serialComponentSum
        $savedPercent = if ($serialWall -gt 0) {
            [Math]::Round(100.0 * $savedCycles / $serialWall, 4)
        } else { 0.0 }
        $gapClosedPercent = if ($serialGap -gt 0) {
            [Math]::Round(100.0 * $savedCycles / $serialGap, 4)
        } else { 0.0 }
        $dataOverlapCycles = [long]$interleavedTest.metrics.data_overlap
        $pmulNonRegression = $interleavedPmulCycles -le $pmulCycles
        $hdcStandaloneMatched = $interleavedHdcCycles -eq $hdcCycles
        $savingTargetMet = $savedPercent -ge 5.0
        $comparison = [ordered]@{
            serial_wall_cycles = $serialWall
            interleaved_wall_cycles = $interleavedWall
            standalone_pmul_cycles = $pmulCycles
            interleaved_pmul_wall_cycles = $interleavedPmulCycles
            pmul_cycle_delta = $interleavedPmulCycles - $pmulCycles
            pmul_non_regression = $pmulNonRegression
            serial_pmul_service_cycles = $serialPmulService
            interleaved_pmul_service_cycles = $interleavedPmulService
            pmul_service_delta = $interleavedPmulService - $serialPmulService
            interleaved_foreground_only_cycles =
                [long]$interleavedTest.metrics.pmul_foreground_only
            standalone_hdc_cycles = $hdcCycles
            interleaved_run_standalone_hdc_cycles = $interleavedHdcCycles
            standalone_hdc_matched = $hdcStandaloneMatched
            measured_cycles_per_episode = [Math]::Round(
                $cyclesPerEpisode, 6
            )
            measured_hdc_to_pmul_ratio = [Math]::Round(
                $hdcToPmulRatio, 8
            )
            nearest_equalized_episode_count = $nearestEqualizedCount
            nearest_equalized_hdc_cycles = [Math]::Round(
                $equalizedHdcEstimate, 6
            )
            nearest_equalized_error_cycles = [Math]::Round(
                $normalizationError, 6
            )
            current_suite_is_nearest_equalized =
                $episodeCount -eq $nearestEqualizedCount
            serial_component_sum_cycles = $serialComponentSum
            serial_control_overhead_cycles = $serialControlOverhead
            independent_dual_accelerator_ideal_cycles = $idealWall
            saved_cycles = $savedCycles
            saved_percent_of_serial = $savedPercent
            five_percent_saving_target_met = $savingTargetMet
            serial_to_ideal_gap_cycles = $serialGap
            gap_closed_percent = $gapClosedPercent
            data_overlap_cycles = $dataOverlapCycles
            any_overlap_cycles = [long]$interleavedTest.metrics.any_overlap
            measured_formulas = [ordered]@{
                serial_components = (
                    "C_serial,components = C_PMUL + C_HDC = " +
                    "$pmulCycles + $hdcCycles = $serialComponentSum"
                )
                serial_measured = (
                    "C_serial,measured = $serialWall = " +
                    "$serialComponentSum + $serialControlOverhead"
                )
                ideal = (
                    "C_ideal = max(C_PMUL,C_HDC) = " +
                    "max($pmulCycles,$hdcCycles) = $idealWall"
                )
                serial_to_ideal_gap = (
                    "C_gap = C_serial,measured - C_ideal = " +
                    "$serialWall - $idealWall = $serialGap"
                )
                saved = (
                    "C_saved = C_serial,measured - C_interleaved = " +
                    "$serialWall - $interleavedWall = $savedCycles"
                )
            }
            method_evidence_gate = if ($savingTargetMet -and
                ($dataOverlapCycles -gt 0) -and $pmulNonRegression -and
                $hdcStandaloneMatched) { "MET" } else { "NOT_MET" }
        }
        Write-Host (
            "[VV33:FIXED_COMPARE] episodes=$episodeCount " +
            "serial=$serialWall interleaved=$interleavedWall " +
            "ideal=$idealWall saved=$savedCycles " +
            "saved_pct=$savedPercent gap_closed_pct=$gapClosedPercent " +
            "cycles_per_episode=$($comparison.measured_cycles_per_episode) " +
            "nearest_equalized=$nearestEqualizedCount " +
            "pmul_delta=$($comparison.pmul_cycle_delta) " +
            "data_overlap=$dataOverlapCycles " +
            "evidence=$($comparison.method_evidence_gate)"
        )
    }
}

$vectorManifestPath = Join-Path $overlayVectorDir "vector_manifest.json"
$vectorManifest = Get-Content -LiteralPath $vectorManifestPath -Raw |
    ConvertFrom-Json
$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
$gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null |
    Out-String).Trim()
$gitStatus = @(& git -C $repoRoot status --short 2>$null)
$testbenchPath = Join-Path $repoRoot `
    "verif\hdec\vv33\system\tb_vv33_fixed_workload.sv"
$hasFailure = $rtlChangedDuringRun -or
    (@($tests | Where-Object { $_.status -ne "PASS" }).Count -ne 0)
$manifest = [ordered]@{
    schema = "hdec-vv33-fixed-workload-run-v2"
    status = if ($hasFailure) { "FAIL" } else { "PASS" }
    suite = $Suite
    mode = $Mode
    episode_count = $episodeCount
    suite_episode_policy = switch ($Suite) {
        "equalized" {
            "nearest-integer PMUL-equalized workload selected from the prior " +
            "measured 874-cycle episode; recomputed from this run in comparison"
        }
        "full" {
            "originally requested 46-episode workload retained for traceability"
        }
        default { "two-episode compile and functional smoke workload" }
    }
    normalization_recomputed_from_measured_standalone_hdc =
        ($Mode -eq "compare")
    input_preload_in_timed_interval = $false
    episode_vector_policy = (
        "one preloaded random base HV; four deterministic aligned role " +
        "rotations per episode; no host data load in the timed interval"
    )
    generated_vectors = $generatedVectors
    seed_hex = [string]$vectorManifest.seed_hex
    vector_dir = $overlayVectorDir
    vector_manifest_sha256 = Get-Sha256 -Path $vectorManifestPath
    testbench_sha256 = Get-Sha256 -Path $testbenchPath
    runner_sha256 = Get-Sha256 -Path $MyInvocation.MyCommand.Path
    branch = $gitBranch
    commit = $gitCommit
    git_status = $gitStatus
    hdec_top_sha256_start = $rtlStartHash
    hdec_top_sha256_end = $rtlEndHash
    rtl_changed_during_run = $rtlChangedDuringRun
    vivado_version = $vivadoVersion
    target_device = "xc7z020clg400-2"
    clock_constraint_ns = 5.0
    tests = $tests
    comparison = $comparison
    replay_command = (
        "powershell -ExecutionPolicy Bypass -File " +
        "`"$($MyInvocation.MyCommand.Path)`" -Suite $Suite -Mode $Mode " +
        "-Seed $($vectorManifest.seed_hex) -OutRoot `"<new-output-dir>`""
    )
}
$manifestPath = Join-Path $OutRoot "run_manifest.json"
$manifest | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host (
    "[VV33:FIXED_RUN] $($manifest.status) suite=$Suite mode=$Mode " +
    "episodes=$episodeCount manifest=$manifestPath"
)
Write-Host "[VV33:FIXED_RUN] replay=$($manifest.replay_command)"
if ($hasFailure) {
    exit 1
}
exit 0
