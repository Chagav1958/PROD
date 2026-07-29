param(
    [string]$MisRoot = "C:\SRC125\gold",
    [string]$OutRoot = "C:\AIS\AI\AIS\PB",
    [string]$PbldumpExe = "",
    [string]$PbtName = "gold",
    [string]$PbtPath = "",
    [string]$LogDir = "",
    [switch]$CleanArtifactsOnly
)
$scriptPath = Split-Path $PSCommandPath -Parent
$projectRoot = Split-Path $scriptPath -Parent
$realScript = Join-Path $projectRoot "scripts\AIS_export.ps1"
$params = @{}
if ($MisRoot) { $params.MisRoot = $MisRoot }
if ($OutRoot) { $params.OutRoot = $OutRoot }
if ($PbldumpExe) { $params.PbldumpExe = $PbldumpExe }
if ($PbtName) { $params.PbtName = $PbtName }
if ($PbtPath) { $params.PbtPath = $PbtPath }
if ($LogDir) { $params.LogDir = $LogDir }
if ($CleanArtifactsOnly) { $params.CleanArtifactsOnly = $true }
& $realScript @params 2>&1
