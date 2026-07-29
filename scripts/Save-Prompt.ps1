param(
    [string]$PromptText,
    [string]$LogFile = "C:\AIS\AI\Prod\temp\user_prompts.log"
)

if (-not $PromptText) {
    Write-Host "Usage: Save-Prompt.ps1 -PromptText \"your prompt here\""
    exit 1
}

$dt = Get-Date -Format "dd.MM.yyyy, HH:mm:ss"
$entry = "`n============================================================`n [$dt]`n$PromptText"

$dir = Split-Path $LogFile -Parent
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

Add-Content -Path $LogFile -Value $entry -Encoding UTF8
Write-Host "Prompt saved to $LogFile"