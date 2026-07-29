param(
    [string]$TaskName,
    [string]$Prompt,
    [string]$Response,
    [string]$Notes = ""
)

if ([string]::IsNullOrWhiteSpace($Prompt) -or [string]::IsNullOrWhiteSpace($Response)) {
    Write-Host "ОШИБКА: укажите -Prompt и -Response"
    exit 1
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$dt = Get-Date -Format "dd.MM.yyyy HH:mm:ss"

if ($TaskName) {
    $taskDir = "C:\AIS\1 Release\$TaskName\Describe"
} else {
    $taskDir = Join-Path $PSScriptRoot "..\temp\analysis"
}
if (-not (Test-Path $taskDir)) { New-Item -ItemType Directory $taskDir -Force | Out-Null }

$fileName = "analysis_$ts.md"
$filePath = Join-Path $taskDir $fileName

$header = "# Анализ"
if ($TaskName) { $header += ": $TaskName" }
$header += "`n**Дата:** $dt"
if ($Notes) { $header += "`n**Примечание:** $Notes" }

$content = @"
$header

## Промпт

$Prompt

## Ответ LLM

$Response

---
*Автосохранение: Save-Analysis.ps1, $dt*
"@

$content | Out-File -FilePath $filePath -Encoding UTF8
Write-Host "Сохранено: $filePath"
Write-Host "Размер: $((Get-Item $filePath).Length) байт"
