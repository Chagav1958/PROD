param(
    [string]$CacheDir = "C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\Cache\Cache_Data",
    [int]$IntervalMs = 300,
    [switch]$Forever,
    [string]$StopWhenProcessExits = ""
)

$OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8

function Test-ProcessAlive {
    param([string]$ProcessName)
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $true }
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($p) { return $true } else { return $false }
}

Write-Host "=== Cache Guard ===" -ForegroundColor Cyan
Write-Host "CacheDir : $CacheDir"
Write-Host "Interval : ${IntervalMs}ms"
$watch = $false
if (-not [string]::IsNullOrWhiteSpace($StopWhenProcessExits)) {
    Write-Host "Watch    : $StopWhenProcessExits (останов при завершении процесса)"
    $watch = $true
} elseif ($Forever) {
    Write-Host "Mode     : бесконечный (Forever)"
} else {
    Write-Host "Mode     : бесконечный (по умолчанию)"
}
Write-Host ""

# Проверка папки
if (-not (Test-Path $CacheDir)) {
    Write-Host "[!] Папка не найдена: $CacheDir" -ForegroundColor Red
    Write-Host "    Монитор завершён."
    exit 1
}

Write-Host "[OK] Папка найдена, запуск монитора..." -ForegroundColor Green

$iteration = 0
$deletedTotal = 0

while ($true) {
    $iteration++
    $files = Get-ChildItem $CacheDir -File -ErrorAction SilentlyContinue
    $count = $files.Count
    if ($count -gt 0) {
        $files | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        $deletedTotal = $deletedTotal + $count
        if ($iteration % 20 -eq 1 -or $count -gt 5) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] #$iteration удалено $count файлов (всего: $deletedTotal)" -ForegroundColor DarkGray
        }
    }

    if ($watch) {
        $alive = Test-ProcessAlive -ProcessName $StopWhenProcessExits
        if (-not $alive) {
            Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Процесс '$StopWhenProcessExits' завершён. Останов монитора." -ForegroundColor Yellow
            Write-Host "  Всего итераций: $iteration, удалено файлов: $deletedTotal" -ForegroundColor Green
            break
        }
    }

    Start-Sleep -Milliseconds $IntervalMs
}
