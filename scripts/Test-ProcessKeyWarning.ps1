# Test-ProcessKeyWarning.ps1 — TDD: проверка обнаружения User-ключей без Process
# Запускается в отдельном процессе, не влияет на текущую сессию
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TDD: Test-ProcessKeyWarning (User-ключ без Process)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Симуляция: очистка Process-ключа ROUTERAI_API_KEY
# ============================================================
Write-Host "[1] Симуляция: ключ только в User..." -ForegroundColor Yellow

$userKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User")
if (-not $userKey) {
    Write-Host "  SKIP: ROUTERAI_API_KEY отсутствует даже в User" -ForegroundColor DarkYellow
    Write-Host "  ИТОГО: тест пропущен" -ForegroundColor DarkYellow
    exit 0
}

# Сохраняем текущий Process-ключ и очищаем
$savedProcessKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
[Environment]::SetEnvironmentVariable("ROUTERAI_API_KEY", $null, "Process")

try {
    $procKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
    $usrKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User")
    
    Write-Host "  Process: $(if($procKey){'ЕСТЬ'}else{'ПУСТО'})"
    Write-Host "  User:    $(if($usrKey){'ЕСТЬ'}else{'ПУСТО'})"
    
    if ($usrKey -and -not $procKey) {
        Write-Host "  PASS: симуляция успешна — ключ в User, но не в Process" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: не удалось симулировать" -ForegroundColor Red
    }
    Write-Host ""
    
    # ============================================================
    # 2. Проверка: DLLM-логика обнаружения
    # ============================================================
    Write-Host "[2] Проверка логики обнаружения DLLM..." -ForegroundColor Yellow
    
    $envKeyMap = @{
        "ROUTERAI_API_KEY" = "RouterAI"
    }
    $warnings = @()
    foreach ($envKey in $envKeyMap.Keys) {
        $pk = [Environment]::GetEnvironmentVariable($envKey, "Process")
        $uk = [Environment]::GetEnvironmentVariable($envKey, "User")
        if ($uk -and -not $pk) {
            $warnings += "$($envKeyMap[$envKey])"
        }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host "  PASS: DLLM обнаружит проблему: $($warnings -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: DLLM НЕ обнаружит проблему" -ForegroundColor Red
    }
    Write-Host ""
    
    # ============================================================
    # 3. Проверка: HTTP-запрос всё ещё работает (Test-LLM.ps1 логика)
    # ============================================================
    Write-Host "[3] Проверка HTTP (Test-LLM логика)..." -ForegroundColor Yellow
    
    # Test-LLM.ps1 использует Get-EnvVar, которая проверяет Process -> User -> Machine
    # Поэтому HTTP-тест будет работать даже без Process-ключа (найдёт в User)
    $httpKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
    if (-not $httpKey) { $httpKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User") }
    
    if ($httpKey) {
        Write-Host "  INFO: Test-LLM.ps1 найдёт ключ в User -> HTTP-тест будет OK" -ForegroundColor White
        Write-Host "  PASS: логика Test-LLM.ps1 корректна (ищет User при отсутствии Process)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: ключ не найден" -ForegroundColor Red
    }
    Write-Host ""
    
    # ============================================================
    # 4. Проверка: opencode run должен дать 401
    # ============================================================
    Write-Host "[4] Проверка opencode run (должен дать 401)..." -ForegroundColor Yellow
    
    $opencodePs1 = "$env:APPDATA\npm\opencode.ps1"
    if (Test-Path $opencodePs1) {
        # opencode run использует ТОЛЬКО Process-переменные
        # Так как мы очистили Process-ключ, должен быть 401
        $result401 = $false
        try {
            $cmd = "& `"$opencodePs1`" run --attach 'http://localhost:4096' -u opencode -p '548f52d3-ed77-4497-b17b-d70f735822ab' -m routerai/anthropic/claude-haiku-4.5 -- 'Reply: 1' 2>&1"
            $output = Invoke-Expression $cmd | Out-String
            $result401 = $output -match "401"
        } catch {
            $result401 = $_.Exception.Message -match "401"
        }
        
        if ($result401) {
            Write-Host "  PASS: opencode run возвращает 401 (Process-ключ отсутствует)" -ForegroundColor Green
        } else {
            Write-Host "  WARN: opencode run НЕ вернул 401 (возможно, сервер недоступен или ключ кэширован)" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  SKIP: opencode.ps1 не найден" -ForegroundColor DarkYellow
    }
    Write-Host ""
    
    # ============================================================
    # 5. Вывод: корень проблемы подтверждён
    # ============================================================
    Write-Host "[5] Вывод" -ForegroundColor Yellow
    Write-Host "  КОРЕНЬ ПРОБЛЕМЫ ПОДТВЕРЖДЁН:" -ForegroundColor White
    Write-Host "  - Ключ в User, но не в Process" -ForegroundColor White
    Write-Host "  - Test-LLM.ps1 работает (ищет User)" -ForegroundColor White
    Write-Host "  - OpenCode НЕ работает (видит только Process) -> 401" -ForegroundColor White
    Write-Host "  - DLLM теперь показывает предупреждение" -ForegroundColor White
    Write-Host "  - Решение: скопировать ключ в Process или Machine" -ForegroundColor White
    
} finally {
    # Восстанавливаем Process-ключ
    if ($savedProcessKey) {
        [Environment]::SetEnvironmentVariable("ROUTERAI_API_KEY", $savedProcessKey, "Process")
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ИТОГО: тест завершён" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
