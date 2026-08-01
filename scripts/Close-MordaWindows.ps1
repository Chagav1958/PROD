<#
.SYNOPSIS
    Закрывает все окна МОРДА2 (процессы МОРДА — Подготовка релизов).
.DESCRIPTION
    Находит процессы powershell.exe, открывшие окно "МОРДА — Подготовка релизов",
    и завершает их. Скрипт-файл (UTF-8 BOM) — чтобы сравнение кириллицы
    MainWindowTitle работало корректно (в командной строке bash кириллица
    искажается, и фильтр по -like '-МОРДА-' не находил процессы).
.EXAMPLE
    .\Close-MordaWindows.ps1
#>

$ErrorActionPreference = "Continue"
$targetTitle = "МОРДА — Подготовка релизов"
$resultTitle = "Результат: "

$targets = Get-Process | Where-Object {
    $_.Id -ne $PID -and (
        $_.MainWindowTitle -eq $targetTitle -or
        $_.MainWindowTitle -like "$resultTitle*"
    )
} | Sort-Object Id

if (-not $targets) {
    Write-Host "Окон МОРДА2 не найдено."
    exit 0
}

Write-Host "Закрываю окон МОРДА2: $($targets.Count)"
foreach ($p in $targets) {
    Write-Host ("  PID {0}: {1}" -f $p.Id, $p.MainWindowTitle)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$left = Get-Process | Where-Object {
    $_.Id -ne $PID -and (
        $_.MainWindowTitle -eq $targetTitle -or
        $_.MainWindowTitle -like "$resultTitle*"
    )
}
if ($left) {
    Write-Host "ОСТАЛИСЬ:"
    $left | ForEach-Object { Write-Host ("  PID {0}: {1}" -f $_.Id, $_.MainWindowTitle) }
    exit 1
}
Write-Host "Все окна МОРДА2 закрыты."
exit 0
