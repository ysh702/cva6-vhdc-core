[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..\..")).Path
$python = "C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
if (-not (Test-Path -LiteralPath $python)) { $python = "python" }

& $python (Join-Path $scriptDir "validate_vv35_lab_assets.py")
if ($LASTEXITCODE -ne 0) { throw "VV35 laboratory asset validation failed" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = "E:\HDEC\lab_bundles\vv35_$stamp"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$include = @(
    "docs\hdec\vv35_lab_measurement_handoff.md",
    "verif\hdec\vv35_eval\common",
    "verif\hdec\vv35_eval\board",
    "verif\hdec\vv35_eval\asic",
    "verif\hdec\vv35_eval\gate\tb_vv35_schedule_gate.sv",
    "scripts\hdec\vv35_eval\board",
    "scripts\hdec\vv35_eval\asic",
    "scripts\hdec\vv35_eval\validate_vv35_lab_assets.py"
)

$stage = Join-Path $OutputDirectory "stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($relative in $include) {
    $source = Join-Path $repoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing bundle source $source" }
    $destination = Join-Path $stage $relative
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    if (Test-Path -LiteralPath $source -PathType Container) {
        Copy-Item -LiteralPath $source -Destination $parent -Recurse -Force
    } else {
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
}

Get-ChildItem -LiteralPath $stage -Recurse -Directory -Filter "__pycache__" |
    ForEach-Object {
        if (-not $_.FullName.StartsWith($stage, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove cache path outside staging directory: $($_.FullName)"
        }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }

$manifest = Join-Path $OutputDirectory "bundle_manifest.sha256"
Get-ChildItem -LiteralPath $stage -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
        "$hash  $relative"
    } | Set-Content -LiteralPath $manifest -Encoding ascii

$zip = Join-Path $OutputDirectory "vv35_lab_bundle_$stamp.zip"
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
if (-not $stage.StartsWith($OutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove staging path outside output directory: $stage"
}
Remove-Item -LiteralPath $stage -Recurse -Force

$context = [ordered]@{
    branch = (& git -C $repoRoot branch --show-current).Trim()
    commit = (& git -C $repoRoot rev-parse HEAD).Trim()
    zip = $zip
    zip_sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    manifest = $manifest
}
$context | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory "bundle_context.json") -Encoding utf8
$context | ConvertTo-Json
