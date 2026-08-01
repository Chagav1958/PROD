<#
.SYNOPSIS
    OUT/ОБР — анализ последнего вывода МОРДА или МОРДА2.
.DESCRIPTION
    Определяет, какой GUI был активен (МОРДА или МОРДА2) по свежести логов
    и выводит путь + содержимое наиболее свежего журнала вывода.
    - МОРДА (Prod-GUI.ps1 / STANDART1): temp\last_output.log
    - МОРДА2 (Prod-GUI_STANDART2.ps1): %TEMP%\tech_journal_*.log
.PARAMETER PathOnly
    Вывести только путь к свежему логу (без содержимого).
.PARAMETER Hours
    Окно времени для tech_journal_*.log (по умолчанию 2 часа).
.EXAMPLE
    powershell -NoLogo -File scripts\Out-LastOutput.ps1
#>
param(
    [switch]$PathOnly,
    [int]$Hours = 2
)

$ProjectRoot = if ($PSScriptRoot -match '[\\/]scripts$') { Split-Path $PSScriptRoot -Parent } else { 'C:\AIS\AI\Prod' }

$logs = @()

# 1. МОРДА: temp\last_output.log
$mordaLog = Join-Path $ProjectRoot "temp\last_output.log"
if (Test-Path $mordaLog) {
    $logs += [PSCustomObject]@{
        Source = "МОРДА"
        Path   = $mordaLog
        Time   = (Get-Item $mordaLog).LastWriteTime
    }
}

# 2. МОРДА2: свежие tech_journal_*.log из %TEMP%
$cutoff = (Get-Date).AddHours(-$Hours)
$journals = Get-ChildItem (Join-Path $env:TEMP "tech_journal_*.log") -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $cutoff }
foreach ($j in $journals) {
    $logs += [PSCustomObject]@{
        Source = "МОРДА2 ($($j.Name))"
        Path   = $j.FullName
        Time   = $j.LastWriteTime
    }
}

if ($logs.Count -eq 0) {
    Write-Host "НЕТ СВЕЖЕГО ВЫВОДА. Нет last_output.log и нет свежих tech_journal_*.log (за $Hours ч)." -ForegroundColor Yellow
    exit 0
}

$latest = $logs | Sort-Object Time -Descending | Select-Object -First 1

Write-Host ("=== ВЫБРАН ЛОГ [{0}] ===" -f $latest.Source) -ForegroundColor Cyan
Write-Host ("Путь: {0}" -f $latest.Path) -ForegroundColor Gray
Write-Host ("Время: {0:yyyy-MM-dd HH:mm:ss}" -f $latest.Time) -ForegroundColor Gray
Write-Host ""

if (-not $PathOnly) {
    try {
        Get-Content -LiteralPath $latest.Path -Encoding UTF8
    } catch {
        Write-Host "ОШИБКА чтения лога: $_" -ForegroundColor Red
    }
}
