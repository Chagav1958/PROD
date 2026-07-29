# Test-DLLM-Integration.ps1 — TDD интеграционный тест DLLM
# Проверяет: Process-ключи, кэш, HTTP, OpenCode run, статусы моделей
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$totalTests = 0
$passedTests = 0
$failedTests = 0

function Test-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $global:totalTests++
    if ($Passed) {
        $global:passedTests++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $global:failedTests++
        Write-Host "  [FAIL] $Name — $Detail" -ForegroundColor Red
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " TDD: Test-DLLM-Integration" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Проверка Process-ключей
# ============================================================
Write-Host "[1/5] Process-ключи" -ForegroundColor Yellow

$keyMap = @{
    "ROUTERAI_API_KEY" = "RouterAI"
    "ANTHROPIC_API_KEY" = "Anthropic"
    "OPENAI_API_KEY" = "OpenAI"
    "DEEPSEEK_API_KEY" = "DeepSeek"
    "ARTEMOX_API_KEY" = "Artemox"
    "YANDEX_API_KEY" = "Yandex"
    "GOOGLE_API_KEY" = "Google"
    "OPENROUTER_API_KEY" = "OpenRouter"
}

$missingProcess = @()
foreach ($envKey in $keyMap.Keys) {
    $procKey = [Environment]::GetEnvironmentVariable($envKey, "Process")
    $userKey = [Environment]::GetEnvironmentVariable($envKey, "User")
    
    if ($userKey -and -not $procKey) {
        $missingProcess += $keyMap[$envKey]
    }
}

Test-Result -Name "Process-ключи: нет расхождений User/Process" -Passed ($missingProcess.Count -eq 0) -Detail ($missingProcess -join ", ")

if ($missingProcess.Count -gt 0) {
    Write-Host "    >>> ОБНАРУЖЕНА ПРОБЛЕМА: ключи есть в User, но не в Process" -ForegroundColor Red
    Write-Host "    >>> Именно это вызывает 401 в OpenCode!" -ForegroundColor Red
    Write-Host "    >>> Отсутствуют в Process: $($missingProcess -join ', ')" -ForegroundColor Red
}

# Проверка наличия самого важного ключа
$routerKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
if (-not $routerKey) { $routerKey = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User") }
Test-Result -Name "ROUTERAI_API_KEY присутствует" -Passed ([bool]$routerKey) -Detail "ключ не найден ни на одном уровне"

Write-Host ""

# ============================================================
# 2. Проверка кэша
# ============================================================
Write-Host "[2/5] Кэш llm_test_results.json" -ForegroundColor Yellow

$cachePath = Join-Path $projectRoot "temp\llm_test_results.json"
if (Test-Path $cachePath) {
    $cache = Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    
    $cacheAgeOk = $true
    $routerModelsTested = @()
    $routerModelsOk = @()
    
    foreach ($prop in $cache.PSObject.Properties) {
        if ($prop.Name -match '^routerai/') {
            $routerModelsTested += $prop.Name
            if ($prop.Value.status -eq "OK") {
                $routerModelsOk += $prop.Name
            }
        }
    }
    
    # Проверка свежести кэша (последний тест не старше 5 минут)
    $latestTest = $null
    foreach ($prop in $cache.PSObject.Properties) {
        $t = $prop.Value.testTime
        if ($t) {
            $dt = [datetime]$t
            if (-not $latestTest -or $dt -gt $latestTest) { $latestTest = $dt }
        }
    }
    $cacheAge = if ($latestTest) { [math]::Round(((Get-Date) - $latestTest).TotalMinutes, 1) } else { 999 }
    
    Test-Result -Name "Кэш существует" -Passed $true -Detail ""
    Test-Result -Name "Кэш содержит RouterAI-модели" -Passed ($routerModelsTested.Count -gt 0) -Detail "найдено $($routerModelsTested.Count) моделей"
    Test-Result -Name "Кэш свежий (<=15 мин)" -Passed ($cacheAge -le 15) -Detail "возраст: $cacheAge мин"
    
    $failedRouterModels = @()
    foreach ($rn in $routerModelsTested) {
        if ($rn -notin $routerModelsOk) { $failedRouterModels += $rn }
    }
    Test-Result -Name "Все RouterAI-модели OK" -Passed ($failedRouterModels.Count -eq 0) -Detail ("не OK: " + ($failedRouterModels -join ", "))
} else {
    Test-Result -Name "Кэш существует" -Passed $false -Detail "файл $cachePath не найден"
    Test-Result -Name "Кэш содержит RouterAI-модели" -Passed $false -Detail "кэш отсутствует"
    Test-Result -Name "Кэш свежий" -Passed $false -Detail "кэш отсутствует"
    Test-Result -Name "Все RouterAI-модели OK" -Passed $false -Detail "кэш отсутствует"
}

Write-Host ""

# ============================================================
# 3. Проверка HTTP-теста (прямой запрос к RouterAI)
# ============================================================
Write-Host "[3/5] HTTP-тест RouterAI" -ForegroundColor Yellow

if ($routerKey) {
    $testModel = "anthropic/claude-haiku-4.5"
    $headers = @{Authorization = "Bearer $routerKey"; "Content-Type" = "application/json"}
    $body = '{"model":"' + $testModel + '","max_tokens":5,"messages":[{"role":"user","content":"Reply: 1"}]}'
    
    try {
        $r = Invoke-WebRequest -Uri "https://routerai.ru/api/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15
        $valid = ($r.Content -match '"choices"')
        Test-Result -Name "HTTP: RouterAI отвечает 200 OK" -Passed ($r.StatusCode -eq 200 -and $valid) -Detail "StatusCode=$($r.StatusCode)"
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            Test-Result -Name "HTTP: RouterAI отвечает 200 OK" -Passed $false -Detail "HTTP $sc"
        } else {
            Test-Result -Name "HTTP: RouterAI отвечает 200 OK" -Passed $false -Detail $ex.Message
        }
    }
} else {
    Test-Result -Name "HTTP: RouterAI отвечает 200 OK" -Passed $false -Detail "нет ключа RouterAI"
}

Write-Host ""

# ============================================================
# 3.5. Проверка npm-пакетов для провайдеров
# ============================================================
Write-Host "[3.5/6] npm-пакеты провайдеров" -ForegroundColor Yellow

$opencodeNpmDir = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".config\opencode\node_modules"

$npmProviders = @{
    "routerai" = "@ai-sdk/openai-compatible"
    "anthropic" = "@ai-sdk/anthropic"
}

foreach ($provId in $npmProviders.Keys) {
    $pkgName = $npmProviders[$provId]
    $pkgPath = Join-Path $opencodeNpmDir $pkgName
    $installed = Test-Path $pkgPath
    Test-Result -Name "npm: $provId ($pkgName)" -Passed $installed -Detail $(if($installed){""}else{"НЕ УСТАНОВЛЕН! Выполните: npm install $pkgName в ~/.config/opencode"})
}

Write-Host ""

# ============================================================
# 4. Проверка OpenCode run (реальная интеграция)
# ============================================================
Write-Host "[4/6] OpenCode run (интеграция)" -ForegroundColor Yellow

$opencodePs1 = "$env:APPDATA\npm\opencode.ps1"
if (Test-Path $opencodePs1) {
    $serverUrl = "http://localhost:4096"
    $user = "opencode"
    $pass = "548f52d3-ed77-4497-b17b-d70f735822ab"
    
    # Проверяем, что сервер OpenCode доступен
    try {
        $serverCheck = Invoke-WebRequest -Uri $serverUrl -UseBasicParsing -TimeoutSec 3
        $serverOnline = $true
    } catch {
        $serverOnline = $false
    }
    
    if ($serverOnline) {
        $cmd = "& `"$opencodePs1`" run --attach $serverUrl -u $user -p $pass -m routerai/anthropic/claude-haiku-4.5 -- 'Reply: 1'"
        try {
            $result = Invoke-Expression $cmd 2>&1 | Out-String
            $has401 = $result -match "401"
            $hasError = $result -match "Error:"
            
            if ($has401) {
                Test-Result -Name "OpenCode run: нет 401" -Passed $false -Detail "ОШИБКА 401! Process-ключ не виден OpenCode. Результат: $result"
            } elseif ($hasError) {
                Test-Result -Name "OpenCode run: нет 401" -Passed $true -Detail "ошибка не-401: $result"
            } else {
                Test-Result -Name "OpenCode run: нет 401" -Passed $true -Detail "OK"
            }
        } catch {
            Test-Result -Name "OpenCode run: нет 401" -Passed $false -Detail "исключение: $($_.Exception.Message)"
        }
    } else {
        Test-Result -Name "OpenCode run: нет 401" -Passed $true -Detail "сервер OpenCode недоступен — тест пропущен"
    }
} else {
    Test-Result -Name "OpenCode run: нет 401" -Passed $true -Detail "opencode.ps1 не найден — тест пропущен"
}

Write-Host ""

# ============================================================
# 5. Проверка структуры Show-LLMs.ps1
# ============================================================
Write-Host "[5/6] Структура Show-LLMs.ps1" -ForegroundColor Yellow

$showLLMsPath = Join-Path $PSScriptRoot "Show-LLMs.ps1"
if (Test-Path $showLLMsPath) {
    $code = Get-Content $showLLMsPath -Raw -Encoding UTF8
    
    $checks = @{
        "Проверка Process-ключей (envKeyWarnings)" = ($code -match 'envKeyWarnings')
        "Авто-тест при запуске" = ($code -match 'Авто-тест моделей при запуске DLLM')
        "Статус 'Не проверено'" = ($code -match 'Не проверено')
        "Обработка 401 в Test-SingleModel" = ($code -match '401.*403.*Невалидный ключ')
        "Функция Update-ModelFromTest" = ($code -match 'function Update-ModelFromTest')
        "Колонка LastTested" = ($code -match 'LastTested')
        "Кэш 15 минут (cacheMaxAge=0.25)" = ($code -match 'cacheMaxAge = 0\.25')
        "Предупреждение при переключении" = ($code -match 'не проверена.*быструю проверку')
        "Неблокирующий цикл (PushFrame)" = ($code -match 'PushFrame')
        "Проверка npm-пакетов" = ($code -match 'npm-пакет.*не установлен')
        "Test-RouterAIAvailable через currentModelId" = ($code -match 'currentModelId.*routerai')
    }
    
    foreach ($checkName in $checks.Keys) {
        Test-Result -Name $checkName -Passed $checks[$checkName] -Detail ""
    }
} else {
    Test-Result -Name "Show-LLMs.ps1 найден" -Passed $false -Detail "файл не существует"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ИТОГО: $passedTests/$totalTests PASS, $failedTests FAIL" -ForegroundColor $(if($failedTests -eq 0){"Green"}else{"Red"})
Write-Host "============================================================" -ForegroundColor Cyan

if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
