[CmdletBinding()]
param(
    [ValidateSet("smoke", "quick", "full", "ecc_direct", "hdc_direct")]
    [string]$Suite = "quick",
    [string]$Seed,
    [string]$OutRoot,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
$configPath = Join-Path $scriptDir "vv35_functional_tests.json"

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-TreeHash {
    param([Parameter(Mandatory = $true)][string]$Root)

    $entries = @()
    $lines = @()
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($repoRoot.Length).
                TrimStart("\", "/").Replace("\", "/")
            $hash = Get-Sha256 -Path $_.FullName
            $entries += [ordered]@{ path = $relative; sha256 = $hash }
            $lines += "$relative|$hash"
        }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $aggregate = -join (
            $hasher.ComputeHash($bytes) |
                ForEach-Object { $_.ToString("x2") }
        )
    }
    finally {
        $hasher.Dispose()
    }
    return [ordered]@{ aggregate = $aggregate; files = $entries }
}

function Resolve-Python3 {
    param([string]$Requested)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $candidates += $Requested
    }
    $candidates += @(
        "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
        "E:\HDEC\tools\python_envs\nature_figure\Scripts\python.exe",
        "E:\HDEC\tools\python_envs\scipilot_figure\Scripts\python.exe"
    )
    $commandPython = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $commandPython) {
        $candidates += $commandPython.Source
    }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        $probe = (& $candidate --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $probe -match "Python 3") {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "No working Python 3 interpreter was found."
}

function Convert-MetricFields {
    param([Parameter(Mandatory = $true)][string]$Line)

    $fields = [ordered]@{}
    foreach ($match in [regex]::Matches($Line, "([A-Za-z0-9_]+)=([^\s]+)")) {
        $fields[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return $fields
}

function Write-Outputs {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $manifestPath = Join-Path $OutputDirectory "run_manifest.json"
    $Manifest | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $csvRows = foreach ($test in $Manifest.tests) {
        [pscustomobject]@{
            test = $test.name
            status = $test.status
            runner = $test.runner
            elapsed_seconds = $test.elapsed_seconds
            vivado_exit = $test.vivado_exit
            xvlog_exit = if ($null -ne $test.tool_status) {
                $test.tool_status.xvlog
            } else { "" }
            xelab_exit = if ($null -ne $test.tool_status) {
                $test.tool_status.xelab
            } else { "" }
            xsim_exit = if ($null -ne $test.tool_status) {
                $test.tool_status.xsim
            } else { "" }
            pass_marker_count = $test.pass_marker_count
            coverage_equal = $test.coverage_equal
            cycle_evidence = ($test.cycle_evidence -join " || ")
            xsim_log = $test.xsim_log
        }
    }
    $csvPath = Join-Path $OutputDirectory "VV35_FUNCTIONAL_COVERAGE.csv"
    $csvRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $md = @()
    $md += "# VV35 functional and cycle regression"
    $md += ""
    $md += "- Result: **$($Manifest.overall)**"
    $md += "- Suite: ``$($Manifest.suite)``"
    $md += "- Commit: ``$($Manifest.git_commit)``"
    $md += "- RTL SHA-256: ``$($Manifest.rtl_sha256)``"
    $md += "- Seed: ``$($Manifest.vector_manifest.seed_hex)``"
    $md += "- Vivado: ``$($Manifest.vivado_version_short)``"
    $md += ""
    $md += "## Vector-bundle compatibility"
    $md += ""
    $md += "VV31 is the canonical source for random K, PMUL, and HDC vectors. The legacy GFMAC contract additionally needs accumulator and MAC-expected files that VV31 does not emit. The runner regenerates the complete VV30 primitive group from the identical master seed, overlays the mutually dependent GF, inversion, and square files, regenerates GF multiplication expectations through the existing VV30 reference model, and records the final bundle hash."
    $md += ""
    $md += "| Test | Result | Runtime (s) | PASS count | Coverage |"
    $md += "|---|---:|---:|---:|---:|"
    foreach ($test in $Manifest.tests) {
        $coverage = if ($test.coverage_records -gt 0) {
            [string]$test.coverage_equal
        } else { "n/a" }
        $md += "| $($test.name) | $($test.status) | $($test.elapsed_seconds) | $($test.pass_marker_count) | $coverage |"
    }
    $md += ""
    $md += "## Cycle evidence"
    $md += ""
    foreach ($test in $Manifest.tests) {
        foreach ($line in $test.cycle_evidence) {
            $md += "- ``$($test.name)``: ``$line``"
        }
    }
    $md += ""
    $md += "PASS requires a zero Vivado process exit code, zero xvlog/xelab/xsim exits when the generic runner is used, exactly one PASS marker in xsim.log, no failure marker in xsim.log, and equal observed/expected coverage records."
    $summaryPath = Join-Path $OutputDirectory "VV35_FUNCTIONAL_SUMMARY.md"
    ($md -join "`n") + "`n" |
        Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [ordered]@{
        manifest = $manifestPath
        csv = $csvPath
        summary = $summaryPath
    }
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.schema -ne "hdec-vv35-functional-tests-v1") {
    throw "Unsupported test-list schema '$($config.schema)'"
}
$selectedTests = @($config.suites.$Suite)
if ($selectedTests.Count -eq 0) {
    throw "Suite '$Suite' has no tests."
}
foreach ($name in $selectedTests) {
    if ($null -eq $config.tests.$name) {
        throw "Suite '$Suite' references unknown test '$name'."
    }
    $definition = $config.tests.$name
    if ($definition.runner -eq "vv31_generic") {
        $source = Join-Path $repoRoot ([string]$definition.file)
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Registered test source is missing: $source"
        }
    }
    if ($definition.runner -eq "dedicated_tcl") {
        $source = Join-Path $repoRoot ([string]$definition.script)
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Registered Tcl runner is missing: $source"
        }
    }
}

