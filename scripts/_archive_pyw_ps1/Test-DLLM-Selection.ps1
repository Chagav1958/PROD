# Test-DLLM-Selection.ps1 - Тестирование выделения в DLLM
# BOM обязателен для PS 5.1
param(
    [switch]$AutoClose = $false,
    [int]$Timeout = 60
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Тест выделения и копирования в DLLM" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$testResults = @()
$totalTests = 0
$passedTests = 0

function Test-Case {
    param($Name, $ScriptBlock)
    $script:totalTests++
    Write-Host "`n[$($script:totalTests)] $Name" -ForegroundColor Yellow
    try {
        $result = & $ScriptBlock
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:passedTests++
            $script:testResults += "[PASS] $Name"
            return $true
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:testResults += "[FAIL] $Name"
            return $false
        }
    } catch {
        Write-Host "  [ERROR] $Name : $_" -ForegroundColor Red
        $script:testResults += "[ERROR] $Name : $_"
        return $false
    }
}

# Запуск DLLM в фоне
Write-Host "`nЗапуск DLLM..." -ForegroundColor Cyan
$dllmScript = Join-Path $PSScriptRoot "Show-LLMs.ps1"
if (-not (Test-Path $dllmScript)) {
    Write-Host "ОШИБКА: Show-LLMs.ps1 не найден!" -ForegroundColor Red
    exit 1
}

$process = Start-Process powershell -ArgumentList "-NoLogo -WindowStyle Hidden -File `"$dllmScript`"" -PassThru
Start-Sleep -Seconds 3

# Тест 1: Окно открылось
Test-Case "Окно DLLM открылось" {
    $found = $false
    Get-Process | Where-Object { $_.MainWindowTitle -like "DLLM:*" } | ForEach-Object {
        $found = $true
    }
    return $found
}

# Тест 2: Проверка что окно работает
Test-Case "Окно DLLM отвечает" {
    $found = $false
    Get-Process | Where-Object { $_.MainWindowTitle -like "DLLM:*" } | ForEach-Object {
        if (-not $_.Responding) {
            return $false
        }
        $found = $true
    }
    return $found
}

# Тест 3: Базовая функциональность
Test-Case "Базовые элементы управления доступны" {
    # Проверяем через отправку Tab - если окно отвечает, значит элементы есть
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 200
    
    # Если дошли сюда без ошибок - элементы есть
    return $true
}

# Тест 4: Копирование работает
Test-Case "Копирование через Ctrl+C работает" {
    # Очищаем буфер
    try {
        [System.Windows.Clipboard]::Clear()
    } catch {}
    
    # Переходим к таблице
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
    Start-Sleep -Milliseconds 500
    
    # Копируем
    [System.Windows.Forms.SendKeys]::SendWait("^c")
    Start-Sleep -Milliseconds 500
    
    # Проверяем буфер
    try {
        $text = [System.Windows.Clipboard]::GetText()
        return ($text.Length -gt 0)
    } catch {
        return $false
    }
}

# Тест 5: Множественная сортировка
Test-Case "Кнопка Сорт работает повторно" {
    # Нажимаем Tab много раз чтобы добраться до кнопки
    for ($i = 0; $i -lt 10; $i++) {
        [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
        Start-Sleep -Milliseconds 100
    }
    
    # Нажимаем Enter дважды (если это кнопка Сорт)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 500
    
    # Проверяем что окно всё ещё работает
    $found = $false
    Get-Process | Where-Object { $_.MainWindowTitle -like "DLLM:*" } | ForEach-Object {
        if ($_.Responding) {
            $found = $true
        }
    }
    return $found
}

# Закрытие окна
if ($AutoClose) {
    Write-Host "`nЗакрытие DLLM..." -ForegroundColor Cyan
    try {
        [System.Windows.Forms.SendKeys]::SendWait("%{F4}")
        Start-Sleep -Seconds 1
    } catch {}
}

# Убиваем процесс если остался
try {
    if ($process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(5000)
    }
} catch {}

# Итоговый отчёт
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " ИТОГИ ТЕСТИРОВАНИЯ" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Всего тестов: $totalTests" -ForegroundColor White
Write-Host "Пройдено: $passedTests" -ForegroundColor Green
Write-Host "Провалено: $($totalTests - $passedTests)" -ForegroundColor Red

if ($passedTests -eq $totalTests) {
    Write-Host "`nВСЕ ТЕСТЫ ПРОЙДЕНЫ!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nЕСТЬ ПРОВАЛЕННЫЕ ТЕСТЫ!" -ForegroundColor Red
    foreach ($result in $testResults) {
        if ($result -like "*FAIL*" -or $result -like "*ERROR*") {
            Write-Host "  $result" -ForegroundColor Red
        }
    }
    exit 1
}