param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string]$Label
)

$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path -LiteralPath $Repo).Path
$outPath = $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

$tmpRoot = Join-Path $repoPath 'tmp\vivado_sandbox'
$env:HOME = Join-Path $tmpRoot 'home'
$env:USERPROFILE = $env:HOME
$env:APPDATA = Join-Path $tmpRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $tmpRoot 'localappdata'
$env:TEMP = Join-Path $tmpRoot 'temp'
$env:TMP = $env:TEMP
$env:XILINX_LOCAL_USER_DATA = Join-Path $tmpRoot 'xilinx_local_user_data'
New-Item -ItemType Directory -Force -Path $env:HOME,$env:APPDATA,$env:LOCALAPPDATA,$env:TEMP,$env:XILINX_LOCAL_USER_DATA | Out-Null

$vivado = $env:HDEC_VIVADO_2024_2
if ([string]::IsNullOrWhiteSpace($vivado)) {
    $vivado = 'D:\vivado2024.2\Vivado\2024.2\bin\vivado.bat'
}
if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado 2024.2 was not found at '$vivado'. Set HDEC_VIVADO_2024_2 to override."
}
& $vivado -mode batch -nolog -nojournal -notrace -source (Join-Path $repoPath 'scripts\hdec\ooc_hdec_timing_atlas.tcl') -tclargs $repoPath $outPath 5.000 $Label

$summaryPath = Join-Path $outPath 'reports\run_summary.txt'
$utilPath = Join-Path $outPath 'reports\utilization.rpt'
$summary = @{}
Get-Content $summaryPath | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $summary[$matches[1]] = $matches[2]
    }
}

$lut = $logic = $lutram = $ff = $bram = $dsp = $carry4 = ''
foreach ($line in Get-Content $utilPath) {
    if ($line -match '^\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)') { $lut = $matches[1] }
    elseif ($line -match '^\|\s*LUT as Logic\s*\|\s*([0-9]+)') { $logic = $matches[1] }
    elseif ($line -match '^\|\s*LUT as Memory\s*\|\s*([0-9]+)') { $lutram = $matches[1] }
    elseif ($line -match '^\|\s*Slice Registers\s*\|\s*([0-9]+)') { $ff = $matches[1] }
    elseif ($line -match '^\|\s*Block RAM Tile\s*\|\s*([0-9.]+)') { $bram = $matches[1] }
    elseif ($line -match '^\|\s*DSPs\s*\|\s*([0-9]+)') { $dsp = $matches[1] }
    elseif ($line -match '^\|\s*CARRY4\s*\|\s*([0-9]+)') { $carry4 = $matches[1] }
}

[pscustomobject]@{
    Label = $Label
    WNS = $summary['wns']
    FmaxMHz = $summary['fmax_est_mhz']
    LUT = $lut
    LogicLUT = $logic
    LUTRAM = $lutram
    FF = $ff
    BRAM = $bram
    DSP = $dsp
    CARRY4 = $carry4
    WorstEndpoint = $summary['top_endpoint']
    OutDir = $outPath
} | ConvertTo-Json -Compress
