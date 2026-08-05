param(
    [string]$RepoRoot = "E:\HDEC\cva6-vhdc-core\tmp\hdec_vv35_ecc_area_worktree",
    [string]$OutRoot,
    [string]$Top = "hdec_top",
    [double]$PeriodNs = 5.0,
    [string]$RunLabel = "vv35_ecc_area_full",
    [string]$VivadoBin = "E:\Vivado\Vivado\2024.2\bin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-FileRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $item = Get-Item -LiteralPath $resolved
    $hash = Get-FileHash -LiteralPath $resolved -Algorithm SHA256
    [pscustomobject]@{
        path = $resolved
        bytes = [int64]$item.Length
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

function Get-StringSha256 {
    param([AllowEmptyString()][string]$Text)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $digest = $sha256.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($digest)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return ($output -join "`n").Trim()
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$vivado = Join-Path $VivadoBin "vivado.bat"
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado launcher not found: $vivado"
}

$scriptDir = Join-Path $repo "scripts\hdec\vv35_eval\area"
$tclScript = Join-Path $scriptDir "vv35_ecc_area_impl.tcl"
$rtlManifest = Join-Path $scriptDir "vv35_area_rtl_files.txt"
foreach ($requiredPath in @($tclScript, $rtlManifest)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required flow file not found: $requiredPath"
    }
}

if ($Top -notmatch '^[A-Za-z_][A-Za-z0-9_$]*$') {
    throw "Invalid SystemVerilog top-module name: $Top"
}
if ($RunLabel -notmatch '^[A-Za-z0-9_.-]+$') {
    throw "RunLabel may contain only letters, numbers, underscore, dot, and hyphen"
}
if ($PeriodNs -le 0.0) {
    throw "PeriodNs must be positive"
}

if ([string]::IsNullOrWhiteSpace($OutRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutRoot = Join-Path $repo "reports\hdec\vv35_ecc_area_full_$stamp"
}
$out = [System.IO.Path]::GetFullPath($OutRoot)
if (Test-Path -LiteralPath $out) {
    $existing = Get-ChildItem -LiteralPath $out -Force | Select-Object -First 1
    if ($null -ne $existing) {
        throw "Output directory is not empty; choose a new OutRoot: $out"
    }
}
else {
    New-Item -ItemType Directory -Path $out -Force | Out-Null
}

$versionOutput = & $vivado -version 2>&1
$versionText = ($versionOutput -join "`n").Trim()
if ($versionText -notmatch 'v2024\.2') {
    throw "Vivado 2024.2 is required; detected: $versionText"
}

$manifestLines = Get-Content -LiteralPath $rtlManifest
$rtlPaths = foreach ($rawLine in $manifestLines) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith("#")) {
        continue
    }
    $path = [System.IO.Path]::GetFullPath((Join-Path $repo $line))
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required RTL source not found: $path"
    }
    $path
}
if (@($rtlPaths).Count -eq 0) {
    throw "RTL manifest contains no source files: $rtlManifest"
}

$runnerPath = $MyInvocation.MyCommand.Path
$inputPaths = @($rtlPaths) + @($tclScript, $rtlManifest, $runnerPath)
$inputBefore = @($inputPaths | ForEach-Object { Get-FileRecord -Path $_ })
$inputHashCsv = Join-Path $out "input_hashes_before.csv"
$inputBefore | Export-Csv -LiteralPath $inputHashCsv -NoTypeInformation -Encoding UTF8

$gitHeadBefore = Get-GitText -Repository $repo -Arguments @("rev-parse", "HEAD")
$gitStatusBefore = Get-GitText -Repository $repo -Arguments @("status", "--porcelain=v1")
$periodText = $PeriodNs.ToString("0.############", [System.Globalization.CultureInfo]::InvariantCulture)
$startUtc = [DateTime]::UtcNow

$runConfig = [ordered]@{
    schema = "vv35-ecc-area-run-config-v1"
    start_utc = $startUtc.ToString("o")
    repo_root = $repo
    git_head = $gitHeadBefore
    git_status_sha256 = Get-StringSha256 -Text $gitStatusBefore
    vivado_launcher = $vivado
    vivado_version = $versionText
    part = "xc7z020clg400-2"
    top = $Top
    configuration = "FULL"
    parameter_overrides = @()
    period_ns = $PeriodNs
    run_label = $RunLabel
    input_hash_file = $inputHashCsv
}
$runConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out "run_config.json") -Encoding UTF8

