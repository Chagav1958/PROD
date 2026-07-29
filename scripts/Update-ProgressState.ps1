param(
    [string]$Step = "",
    [int]$StepPct = 0,
    [string]$TaskName = "",
    [int]$TaskNum = 0,
    [int]$TaskTotal = 0,
    [string]$Status = "",
    [switch]$Done
)

$stateFile = Join-Path $PSScriptRoot "..\temp\progress_state.json"
$dir = Split-Path $stateFile -Parent
if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$state = @{
    step      = $Step
    step_pct  = $StepPct
    task_name = $TaskName
    task_num  = $TaskNum
    task_total = $TaskTotal
    status    = $Status
    done      = if ($Done) { $true } else { $false }
    timestamp = (Get-Date -Format "HH:mm:ss")
}

$json = $state | ConvertTo-Json -Compress
Set-Content -Path $stateFile -Value $json -Encoding UTF8 -Force
