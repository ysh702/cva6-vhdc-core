[CmdletBinding()]
param(
    [ValidateSet("SERIAL", "INTERLEAVED", "INDEPENDENT", "BOTH")]
    [string]$Scenario = "BOTH",
    [ValidateRange(1, 100000)]
    [int]$TaskCount = 1632,
    [ValidateRange(0, 1000000000)]
    [long]$WindowCycles = 0,
    [ValidateRange(1, 1000000000)]
    [long]$PmulCycles = 146908,
    [bool]$UseSdf = $true,
    [string]$VectorDir,
    [string]$Checkpoint,
    [string]$OutRoot,
    [string]$ReportRoot,
    [switch]$ReuseExport,
    [switch]$SkipPower,
    [switch]$DualIndependent,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe = "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path

if ($DualIndependent -and ($Scenario -ne "INDEPENDENT")) {
    throw "-DualIndependent requires -Scenario INDEPENDENT"
}

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Sha256OrNull {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Invoke-LoggedNative {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][object[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][string]$Description
    )
    & $Executable @Arguments 2>&1 |
        Tee-Object -LiteralPath $LogPath |
        ForEach-Object { Write-Host $_ }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$Description failed with exit code $code. See $LogPath"
    }
}

function Get-PowerMetrics {
    param([Parameter(Mandatory = $true)][string]$PowerReport)
    $text = Get-Content -LiteralPath $PowerReport -Raw
    $matched = [regex]::Match(
        $text,
        '(?m)\|\s*Design Nets Matched\s*\|\s*(\d+)%\s*\((\d+)\/(\d+)\)'
    )
    $total = [regex]::Match(
        $text,
        '(?m)\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)'
    )
    $dynamic = [regex]::Match(
        $text,
        '(?m)\|\s*Dynamic \(W\)\s*\|\s*([0-9.]+)'
    )
    $static = [regex]::Match(
        $text,
        '(?m)\|\s*Device Static \(W\)\s*\|\s*([0-9.]+)'
    )
    $confidence = [regex]::Match(
        $text,
        '(?m)\|\s*Confidence Level\s*\|\s*([^|]+)\|'
    )
    return [ordered]@{
        design_nets_matched_percent = if ($matched.Success) { [int]$matched.Groups[1].Value } else { $null }
        design_nets_matched = if ($matched.Success) { [long]$matched.Groups[2].Value } else { $null }
        design_nets_total = if ($matched.Success) { [long]$matched.Groups[3].Value } else { $null }
        total_on_chip_power_w = if ($total.Success) { [double]$total.Groups[1].Value } else { $null }
        dynamic_power_w = if ($dynamic.Success) { [double]$dynamic.Groups[1].Value } else { $null }
        device_static_power_w = if ($static.Success) { [double]$static.Groups[1].Value } else { $null }
        confidence = if ($confidence.Success) { $confidence.Groups[1].Value.Trim() } else { $null }
    }
}

function Get-SaifMetrics {
    param([Parameter(Mandatory = $true)][string]$SaifPath)
    # Header fields are near the beginning, so avoid loading a potentially very
    # large physical SAIF into memory merely to extract its duration.
    $header = (Get-Content -LiteralPath $SaifPath -TotalCount 80) -join "`n"
    $duration = [regex]::Match($header, '\(DURATION\s+([0-9]+)\)')
    $timescale = [regex]::Match($header, '\(TIMESCALE\s+([^\)]+)\)')
    return [ordered]@{
        duration_units = if ($duration.Success) { [long]$duration.Groups[1].Value } else { $null }
        timescale = if ($timescale.Success) { $timescale.Groups[1].Value.Trim() } else { $null }
        bytes = (Get-Item -LiteralPath $SaifPath).Length
        sha256 = Get-Sha256OrNull $SaifPath
    }
}

