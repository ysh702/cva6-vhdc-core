[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputRoot,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'r16_acceptance_summary_20260805.json'),

    [string]$ArchivePath,

    [string]$ArchiveHashPath,

    [string]$ArchiveStatusPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedCommit = '498e957761d562030b67c68cb13e60bcdfd4da0c'
$ExpectedFrequencyHz = 200000000.0
$ExpectedMinimumAnnotationPercent = 99.0
$ExpectedScenarios = [ordered]@{
    serial = [ordered]@{
        scenario = 'SERIAL'
        cycles = 337853
        duration_ns = 1689265
    }
    interleaved = [ordered]@{
        scenario = 'INTERLEAVED'
        cycles = 200144
        duration_ns = 1000720
    }
}

$Checks = New-Object System.Collections.Generic.List[object]
$ScenarioMetrics = [ordered]@{}
$ComparisonMetrics = [ordered]@{}
$Discovery = [ordered]@{}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [string]$Path = '',
        [object]$Expected = $null,
        [object]$Actual = $null,
        [string]$Message = '',
        [ValidateSet('required', 'informational')][string]$Severity = 'required'
    )

    [void]$script:Checks.Add([pscustomobject][ordered]@{
        name = $Name
        status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        severity = $Severity
        path = $Path
        expected = $Expected
        actual = $Actual
        message = $Message
    })
}

function Test-NonemptyFile {
    param([string]$Path, [string]$Name)

    $exists = $false
    $length = $null
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $length = (Get-Item -LiteralPath $Path).Length
        $exists = $length -gt 0
    }
    Add-Check -Name $Name -Passed $exists -Path $Path -Expected 'nonempty file' -Actual $length `
        -Message $(if ($exists) { '' } else { 'Required result file is missing or empty.' })
    return $exists
}

function Read-KeyValueFile {
    param([string]$Path)

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim()
        $value = $line.Substring($index + 1).Trim()
        if ($key.Length -gt 0) { $result[$key] = $value }
    }
    return $result
}

function Test-KvExact {
    param(
        [hashtable]$Map,
        [string]$Path,
        [string]$Key,
        [string]$Expected,
        [string]$NamePrefix
    )

    $present = $Map.ContainsKey($Key)
    $actual = $(if ($present) { [string]$Map[$Key] } else { $null })
    $passed = $present -and $actual -ceq $Expected
    Add-Check -Name "$NamePrefix.$Key" -Passed $passed -Path $Path -Expected $Expected -Actual $actual `
        -Message $(if ($present) { '' } else { "Missing key: $Key" })
    return $passed
}

function Try-ParseInvariantDouble {
    param([object]$Value, [ref]$Parsed)

    $number = 0.0
    $ok = $false
    if ($null -ne $Value) {
        $ok = [double]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$number
        )
    }
    if ($ok -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) {
        $Parsed.Value = $number
        return $true
    }
    return $false
}

function Test-KvNumberRange {
    param(
        [hashtable]$Map,
        [string]$Path,
        [string]$Key,
        [double]$Minimum,
        [double]$Maximum,
        [string]$NamePrefix
    )

    $parsed = 0.0
    $present = $Map.ContainsKey($Key)
    $numeric = $present -and (Try-ParseInvariantDouble -Value $Map[$Key] -Parsed ([ref]$parsed))
    $passed = $numeric -and $parsed -ge $Minimum -and $parsed -le $Maximum
    Add-Check -Name "$NamePrefix.$Key" -Passed $passed -Path $Path `
        -Expected "numeric in [$Minimum, $Maximum]" -Actual $(if ($present) { $Map[$Key] } else { $null }) `
        -Message $(if ($present) { '' } else { "Missing key: $Key" })
    return $passed
}

function Test-KvHash {
    param([hashtable]$Map, [string]$Path, [string]$Key, [string]$NamePrefix)

    $present = $Map.ContainsKey($Key)
    $actual = $(if ($present) { [string]$Map[$Key] } else { $null })
    $passed = $present -and $actual -cmatch '^[0-9a-f]{64}$'
    Add-Check -Name "$NamePrefix.$Key" -Passed $passed -Path $Path -Expected '64 lowercase hex SHA-256' `
        -Actual $actual -Message $(if ($present) { '' } else { "Missing key: $Key" })
    return $passed
}

function Get-Sha256 {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ManifestFileHash {
    param(
        [hashtable]$Map,
        [string]$ManifestPath,
        [string]$Key,
        [string]$TargetPath,
        [string]$NamePrefix
    )

    $expected = $(if ($Map.ContainsKey($Key)) { [string]$Map[$Key] } else { $null })
    $actual = Get-Sha256 -Path $TargetPath
    $passed = $null -ne $expected -and $expected -cmatch '^[0-9a-f]{64}$' -and $actual -ceq $expected
    Add-Check -Name "$NamePrefix.$Key.file_match" -Passed $passed -Path $TargetPath -Expected $expected -Actual $actual `
        -Message $(if ($null -eq $actual) { 'Target file is missing.' } else { '' })
    return $passed
}

