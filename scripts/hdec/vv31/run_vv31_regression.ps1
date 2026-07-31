<#
.SYNOPSIS
Runs the VV31 randomized XSim regression or generates a replayable vector bundle.

.DESCRIPTION
The runner requires Vivado Simulator 2024.2 for simulation.  A normal run
creates a new 256-bit OS-CSPRNG master seed.  Supplying -Seed, -Replay, or
-ReplayManifest explicitly selects replay mode.  The same vector bundle is
shared by every test in one run.  The stage profile is the per-candidate gate
and uses one fresh legal random K.  Use the full profile for final or freeze
multi-K regression.

.EXAMPLE
.\run_vv31_regression.ps1 -Suite quick

.EXAMPLE
.\run_vv31_regression.ps1 -Suite stage -VectorsOnly

.EXAMPLE
.\run_vv31_regression.ps1 -Suite full

.EXAMPLE
.\run_vv31_regression.ps1 -Suite replay -ReplayProfile stage -Seed <64-hex>

.EXAMPLE
.\run_vv31_regression.ps1 -ReplayManifest <old-run-manifest.json>
#>

[CmdletBinding()]
param(
    [ValidateSet(
        "baseline_gap", "quick", "stage", "full", "stress", "replay"
    )]
    [string]$Suite = "quick",
    [string]$Seed,
    [switch]$Replay,
    [ValidateSet("baseline_gap", "quick", "stage", "full", "stress")]
    [string]$ReplayProfile = "full",
    [string]$ReplayManifest,
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin",
    [string]$PythonExe,
    [string]$TbRepoRoot,
    [string]$OutRoot,
    [switch]$VectorsOnly,
    [switch]$ValidateOnly,
    [switch]$AllowMissingTests,
    [switch]$ListSuites,
    [switch]$ListTests
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
if ([string]::IsNullOrWhiteSpace($TbRepoRoot)) {
    $TbRepoRoot = $repoRoot
} else {
    $TbRepoRoot = (Resolve-Path -LiteralPath $TbRepoRoot).Path
}

function Resolve-Python3 {
    param([string]$Requested)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        $candidates = @($Requested)
    } else {
        $candidates = @(
            "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe",
            "E:\HDEC\tools\python_envs\nature_figure\Scripts\python.exe",
            "E:\HDEC\tools\python_envs\scipilot_figure\Scripts\python.exe"
        )
        $commandPython = Get-Command python -ErrorAction SilentlyContinue
        if ($null -ne $commandPython) {
            $candidates += $commandPython.Source
        }
    }
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) {
            continue
        }
        $probe = (& $candidate --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $probe -match "Python 3\.(1[0-9]|[2-9][0-9])") {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "No working Python 3.10+ interpreter was found. Pass -PythonExe explicitly."
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-TreeHash {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$BaseForRelativePath,
        [string[]]$Extensions = @()
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        return [ordered]@{ aggregate = $null; files = @() }
    }
    $entries = @()
    $lines = @()
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            if ($Extensions.Count -gt 0 -and
                $Extensions -notcontains $_.Extension.ToLower()) {
                return
            }
            $relative = $_.FullName.Substring(
                $BaseForRelativePath.Length
            ).TrimStart("\", "/").Replace("\", "/")
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

function Convert-MetricLine {
    param([string]$Tag, [string]$Payload)

    $fields = [ordered]@{}
    $matches = [regex]::Matches($Payload, "([A-Za-z0-9_]+)=([^\s]+)")
    foreach ($match in $matches) {
        $fields[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    return [ordered]@{
        tag = $Tag
        fields = $fields
        raw = $Payload.Trim()
    }
}

function Get-MetricRecords {
    param([string]$LogText)

    $records = @()
    $matches = [regex]::Matches(
        $LogText,
        "(?m)^\[VV31:([A-Z][A-Z0-9_]*)\]\s*(.*)$"
    )
    foreach ($match in $matches) {
        $records += Convert-MetricLine `
            -Tag $match.Groups[1].Value `
            -Payload $match.Groups[2].Value
    }
    return $records
}

function Get-VectorManifestFromFile {
    param([string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $parsed = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
    if ([string]$parsed.schema -like "hdec-vv31-run-*") {
        if ($null -eq $parsed.vector_manifest) {
            throw "Run manifest does not contain vector_manifest: $resolved"
        }
        return [ordered]@{
            source_path = $resolved
            vector_manifest = $parsed.vector_manifest
        }
    }
    if ([string]$parsed.schema -like "hdec-vv31-vectors-*") {
        return [ordered]@{
            source_path = $resolved
            vector_manifest = $parsed
        }
    }
    throw "Unsupported VV31 replay manifest schema '$($parsed.schema)'"
}

$configPath = Join-Path $scriptDir "vv31_tests.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.schema -ne "hdec-vv31-tests-v1") {
    throw "Unsupported VV31 test schema '$($config.schema)'"
}

if ($ListSuites) {
    $config.suites.PSObject.Properties.Name | Sort-Object | ForEach-Object {
        $count = @($config.suites.$_).Count
        Write-Host "$_ ($count tests)"
    }
    exit 0
}
if ($ListTests) {
    $config.tests.PSObject.Properties.Name | Sort-Object | ForEach-Object {
        $definition = $config.tests.$_
        Write-Host "$_ -> $($definition.top) [$($definition.file)]"
    }
    exit 0
}

$python = Resolve-Python3 -Requested $PythonExe
$generator = Join-Path $scriptDir "gen_vv31_vectors.py"
$reference = Join-Path $scriptDir "k233_reference.py"

$pythonSyntaxFiles = @($generator, $reference)
foreach ($pythonFile in $pythonSyntaxFiles) {
    $syntaxProbe = @"
import ast
from pathlib import Path
ast.parse(Path(r'''$pythonFile''').read_text(encoding='utf-8'))
"@
    & $python -c $syntaxProbe
    if ($LASTEXITCODE -ne 0) {
        throw "Python syntax validation failed: $pythonFile"
    }
}

$allSelectedDefinitions = @()
$suiteNames = @($config.suites.PSObject.Properties.Name)
foreach ($suiteName in $suiteNames) {
    foreach ($testName in @($config.suites.$suiteName)) {
        if ($null -eq $config.tests.$testName) {
            throw "Suite '$suiteName' references unknown test '$testName'"
        }
    }
}
foreach ($testProperty in $config.tests.PSObject.Properties) {
    $definition = $testProperty.Value
    if ($definition.runner -eq "generic") {
        if ([string]::IsNullOrWhiteSpace([string]$definition.top) -or
            [string]::IsNullOrWhiteSpace([string]$definition.file) -or
            [string]::IsNullOrWhiteSpace([string]$definition.pass_marker)) {
            throw "Generic test '$($testProperty.Name)' has an incomplete definition"
        }
        $testPath = Join-Path $TbRepoRoot ([string]$definition.file)
        $allSelectedDefinitions += [ordered]@{
            name = $testProperty.Name
            path = $testPath
            exists = Test-Path -LiteralPath $testPath
        }
    }
}

if ($ValidateOnly) {
    $missing = @($allSelectedDefinitions | Where-Object { -not $_.exists })
    if ($missing.Count -gt 0) {
        foreach ($entry in $missing) {
            Write-Warning "VV31 test source is not present yet: $($entry.name) -> $($entry.path)"
        }
        if (-not $AllowMissingTests) {
            throw "VV31 validation found $($missing.Count) missing test source(s)."
        }
    }
    Write-Host (
        "[VV31:runner_validate] PASS tests=$($allSelectedDefinitions.Count) " +
        "missing=$($missing.Count) config=$configPath"
    )
    exit 0
}

$requestedSuite = $Suite
$replaySource = $null
if (-not [string]::IsNullOrWhiteSpace($ReplayManifest)) {
    $replaySource = Get-VectorManifestFromFile -Path $ReplayManifest
    $oldVectorManifest = $replaySource.vector_manifest
    $manifestSeed = [string]$oldVectorManifest.seed_hex
    if (-not [string]::IsNullOrWhiteSpace($Seed)) {
        $normalizedSeed = ($Seed -replace "^0[xX]", "").ToLower()
        if ($normalizedSeed -ne $manifestSeed.ToLower()) {
            throw "-Seed does not match the seed in -ReplayManifest."
        }
    }
    $Seed = $manifestSeed
    if ($null -ne $oldVectorManifest.profile -and
        @("baseline_gap", "quick", "stage", "full", "stress") -contains
            [string]$oldVectorManifest.profile) {
        $ReplayProfile = [string]$oldVectorManifest.profile
    }
    $Suite = "replay"
} elseif ($Replay) {
    if (-not $PSBoundParameters.ContainsKey("ReplayProfile") -and
        $Suite -ne "replay") {
        $ReplayProfile = $Suite
    }
    $Suite = "replay"
} elseif (-not [string]::IsNullOrWhiteSpace($Seed) -and $Suite -ne "replay") {
    $ReplayProfile = $Suite
    $Suite = "replay"
}
if ($Suite -eq "replay" -and [string]::IsNullOrWhiteSpace($Seed)) {
    throw "Replay mode requires -Seed or -ReplayManifest."
}

$testSuiteName = if ($Suite -eq "replay") { $ReplayProfile } else { $Suite }
if ($testSuiteName -notin @($config.suites.PSObject.Properties.Name)) {
    throw "No test suite is registered for profile '$testSuiteName'."
}
$selectedTests = @($config.suites.$testSuiteName)
if ($selectedTests.Count -eq 0 -and -not $VectorsOnly) {
    throw "No tests are registered for suite '$testSuiteName'."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$runStartedAt = (Get-Date).ToString("o")
if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $OutRoot = Join-Path $repoRoot "tmp\hdec_logs\vv31\$timestamp"
}
$OutRoot = [System.IO.Path]::GetFullPath($OutRoot)
$vectorDir = Join-Path $OutRoot "vectors"
New-Item -ItemType Directory -Force -Path $vectorDir | Out-Null

$generatorLog = Join-Path $OutRoot "vector_generator.log"
$generatorArgs = @(
    $generator,
    "--out-dir", $vectorDir,
    "--suite", $Suite,
    "--replay-profile", $ReplayProfile
)
if (-not [string]::IsNullOrWhiteSpace($Seed)) {
    $generatorArgs += @("--seed", $Seed)
}
& $python @generatorArgs 2>&1 | Tee-Object -FilePath $generatorLog
$generatorExit = $LASTEXITCODE
if ($generatorExit -ne 0) {
    throw "VV31 vector generation failed. See $generatorLog"
}

$vectorManifestPath = Join-Path $vectorDir "vector_manifest.json"
$vectorManifest = Get-Content -Raw -LiteralPath $vectorManifestPath |
    ConvertFrom-Json

$replayComparison = [ordered]@{
    enabled = $null -ne $replaySource
    source_manifest = if ($null -ne $replaySource) {
        $replaySource.source_path
    } else {
        $null
    }
    checked_files = 0
    hashes_equal = $null
    mismatches = @()
}
if ($null -ne $replaySource) {
    $mismatches = @()
    foreach ($property in $replaySource.vector_manifest.files.PSObject.Properties) {
        $name = $property.Name
        $oldHash = [string]$property.Value.sha256
        $newProperty = $vectorManifest.files.PSObject.Properties[$name]
        if ($null -eq $newProperty) {
            $mismatches += "$name:missing"
            continue
        }
        $newHash = [string]$newProperty.Value.sha256
        if ($newHash.ToLower() -ne $oldHash.ToLower()) {
            $mismatches += "$name:hash"
        }
        $replayComparison.checked_files++
    }
    $replayComparison.hashes_equal = $mismatches.Count -eq 0
    $replayComparison.mismatches = $mismatches
    if ($mismatches.Count -gt 0) {
        throw "Replay vector hashes differ: $($mismatches -join ', ')"
    }
}

$vivadoVersionText = "NOT_RUN"
$vivado = $null
if (-not $VectorsOnly) {
    $requiredTools = @("xvlog.bat", "xelab.bat", "xsim.bat", "vivado.bat")
    foreach ($toolName in $requiredTools) {
        $toolPath = Join-Path $VivadoBin $toolName
        if (-not (Test-Path -LiteralPath $toolPath)) {
            throw "Vivado tool was not found: $toolPath"
        }
    }
    $xvlog = Join-Path $VivadoBin "xvlog.bat"
    $vivado = Join-Path $VivadoBin "vivado.bat"
    $vivadoVersionText = (& $xvlog --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $vivadoVersionText -notmatch "v2024\.2") {
        throw "VV31 requires Vivado Simulator v2024.2. Detected: $vivadoVersionText"
    }
}

$testResults = @()
$hasFailure = $false
$hasNoDecision = $false
$failurePattern = (
    "(?im)(^\s*ERROR:|^\s*\*\*\s*Error:|" +
    "\b(FAIL|FAILED|FATAL|ASSERT|ABORTED|SEGMENTATION FAULT)\b)"
)

if (-not $VectorsOnly) {
    $oldPath = $env:Path
    $env:Path = "$VivadoBin;$oldPath"
    try {
        foreach ($testName in $selectedTests) {
            $definition = $config.tests.$testName
            $testPath = Join-Path $TbRepoRoot ([string]$definition.file)
            if (-not (Test-Path -LiteralPath $testPath)) {
                $reason = "test source is not present: $testPath"
                if (-not $AllowMissingTests) {
                    throw $reason
                }
                Write-Warning "[VV31:$testName] NO_DECISION $reason"
                $testResults += [ordered]@{
                    name = $testName
                    status = "NO_DECISION"
                    reason = $reason
                }
                $hasNoDecision = $true
                continue
            }

            $testLog = Join-Path $OutRoot "$testName.log"
            $testStartedAt = (Get-Date).ToString("o")
            $toolExit = -1
            Push-Location $OutRoot
            try {
                if ($definition.runner -eq "generic") {
                    $runTcl = Join-Path $scriptDir "vv31_xsim_run.tcl"
                    & $vivado -mode batch -nolog -nojournal -notrace `
                        -source $runTcl -tclargs `
                        $repoRoot $TbRepoRoot $OutRoot $testName `
                        $definition.top $definition.file $vectorDir 2>&1 |
                        Tee-Object -FilePath $testLog
                    $toolExit = $LASTEXITCODE
                } elseif ($definition.runner -eq "dedicated_tcl") {
                    $runTcl = Join-Path $TbRepoRoot ([string]$definition.script)
                    & $vivado -mode batch -nolog -nojournal -notrace `
                        -source $runTcl -tclargs `
                        $repoRoot $TbRepoRoot $OutRoot $vectorDir 2>&1 |
                        Tee-Object -FilePath $testLog
                    $toolExit = $LASTEXITCODE
                } else {
                    throw "Unknown runner '$($definition.runner)' for $testName"
                }
            }
            finally {
                Pop-Location
            }
            $testCompletedAt = (Get-Date).ToString("o")
            if (-not (Test-Path -LiteralPath $testLog)) {
                throw "Test did not create its runner log: $testLog"
            }
            $logText = Get-Content -Raw -LiteralPath $testLog
            if ($definition.runner -eq "dedicated_tcl" -and
                $null -ne $definition.result_log) {
                $resultLog = Join-Path $OutRoot ([string]$definition.result_log)
                if (Test-Path -LiteralPath $resultLog) {
                    $logText += "`n" + (
                        Get-Content -Raw -LiteralPath $resultLog
                    )
                } else {
                    $logText += "`n[VV31:$testName] RESULT_LOG_MISSING"
                }
            }

            $marker = [regex]::Escape([string]$definition.pass_marker)
            $markerCount = [regex]::Matches($logText, $marker).Count
            $failureFound = [regex]::IsMatch($logText, $failurePattern)
            $coverageMatches = [regex]::Matches(
                $logText,
                "\[VV31:COVERAGE\]\s+test=\S+\s+observed=(\d+)\s+expected=(\d+)"
            )
            $coverageOk = $true
            foreach ($coverage in $coverageMatches) {
                if ($coverage.Groups[1].Value -ne $coverage.Groups[2].Value) {
                    $coverageOk = $false
                }
            }

            $pmulCycleMatches = [regex]::Matches(
                $logText,
                "\[VV31:PMUL_CYCLE\]\s+case=(\d+)\s+K=([0-9a-fA-F]+)" +
                "\s+weight=(\d+)\s+cycles=(\d+)"
            )
            $pmulCycles = @()
            foreach ($cycleMatch in $pmulCycleMatches) {
                $pmulCycles += [ordered]@{
                    case = [int]$cycleMatch.Groups[1].Value
                    k_hex = $cycleMatch.Groups[2].Value.ToLower()
                    hamming_weight = [int]$cycleMatch.Groups[3].Value
                    cycles = [int]$cycleMatch.Groups[4].Value
                }
            }
            $pmulCycleValues = @(
                $pmulCycles | ForEach-Object { $_.cycles } | Select-Object -Unique
            )
            $pmulConstant = $pmulCycleValues.Count -le 1

            $metricRecords = Get-MetricRecords -LogText $logText
            $resourceEventCount = [regex]::Matches(
                $logText,
                "(?m)^\[VV31:RESOURCE_EVENT\]"
            ).Count
            $internalToolStatus = $null
            if ($definition.runner -eq "generic") {
                $toolStatusPath = Join-Path (
                    Join-Path $OutRoot "xsim_$testName"
                ) "tool_status.json"
                if (Test-Path -LiteralPath $toolStatusPath) {
                    $internalToolStatus = Get-Content -Raw `
                        -LiteralPath $toolStatusPath | ConvertFrom-Json
                }
            }
            $passed = ($toolExit -eq 0) -and ($markerCount -eq 1) `
                -and (-not $failureFound) -and $coverageOk -and $pmulConstant
            $status = if ($passed) { "PASS" } else { "FAIL" }
            if (-not $passed) {
                $hasFailure = $true
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
                pmul_cycles_constant = $pmulConstant
                pmul_cycle_records = $pmulCycles
                resource_event_count = $resourceEventCount
                metric_records = $metricRecords
                log = $testLog
                log_sha256 = Get-Sha256 -Path $testLog
            }
        }
    }
    finally {
        $env:Path = $oldPath
    }
}

$gitCommit = (& git -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
$gitBranch = (& git -C $repoRoot rev-parse --abbrev-ref HEAD 2>&1 |
    Out-String).Trim()
$gitStatus = @(& git -C $repoRoot status --short 2>&1)
$rtlHashes = Get-TreeHash `
    -Root (Join-Path $repoRoot "core\hdec\rtl") `
    -BaseForRelativePath $repoRoot `
    -Extensions @(".sv")
$verificationHashes = Get-TreeHash `
    -Root (Join-Path $TbRepoRoot "verif\hdec\vv31") `
    -BaseForRelativePath $TbRepoRoot `
    -Extensions @(".sv")
$scriptHashes = Get-TreeHash `
    -Root $scriptDir `
    -BaseForRelativePath $repoRoot `
    -Extensions @(".ps1", ".py", ".tcl", ".json")

$overall = if ($hasFailure) {
    "FAIL"
} elseif ($hasNoDecision) {
    "NO_DECISION"
} else {
    "PASS"
}
if ($VectorsOnly) {
    $overall = "PASS"
}

$runManifest = [ordered]@{
    schema = "hdec-vv31-run-v1"
    suite = $Suite
    requested_suite = $requestedSuite
    profile = if ($Suite -eq "replay") { $ReplayProfile } else { $Suite }
    run_mode = if ($VectorsOnly) { "vectors_only" } else { "xsim_regression" }
    overall = $overall
    started_at = $runStartedAt
    completed_at = (Get-Date).ToString("o")
    repo_root = $repoRoot
    tb_repo_root = $TbRepoRoot
    output_root = $OutRoot
    git_branch = $gitBranch
    git_commit = $gitCommit
    git_status = $gitStatus
    vivado_version = $vivadoVersionText
    target_device = "xc7z020clg400-2"
    clock_constraint_ns = 5.0
    python_executable = $python
    rtl_sha256 = $rtlHashes.aggregate
    rtl_files = $rtlHashes.files
    verification_sha256 = $verificationHashes.aggregate
    verification_files = $verificationHashes.files
    runner_sha256 = $scriptHashes.aggregate
    runner_files = $scriptHashes.files
    vector_manifest = $vectorManifest
    replay_comparison = $replayComparison
    selected_tests = $selectedTests
    tests = $testResults
    chapter_v_evidence_gate = "NOT_EVALUATED_BY_RUNNER"
}
$runManifestPath = Join-Path $OutRoot "run_manifest.json"
$runManifest | ConvertTo-Json -Depth 20 |
    Set-Content -Encoding UTF8 -LiteralPath $runManifestPath

Write-Host (
    "[VV31:RUN] $overall suite=$Suite profile=$testSuiteName " +
    "manifest=$runManifestPath"
)
if ($hasFailure) {
    exit 1
}
if ($hasNoDecision) {
    exit 2
}
exit 0