if ([string]::IsNullOrWhiteSpace($Checkpoint)) {
    $Checkpoint = Join-Path $repoRoot "reports\hdec\vv35_eval_postroute_repair_20260803\dcp\02_postroute_repaired.dcp"
}
$Checkpoint = Resolve-FullPath $Checkpoint
if (-not (Test-Path -LiteralPath $Checkpoint -PathType Leaf)) {
    throw "Routed checkpoint not found: $Checkpoint"
}

if ([string]::IsNullOrWhiteSpace($VectorDir)) {
    $VectorDir = Join-Path $repoRoot "tmp\hdec_logs\vv35_eval\schedule_same_net_smoke"
}
$VectorDir = Resolve-FullPath $VectorDir
if (-not (Test-Path -LiteralPath $VectorDir -PathType Container)) {
    throw "Vector directory not found: $VectorDir"
}
foreach ($requiredVector in @(
    "vector_manifest.json",
    "scalar_count.mem",
    "pmul_scalars.mem",
    "pmul_point_x.mem",
    "pmul_point_y.mem",
    "pmul_expected_x.mem",
    "pmul_expected_y.mem",
    "hdc_train_samples.mem",
    "hdc_role_vectors.mem"
)) {
    $requiredPath = Join-Path $VectorDir $requiredVector
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required vector file not found: $requiredPath"
    }
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv35_eval\gate_saif_$stamp"
}
$OutRoot = Resolve-FullPath $OutRoot
if ([string]::IsNullOrWhiteSpace($ReportRoot)) {
    $ReportRoot = Join-Path $repoRoot "reports\hdec\vv35_eval_gate_saif_$stamp"
}
$ReportRoot = Resolve-FullPath $ReportRoot
New-Item -ItemType Directory -Force -Path $OutRoot, $ReportRoot | Out-Null

$vivado = Join-Path $VivadoBin "vivado.bat"
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($vivado, $xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required Vivado tool not found: $tool"
    }
}
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Python runtime not found: $PythonExe"
}

$versionLog = Join-Path $OutRoot "vivado_version.log"
# Vivado 2024.2 on Windows prints a valid version banner but its batch wrapper
# may still return exit code 1 for `-version`.  Treat the banner, rather than
# that wrapper exit code, as the version-query contract.
& $vivado -version 2>&1 |
    Tee-Object -LiteralPath $versionLog |
    ForEach-Object { Write-Host $_ }
$versionText = Get-Content -LiteralPath $versionLog -Raw
if ($versionText -notmatch 'v2024\.2') {
    throw "Expected Vivado v2024.2, got: $versionText"
}

if (($TaskCount -ne 1632) -and ($WindowCycles -eq 0)) {
    throw "A nonzero -WindowCycles is required when TaskCount is not the frozen 1632 workload"
}

$exportDir = Join-Path $OutRoot "export"
$simDir = Join-Path $OutRoot "sim"
New-Item -ItemType Directory -Force -Path $exportDir, $simDir | Out-Null
$exportTcl = Join-Path $scriptDir "vv35_export_postroute_sim.tcl"
$stripSdf = Join-Path $scriptDir "strip_sdf_timingchecks.py"
$powerTcl = Join-Path $scriptDir "vv35_report_power.tcl"
$saifTcl = Join-Path $repoRoot "verif\hdec\vv35_eval\gate\vv35_gate_saif_active.tcl"
$tb = Join-Path $repoRoot "verif\hdec\vv35_eval\gate\tb_vv35_schedule_gate.sv"
foreach ($source in @($exportTcl, $stripSdf, $powerTcl, $saifTcl, $tb)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required flow source not found: $source"
    }
}