$requiredTools = @("vivado.bat", "xvlog.bat", "xelab.bat", "xsim.bat")
foreach ($toolName in $requiredTools) {
    $toolPath = Join-Path $VivadoBin $toolName
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Required Vivado tool is missing: $toolPath"
    }
}
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$vivado = Join-Path $VivadoBin "vivado.bat"
$vivadoVersion = (& $xvlog --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $vivadoVersion -notmatch "v2024\.2") {
    throw "VV35 evaluation requires Vivado Simulator v2024.2."
}
$vivadoVersionShort = ([regex]::Match($vivadoVersion, "Vivado Simulator v2024\.2[^\r\n]*")).Value

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$startedAt = (Get-Date).ToString("o")
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv35_eval\functional_$timestamp"
}
$OutRoot = [System.IO.Path]::GetFullPath($OutRoot)
if (Test-Path -LiteralPath (Join-Path $OutRoot "run_manifest.json")) {
    throw "Output directory already contains a completed run: $OutRoot"
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$python = Resolve-Python3 -Requested $PythonExe
$vectorProfile = if ($Suite -eq "full") { "full" } else { "quick" }
$vectorRun = Join-Path $OutRoot "vector_run"
$vv31Runner = Join-Path $repoRoot "scripts\hdec\vv31\run_vv31_regression.ps1"
$vectorArgs = @{
    Suite = $vectorProfile
    VectorsOnly = $true
    OutRoot = $vectorRun
    PythonExe = $python
}
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $vectorArgs.Seed = $Seed
}
& $vv31Runner @vectorArgs
if ($LASTEXITCODE -ne 0) {
    throw "VV31 vector generation failed with exit code $LASTEXITCODE."
}
$vectorDir = Join-Path $vectorRun "vectors"
$vectorManifestPath = Join-Path $vectorDir "vector_manifest.json"
$vectorManifest = Get-Content -LiteralPath $vectorManifestPath -Raw |
    ConvertFrom-Json

# The VV31 bundle intentionally does not emit the legacy GFMAC accumulator
# inputs.  Generate the complete VV30 primitive-operation group from the same
# master seed, then overlay only the mutually dependent GF/inversion files.
# PMUL and HDC vectors remain the VV31 canonical bundle.
$vv30SupplementDir = Join-Path $OutRoot "vv30_primitive_vectors"
$vv30Generator = Join-Path $repoRoot "scripts\hdec\vv30\gen_vv30_vectors.py"
& $python $vv30Generator --out-dir $vv30SupplementDir --suite stage1 `
    --seed ([string]$vectorManifest.seed_hex)
if ($LASTEXITCODE -ne 0) {
    throw "VV30 primitive-vector supplement generation failed."
}
$primitiveFiles = @(
    "gf_a_inputs.mem",
    "gf_b_inputs.mem",
    "gf_acc_inputs.mem",
    "gf_mac_expected.mem",
    "inv_count.mem",
    "inv_inputs.mem",
    "inv_expected.mem",
    "square_inputs.mem",
    "square_expected.mem"
)
foreach ($name in $primitiveFiles) {
    $source = Join-Path $vv30SupplementDir $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "VV30 primitive-vector supplement is missing $name."
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $vectorDir $name) `
        -Force
}
$vectorCompletion = Join-Path $scriptDir "prepare_vv35_primitive_vectors.py"
& $python $vectorCompletion --repo-root $repoRoot --vector-dir $vectorDir
if ($LASTEXITCODE -ne 0) {
    throw "VV35 primitive-vector completion failed."
}

$rtlRoot = Join-Path $repoRoot "core\hdec\rtl"
$rtlStart = Get-TreeHash -Root $rtlRoot
$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
$gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>&1 | Out-String).Trim()
$gitStatusStart = @(& git -C $repoRoot status --short 2>&1)