$log = Join-Path $out "vivado_impl.log"
$journal = Join-Path $out "vivado_impl.jou"
$vivadoExitCode = -1
$failureMessage = $null

try {
    & $vivado -mode batch -notrace -log $log -journal $journal `
        -source $tclScript -tclargs $repo $out $Top $periodText $RunLabel
    $vivadoExitCode = $LASTEXITCODE
    if ($vivadoExitCode -ne 0) {
        throw "Vivado implementation failed with exit code $vivadoExitCode. See $log"
    }
}
catch {
    $failureMessage = $_.Exception.Message
}

$endUtc = [DateTime]::UtcNow
$gitHeadAfter = Get-GitText -Repository $repo -Arguments @("rev-parse", "HEAD")
$gitStatusAfter = Get-GitText -Repository $repo -Arguments @("status", "--porcelain=v1")
$inputAfter = @($inputPaths | ForEach-Object { Get-FileRecord -Path $_ })
$inputAfter | Export-Csv -LiteralPath (Join-Path $out "input_hashes_after.csv") -NoTypeInformation -Encoding UTF8

$beforeByPath = @{}
foreach ($record in $inputBefore) {
    $beforeByPath[$record.path] = $record.sha256
}
$changedInputs = @($inputAfter | Where-Object {
    (-not $beforeByPath.ContainsKey($_.path)) -or ($beforeByPath[$_.path] -ne $_.sha256)
} | ForEach-Object { $_.path })

if ($gitHeadBefore -ne $gitHeadAfter) {
    $failureMessage = "Repository HEAD changed during the run: $gitHeadBefore -> $gitHeadAfter"
}
elseif ($changedInputs.Count -ne 0) {
    $failureMessage = "One or more hashed flow inputs changed during the run"
}

$artifactFiles = @(Get-ChildItem -LiteralPath $out -Recurse -File | Where-Object {
    $_.Name -ne "run_manifest.json" -and $_.Name -ne "artifact_hashes.csv"
})
$artifactRecords = @($artifactFiles | ForEach-Object { Get-FileRecord -Path $_.FullName })
$artifactHashCsv = Join-Path $out "artifact_hashes.csv"
$artifactRecords | Export-Csv -LiteralPath $artifactHashCsv -NoTypeInformation -Encoding UTF8

$summaryPath = Join-Path $out "reports\run_summary.txt"
if ($null -eq $failureMessage -and -not (Test-Path -LiteralPath $summaryPath)) {
    $failureMessage = "Implementation completed without reports/run_summary.txt"
}

$runManifest = [ordered]@{
    schema = "vv35-ecc-area-run-manifest-v1"
    status = if ($null -eq $failureMessage) { "PASS" } else { "FAIL" }
    failure = $failureMessage
    start_utc = $startUtc.ToString("o")
    end_utc = $endUtc.ToString("o")
    elapsed_seconds = [math]::Round(($endUtc - $startUtc).TotalSeconds, 3)
    vivado_exit_code = $vivadoExitCode
    repo_root = $repo
    git_head_before = $gitHeadBefore
    git_head_after = $gitHeadAfter
    git_status_before = $gitStatusBefore
    git_status_after = $gitStatusAfter
    git_status_before_sha256 = Get-StringSha256 -Text $gitStatusBefore
    git_status_after_sha256 = Get-StringSha256 -Text $gitStatusAfter
    part = "xc7z020clg400-2"
    top = $Top
    configuration = "FULL"
    parameter_overrides = @()
    period_ns = $PeriodNs
    run_label = $RunLabel
    input_hashes_before = $inputBefore
    input_hashes_after = $inputAfter
    changed_inputs = $changedInputs
    artifact_hash_file = $artifactHashCsv
}
$runManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out "run_manifest.json") -Encoding UTF8

if ($null -ne $failureMessage) {
    throw "$failureMessage. Run manifest: $(Join-Path $out 'run_manifest.json')"
}

Get-Content -LiteralPath $summaryPath
Write-Host "VV35 ECC-area FULL output: $out"
Write-Host "Run manifest: $(Join-Path $out 'run_manifest.json')"
