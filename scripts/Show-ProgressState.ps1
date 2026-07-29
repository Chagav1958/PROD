$stateFile = Join-Path $PSScriptRoot "..\temp\progress_state.json"
$Host.UI.RawUI.WindowTitle = "AIS Release — Выполнение задач"

$prevHash = ""
$barLen = 30

function Show-Bar($pct) {
    $filled = [math]::Round($pct / 100 * $barLen)
    $empty = $barLen - $filled
    return "[$('#' * $filled)$('-' * $empty)] $pct%"
}

while ($true) {
    if (!(Test-Path $stateFile)) {
        Clear-Host
        Write-Host "=== AIS Release — Выполнение задач ===" -ForegroundColor Cyan
        Write-Host "`nОжидание запуска задач..." -ForegroundColor Gray
        Start-Sleep -Milliseconds 500
        continue
    }
    try {
        $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $hash = "$($state.task_num)|$($state.step_pct)|$($state.done)|$($state.task_name)"
        if ($hash -eq $prevHash) { Start-Sleep -Milliseconds 500; continue }

        if ($state.done) {
            Clear-Host
            Write-Host "=== AIS Release — Выполнение задач ===" -ForegroundColor Cyan
            Write-Host "`n✅ Все задачи выполнены!" -ForegroundColor Green
            Write-Host "   Последнее обновление: $($state.timestamp)" -ForegroundColor DarkGray
            Start-Sleep -Seconds 4
            break
        }

        Clear-Host
        Write-Host "=== AIS Release — Выполнение задач ===" -ForegroundColor Cyan
        Write-Host ""

        $overallPct = if ($state.task_total -gt 0) { [math]::Round($state.task_num / $state.task_total * 100, 0) } else { 0 }
        Write-Host "Общий:    $(Show-Bar $overallPct)" -ForegroundColor Yellow
        Write-Host "Задача:   $($state.task_num) из $($state.task_total) — $($state.task_name)" -ForegroundColor White

        $stepPct = [math]::Round($state.step_pct, 0)
        Write-Host "Текущая:  $(Show-Bar $stepPct)" -ForegroundColor Green
        if ($state.step) { Write-Host "Шаг:      $($state.step)" -ForegroundColor Gray }
        if ($state.status) { Write-Host "Статус:   $($state.status)" -ForegroundColor DarkGray }
        Write-Host ""
        Write-Host "Обновлено: $($state.timestamp)" -ForegroundColor DarkGray

        $prevHash = $hash
    } catch {
        Clear-Host
        Write-Host "=== AIS Release — Выполнение задач ===" -ForegroundColor Cyan
        Write-Host "`nОшибка чтения данных..." -ForegroundColor Red
    }
    Start-Sleep -Milliseconds 500
}

