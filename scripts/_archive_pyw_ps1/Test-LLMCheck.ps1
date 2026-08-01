# Test-LLMCheck.ps1 — TDD: проверка авто-теста и обработки 401
# Запуск: powershell -NoLogo -File Test-LLMCheck.ps1
param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $PSScriptRoot -Parent

Write-Host "=== TDD: Test-LLMCheck ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Загрузка функций из Show-LLMs.ps1 (без выполнения WPF)
# ============================================================
Write-Host "[1/6] Загрузка Test-LLM.ps1..." -ForegroundColor Yellow

$testLLMPath = Join-Path $PSScriptRoot "Test-LLM.ps1"
if (-not (Test-Path $testLLMPath)) {
    Write-Host "  FAIL: Test-LLM.ps1 не найден: $testLLMPath" -ForegroundColor Red
    exit 1
}

# Читаем конфиг для получения текущей модели
$opencodeConfigPath = Join-Path $projectRoot "opencode.jsonc"
if (-not (Test-Path $opencodeConfigPath)) {
    Write-Host "  FAIL: opencode.jsonc не найден" -ForegroundColor Red
    exit 1
}
$cfg = Get-Content $opencodeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$userConfigPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".config\opencode\opencode.jsonc"
$userCfg = $null
if (Test-Path $userConfigPath) {
    try { $userCfg = Get-Content $userConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
$currentModelId = if ($userCfg -and $userCfg.model) { $userCfg.model } elseif ($cfg.model) { $cfg.model } else { "" }

Write-Host "  Текущая модель: $currentModelId" -ForegroundColor White
Write-Host ""

# ============================================================
# 2. Проверка: Test-LLM.ps1 возвращает реальный статус
# ============================================================
Write-Host "[2/6] Прямой тест текущей модели через Test-LLM.ps1..." -ForegroundColor Yellow

$resultDir = Join-Path $projectRoot "temp\llm_test"
if (Test-Path $resultDir) { Remove-Item "$resultDir\*" -Force -ErrorAction SilentlyContinue }
else { New-Item -ItemType Directory -Path $resultDir -Force | Out-Null }

$cleanModelArg = $currentModelId
$proc = Start-Process powershell -ArgumentList "-NoLogo -NoProfile -STA -File `"$testLLMPath`" -ModelName `"$cleanModelArg`"" -PassThru -Wait -WindowStyle Minimized

$safeName = $currentModelId -replace '[/\\:<>"|?*]', '_'
$resultFile = Join-Path $resultDir "$safeName.log"
if (Test-Path $resultFile) {
    $result = Get-Content $resultFile -Raw -Encoding UTF8
    Write-Host "  Результат Test-LLM.ps1: $result" -ForegroundColor White
    if ($result -eq "Ok") {
        Write-Host "  PASS: модель доступна" -ForegroundColor Green
    } elseif ($result -like "Error:*") {
        $errReason = $result -replace "^Error:\s*", ""
        Write-Host "  INFO: модель недоступна — $errReason" -ForegroundColor Magenta
        if ($result -match "401") {
            Write-Host "  PASS: 401 корректно обнаружен Test-LLM.ps1" -ForegroundColor Green
        }
    } else {
        Write-Host "  WARN: неизвестный результат" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  FAIL: Test-LLM.ps1 не создал файл результата" -ForegroundColor Red
}
Write-Host ""

# ============================================================
# 3. Проверка: Test-LLM.ps1 ловит 401 с невалидным ключом
# ============================================================
Write-Host "[3/6] Тест с заведомо невалидным ключом..." -ForegroundColor Yellow

$oldKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
$fakeKey = "sk-fake-test-key-12345"

try {
    [Environment]::SetEnvironmentVariable("ROUTERAI_API_KEY", $fakeKey, "Process")

    $fakeResultFile = Join-Path $resultDir "fake_test.log"
    Remove-Item $fakeResultFile -Force -ErrorAction SilentlyContinue

    $proc2 = Start-Process powershell -ArgumentList "-NoLogo -NoProfile -STA -File `"$testLLMPath`" -ModelName `"$cleanModelArg`"" -PassThru -Wait -WindowStyle Minimized

    $fakeSafeName = $currentModelId -replace '[/\\:<>"|?*]', '_'
    $actualResultFile = Join-Path $resultDir "$fakeSafeName.log"
    if (Test-Path $actualResultFile) {
        $fakeResult = Get-Content $actualResultFile -Raw -Encoding UTF8
        Write-Host "  Результат с фейк-ключом: $fakeResult" -ForegroundColor White
        if ($fakeResult -match "401|403|Невалидный ключ") {
            Write-Host "  PASS: фейк-ключ корректно обнаружен как 401/403" -ForegroundColor Green
        } elseif ($fakeResult -eq "Ok") {
            Write-Host "  FAIL: фейк-ключ НЕ обнаружен! Test-LLM.ps1 вернул Ok" -ForegroundColor Red
            Write-Host "  >>> КОРЕНЬ ПРОБЛЕМЫ: RouterAI принимает любой ключ?" -ForegroundColor Red
        } else {
            Write-Host "  WARN: неожиданный результат с фейк-ключом" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  FAIL: Test-LLM.ps1 не создал файл с фейк-ключом" -ForegroundColor Red
    }
} finally {
    if ($oldKey) {
        [Environment]::SetEnvironmentVariable("ROUTERAI_API_KEY", $oldKey, "Process")
    }
}
Write-Host ""

# ============================================================
# 4. Проверка: кэш llm_test_results.json
# ============================================================
Write-Host "[4/6] Проверка кэша llm_test_results.json..." -ForegroundColor Yellow

$cachePath = Join-Path $projectRoot "temp\llm_test_results.json"
if (Test-Path $cachePath) {
    $cache = Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $cacheEntry = $cache.$currentModelId
    if ($cacheEntry) {
        $age = 0
        try { $age = ((Get-Date) - [datetime]$cacheEntry.testTime).TotalMinutes } catch { }
        Write-Host "  Кэш для '$currentModelId': status=$($cacheEntry.status), age=$([math]::Round($age,1))мин" -ForegroundColor White
        if ($age -le 5) {
            Write-Host "  PASS: кэш свежий (<=5 мин), авто-тест отработал" -ForegroundColor Green
        } elseif ($age -le 60) {
            Write-Host "  WARN: кэшу $([math]::Round($age,0))мин, ещё валиден но не от авто-теста" -ForegroundColor DarkYellow
        } else {
            Write-Host "  WARN: кэш устарел (>60мин), авто-тест не обновил" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  FAIL: текущая модель '$currentModelId' отсутствует в кэше" -ForegroundColor Red
        Write-Host "  >>> Авто-тест не записал результат!" -ForegroundColor Red
    }
} else {
    Write-Host "  FAIL: файл кэша не существует" -ForegroundColor Red
}
Write-Host ""

# ============================================================
# 5. Проверка: Test-SingleModel (из Show-LLMs.ps1) — обработка 401
# ============================================================
Write-Host "[5/6] Проверка Test-SingleModel из Show-LLMs.ps1..." -ForegroundColor Yellow

$showLLMsPath = Join-Path $PSScriptRoot "Show-LLMs.ps1"
if (-not (Test-Path $showLLMsPath)) {
    Write-Host "  FAIL: Show-LLMs.ps1 не найден" -ForegroundColor Red
} else {
    # Извлекаем Test-SingleModel как отдельную функцию через парсинг
    $showLLMsCode = Get-Content $showLLMsPath -Raw -Encoding UTF8
    
    # Проверяем, что в коде есть правильная обработка 401
    if ($showLLMsCode -match 'if \(\$sc -eq 401 -or \$sc -eq 403\) \{ return @\{ Status="Error"; Code=\$sc; Reason="Невалидный ключ \(\$sc\)" \}') {
        Write-Host "  PASS: Test-SingleModel содержит проверку 401/403" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Test-SingleModel НЕ содержит проверку 401/403" -ForegroundColor Red
    }
    
    # Проверяем, что Test-RouterAIAvailable использует текущую модель
    if ($showLLMsCode -match 'Test-RouterAIAvailable') {
        if ($showLLMsCode -match 'currentModelId.*routerai') {
            Write-Host "  PASS: Test-RouterAIAvailable использует currentModelId" -ForegroundColor Green
        } else {
            Write-Host "  WARN: не удалось подтвердить использование currentModelId в Test-RouterAIAvailable" -ForegroundColor DarkYellow
        }
    }
    
    # Проверяем наличие авто-теста
    if ($showLLMsCode -match 'Авто-тест текущей модели при запуске DLLM') {
        Write-Host "  PASS: блок авто-теста присутствует" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: блок авто-теста отсутствует" -ForegroundColor Red
    }

    # Проверяем наличие статуса "Не проверено"
    if ($showLLMsCode -match 'Не проверено') {
        Write-Host "  PASS: статус 'Не проверено' присутствует" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: статус 'Не проверено' отсутствует" -ForegroundColor Red
    }
}
Write-Host ""

# ============================================================
# 6. Проверка: расхождение Test-LLM.ps1 vs OpenCode
# ============================================================
Write-Host "[6/6] Проверка идентичности ключа и URL..." -ForegroundColor Yellow

$routerKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
if (-not $routerKey) { $routerKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User") }

$cfgRouterKey = ""
if ($cfg.provider.routerai.options.apiKey) {
    $cfgRouterKey = $cfg.provider.routerai.options.apiKey
    # Раскрываем ${ROUTERAI_API_KEY}
    if ($cfgRouterKey -match '\$\{ROUTERAI_API_KEY\}') {
        $cfgRouterKey = $routerKey
    }
}

$cfgBaseURL = ""
if ($cfg.provider.routerai.options.baseURL) {
    $cfgBaseURL = $cfg.provider.routerai.options.baseURL
}

Write-Host "  Ключ из env:      $(if($routerKey){'***' + $routerKey.Substring([Math]::Max(0,$routerKey.Length-6))}else{'НЕТ'})" -ForegroundColor White
Write-Host "  Ключ в конфиге:   $(if($cfgRouterKey){'***' + $cfgRouterKey.Substring([Math]::Max(0,$cfgRouterKey.Length-6))}else{'НЕТ'})" -ForegroundColor White
Write-Host "  URL в конфиге:    $cfgBaseURL" -ForegroundColor White
Write-Host "  URL в Test-LLM:   https://routerai.ru/api/v1/chat/completions" -ForegroundColor White

if ($cfgBaseURL -and $cfgBaseURL -match "routerai.ru/api/v1") {
    Write-Host "  PASS: URL совпадает (routerai.ru/api/v1)" -ForegroundColor Green
} else {
    Write-Host "  FAIL: URL в конфиге не совпадает с routerai.ru/api/v1" -ForegroundColor Red
}

if ($routerKey -and $routerKey.Length -gt 10) {
    Write-Host "  PASS: ключ RouterAI присутствует в env" -ForegroundColor Green
} else {
    Write-Host "  FAIL: ключ RouterAI отсутствует или слишком короткий" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== TDD: Test-LLMCheck завершён ===" -ForegroundColor Cyan
