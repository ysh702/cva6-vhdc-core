[CmdletBinding()]
param(
    [ValidateSet("quick", "stage1", "stage2", "stage3", "full", "stress", "replay")]
    [string]$Suite = "quick",
    [string]$Seed,
    [switch]$Replay,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe,
    [string]$OutRoot
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path

if ($Replay) {
    $Suite = "replay"
}
if ($Suite -eq "replay" -and [string]::IsNullOrWhiteSpace($Seed)) {
    throw "-Suite replay or -Replay requires -Seed."
}

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $xvlog) -or -not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado simulator tools were not found under $VivadoBin"
}
$versionText = (& $xvlog --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $versionText -notmatch "v2024\.2") {
    throw "VV30 requires Vivado Simulator v2024.2. Detected: $versionText"
}

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $candidates = @(
        "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
        "E:\HDEC\tools\python_envs\nature_figure\Scripts\python.exe",
        "E:\HDEC\tools\python_envs\scipilot_figure\Scripts\python.exe"
    )
    $commandPython = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $commandPython) {
        $candidates += $commandPython.Source
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            $probe = (& $candidate --version 2>&1 | Out-String)
            if ($LASTEXITCODE -eq 0 -and $probe -match "Python 3") {
                $PythonExe = $candidate
                break
            }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    throw "No working Python 3 interpreter was found. Pass -PythonExe explicitly."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$runStartedAt = (Get-Date).ToString("o")
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv30\$timestamp"
}
$OutRoot = [System.IO.Path]::GetFullPath($OutRoot)
$vectorDir = Join-Path $OutRoot "vectors"
New-Item -ItemType Directory -Force -Path $vectorDir | Out-Null

$generator = Join-Path $scriptDir "gen_vv30_vectors.py"
$generatorLog = Join-Path $OutRoot "vector_generator.log"
$generatorArgs = @($generator, "--out-dir", $vectorDir, "--suite", $Suite)
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $generatorArgs += @("--seed", $Seed)
}
& $PythonExe @generatorArgs 2>&1 | Tee-Object -FilePath $generatorLog
if ($LASTEXITCODE -ne 0) {
    throw "VV30 vector generation failed. See $generatorLog"
}

$configPath = Join-Path $scriptDir "vv30_tests.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
$selectedTests = @($config.suites.$Suite)
if ($selectedTests.Count -eq 0) {
    throw "No tests are registered for suite $Suite"
}

$oldPath = $env:Path
$env:Path = "$VivadoBin;$oldPath"
$testResults = @()
$hasFailure = $false
$hasNoDecision = $false
$failurePattern = "(?im)(^\s*ERROR:|^\s*\*\*\s*Error:|\b(FAIL|FAILED|FATAL|ASSERT|ABORTED|SEGMENTATION FAULT)\b)"