$outputStem = if ($DualIndependent) { "vv35_dual_independent" } else { "hdec_top" }
$netlist = Join-Path $exportDir "${outputStem}_postroute_timesim.v"
$sdfRaw = Join-Path $exportDir "${outputStem}_postroute_max.sdf"
$sdfDelayOnly = Join-Path $exportDir "${outputStem}_postroute_delay_only.sdf"
if (-not $ReuseExport) {
    Invoke-LoggedNative $vivado @(
        "-mode", "batch", "-nolog", "-nojournal", "-notrace",
        "-source", $exportTcl,
        "-tclargs", $Checkpoint, $exportDir, $outputStem
    ) (Join-Path $OutRoot "export.log") "Post-route netlist export"
}
foreach ($exported in @($netlist, $sdfRaw)) {
    if (-not (Test-Path -LiteralPath $exported -PathType Leaf)) {
        throw "Expected exported artifact not found: $exported"
    }
}
if ((-not $ReuseExport) -or
    -not (Test-Path -LiteralPath $sdfDelayOnly -PathType Leaf)) {
    Invoke-LoggedNative $PythonExe @(
        $stripSdf, $sdfRaw, $sdfDelayOnly
    ) (Join-Path $OutRoot "strip_sdf.log") "SDF timing-check stripping"
}

# The gate testbench also accepts an explicit vector path.  Copying the vector
# bundle into the simulation directory preserves compatibility with packages
# that use fixed $readmemh file names.
Get-ChildItem -LiteralPath $VectorDir -File |
    Where-Object { $_.Extension -in @(".mem", ".json", ".sha256") } |
    Copy-Item -Destination $simDir -Force

$hdecPkg = Join-Path $repoRoot "core\hdec\rtl\hdec_pkg.sv"
$vectorsPkg = Join-Path $repoRoot "verif\hdec\vv31\common\hdec_vv31_vectors_pkg.sv"
$refPkg = Join-Path $repoRoot "verif\hdec\vv31\common\hdec_vv31_ref_pkg.sv"
$driverPkg = Join-Path $repoRoot "verif\hdec\vv31\common\hdec_vv31_driver_pkg.sv"
$checkPkg = Join-Path $repoRoot "verif\hdec\vv31\common\hdec_vv31_check_pkg.sv"
$glbl = Join-Path (Split-Path -Parent $VivadoBin) "data\verilog\src\glbl.v"
foreach ($source in @(
    $hdecPkg, $vectorsPkg, $refPkg, $driverPkg, $checkPkg, $glbl
)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required compile source not found: $source"
    }
}

$snapshot = if ($UseSdf) {
    if ($DualIndependent) {
        "tb_vv35_dual_independent_gate_postroute_sdf"
    } else {
        "tb_vv35_schedule_gate_postroute_sdf"
    }
} else {
    if ($DualIndependent) {
        "tb_vv35_dual_independent_gate_postroute_nosdf"
    } else {
        "tb_vv35_schedule_gate_postroute_nosdf"
    }
}

Push-Location $simDir
try {
    $xvlogArguments = @("-sv")
    if ($DualIndependent) {
        $xvlogArguments += "--define=VV35_DUAL_INDEPENDENT_DUT"
    }
    $xvlogArguments += @(
        $hdecPkg, $vectorsPkg, $refPkg, $driverPkg, $checkPkg,
        $netlist, $tb, $glbl
    )
    Invoke-LoggedNative $xvlog $xvlogArguments `
        (Join-Path $simDir "xvlog_console.log") "xvlog"

    $xelabArgs = Join-Path $simDir "xelab_args.f"
    $elabTokens = @(
        "tb_vv35_schedule_gate",
        "glbl",
        "-L", "simprims_ver",
        "--timescale", "1ns/1ps",
        "-debug", "typical"
    )
    if ($UseSdf) {
        $sdfForward = $sdfDelayOnly.Replace('\', '/')
        $sdfArg = "/tb_vv35_schedule_gate/dut=$sdfForward"
        $elabTokens += @("--maxdelay", "--sdfmax", $sdfArg)
    }
    $elabTokens += @("-s", $snapshot)
    $elabTokens | Set-Content -LiteralPath $xelabArgs -Encoding ascii
    Invoke-LoggedNative $xelab @("-f", $xelabArgs) `
        (Join-Path $simDir "xelab_console.log") "xelab"
}
finally {
    Pop-Location
}