function Find-FirstExistingFile {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Find-FirstExistingDirectory {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Test-NearlyEqual {
    param([double]$Left, [double]$Right, [double]$RelativeTolerance = 1.0e-9, [double]$AbsoluteTolerance = 1.0e-9)

    $difference = [math]::Abs($Left - $Right)
    $scale = [math]::Max([math]::Abs($Left), [math]::Abs($Right))
    return $difference -le [math]::Max($AbsoluteTolerance, $scale * $RelativeTolerance)
}

function Parse-PowerReport {
    param([string]$Path, [string]$Scenario)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $text = Get-Content -LiteralPath $Path -Raw
    $headerPassed = $text -match '(?im)^\s*Report\s*:\s*power\s*$'
    Add-Check -Name "$Scenario.power_report.header" -Passed $headerPassed -Path $Path -Expected 'Report : power' `
        -Actual $(if ($headerPassed) { 'present' } else { 'absent' })

    $labels = [ordered]@{
        internal_power_mw = 'Cell Internal Power'
        switching_power_mw = 'Net Switching Power'
        leakage_power_mw = 'Cell Leakage Power'
        dynamic_power_mw = 'Total Dynamic Power'
    }
    $numberPattern = '([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)'
    foreach ($entry in $labels.GetEnumerator()) {
        $pattern = '(?im)^\s*' + [regex]::Escape($entry.Value) + '\s*=\s*' + $numberPattern + '\s*(W|mW|uW|nW)\b'
        $matches = [regex]::Matches($text, $pattern)
        $passed = $matches.Count -eq 1
        $normalized = $null
        $raw = $null
        if ($passed) {
            $value = 0.0
            $numeric = Try-ParseInvariantDouble -Value $matches[0].Groups[1].Value -Parsed ([ref]$value)
            $unit = $matches[0].Groups[2].Value
            $factor = switch -CaseSensitive ($unit) {
                'W' { 1000.0 }
                'mW' { 1.0 }
                'uW' { 0.001 }
                'nW' { 0.000001 }
                default { $null }
            }
            $passed = $numeric -and $null -ne $factor
            if ($passed) {
                $normalized = $value * [double]$factor
                $passed = $normalized -ge 0.0 -and -not [double]::IsInfinity($normalized)
                $raw = [ordered]@{ value = $value; unit = $unit }
            }
        }
        Add-Check -Name "$Scenario.power_report.$($entry.Key)" -Passed $passed -Path $Path `
            -Expected 'exactly one finite nonnegative value with W/mW/uW/nW unit' -Actual $raw `
            -Message $(if ($matches.Count -ne 1) { "Found $($matches.Count) matching rows." } else { '' })
        if ($passed) { $result[$entry.Key] = $normalized }
    }

    if ($result.Contains('internal_power_mw') -and $result.Contains('switching_power_mw') -and $result.Contains('dynamic_power_mw')) {
        $sum = [double]$result.internal_power_mw + [double]$result.switching_power_mw
        $dynamic = [double]$result.dynamic_power_mw
        $tolerance = [math]::Max(0.000001, [math]::Abs($dynamic) * 0.0005)
        $passed = [math]::Abs($sum - $dynamic) -le $tolerance
        Add-Check -Name "$Scenario.power_report.dynamic_component_consistency" -Passed $passed -Path $Path `
            -Expected "|internal + switching - dynamic| <= $tolerance mW" -Actual ([math]::Abs($sum - $dynamic))
    }
    if ($result.Contains('dynamic_power_mw') -and $result.Contains('leakage_power_mw')) {
        $result.total_power_mw = [double]$result.dynamic_power_mw + [double]$result.leakage_power_mw
    }
    return $result
}

function Parse-AreaReport {
    param([string]$Path, [string]$Scenario)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $text = Get-Content -LiteralPath $Path -Raw
    $fields = [ordered]@{
        number_of_ports = [ordered]@{ label = 'Number of ports'; required = $false }
        number_of_nets = [ordered]@{ label = 'Number of nets'; required = $false }
        number_of_cells = [ordered]@{ label = 'Number of cells'; required = $true }
        number_of_combinational_cells = [ordered]@{ label = 'Number of combinational cells'; required = $true }
        number_of_sequential_cells = [ordered]@{ label = 'Number of sequential cells'; required = $true }
        number_of_buf_inv_cells = [ordered]@{ label = 'Number of buf/inv cells'; required = $false }
        combinational_area = [ordered]@{ label = 'Combinational area'; required = $true }
        buf_inv_area = [ordered]@{ label = 'Buf/Inv area'; required = $false }
        noncombinational_area = [ordered]@{ label = 'Noncombinational area'; required = $true }
        macro_black_box_area = [ordered]@{ label = 'Macro/Black Box area'; required = $false }
        net_interconnect_area = [ordered]@{ label = 'Net Interconnect area'; required = $false }
        total_cell_area = [ordered]@{ label = 'Total cell area'; required = $true }
        total_area = [ordered]@{ label = 'Total area'; required = $false }
    }
    $numberPattern = '([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)'
    foreach ($entry in $fields.GetEnumerator()) {
        $pattern = '(?im)^\s*' + [regex]::Escape($entry.Value.label) + '\s*:\s*' + $numberPattern + '\s*$'
        $matches = [regex]::Matches($text, $pattern)
        if ($matches.Count -eq 0) {
            Add-Check -Name "$Scenario.area.$($entry.Key)" -Passed (-not $entry.Value.required) -Path $Path `
                -Expected $(if ($entry.Value.required) { 'numeric field present' } else { 'optional field' }) -Actual $null `
                -Message 'Field not present in this DC area report.' `
                -Severity $(if ($entry.Value.required) { 'required' } else { 'informational' })
            continue
        }
        $value = 0.0
        $numeric = Try-ParseInvariantDouble -Value $matches[$matches.Count - 1].Groups[1].Value -Parsed ([ref]$value)
        $passed = $numeric -and $value -ge 0.0
        Add-Check -Name "$Scenario.area.$($entry.Key)" -Passed $passed -Path $Path -Expected 'finite nonnegative number' -Actual $value `
            -Severity $(if ($entry.Value.required) { 'required' } else { 'informational' })
        if ($passed) { $result[$entry.Key] = $value }
    }
    return $result
}

function Parse-TimingReport {
    param([string]$Path, [string]$Scenario)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $text = Get-Content -LiteralPath $Path -Raw
    $matches = [regex]::Matches($text, '(?im)^\s*slack\s*\((MET|VIOLATED)\)\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\s*$')
    $slacks = New-Object System.Collections.Generic.List[double]
    $violated = 0
    foreach ($match in $matches) {
        $value = 0.0
        if (Try-ParseInvariantDouble -Value $match.Groups[2].Value -Parsed ([ref]$value)) {
            [void]$slacks.Add($value)
            if ($match.Groups[1].Value -ceq 'VIOLATED') { $violated++ }
        }
    }
    $hasPaths = $slacks.Count -gt 0
    Add-Check -Name "$Scenario.timing.constrained_paths" -Passed $hasPaths -Path $Path -Expected 'at least one numeric slack path' -Actual $slacks.Count
    Add-Check -Name "$Scenario.timing.violated_paths" -Passed ($hasPaths -and $violated -eq 0) -Path $Path -Expected 0 -Actual $violated
    if ($hasPaths) {
        $worst = ($slacks | Measure-Object -Minimum).Minimum
        Add-Check -Name "$Scenario.timing.worst_setup_slack_nonnegative" -Passed ($worst -ge 0.0) -Path $Path `
            -Expected '>= 0 ns' -Actual $worst
        $result.worst_setup_slack_ns = [double]$worst
        $result.path_count = $slacks.Count
        $result.violated_path_count = $violated
        $result.slacks_ns = @($slacks | ForEach-Object { $_ })
    }

    foreach ($label in @('Operating Conditions', 'Library', 'Wire Load Model')) {
        $match = [regex]::Match($text, '(?im)^\s*' + [regex]::Escape($label) + '\s*:\s*(.+?)\s*$')
        if ($match.Success) {
            $key = ($label.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
            $result[$key] = $match.Groups[1].Value.Trim()
        }
    }
    return $result
}

function Parse-ComparisonCsv {
    param([string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }
    $lines = @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 7) {
        Add-Check -Name 'comparison_csv.structure' -Passed $false -Path $Path -Expected 'header, two scenario rows, four key/value rows' `
            -Actual $lines.Count -Message 'Comparison CSV is truncated.'
        return $result
    }
    $expectedHeader = 'scenario,total_power_mw,dynamic_power_mw,cycles,time_s,total_energy_mj,dynamic_energy_mj'
    Add-Check -Name 'comparison_csv.header' -Passed ($lines[0] -ceq $expectedHeader) -Path $Path -Expected $expectedHeader -Actual $lines[0]
    foreach ($index in 1, 2) {
        $parts = $lines[$index].Split(',')
        $scenario = $(if ($parts.Count -gt 0) { $parts[0] } else { "row_$index" })
        $passed = $parts.Count -eq 7 -and ($scenario -ceq 'serial' -or $scenario -ceq 'interleaved')
        Add-Check -Name "comparison_csv.$scenario.row_shape" -Passed $passed -Path $Path -Expected '7 columns' -Actual $parts.Count
        if (-not $passed) { continue }
        $row = [ordered]@{}
        $names = @('total_power_mw', 'dynamic_power_mw', 'cycles', 'time_s', 'total_energy_mj', 'dynamic_energy_mj')
        for ($column = 1; $column -lt 7; $column++) {
            $value = 0.0
            if (Try-ParseInvariantDouble -Value $parts[$column] -Parsed ([ref]$value)) {
                $row[$names[$column - 1]] = $value
            }
        }
        $result[$scenario] = $row
    }
    for ($index = 3; $index -lt $lines.Count; $index++) {
        $parts = $lines[$index].Split(',')
        if ($parts.Count -ne 2) {
            Add-Check -Name "comparison_csv.key_value_row_$index" -Passed $false -Path $Path -Expected '2 columns' -Actual $parts.Count
            continue
        }
        $value = 0.0
        if (Try-ParseInvariantDouble -Value $parts[1] -Parsed ([ref]$value)) {
            $result[$parts[0]] = $value
        } else {
            Add-Check -Name "comparison_csv.$($parts[0]).numeric" -Passed $false -Path $Path -Expected 'numeric' -Actual $parts[1]
        }
    }
    Add-Check -Name 'comparison_csv.structure' -Passed ($result.Contains('serial') -and $result.Contains('interleaved')) `
        -Path $Path -Expected 'serial and interleaved scenario rows' -Actual @($result.Keys)
    return $result
}

function Write-FinalSummary {
    param([string]$ResolvedInputRoot)

    $requiredFailures = @($script:Checks | Where-Object { $_.severity -eq 'required' -and $_.status -eq 'FAIL' })
    $checkArray = @($script:Checks | ForEach-Object { $_ })
    $status = $(if ($requiredFailures.Count -eq 0) { 'PASS' } else { 'FAIL' })
    $summary = [ordered]@{
        schema = 'vv35-r16-acceptance-summary-v1'
        generated_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        input_root = $ResolvedInputRoot
        overall_status = $status
        required_failure_count = $requiredFailures.Count
        check_count = $script:Checks.Count
        evidence_scope = 'DC mapped-gate synthesis-level power using R13 max-SDF-requested gate-testbench SAIF; retained evidence does not quantify SDF annotation coverage; no placement/route parasitics'
        discovery = $script:Discovery
        scenarios = $script:ScenarioMetrics
        comparison = $script:ComparisonMetrics
        checks = $checkArray
    }
    # This schema needs depth 5. Windows PowerShell 5.1 expands populated
    # adapted-property graphs exponentially at the unnecessary depth of 30.
    $json = $summary | ConvertTo-Json -Depth 5
    $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $outputFullPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($outputFullPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output $json
    if ($status -eq 'PASS') { exit 0 } else { exit 1 }
}

$ResolvedInputRoot = $null
if (Test-Path -LiteralPath $InputRoot -PathType Container) {
    $ResolvedInputRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $InputRoot).Path)
    Add-Check -Name 'input_root.exists' -Passed $true -Path $ResolvedInputRoot -Expected 'directory' -Actual 'directory'
} else {
    Add-Check -Name 'input_root.exists' -Passed $false -Path $InputRoot -Expected 'directory' -Actual 'missing' `
        -Message 'The extracted R16 root has not been downloaded or the supplied path is incorrect.'
    $Discovery.input_root = $InputRoot
    Write-FinalSummary -ResolvedInputRoot $InputRoot
}

$ResultRoot = $null
$BaseRoot = $ResolvedInputRoot
if ((Split-Path -Leaf $ResolvedInputRoot) -ceq 'hdec_vv35_asic_power_only_r16') {
    $ResultRoot = $ResolvedInputRoot
    $BaseRoot = Split-Path -Parent $ResolvedInputRoot
} else {
    $ResultRoot = Find-FirstExistingDirectory -Candidates @(
        (Join-Path $ResolvedInputRoot 'hdec_vv35_asic_power_only_r16'),
        (Join-Path $ResolvedInputRoot 'out\hdec_vv35_asic_power_only_r16')
    )
    if ($null -eq $ResultRoot) {
        $recursive = Get-ChildItem -LiteralPath $ResolvedInputRoot -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ceq 'hdec_vv35_asic_power_only_r16' } | Select-Object -First 1
        if ($null -ne $recursive) {
            $ResultRoot = $recursive.FullName
            $BaseRoot = Split-Path -Parent $ResultRoot
        }
    }
}

$StatusDir = Find-FirstExistingDirectory -Candidates @(
    (Join-Path $BaseRoot 'remote_job_status_r16'),
    (Join-Path $ResolvedInputRoot 'remote_job_status_r16'),
    (Join-Path $ResolvedInputRoot 'out\remote_job_status_r16')
)
$SubmissionDir = Find-FirstExistingDirectory -Candidates @(
    (Join-Path $BaseRoot 'remote_submission_r16'),
    (Join-Path $ResolvedInputRoot 'remote_submission_r16'),
    (Join-Path $ResolvedInputRoot 'out\remote_submission_r16')
)
$FilesManifest = Find-FirstExistingFile -Candidates @(
    (Join-Path $BaseRoot 'vv35_asic_power_only_r16_files.sha256'),
    (Join-Path $ResolvedInputRoot 'vv35_asic_power_only_r16_files.sha256'),
    (Join-Path $ResolvedInputRoot 'out\vv35_asic_power_only_r16_files.sha256')
)

$Discovery.result_root = $ResultRoot
$Discovery.status_dir = $StatusDir
$Discovery.submission_dir = $SubmissionDir
$Discovery.files_manifest = $FilesManifest
Add-Check -Name 'result_root.exists' -Passed ($null -ne $ResultRoot) -Path $ResultRoot -Expected 'hdec_vv35_asic_power_only_r16 directory' -Actual $ResultRoot
Add-Check -Name 'status_dir.exists' -Passed ($null -ne $StatusDir) -Path $StatusDir -Expected 'remote_job_status_r16 directory' -Actual $StatusDir
Add-Check -Name 'submission_dir.exists' -Passed ($null -ne $SubmissionDir) -Path $SubmissionDir -Expected 'remote_submission_r16 directory' -Actual $SubmissionDir

$LauncherStatus = $(if ($null -ne $SubmissionDir) { Join-Path $SubmissionDir 'launcher_status_r16.txt' } else { '' })
$launcher = @{}
if (Test-NonemptyFile -Path $LauncherStatus -Name 'launcher_status.file') {
    $launcher = Read-KeyValueFile -Path $LauncherStatus
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'execution_mode' -Expected 'R13_POWER_ONLY_RECOVERY_NO_VCS' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'scenario_order' -Expected 'SERIAL_THEN_INTERLEAVED' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'saif_consumer' -Expected 'YES' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'vcd_consumer' -Expected 'NO' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'vcd_provenance' -Expected 'R13_MANIFEST_HASH_NOT_LIVE_REHASHED' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'selftest' -Expected 'PASS' -NamePrefix 'launcher' | Out-Null
    Test-KvExact -Map $launcher -Path $LauncherStatus -Key 'submit_status' -Expected 'PASS' -NamePrefix 'launcher' | Out-Null
    $jobIdPassed = $launcher.ContainsKey('lsf_job_id') -and [string]$launcher.lsf_job_id -match '^[0-9]+$'
    Add-Check -Name 'launcher.lsf_job_id' -Passed $jobIdPassed -Path $LauncherStatus -Expected 'numeric' `
        -Actual $(if ($launcher.ContainsKey('lsf_job_id')) { $launcher.lsf_job_id } else { $null })
}

$JobStatus = $(if ($null -ne $StatusDir) { Join-Path $StatusDir 'job_status_r16.txt' } else { '' })
$job = @{}
if (Test-NonemptyFile -Path $JobStatus -Name 'job_status.file') {
    $job = Read-KeyValueFile -Path $JobStatus
    $jobExpected = [ordered]@{
        branch = 'VV35'
        commit = $ExpectedCommit
        execution_mode = 'R13_SYNTH_AND_SDF_SAIF_REUSE_POWER_ONLY_NO_VCS'
        dc_power_evaluation = 'REPORT_POWER_NATIVE_NO_UPDATE_POWER'
        dc_version = 'T-2022.03-SP5-2'
        scenario_order = 'SERIAL_THEN_INTERLEAVED'
        vcs_execution = 'FORBIDDEN'
        saif_consumer = 'YES'
        vcd_consumer = 'NO'
        vcd_provenance = 'R13_MANIFEST_HASH_NOT_LIVE_REHASHED'
        mutation_policy = 'R16_NAMESPACE_ONLY_R13_READ_ONLY'
        r16_payload_hashes = 'PASS'
        saif_parser_selftest = 'PASS'
        isolated_workspace_status = 'PASS'
        r13_reuse_audit = 'PASS'
        serial_power_execution = 'PASS'
        interleaved_power_execution = 'PASS'
        power_output_audit = 'PASS'
        remote_workflow_status = 'PASS'
        workflow_exit_code = '0'
        workflow_status = 'PASS'
        first_error_rc = '0'
        first_error_line = 'NONE'
        first_error_command = 'NONE'
    }
    foreach ($entry in $jobExpected.GetEnumerator()) {
        Test-KvExact -Map $job -Path $JobStatus -Key $entry.Key -Expected ([string]$entry.Value) -NamePrefix 'job_status' | Out-Null
    }
    $jobIdPassed = $job.ContainsKey('lsf_job_id') -and [string]$job.lsf_job_id -match '^[0-9]+$'
    Add-Check -Name 'job_status.lsf_job_id' -Passed $jobIdPassed -Path $JobStatus -Expected 'numeric' `
        -Actual $(if ($job.ContainsKey('lsf_job_id')) { $job.lsf_job_id } else { $null })
    if ($launcher.ContainsKey('lsf_job_id') -and $job.ContainsKey('lsf_job_id')) {
        Add-Check -Name 'submission_job_id.matches_execution_job_id' `
            -Passed ([string]$launcher.lsf_job_id -ceq [string]$job.lsf_job_id) -Path $JobStatus `
            -Expected $launcher.lsf_job_id -Actual $job.lsf_job_id
    }
}

$SummaryPath = $(if ($null -ne $ResultRoot) { Join-Path $ResultRoot 'R16_POWER_ONLY_SUMMARY.txt' } else { '' })
$summaryKv = @{}
if (Test-NonemptyFile -Path $SummaryPath -Name 'r16_summary.file') {
    $summaryKv = Read-KeyValueFile -Path $SummaryPath
    $summaryExpected = [ordered]@{
        r16_power_only_status = 'PASS'
        qualification = 'MAPPED_GATE_SYNTHESIS_LEVEL_DC_POWER_WITH_R13_SDF_GATE_TB_SAIF_NO_PLACEMENT_ROUTE_PARASITICS'
        serial_cycles = '337853'
        interleaved_cycles = '200144'
        vcs_rerun = '0'
        r13_inputs_modified = '0'
    }
    foreach ($entry in $summaryExpected.GetEnumerator()) {
        Test-KvExact -Map $summaryKv -Path $SummaryPath -Key $entry.Key -Expected ([string]$entry.Value) -NamePrefix 'r16_summary' | Out-Null
    }
    Test-KvNumberRange -Map $summaryKv -Path $SummaryPath -Key 'serial_annotation_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix 'r16_summary' | Out-Null
    Test-KvNumberRange -Map $summaryKv -Path $SummaryPath -Key 'interleaved_annotation_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix 'r16_summary' | Out-Null
}

$ReuseAudit = $(if ($null -ne $StatusDir) { Join-Path $StatusDir 'r13_power_input_reuse_audit.txt' } else { '' })
$reuse = @{}
if (Test-NonemptyFile -Path $ReuseAudit -Name 'r13_reuse_audit.file') {
    $reuse = Read-KeyValueFile -Path $ReuseAudit
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'r13_access' -Expected 'READ_ONLY_SYMLINK_INPUTS' -NamePrefix 'r13_reuse' | Out-Null
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'vcs_rerun' -Expected '0' -NamePrefix 'r13_reuse' | Out-Null
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'saif_consumer' -Expected 'YES' -NamePrefix 'r13_reuse' | Out-Null
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'vcd_consumer' -Expected 'NO' -NamePrefix 'r13_reuse' | Out-Null
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'vcd_provenance' -Expected 'R13_MANIFEST_HASH_NOT_LIVE_REHASHED' -NamePrefix 'r13_reuse' | Out-Null
    Test-KvExact -Map $reuse -Path $ReuseAudit -Key 'r13_power_input_reuse_audit' -Expected 'PASS' -NamePrefix 'r13_reuse' | Out-Null
    foreach ($scenarioEntry in $ExpectedScenarios.GetEnumerator()) {
        $name = $scenarioEntry.Key
        Test-KvHash -Map $reuse -Path $ReuseAudit -Key "${name}_gate_manifest_sha256" -NamePrefix 'r13_reuse' | Out-Null
        Test-KvHash -Map $reuse -Path $ReuseAudit -Key "${name}_saif_sha256" -NamePrefix 'r13_reuse' | Out-Null
        Test-KvHash -Map $reuse -Path $ReuseAudit -Key "${name}_vcd_gzip_sha256" -NamePrefix 'r13_reuse' | Out-Null
        Test-KvExact -Map $reuse -Path $ReuseAudit -Key "${name}_cycles" -Expected ([string]$scenarioEntry.Value.cycles) -NamePrefix 'r13_reuse' | Out-Null
        Test-KvExact -Map $reuse -Path $ReuseAudit -Key "${name}_duration_ns" -Expected ([string]$scenarioEntry.Value.duration_ns) -NamePrefix 'r13_reuse' | Out-Null
        Test-KvNumberRange -Map $reuse -Path $ReuseAudit -Key "${name}_tx_total" -Minimum 1.0 -Maximum ([double]::MaxValue) -NamePrefix 'r13_reuse' | Out-Null
    }
}

$ScenarioArtifacts = @{}
foreach ($scenarioEntry in $ExpectedScenarios.GetEnumerator()) {
    $name = $scenarioEntry.Key
    $expected = $scenarioEntry.Value
    $dir = $(if ($null -ne $ResultRoot) {
        Join-Path $ResultRoot "reg_vrf\power_$name"
    } else {
        Join-Path $ResolvedInputRoot "__missing_hdec_vv35_asic_power_only_r16\reg_vrf\power_$name"
    })
    Add-Check -Name "$name.result_directory" -Passed (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath $dir -PathType Container)) `
        -Path $dir -Expected "power_$name directory" -Actual $dir

    $paths = [ordered]@{
        power_report = Join-Path $dir 'power.rpt'
        hierarchy_report = Join-Path $dir 'power_hierarchy.rpt'
        parsed_power = Join-Path $dir 'parsed_power_metrics.txt'
        saif_audit = Join-Path $dir 'saif_annotation_audit.rpt'
        report_saif = Join-Path $dir 'report_saif_hierarchy.rpt'
        read_saif_verbose = Join-Path $dir 'read_saif_verbose.rpt'
        read_saif_status = Join-Path $dir 'read_saif_status.txt'
        power_context = Join-Path $dir 'power_context.txt'
        execution_status = Join-Path $dir 'power_execution_status.rpt'
        run_manifest = Join-Path $dir 'run_manifest.txt'
        dc_log = Join-Path $dir 'dc_power.log'
        area_report = Join-Path $dir 'area.rpt'
        timing_report = Join-Path $dir 'timing.rpt'
    }
    foreach ($pathEntry in $paths.GetEnumerator()) {
        Test-NonemptyFile -Path $pathEntry.Value -Name "$name.file.$($pathEntry.Key)" | Out-Null
    }

    $manifest = Read-KeyValueFile -Path $paths.run_manifest
    $manifestExpected = [ordered]@{
        branch = 'VV35'
        commit = $ExpectedCommit
        scenario = $expected.scenario
        vrf_mode = 'REG_VRF'
        activity_source = 'VCD2SAIF_FROM_SDF_GATE_TB'
        cycles = [string]$expected.cycles
        saif_duration_ns = [string]$expected.duration_ns
        expected_saif_duration_ns = [string]$expected.duration_ns
    }
    foreach ($entry in $manifestExpected.GetEnumerator()) {
        Test-KvExact -Map $manifest -Path $paths.run_manifest -Key $entry.Key -Expected ([string]$entry.Value) -NamePrefix "$name.manifest" | Out-Null
    }
    Test-KvNumberRange -Map $manifest -Path $paths.run_manifest -Key 'saif_annotation_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix "$name.manifest" | Out-Null
    foreach ($hashKey in @(
        'ddc_sha256', 'netlist_sha256', 'sdf_sha256', 'saif_sha256',
        'activity_vcd_gzip_sha256', 'source_gate_manifest_sha256',
        'saif_annotation_audit_sha256', 'power_context_sha256', 'power_report_sha256',
        'contract_sha256', 'vector_manifest_sha256', 'rtl_filelist_sha256',
        'rtl_bundle_sha256', 'gate_testbench_sha256', 'runner_sha256'
    )) {
        Test-KvHash -Map $manifest -Path $paths.run_manifest -Key $hashKey -NamePrefix "$name.manifest" | Out-Null
    }
    Test-ManifestFileHash -Map $manifest -ManifestPath $paths.run_manifest -Key 'power_report_sha256' `
        -TargetPath $paths.power_report -NamePrefix "$name.manifest" | Out-Null
    Test-ManifestFileHash -Map $manifest -ManifestPath $paths.run_manifest -Key 'saif_annotation_audit_sha256' `
        -TargetPath $paths.saif_audit -NamePrefix "$name.manifest" | Out-Null
    Test-ManifestFileHash -Map $manifest -ManifestPath $paths.run_manifest -Key 'power_context_sha256' `
        -TargetPath $paths.power_context -NamePrefix "$name.manifest" | Out-Null

    if ($reuse.Count -gt 0) {
        foreach ($pair in @(
            @('source_gate_manifest_sha256', "${name}_gate_manifest_sha256"),
            @('saif_sha256', "${name}_saif_sha256"),
            @('activity_vcd_gzip_sha256', "${name}_vcd_gzip_sha256")
        )) {
            $left = $(if ($manifest.ContainsKey($pair[0])) { [string]$manifest[$pair[0]] } else { $null })
            $right = $(if ($reuse.ContainsKey($pair[1])) { [string]$reuse[$pair[1]] } else { $null })
            Add-Check -Name "$name.reuse_hash.$($pair[0])" -Passed ($null -ne $left -and $left -ceq $right) `
                -Path $paths.run_manifest -Expected $right -Actual $left
        }
    }

    $readStatus = Read-KeyValueFile -Path $paths.read_saif_status
    Test-KvExact -Map $readStatus -Path $paths.read_saif_status -Key 'status' -Expected '0' -NamePrefix "$name.read_saif" | Out-Null
    $instancePresent = $readStatus.ContainsKey('instance_name') -and -not [string]::IsNullOrWhiteSpace([string]$readStatus.instance_name)
    Add-Check -Name "$name.read_saif.instance_name" -Passed $instancePresent -Path $paths.read_saif_status `
        -Expected 'nonempty' -Actual $(if ($readStatus.ContainsKey('instance_name')) { $readStatus.instance_name } else { $null })

    $saifAudit = Read-KeyValueFile -Path $paths.saif_audit
    foreach ($entry in ([ordered]@{
        report_saif_hierarchy = 'PASS'
        report_saif_table_parser_rc = '0'
        table_status = 'PASS'
        report_saif_table_status = 'PASS'
        audit_status = 'PASS'
    }).GetEnumerator()) {
        Test-KvExact -Map $saifAudit -Path $paths.saif_audit -Key $entry.Key -Expected $entry.Value -NamePrefix "$name.saif_audit" | Out-Null
    }
    foreach ($coverageKey in @('user_annotated_min_percent', 'report_saif_user_annotated_min_percent', 'annotation_coverage_percent')) {
        Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key $coverageKey `
            -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix "$name.saif_audit" | Out-Null
    }
    foreach ($zeroKey in @('default_activity_max_percent', 'propagated_activity_max_percent',
            'report_saif_default_activity_max_percent', 'report_saif_propagated_activity_max_percent')) {
        Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key $zeroKey -Minimum 0.0 -Maximum 0.0 -NamePrefix "$name.saif_audit" | Out-Null
    }
    Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key 'minimum_annotation_coverage_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum $ExpectedMinimumAnnotationPercent -NamePrefix "$name.saif_audit" | Out-Null
    foreach ($object in @('nets', 'ports', 'pins')) {
        Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key "${object}_user_count" `
            -Minimum 1.0 -Maximum ([double]::MaxValue) -NamePrefix "$name.saif_audit" | Out-Null
        Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key "${object}_user_percent" `
            -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix "$name.saif_audit" | Out-Null
        foreach ($suffix in @('default_count', 'default_percent', 'propagated_count', 'propagated_percent')) {
            Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key "${object}_$suffix" `
                -Minimum 0.0 -Maximum 0.0 -NamePrefix "$name.saif_audit" | Out-Null
        }
        Test-KvNumberRange -Map $saifAudit -Path $paths.saif_audit -Key "${object}_total" `
            -Minimum 1.0 -Maximum ([double]::MaxValue) -NamePrefix "$name.saif_audit" | Out-Null
        $userCount = 0.0
        $totalCount = 0.0
        $countNumeric = $saifAudit.ContainsKey("${object}_user_count") -and $saifAudit.ContainsKey("${object}_total") -and `
            (Try-ParseInvariantDouble -Value $saifAudit["${object}_user_count"] -Parsed ([ref]$userCount)) -and `
            (Try-ParseInvariantDouble -Value $saifAudit["${object}_total"] -Parsed ([ref]$totalCount))
        Add-Check -Name "$name.saif_audit.${object}_user_count_equals_total" `
            -Passed ($countNumeric -and $userCount -eq $totalCount) -Path $paths.saif_audit `
            -Expected $totalCount -Actual $userCount
    }

    $context = Read-KeyValueFile -Path $paths.power_context
    foreach ($entry in ([ordered]@{
        expected_saif_duration_ns = [string]$expected.duration_ns
        scenario = $expected.scenario
        vrf_mode = 'REG_VRF'
        qualification = 'PRE_LAYOUT_COMPLETE_REGISTER_VRF'
        saif_structural_coverage_requires_review = 'false'
        saif_report_table_objects = 'Nets,Ports,Pins'
    }).GetEnumerator()) {
        Test-KvExact -Map $context -Path $paths.power_context -Key $entry.Key -Expected $entry.Value -NamePrefix "$name.power_context" | Out-Null
    }
    Test-KvNumberRange -Map $context -Path $paths.power_context -Key 'saif_annotation_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum 100.0 -NamePrefix "$name.power_context" | Out-Null
    Test-KvNumberRange -Map $context -Path $paths.power_context -Key 'saif_annotation_minimum_percent' `
        -Minimum $ExpectedMinimumAnnotationPercent -Maximum $ExpectedMinimumAnnotationPercent -NamePrefix "$name.power_context" | Out-Null
    foreach ($zeroKey in @('saif_default_activity_percent', 'saif_propagated_activity_percent')) {
        Test-KvNumberRange -Map $context -Path $paths.power_context -Key $zeroKey -Minimum 0.0 -Maximum 0.0 -NamePrefix "$name.power_context" | Out-Null
    }
    if ($context.ContainsKey('saif_annotation_percent') -and $manifest.ContainsKey('saif_annotation_percent')) {
        $contextCoverage = 0.0
        $manifestCoverage = 0.0
        $coverageNumeric = (Try-ParseInvariantDouble -Value $context.saif_annotation_percent -Parsed ([ref]$contextCoverage)) -and `
            (Try-ParseInvariantDouble -Value $manifest.saif_annotation_percent -Parsed ([ref]$manifestCoverage))
        Add-Check -Name "$name.annotation.context_matches_manifest" `
            -Passed ($coverageNumeric -and (Test-NearlyEqual -Left $contextCoverage -Right $manifestCoverage)) `
            -Path $paths.power_context -Expected $manifestCoverage -Actual $contextCoverage
    }
    if ($readStatus.ContainsKey('instance_name') -and $manifest.ContainsKey('saif_instance_path')) {
        Add-Check -Name "$name.read_saif.instance_matches_manifest" `
            -Passed ([string]$readStatus.instance_name -ceq [string]$manifest.saif_instance_path) `
            -Path $paths.read_saif_status -Expected $manifest.saif_instance_path -Actual $readStatus.instance_name
    }

    $execution = Read-KeyValueFile -Path $paths.execution_status
    Test-KvExact -Map $execution -Path $paths.execution_status -Key 'audit_status' -Expected 'PASS' -NamePrefix "$name.power_execution" | Out-Null
    Test-KvExact -Map $execution -Path $paths.execution_status -Key 'required_power_report' -Expected 'power.rpt' -NamePrefix "$name.power_execution" | Out-Null
    Test-KvExact -Map $execution -Path $paths.execution_status -Key 'required_hierarchy_report' -Expected 'power_hierarchy.rpt' -NamePrefix "$name.power_execution" | Out-Null
    Test-KvExact -Map $execution -Path $paths.execution_status -Key 'activity_source' -Expected 'READ_SAIF_FROM_SDF_GATE_VCD' -NamePrefix "$name.power_execution" | Out-Null

    if (Test-Path -LiteralPath $paths.dc_log -PathType Leaf) {
        $logText = Get-Content -LiteralPath $paths.dc_log -Raw
        $runtimeErrors = [regex]::Matches($logText, '(?im)^\s*(Error|Fatal)(:|-|$)')
        $updatePowerError = $logText -match '(?im)^\s*(?:Error|Fatal)(?::|-).*?(?:CMD-005|unknown\s+command\s+[''\"]?update_power)\b'
        Add-Check -Name "$name.dc_log.runtime_errors" -Passed ($runtimeErrors.Count -eq 0) -Path $paths.dc_log `
            -Expected 0 -Actual $runtimeErrors.Count
        Add-Check -Name "$name.dc_log.update_power_compatibility" -Passed (-not $updatePowerError) -Path $paths.dc_log `
            -Expected 'no CMD-005 or unknown update_power diagnostic' -Actual $(if ($updatePowerError) { 'found' } else { 'not found' })
    }

    if (Test-Path -LiteralPath $paths.hierarchy_report -PathType Leaf) {
        $hierarchyText = Get-Content -LiteralPath $paths.hierarchy_report -Raw
        $hierarchyHeader = $hierarchyText -match '(?im)^\s*Report\s*:\s*power\s*$'
        Add-Check -Name "$name.power_hierarchy.header" -Passed $hierarchyHeader -Path $paths.hierarchy_report `
            -Expected 'Report : power' -Actual $(if ($hierarchyHeader) { 'present' } else { 'absent' })
    }

    $power = Parse-PowerReport -Path $paths.power_report -Scenario $name
    $parsedPowerKv = Read-KeyValueFile -Path $paths.parsed_power
    foreach ($metricName in @('internal_power_mw', 'switching_power_mw', 'leakage_power_mw', 'dynamic_power_mw', 'total_power_mw')) {
        $reported = $(if ($power.Contains($metricName)) { [double]$power[$metricName] } else { $null })
        $parsed = 0.0
        $parsedOk = $parsedPowerKv.ContainsKey($metricName) -and (Try-ParseInvariantDouble -Value $parsedPowerKv[$metricName] -Parsed ([ref]$parsed))
        $passed = $null -ne $reported -and $parsedOk -and (Test-NearlyEqual -Left $reported -Right $parsed -RelativeTolerance 1.0e-9 -AbsoluteTolerance 1.0e-9)
        Add-Check -Name "$name.parsed_power.$metricName" -Passed $passed -Path $paths.parsed_power -Expected $reported `
            -Actual $(if ($parsedOk) { $parsed } else { $null })
    }

    $area = Parse-AreaReport -Path $paths.area_report -Scenario $name
    $timing = Parse-TimingReport -Path $paths.timing_report -Scenario $name
    $timeSeconds = [double]$expected.cycles / $ExpectedFrequencyHz
    if ($power.Contains('total_power_mw')) {
        $power.total_energy_mj = [double]$power.total_power_mw * $timeSeconds
    }
    if ($power.Contains('dynamic_power_mw')) {
        $power.dynamic_energy_mj = [double]$power.dynamic_power_mw * $timeSeconds
    }
    $ScenarioMetrics[$name] = [ordered]@{
        scenario = $expected.scenario
        cycles = $expected.cycles
        duration_ns = $expected.duration_ns
        time_s = $timeSeconds
        power = $power
        area = $area
        timing = $timing
        saif_annotation_percent = $(if ($context.ContainsKey('saif_annotation_percent')) { $context.saif_annotation_percent } else { $null })
    }
    $ScenarioArtifacts[$name] = [ordered]@{ manifest = $manifest; paths = $paths }
}

if ($ScenarioArtifacts.ContainsKey('serial') -and $ScenarioArtifacts.ContainsKey('interleaved')) {
    $serialManifest = $ScenarioArtifacts.serial.manifest
    $interleavedManifest = $ScenarioArtifacts.interleaved.manifest
    foreach ($key in @('ddc_sha256', 'netlist_sha256', 'sdf_sha256', 'contract_sha256', 'vector_manifest_sha256',
            'rtl_filelist_sha256', 'rtl_bundle_sha256', 'gate_testbench_sha256')) {
        $left = $(if ($serialManifest.ContainsKey($key)) { [string]$serialManifest[$key] } else { $null })
        $right = $(if ($interleavedManifest.ContainsKey($key)) { [string]$interleavedManifest[$key] } else { $null })
        Add-Check -Name "paired_manifest.shared_$key" -Passed ($null -ne $left -and $left -ceq $right) `
            -Expected $left -Actual $right
    }

    $serialArea = $ScenarioMetrics.serial.area
    $interleavedArea = $ScenarioMetrics.interleaved.area
    foreach ($key in @('number_of_cells', 'number_of_combinational_cells', 'number_of_sequential_cells',
            'combinational_area', 'noncombinational_area', 'total_cell_area')) {
        $leftPresent = $serialArea.Contains($key)
        $rightPresent = $interleavedArea.Contains($key)
        $passed = $leftPresent -and $rightPresent
        if ($passed) {
            $passed = Test-NearlyEqual -Left ([double]$serialArea[$key]) -Right ([double]$interleavedArea[$key]) `
                -RelativeTolerance 1.0e-9 -AbsoluteTolerance 1.0e-9
        }
        Add-Check -Name "paired_area.$key" -Passed $passed -Expected $(if ($leftPresent) { $serialArea[$key] } else { $null }) `
            -Actual $(if ($rightPresent) { $interleavedArea[$key] } else { $null }) `
            -Message 'SERIAL and INTERLEAVED use the same mapped DDC and must report identical area metrics.'
    }

    $serialTiming = $ScenarioMetrics.serial.timing
    $interleavedTiming = $ScenarioMetrics.interleaved.timing
    $timingPresent = $serialTiming.Contains('worst_setup_slack_ns') -and $interleavedTiming.Contains('worst_setup_slack_ns')
    $timingEqual = $timingPresent -and (Test-NearlyEqual -Left ([double]$serialTiming.worst_setup_slack_ns) `
        -Right ([double]$interleavedTiming.worst_setup_slack_ns) -RelativeTolerance 1.0e-9 -AbsoluteTolerance 1.0e-9)
    Add-Check -Name 'paired_timing.worst_setup_slack_ns' -Passed $timingEqual `
        -Expected $(if ($serialTiming.Contains('worst_setup_slack_ns')) { $serialTiming.worst_setup_slack_ns } else { $null }) `
        -Actual $(if ($interleavedTiming.Contains('worst_setup_slack_ns')) { $interleavedTiming.worst_setup_slack_ns } else { $null }) `
        -Message 'SERIAL and INTERLEAVED use the same mapped DDC and must report identical timing.'
    $pathCountEqual = $serialTiming.Contains('path_count') -and $interleavedTiming.Contains('path_count') -and `
        [int]$serialTiming.path_count -eq [int]$interleavedTiming.path_count
    Add-Check -Name 'paired_timing.path_count' -Passed $pathCountEqual `
        -Expected $(if ($serialTiming.Contains('path_count')) { $serialTiming.path_count } else { $null }) `
        -Actual $(if ($interleavedTiming.Contains('path_count')) { $interleavedTiming.path_count } else { $null })
}

$ComparisonPath = $(if ($null -ne $ResultRoot) { Join-Path $ResultRoot 'VV35_ASIC_POWER_ONLY_R16_COMPARISON.csv' } else { '' })
if (Test-NonemptyFile -Path $ComparisonPath -Name 'comparison_csv.file') {
    $ComparisonMetrics = Parse-ComparisonCsv -Path $ComparisonPath
    foreach ($scenarioEntry in $ExpectedScenarios.GetEnumerator()) {
        $name = $scenarioEntry.Key
        if (-not $ComparisonMetrics.Contains($name) -or -not $ScenarioMetrics.Contains($name)) { continue }
        $row = $ComparisonMetrics[$name]
        $computed = $ScenarioMetrics[$name]
        $expectedValues = [ordered]@{
            total_power_mw = $(if ($computed.power.Contains('total_power_mw')) { $computed.power.total_power_mw } else { $null })
            dynamic_power_mw = $(if ($computed.power.Contains('dynamic_power_mw')) { $computed.power.dynamic_power_mw } else { $null })
            cycles = [double]$computed.cycles
            time_s = [double]$computed.time_s
            total_energy_mj = $(if ($computed.power.Contains('total_energy_mj')) { $computed.power.total_energy_mj } else { $null })
            dynamic_energy_mj = $(if ($computed.power.Contains('dynamic_energy_mj')) { $computed.power.dynamic_energy_mj } else { $null })
        }
        foreach ($entry in $expectedValues.GetEnumerator()) {
            $actualPresent = $row.Contains($entry.Key)
            $passed = $null -ne $entry.Value -and $actualPresent -and (Test-NearlyEqual -Left ([double]$entry.Value) `
                -Right ([double]$row[$entry.Key]) -RelativeTolerance 1.0e-8 -AbsoluteTolerance 1.0e-12)
            Add-Check -Name "comparison_csv.$name.$($entry.Key)" -Passed $passed -Path $ComparisonPath `
                -Expected $entry.Value -Actual $(if ($actualPresent) { $row[$entry.Key] } else { $null })
        }
    }

    $serialCycles = [double]$ExpectedScenarios.serial.cycles
    $interleavedCycles = [double]$ExpectedScenarios.interleaved.cycles
    $derived = [ordered]@{
        cycle_reduction_percent = 100.0 * ($serialCycles - $interleavedCycles) / $serialCycles
        speedup = $serialCycles / $interleavedCycles
    }
    if ($ScenarioMetrics.Contains('serial') -and $ScenarioMetrics.Contains('interleaved') -and
        $ScenarioMetrics.serial.power.Contains('total_energy_mj') -and $ScenarioMetrics.interleaved.power.Contains('total_energy_mj')) {
        $derived.total_energy_reduction_percent = 100.0 * `
            ([double]$ScenarioMetrics.serial.power.total_energy_mj - [double]$ScenarioMetrics.interleaved.power.total_energy_mj) / `
            [double]$ScenarioMetrics.serial.power.total_energy_mj
    }
    if ($ScenarioMetrics.Contains('serial') -and $ScenarioMetrics.Contains('interleaved') -and
        $ScenarioMetrics.serial.power.Contains('dynamic_energy_mj') -and $ScenarioMetrics.interleaved.power.Contains('dynamic_energy_mj')) {
        $derived.dynamic_energy_reduction_percent = 100.0 * `
            ([double]$ScenarioMetrics.serial.power.dynamic_energy_mj - [double]$ScenarioMetrics.interleaved.power.dynamic_energy_mj) / `
            [double]$ScenarioMetrics.serial.power.dynamic_energy_mj
    }
    foreach ($entry in $derived.GetEnumerator()) {
        $present = $ComparisonMetrics.Contains($entry.Key)
        $passed = $present -and (Test-NearlyEqual -Left ([double]$entry.Value) -Right ([double]$ComparisonMetrics[$entry.Key]) `
            -RelativeTolerance 1.0e-8 -AbsoluteTolerance 1.0e-6)
        Add-Check -Name "comparison_csv.derived.$($entry.Key)" -Passed $passed -Path $ComparisonPath `
            -Expected $entry.Value -Actual $(if ($present) { $ComparisonMetrics[$entry.Key] } else { $null })
    }
}

if ($null -eq $ArchiveStatusPath -or [string]::IsNullOrWhiteSpace($ArchiveStatusPath)) {
    $ArchiveStatusPath = Find-FirstExistingFile -Candidates @(
        $(if ($null -ne $StatusDir) { Join-Path $StatusDir 'archive_status_r16.txt' } else { '' }),
        (Join-Path $ResolvedInputRoot 'archive_status_r16.txt')
    )
}
$archiveStatusKv = @{}
if (Test-NonemptyFile -Path $ArchiveStatusPath -Name 'archive_status.file') {
    $archiveStatusKv = Read-KeyValueFile -Path $ArchiveStatusPath
    Test-KvExact -Map $archiveStatusKv -Path $ArchiveStatusPath -Key 'archive_status' -Expected 'PASS' -NamePrefix 'archive_status' | Out-Null
    Test-KvExact -Map $archiveStatusKv -Path $ArchiveStatusPath -Key 'final_exit_code' -Expected '0' -NamePrefix 'archive_status' | Out-Null
    Test-KvHash -Map $archiveStatusKv -Path $ArchiveStatusPath -Key 'archive_sha256' -NamePrefix 'archive_status' | Out-Null
}

if ($null -eq $ArchivePath -or [string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Find-FirstExistingFile -Candidates @(
        (Join-Path $ResolvedInputRoot 'vv35_asic_power_only_r16.tar.gz'),
        (Join-Path (Split-Path -Parent $ResolvedInputRoot) 'vv35_asic_power_only_r16.tar.gz'),
        (Join-Path $BaseRoot 'vv35_asic_power_only_r16.tar.gz')
    )
}
if ($null -eq $ArchiveHashPath -or [string]::IsNullOrWhiteSpace($ArchiveHashPath)) {
    $ArchiveHashPath = Find-FirstExistingFile -Candidates @(
        (Join-Path $ResolvedInputRoot 'vv35_asic_power_only_r16.sha256'),
        (Join-Path (Split-Path -Parent $ResolvedInputRoot) 'vv35_asic_power_only_r16.sha256'),
        (Join-Path $BaseRoot 'vv35_asic_power_only_r16.sha256')
    )
}
$Discovery.archive_path = $ArchivePath
$Discovery.archive_hash_path = $ArchiveHashPath
$Discovery.archive_status_path = $ArchiveStatusPath
$archiveExists = Test-NonemptyFile -Path $ArchivePath -Name 'archive.container'
$archiveHashExists = Test-NonemptyFile -Path $ArchiveHashPath -Name 'archive.sha256_file'
if ($archiveExists -and $archiveHashExists) {
    $actualArchiveHash = Get-Sha256 -Path $ArchivePath
    $hashLine = (Get-Content -LiteralPath $ArchiveHashPath | Select-Object -First 1)
    $declaredArchiveHash = $(if ($hashLine -match '^([0-9a-fA-F]{64})\b') { $matches[1].ToLowerInvariant() } else { $null })
    Add-Check -Name 'archive.sha256_file_match' -Passed ($null -ne $declaredArchiveHash -and $declaredArchiveHash -ceq $actualArchiveHash) `
        -Path $ArchivePath -Expected $declaredArchiveHash -Actual $actualArchiveHash
    if ($archiveStatusKv.ContainsKey('archive_sha256')) {
        Add-Check -Name 'archive.status_hash_match' -Passed ([string]$archiveStatusKv.archive_sha256 -ceq $actualArchiveHash) `
            -Path $ArchivePath -Expected $archiveStatusKv.archive_sha256 -Actual $actualArchiveHash
    }
}

$filesManifestExists = Test-NonemptyFile -Path $FilesManifest -Name 'files_manifest.file'
if ($filesManifestExists) {
    $manifestBase = Split-Path -Parent $FilesManifest
    $entries = 0
    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $FilesManifest) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            [void]$mismatches.Add("malformed line: $line")
            continue
        }
        $expectedHash = $matches[1].ToLowerInvariant()
        $relative = $matches[2].Trim() -replace '/', [System.IO.Path]::DirectorySeparatorChar
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            [void]$mismatches.Add("unsafe path: $relative")
            continue
        }
        $target = Join-Path $manifestBase $relative
        $entries++
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            [void]$mismatches.Add("missing: $relative")
            continue
        }
        $actualHash = Get-Sha256 -Path $target
        if ($actualHash -cne $expectedHash) {
            [void]$mismatches.Add("hash mismatch: $relative")
        }
    }
    Add-Check -Name 'files_manifest.all_files_match' -Passed ($entries -gt 0 -and $mismatches.Count -eq 0) `
        -Path $FilesManifest -Expected 'all listed files present with matching SHA-256' `
        -Actual ([ordered]@{ entries_checked = $entries; mismatch_count = $mismatches.Count; first_mismatches = @($mismatches | Select-Object -First 20) })
}

Write-FinalSummary -ResolvedInputRoot $ResolvedInputRoot
