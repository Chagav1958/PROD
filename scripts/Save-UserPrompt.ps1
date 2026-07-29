param(
    [string]$Text,
    [string]$Timestamp
)

if ([string]::IsNullOrWhiteSpace($Text)) { exit 0 }
$text = $Text.Trim()
if ($text.Length -le 20) { exit 0 }

$logFile = Join-Path $PSScriptRoot "..\temp\user_prompts.log"
$dir = Split-Path $logFile -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }

# Строгая проверка дубликатов: нормализованный текст
$textNorm = $text -replace '\s+', ' '
if (Test-Path $logFile) {
    $raw = Get-Content $logFile -Raw -Encoding UTF8
    $blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
    foreach ($block in $blocks) {
        $lines = $block.Trim() -split "`r`n|`n"
        $existing = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
        $existingNorm = $existing.Trim() -replace '\s+', ' '
        if ($existingNorm -eq $textNorm) { exit 0 }
    }
}

$ts = if ($Timestamp) { $Timestamp } else { Get-Date -Format "dd.MM.yyyy, HH:mm:ss" }
$entry = "`n[$ts]`n$text`n" + ("=" * 60)
Add-Content -Path $logFile -Value $entry -Encoding UTF8