$scenarioList = if ($Scenario -eq "BOTH") {
    @("SERIAL", "INTERLEAVED")
} else {
    @($Scenario)
}
$scenarioResults = [ordered]@{}
$stripPath = "tb_vv35_schedule_gate/dut"
$saifTclForward = $saifTcl.Replace('\', '/')
$vectorDirForward = $VectorDir.Replace('\', '/')

foreach ($currentScenario in $scenarioList) {
    $scenarioLower = $currentScenario.ToLowerInvariant()
    $scenarioDir = Join-Path $OutRoot $scenarioLower
    $powerDir = Join-Path $ReportRoot $scenarioLower
    New-Item -ItemType Directory -Force -Path $scenarioDir, $powerDir | Out-Null
    $currentWindow = $WindowCycles
    if ($currentWindow -eq 0) {
        if ($currentScenario -eq "SERIAL") {
            $currentWindow = 337853
        } elseif ($currentScenario -eq "INDEPENDENT") {
            $currentWindow = 190944
        } else {
            $currentWindow = 200144
        }
    }

    $responseFile = Join-Path $scenarioDir "xsim_args.f"
    @(
        "-testplusarg", "SCENARIO=$currentScenario",
        "-testplusarg", "TASK_COUNT=$TaskCount",
        "-testplusarg", "WINDOW_CYCLES=$currentWindow",
        "-testplusarg", "PMUL_WAIT_CYCLES=$PmulCycles",
        "-testplusarg", "VV31_VECTOR_DIR=$vectorDirForward"
    ) | Set-Content -LiteralPath $responseFile -Encoding ascii

    $saif = Join-Path $scenarioDir "${scenarioLower}_${TaskCount}_gate_active.saif"
    $xsimLog = Join-Path $scenarioDir "xsim.log"
    $env:VV35_GATE_SAIF_PATH = $saif.Replace('\', '/')
    Push-Location $simDir
    try {
        Invoke-LoggedNative $xsim @(
            $snapshot,
            "-f", $responseFile,
            "-tclbatch", $saifTclForward,
            "-log", $xsimLog
        ) (Join-Path $scenarioDir "xsim_console.log") "XSim $currentScenario"
    }
    finally {
        Pop-Location
        Remove-Item Env:\VV35_GATE_SAIF_PATH -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $saif -PathType Leaf) -or
        (Get-Item -LiteralPath $saif).Length -le 0) {
        throw "XSim did not produce a non-empty SAIF file: $saif"
    }
    $xsimText = Get-Content -LiteralPath $xsimLog -Raw
    $passMarker = "[VV35:GATE_SCHEDULE] PASS scenario=$currentScenario"
    $passCount = [regex]::Matches(
        $xsimText,
        [regex]::Escape($passMarker)
    ).Count
    $failureMarker = [regex]::IsMatch(
        $xsimText,
        '(?im)(^\s*ERROR:|\*\*\s*(Error|Fatal):|\[VV35:[^\]]+\]\s+FAIL|\$fatal)'
    )
    if (($passCount -ne 1) -or $failureMarker) {
        throw "Gate schedule $currentScenario did not produce one clean PASS marker. See $xsimLog"
    }

    $metricMatch = [regex]::Match(
        $xsimText,
        '(?m)^\[VV35:GATE_METRIC\].*?window_cycles=(\d+)'
    )
    $measuredWallCycles = if ($metricMatch.Success) {
        [long]$metricMatch.Groups[1].Value
    } else {
        $currentWindow
    }

    $powerMetrics = $null
    $powerReport = $null
    $powerLog = $null
    if (-not $SkipPower) {
        $runLabel = "gate_${scenarioLower}_${TaskCount}"
        $powerLog = Join-Path $powerDir "vivado_power.log"
        Invoke-LoggedNative $vivado @(
            "-mode", "batch", "-notrace",
            "-log", $powerLog,
            "-journal", (Join-Path $powerDir "vivado_power.jou"),
            "-source", $powerTcl,
            "-tclargs", $Checkpoint, $powerDir, $runLabel, $saif, $stripPath
        ) (Join-Path $powerDir "vivado_power_console.log") `
            "Vivado power analysis $currentScenario"
        $powerReport = Join-Path $powerDir "${runLabel}_power.rpt"
        if (-not (Test-Path -LiteralPath $powerReport -PathType Leaf)) {
            throw "Power report not found: $powerReport"
        }
        $powerMetrics = Get-PowerMetrics $powerReport
    }

    $saifMetrics = Get-SaifMetrics $saif
    $totalEnergyMj = $null
    $dynamicEnergyMj = $null
    if (($null -ne $powerMetrics) -and
        ($null -ne $powerMetrics.total_on_chip_power_w)) {
        $seconds = $measuredWallCycles * 5.0e-9
        $totalEnergyMj = $powerMetrics.total_on_chip_power_w * $seconds * 1000.0
        $dynamicEnergyMj = $powerMetrics.dynamic_power_w * $seconds * 1000.0
    }

    $scenarioResults[$scenarioLower] = [ordered]@{
        status = "PASS"
        scenario = $currentScenario
        task_count = $TaskCount
        requested_window_cycles = $currentWindow
        measured_wall_cycles = $measuredWallCycles
        pmul_cycles_contract = $PmulCycles
        use_sdf = $UseSdf
        pass_marker = $passMarker
        pass_marker_count = $passCount
        failure_marker_found = $failureMarker
        response_file = $responseFile
        response_file_sha256 = Get-Sha256OrNull $responseFile
        xsim_log = $xsimLog
        xsim_log_sha256 = Get-Sha256OrNull $xsimLog
        saif = $saif
        saif_metrics = $saifMetrics
        power_report = $powerReport
        power_report_sha256 = Get-Sha256OrNull $powerReport
        power_log = $powerLog
        power_metrics = $powerMetrics
        total_energy_mj = $totalEnergyMj
        dynamic_energy_mj = $dynamicEnergyMj
    }
    $scenarioResults[$scenarioLower] | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $scenarioDir "scenario_manifest.json") `
            -Encoding UTF8
}

$comparison = $null
if ($scenarioResults.Contains("serial") -and
    $scenarioResults.Contains("interleaved")) {
    $serial = $scenarioResults["serial"]
    $interleaved = $scenarioResults["interleaved"]
    $savedCycles = $serial.measured_wall_cycles - $interleaved.measured_wall_cycles
    $comparison = [ordered]@{
        saved_cycles = $savedCycles
        makespan_reduction_percent = 100.0 * $savedCycles / $serial.measured_wall_cycles
        speedup = [double]$serial.measured_wall_cycles / $interleaved.measured_wall_cycles
        total_energy_reduction_percent = if (
            ($null -ne $serial.total_energy_mj) -and
            ($serial.total_energy_mj -ne 0.0) -and
            ($null -ne $interleaved.total_energy_mj)
        ) {
            100.0 * ($serial.total_energy_mj - $interleaved.total_energy_mj) /
                $serial.total_energy_mj
        } else { $null }
        dynamic_energy_reduction_percent = if (
            ($null -ne $serial.dynamic_energy_mj) -and
            ($serial.dynamic_energy_mj -ne 0.0) -and
            ($null -ne $interleaved.dynamic_energy_mj)
        ) {
            100.0 * ($serial.dynamic_energy_mj - $interleaved.dynamic_energy_mj) /
                $serial.dynamic_energy_mj
        } else { $null }
    }
}

$gitCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
$gitBranch = (& git -C $repoRoot branch --show-current).Trim()
$rtlDiff = (& git -C $repoRoot diff -- core/hdec/rtl | Out-String)
$manifest = [ordered]@{
    schema = if ($DualIndependent) {
        "hdec-vv35-dual-independent-postroute-gate-saif-v1"
    } else {
        "hdec-vv35-postroute-gate-saif-v1"
    }
    status = "PASS"
    completed_at = (Get-Date).ToString("o")
    branch = $gitBranch
    commit = $gitCommit
    rtl_diff_empty = [string]::IsNullOrWhiteSpace($rtlDiff)
    vivado_version = ($versionText -split '\r?\n' | Select-Object -First 1).Trim()
    device = "xc7z020clg400-2"
    clock_period_ns = 5.0
    activity_source = if ($UseSdf) {
        "post-route timesim netlist with max-corner path/interconnect SDF; TIMINGCHECK groups removed"
    } else {
        "post-route timesim netlist without SDF; mapping pilot only"
    }
    measurement_boundary = if ($DualIndependent) {
        "one PMUL and 1632 four-class HMATCH searches execute concurrently on separate ECC and HDC IPs"
    } else {
        "same routed checkpoint and same gate netlist; serial/interleaved differ only by runtime request timing"
    }
    checkpoint = $Checkpoint
    checkpoint_sha256 = Get-Sha256OrNull $Checkpoint
    netlist = $netlist
    netlist_sha256 = Get-Sha256OrNull $netlist
    source_sdf = $sdfRaw
    source_sdf_sha256 = Get-Sha256OrNull $sdfRaw
    delay_only_sdf = $sdfDelayOnly
    delay_only_sdf_sha256 = Get-Sha256OrNull $sdfDelayOnly
    sdf_policy = "routed path and interconnect delays retained; SDF TIMINGCHECK groups removed because routed STA is authoritative"
    snapshot = $snapshot
    vector_dir = $VectorDir
    vector_manifest_sha256 = Get-Sha256OrNull (Join-Path $VectorDir "vector_manifest.json")
    testbench = $tb
    testbench_sha256 = Get-Sha256OrNull $tb
    saif_tcl = $saifTcl
    saif_tcl_sha256 = Get-Sha256OrNull $saifTcl
    runner_sha256 = Get-Sha256OrNull $MyInvocation.MyCommand.Path
    export_tcl_sha256 = Get-Sha256OrNull $exportTcl
    sdf_filter_sha256 = Get-Sha256OrNull $stripSdf
    power_tcl_sha256 = Get-Sha256OrNull $powerTcl
    task_count = $TaskCount
    pmul_cycles_contract = $PmulCycles
    scenarios = $scenarioResults
    comparison = $comparison
    confidence_boundary = "activity-based routed FPGA power estimate, not board measurement"
}
$manifestPath = Join-Path $ReportRoot "run_manifest.json"
$manifest | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8

$csvRows = foreach ($key in $scenarioResults.Keys) {
    $result = $scenarioResults[$key]
    [pscustomobject]@{
        scenario = $result.scenario
        task_count = $result.task_count
        wall_cycles = $result.measured_wall_cycles
        total_power_w = if ($null -ne $result.power_metrics) { $result.power_metrics.total_on_chip_power_w } else { $null }
        dynamic_power_w = if ($null -ne $result.power_metrics) { $result.power_metrics.dynamic_power_w } else { $null }
        total_energy_mj = $result.total_energy_mj
        dynamic_energy_mj = $result.dynamic_energy_mj
        matched_nets_percent = if ($null -ne $result.power_metrics) { $result.power_metrics.design_nets_matched_percent } else { $null }
        matched_nets = if ($null -ne $result.power_metrics) { $result.power_metrics.design_nets_matched } else { $null }
        design_nets = if ($null -ne $result.power_metrics) { $result.power_metrics.design_nets_total } else { $null }
        power_confidence = if ($null -ne $result.power_metrics) { $result.power_metrics.confidence } else { $null }
        use_sdf = $UseSdf
    }
}
$csvRows | Export-Csv -LiteralPath (Join-Path $ReportRoot "gate_saif_metrics.csv") `
    -NoTypeInformation -Encoding UTF8

Write-Host "[VV35:GATE_SAIF_FLOW] PASS report=$ReportRoot"
Write-Host "[VV35:GATE_SAIF_FLOW] manifest=$manifestPath"
exit 0