try {
    foreach ($testName in $selectedTests) {
        $definition = $config.tests.$testName
        if ($definition.runner -eq "no_decision") {
            $testResults += [ordered]@{
                name = $testName
                status = "NO_DECISION"
                reason = $definition.reason
            }
            $hasNoDecision = $true
            Write-Host "[VV30:$testName] NO_DECISION $($definition.reason)"
            continue
        }

        $testLog = Join-Path $OutRoot "$testName.log"
        $testStartedAt = (Get-Date).ToString("o")
        Push-Location $OutRoot
        try {
            if ($definition.runner -eq "generic") {
                $runTcl = Join-Path $scriptDir "vv30_xsim_run.tcl"
                & $vivado -mode batch -nolog -nojournal -notrace `
                    -source $runTcl -tclargs `
                    $repoRoot $OutRoot $testName $vectorDir 2>&1 |
                    Tee-Object -FilePath $testLog
            } elseif ($definition.runner -eq "dedicated_tcl") {
                $runTcl = Join-Path $repoRoot $definition.script
                & $vivado -mode batch -nolog -nojournal -notrace `
                    -source $runTcl -tclargs $repoRoot $OutRoot 2>&1 |
                    Tee-Object -FilePath $testLog
            } else {
                throw "Unknown runner '$($definition.runner)' for test $testName"
            }
        }
        finally {
            Pop-Location
        }
        $toolExit = $LASTEXITCODE
        $testCompletedAt = (Get-Date).ToString("o")
        $logText = Get-Content -Raw -LiteralPath $testLog
        if (($definition.runner -eq "dedicated_tcl") -and
            ($null -ne $definition.result_log)) {
            $resultLog = Join-Path $OutRoot ([string]$definition.result_log)
            if (Test-Path -LiteralPath $resultLog) {
                $logText += "`n" + (Get-Content -Raw -LiteralPath $resultLog)
            } else {
                $logText += "`n[VV30:$testName] RESULT_LOG_MISSING $resultLog"
            }
        }
        $marker = [regex]::Escape([string]$definition.pass_marker)
        $markerCount = [regex]::Matches($logText, $marker).Count
        $coverageMatches = [regex]::Matches(
            $logText,
            "\[VV30:COVERAGE\]\s+test=\S+\s+observed=(\d+)\s+expected=(\d+)"
        )
        $coverageOk = $true
        foreach ($coverage in $coverageMatches) {
            if ($coverage.Groups[1].Value -ne $coverage.Groups[2].Value) {
                $coverageOk = $false
            }
        }
        $failureFound = [regex]::IsMatch($logText, $failurePattern)
        $pmulCycleMatches = [regex]::Matches(
            $logText,
            "\[VV30:PMUL_CYCLE\]\s+case=(\d+)\s+K=([0-9a-fA-F]+)\s+weight=(\d+)\s+cycles=(\d+)"
        )
        $pmulCycleRecords = @()
        foreach ($cycleMatch in $pmulCycleMatches) {
            $pmulCycleRecords += [ordered]@{
                case = [int]$cycleMatch.Groups[1].Value
                k_hex = $cycleMatch.Groups[2].Value.ToLower()
                hamming_weight = [int]$cycleMatch.Groups[3].Value
                cycles = [int]$cycleMatch.Groups[4].Value
            }
        }
        $gfmacMetricMatch = [regex]::Match(
            $logText,
            "\[VV30:GFMAC_METRICS\]\s+seed=([0-9a-fA-F]+)\s+cases=(\d+)\s+gfmul_cycles=(\d+)\s+gfmac_cycles=(\d+)\s+delta=(-?\d+)\s+tmp_writes=(\d+)\s+acc_writes=(\d+)"
        )
        $gfmacMetrics = $null
        if ($gfmacMetricMatch.Success) {
            $gfmacMetrics = [ordered]@{
                seed_hex = $gfmacMetricMatch.Groups[1].Value.ToLower()
                cases = [int]$gfmacMetricMatch.Groups[2].Value
                gfmul_cycles = [int]$gfmacMetricMatch.Groups[3].Value
                gfmac_cycles = [int]$gfmacMetricMatch.Groups[4].Value
                cycle_delta = [int]$gfmacMetricMatch.Groups[5].Value
                temporary_writes = [int]$gfmacMetricMatch.Groups[6].Value
                accumulator_writes = [int]$gfmacMetricMatch.Groups[7].Value
            }
        }
        $passed = ($toolExit -eq 0) -and ($markerCount -eq 1) `
                  -and (-not $failureFound) -and $coverageOk
        $status = if ($passed) { "PASS" } else { "FAIL" }
        if (-not $passed) {
            $hasFailure = $true
        }
        $internalToolStatus = $null
        if ($definition.runner -eq "generic") {
            $toolStatusPath = Join-Path $OutRoot "xsim_$testName\tool_status.json"
            if (Test-Path -LiteralPath $toolStatusPath) {
                $internalToolStatus = Get-Content -Raw -LiteralPath $toolStatusPath |
                    ConvertFrom-Json
            }
        }
        $testResults += [ordered]@{
            name = $testName
            status = $status
            started_at = $testStartedAt
            completed_at = $testCompletedAt
            tool_exit = $toolExit
            internal_tool_exits = $internalToolStatus
            pass_marker_count = $markerCount
            failure_marker_found = $failureFound
            coverage_records = $coverageMatches.Count
            coverage_equal = $coverageOk
            pmul_cycle_records = $pmulCycleRecords
            gfmac_metrics = $gfmacMetrics
            log = $testLog
            log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $testLog).Hash.ToLower()
        }
    }
}
finally {
    $env:Path = $oldPath
}

$vectorManifest = Get-Content -Raw -LiteralPath (
    Join-Path $vectorDir "vector_manifest.json"
) | ConvertFrom-Json
$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
$gitStatus = @(& git -C $repoRoot status --short 2>&1)
$rtlHashEntries = @()
$rtlHashLines = @()
Get-ChildItem -LiteralPath (Join-Path $repoRoot "core\hdec\rtl") -Filter "*.sv" |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()
        $relative = "core/hdec/rtl/$($_.Name)"
        $rtlHashEntries += [ordered]@{ path = $relative; sha256 = $hash }
        $rtlHashLines += "$relative|$hash"
    }
$aggregateBytes = [System.Text.Encoding]::UTF8.GetBytes(
    ($rtlHashLines -join "`n") + "`n"
)
$aggregateHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $rtlAggregateHash = -join (
        $aggregateHasher.ComputeHash($aggregateBytes) |
        ForEach-Object { $_.ToString("x2") }
    )
}
finally {
    $aggregateHasher.Dispose()
}
$overall = if ($hasFailure) {
    "FAIL"
} elseif ($hasNoDecision) {
    "NO_DECISION"
} else {
    "PASS"
}
$runManifest = [ordered]@{
    schema = "hdec-vv30-run-v1"
    suite = $Suite
    overall = $overall
    started_at = $runStartedAt
    completed_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
    git_commit = $gitCommit
    git_status = $gitStatus
    vivado_version = $versionText.Trim()
    target_device = "xc7z020clg400-2"
    clock_constraint_ns = 5.0
    python_executable = $PythonExe
    rtl_sha256 = $rtlAggregateHash
    rtl_files = $rtlHashEntries
    vector_manifest = $vectorManifest
    tests = $testResults
}
$runManifestPath = Join-Path $OutRoot "run_manifest.json"
$runManifest | ConvertTo-Json -Depth 12 |
    Set-Content -Encoding UTF8 -LiteralPath $runManifestPath

Write-Host "[VV30:RUN] $overall suite=$Suite manifest=$runManifestPath"
if ($hasFailure) {
    exit 1
}
if ($hasNoDecision) {
    exit 2
}
exit 0