$testResults = @()
$hasFailure = $false
$oldPath = $env:Path
$env:Path = "$VivadoBin;$oldPath"
try {
    foreach ($testName in $selectedTests) {
        $definition = $config.tests.$testName
        $runnerLog = Join-Path $OutRoot "$testName.runner.log"
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $vivadoExit = -1
        $xsimDir = $null
        $xsimLog = $null
        $toolStatusPath = $null
        Write-Host "[VV35:EVAL] START test=$testName runner=$($definition.runner)"
        Push-Location $OutRoot
        try {
            switch ([string]$definition.runner) {
                "vv30_generic" {
                    $runTcl = Join-Path $repoRoot "scripts\hdec\vv30\vv30_xsim_run.tcl"
                    & $vivado -mode batch -nolog -nojournal -notrace `
                        -source $runTcl -tclargs `
                        $repoRoot $OutRoot $definition.legacy_name $vectorDir `
                        2>&1 | Tee-Object -LiteralPath $runnerLog |
                        ForEach-Object { Write-Host $_ }
                    $vivadoExit = $LASTEXITCODE
                    $xsimDir = Join-Path $OutRoot "xsim_$($definition.legacy_name)"
                    $xsimLog = Join-Path $xsimDir "xsim.log"
                    $toolStatusPath = Join-Path $xsimDir "tool_status.json"
                }
                "vv31_generic" {
                    $runTcl = Join-Path $repoRoot "scripts\hdec\vv31\vv31_xsim_run.tcl"
                    & $vivado -mode batch -nolog -nojournal -notrace `
                        -source $runTcl -tclargs `
                        $repoRoot $repoRoot $OutRoot $testName `
                        $definition.top $definition.file $vectorDir `
                        2>&1 | Tee-Object -LiteralPath $runnerLog |
                        ForEach-Object { Write-Host $_ }
                    $vivadoExit = $LASTEXITCODE
                    $xsimDir = Join-Path $OutRoot "xsim_$testName"
                    $xsimLog = Join-Path $xsimDir "xsim.log"
                    $toolStatusPath = Join-Path $xsimDir "tool_status.json"
                }
                "dedicated_tcl" {
                    $runTcl = Join-Path $repoRoot ([string]$definition.script)
                    & $vivado -mode batch -nolog -nojournal -notrace `
                        -source $runTcl -tclargs $repoRoot $OutRoot `
                        2>&1 | Tee-Object -LiteralPath $runnerLog |
                        ForEach-Object { Write-Host $_ }
                    $vivadoExit = $LASTEXITCODE
                    $xsimLog = Join-Path $OutRoot ([string]$definition.result_log)
                    $xsimDir = Split-Path -Parent $xsimLog
                }
                default {
                    throw "Unknown runner '$($definition.runner)' for $testName."
                }
            }
        }
        finally {
            Pop-Location
            $stopwatch.Stop()
        }

        $toolStatus = $null
        $toolOk = $vivadoExit -eq 0
        if (-not [string]::IsNullOrWhiteSpace($toolStatusPath)) {
            if (Test-Path -LiteralPath $toolStatusPath) {
                $toolStatus = Get-Content -LiteralPath $toolStatusPath -Raw |
                    ConvertFrom-Json
                $toolOk = $toolOk -and
                    ($toolStatus.xvlog -eq 0) -and
                    ($toolStatus.xelab -eq 0) -and
                    ($toolStatus.xsim -eq 0)
            }
            else {
                $toolOk = $false
            }
        }

        $xsimLogPresent = Test-Path -LiteralPath $xsimLog
        $xsimText = if ($xsimLogPresent) {
            Get-Content -LiteralPath $xsimLog -Raw
        } else { "" }
        $passCount = [regex]::Matches(
            $xsimText,
            [regex]::Escape([string]$definition.pass_marker)
        ).Count
        $failureFound = [regex]::IsMatch(
            $xsimText,
            "(?im)(^\s*(ERROR|Fatal):|^\s*\*\*\s*(Error|Fatal):|\bFAIL(?:ED)?\b|\bABORTED\b)"
        )
        $coverageMatches = [regex]::Matches(
            $xsimText,
            "\[(VV30|VV31):COVERAGE\]\s+test=\S+\s+observed=(\d+)\s+expected=(\d+)"
        )
        $coverageOk = $true
        foreach ($coverage in $coverageMatches) {
            if ($coverage.Groups[2].Value -ne $coverage.Groups[3].Value) {
                $coverageOk = $false
            }
        }
        $metricMatches = [regex]::Matches(
            $xsimText,
            "(?m)^\[(VV30|VV31):([A-Z][A-Z0-9_]*)\]\s*(.*)$"
        )
        $metricRecords = @()
        $cycleEvidence = @()
        foreach ($metric in $metricMatches) {
            $line = $metric.Value.Trim()
            $record = [ordered]@{
                namespace = $metric.Groups[1].Value
                tag = $metric.Groups[2].Value
                fields = Convert-MetricFields -Line $line
                raw = $line
            }
            $metricRecords += $record
            if ($line -match "(?i)(cycle|timing|wall|service)") {
                $cycleEvidence += $line
            }
        }
        $passed = $toolOk -and $xsimLogPresent -and
            ($passCount -eq 1) -and (-not $failureFound) -and $coverageOk
        $status = if ($passed) { "PASS" } else { "FAIL" }
        if (-not $passed) {
            $hasFailure = $true
        }
        $testResults += [ordered]@{
            name = $testName
            runner = [string]$definition.runner
            status = $status
            elapsed_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
            vivado_exit = $vivadoExit
            tool_status = $toolStatus
            tool_ok = $toolOk
            xsim_log_present = $xsimLogPresent
            pass_marker = [string]$definition.pass_marker
            pass_marker_count = $passCount
            failure_marker_found = $failureFound
            coverage_records = $coverageMatches.Count
            coverage_equal = $coverageOk
            metric_records = $metricRecords
            cycle_evidence = $cycleEvidence
            runner_log = $runnerLog
            xsim_log = $xsimLog
            xsim_log_sha256 = if ($xsimLogPresent) {
                Get-Sha256 -Path $xsimLog
            } else { $null }
        }
        Write-Host (
            "[VV35:EVAL] $status test=$testName " +
            "pass_count=$passCount tool_ok=$toolOk seconds=$([Math]::Round($stopwatch.Elapsed.TotalSeconds, 3))"
        )
    }
}
finally {
    $env:Path = $oldPath
}

$rtlEnd = Get-TreeHash -Root $rtlRoot
$rtlUnchanged = $rtlStart.aggregate -eq $rtlEnd.aggregate
if (-not $rtlUnchanged) {
    $hasFailure = $true
}
$overall = if ($hasFailure) { "FAIL" } else { "PASS" }
$finalVectorTree = Get-TreeHash -Root $vectorDir
$manifest = [ordered]@{
    schema = "hdec-vv35-functional-run-v1"
    overall = $overall
    suite = $Suite
    started_at = $startedAt
    completed_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
    output_root = $OutRoot
    git_branch = $gitBranch
    git_commit = $gitCommit
    git_status_start = $gitStatusStart
    git_status_end = @(& git -C $repoRoot status --short 2>&1)
    vivado_version = $vivadoVersion
    vivado_version_short = $vivadoVersionShort
    target_device = "xc7z020clg400-2"
    clock_constraint_ns = 5.0
    python_executable = $python
    rtl_sha256 = $rtlEnd.aggregate
    rtl_sha256_start = $rtlStart.aggregate
    rtl_sha256_end = $rtlEnd.aggregate
    rtl_unchanged_during_run = $rtlUnchanged
    rtl_files = $rtlEnd.files
    vector_profile = $vectorProfile
    vector_manifest = $vectorManifest
    vector_manifest_scope = (
        "VV31 PMUL/HDC base manifest before the explicit VV30 primitive " +
        "compatibility overlay; final per-file hashes are in vector_files"
    )
    vector_manifest_sha256 = Get-Sha256 -Path $vectorManifestPath
    vector_bundle_sha256 = $finalVectorTree.aggregate
    vector_files = $finalVectorTree.files
    vv30_primitive_supplement_sha256 = (
        Get-Sha256 -Path (Join-Path $vv30SupplementDir "vector_manifest.json")
    )
    verification_infrastructure_correction = [ordered]@{
        issue = (
            "The initial quick probe lacked gf_acc_inputs.mem and " +
            "gf_mac_expected.mem because the VV31 generator does not emit " +
            "the VV30 GFMAC-only files."
        )
        classification = "TEST_INFRASTRUCTURE_VECTOR_BUNDLE_INCOMPLETE"
        rtl_failure = $false
        resolution = (
            "Generate the VV30 primitive group from the identical master " +
            "seed, overlay the complete dependent group, and hash the final bundle."
        )
    }
    test_list_sha256 = Get-Sha256 -Path $configPath
    selected_tests = $selectedTests
    strict_pass_contract = (
        "vivado exit 0; generic xvlog/xelab/xsim exits 0; exactly one pass " +
        "marker in xsim.log; no failure marker in xsim.log; all coverage " +
        "observed counts equal expected counts"
    )
    tests = $testResults
}
$outputs = Write-Outputs -Manifest $manifest -OutputDirectory $OutRoot
Write-Host (
    "[VV35:FUNCTIONAL_RUN] $overall suite=$Suite " +
    "manifest=$($outputs.manifest) summary=$($outputs.summary)"
)
if ($hasFailure) {
    exit 1
}
exit 0
