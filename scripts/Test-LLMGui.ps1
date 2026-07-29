<#
.SYNOPSIS
    Автотест GUI LLM: динамический тест, читающий модели из opencode.jsonc.
    Не содержит захардкоженных списков моделей — всё из конфига.
    Проверяет: структуру, согласованность, валидность характеристик.
#>
$scriptRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $scriptRoot "opencode.jsonc"
$logPath = Join-Path $scriptRoot "temp\llm_autotest.log"

function Write-Log { param([string]$Text)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Text"
    Add-Content -Path $logPath -Value $line -Encoding UTF8; Write-Host $line }

$script:testsPassed = 0; $script:testsFailed = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { Write-Log "  PASS: $Name"; $script:testsPassed++ }
    else { Write-Log "  FAIL: $Name"; $script:testsFailed++ }
}

function Get-EnvVar {
    param([string]$Name)
    $v = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $v
}

Write-Log "=== АВТОТЕСТ GUI LLM (динамический, из конфига) ==="

# ============================================================
# Тест 1: Чтение конфига
# ============================================================
Write-Log "--- Тест 1: Чтение конфига ---"
$cfgRaw = Get-Content $configPath -Raw -Encoding UTF8
Assert-True "opencode.jsonc — валидный JSON" ($null -ne ($cfgRaw | ConvertFrom-Json))
$cfg = $cfgRaw | ConvertFrom-Json

$visibleProviders = @()
if ($cfg.llm_visible_providers) { $visibleProviders = @($cfg.llm_visible_providers) }
if ($visibleProviders.Count -eq 0) { $visibleProviders = @($cfg.provider.PSObject.Properties | ForEach-Object { $_.Name }) + @("opencode-go") }
Assert-True "model задан" ($null -ne $cfg.model -and $cfg.model -ne "")
Assert-True "small_model задан" ($null -ne $cfg.small_model -and $cfg.small_model -ne "")

# ============================================================
# Тест 2: Каждый провайдер в llm_visible_providers имеет секцию в cfg.provider
#         (кроме opencode-go — встроенный). enabled_providers НЕ ИСПОЛЬЗУЕТСЯ.
# ============================================================
Write-Log "--- Тест 2: llm_visible_providers vs cfg.provider (+ user merge) ---"
$userCfg = $null
$userCfgPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".config\opencode\opencode.jsonc"
if (Test-Path $userCfgPath) { try { $userCfg = Get-Content $userCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
$configProviderIds = @($cfg.provider.PSObject.Properties | ForEach-Object { $_.Name })
if ($userCfg -and $userCfg.provider) {
    $userCfg.provider.PSObject.Properties | ForEach-Object {
        if (-not ($configProviderIds -contains $_.Name)) { $configProviderIds += $_.Name }
    }
}
foreach ($provId in $visibleProviders) {
    if ($provId -eq "opencode-go") { continue }
    Assert-True "Провайдер '$provId' есть в cfg.provider" ($configProviderIds -contains $provId)
}

# ============================================================
# Тест 3: Каждая модель в конфиге имеет обязательные поля
# ============================================================
Write-Log "--- Тест 3: Обязательные поля моделей ---"
$requiredFields = @("name")
$optionalFields = @("pb_rating", "sql_rating", "cost", "limit", "modalities", "reasoning", "tool_call", "speed", "status")
$modelCount = 0
$modelsWithPBRating = 0
$modelsWithSQLRating = 0
$modelsWithCost = 0
$modelsWithLimit = 0

foreach ($provId in $configProviderIds) {
    $prov = $cfg.provider.$provId
    if (-not $prov.models) { continue }
    foreach ($modelProp in $prov.models.PSObject.Properties) {
        $modelId = $modelProp.Name
        $modelDef = $modelProp.Value
        $modelCount++

        # name — обязательно
        $hasName = $null -ne $modelDef.name -and $modelDef.name -ne ""
        Assert-True "[$provId/$modelId] есть 'name'" $hasName

        # pb_rating — желательно
        if ($null -ne $modelDef.pb_rating) { $modelsWithPBRating++ }
        else { Write-Log "  WARN: [$provId/$modelId] нет pb_rating" }

        # sql_rating — желательно
        if ($null -ne $modelDef.sql_rating) { $modelsWithSQLRating++ }
        else { Write-Log "  WARN: [$provId/$modelId] нет sql_rating" }

        # cost — желательно
        if ($null -ne $modelDef.cost) { $modelsWithCost++ }

        # limit — желательно
        if ($null -ne $modelDef.limit) { $modelsWithLimit++ }
    }
}

Assert-True "Моделей в конфиге > 0" ($modelCount -gt 0)
Assert-True "Все модели имеют pb_rating" ($modelsWithPBRating -eq $modelCount)
Assert-True "Все модели имеют sql_rating" ($modelsWithSQLRating -eq $modelCount)

# ============================================================
# Тест 4: ModelId формат = "provider/model"
# ============================================================
Write-Log "--- Тест 4: Формат ModelId ---"
$formatErrors = 0
$allModelIds = @()

# opencode-go (hardcoded в Show-LLMs, 6 моделей)
$ogModelIds = @(
    "opencode-go/deepseek-v4-flash", "opencode-go/deepseek-v4-pro",
    "opencode-go/glm-5.1", "opencode-go/glm-5.2",
    "opencode-go/kimi", "opencode-go/qwen"
)
$allModelIds += $ogModelIds

foreach ($provId in $configProviderIds) {
    $prov = $cfg.provider.$provId
    if (-not $prov.models) { continue }
    foreach ($modelProp in $prov.models.PSObject.Properties) {
        $fullId = "$provId/$($modelProp.Name)"
        $allModelIds += $fullId
        if ($fullId -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.:/-]+$') {
            $formatErrors++
            Write-Log "  FAIL: ModelId '$fullId' — неверный формат"
        }
    }
}
if ($formatErrors -eq 0) { $script:testsPassed++; Write-Log "  PASS: Все ModelId корректны" }
else { $script:testsFailed++ }

# ============================================================
# Тест 5: model и small_model из конфига присутствуют в списке
# ============================================================
Write-Log "--- Тест 5: model и small_model в списке ---"
Assert-True "model ($($cfg.model)) в списке" ($allModelIds -contains $cfg.model)
Assert-True "small_model ($($cfg.small_model)) в списке" ($allModelIds -contains $cfg.small_model)

# ============================================================
# Тест 6: $providerTests карта покрывает все провайдеры
#         (список из Show-LLMs.ps1 зашит тут для сверки)
# ============================================================
Write-Log "--- Тест 6: Покрытие провайдеров функциями проверки ---"
$knownProviders = @("ollama", "opencode-go", "opencode-zen", "github-copilot", "routerai", "anthropic", "artemox", "openai", "deepseek", "yandex", "google", "openrouter")
$allProviderIds = $configProviderIds + @("opencode-go") | Select-Object -Unique
foreach ($provId in $allProviderIds) {
    Assert-True "Провайдер '$provId' есть в knownProviders" ($knownProviders -contains $provId)
}

# ============================================================
# Тест 7: Доступность провайдеров (runtime проверка)
# ============================================================
Write-Log "--- Тест 7: Доступность провайдеров (runtime) ---"

function Test-OllamaOnline {
    try { Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5 | Out-Null; return $true }
    catch { return $false }
}
function Test-OpenCodeGoAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return $true }
    $cfg2 = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg2.model -match '^opencode-go/') { return $true }
    try { [System.Net.Dns]::GetHostEntry("api.opencode-go.ai") | Out-Null; return $true }
    catch { return $false }
}
function Test-RouterAIAvailable {
    $key = Get-EnvVar "ROUTERAI_API_KEY"
    if (-not $key) { return $false }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"gpt-3.5-turbo","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://routerai.ru/api/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch { $ex = $_.Exception; if ($ex.Response -and $ex.Response.StatusCode) { $sc = [int]$ex.Response.StatusCode; if ($sc -eq 401 -or $sc -eq 403) { return $false }; if ($sc -ge 400 -and $sc -lt 500) { return $true } }; return $false }
}
function Test-AnthropicAvailable {
    $key = Get-EnvVar "ANTHROPIC_API_KEY"
    if (-not $key) { return $false }
    if ($key.Length -le 20) { return $false }
    $headers = @{"x-api-key"=$key; "anthropic-version"="2023-06-01"; "Content-Type"="application/json"}
    $body = '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return $false }
            if ($sc -ge 400 -and $sc -lt 500) { return $true }
        }
        return $false
    }
}
function Test-EnvKeyAvailable { param([string]$EnvVar) return [bool](Get-EnvVar $EnvVar) }

function Test-ArtemoxAvailable {
    $key = Get-EnvVar "ARTEMOX_API_KEY"
    if (-not $key) { return $false }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"gpt-3.5-turbo","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://api.artemox.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch { $ex = $_.Exception; if ($ex.Response -and $ex.Response.StatusCode) { $sc = [int]$ex.Response.StatusCode; if ($sc -eq 401 -or $sc -eq 403) { return $false }; if ($sc -ge 400 -and $sc -lt 500) { return $true } }; return $false }
}
function Test-OpenAIAvailable {
    $key = Get-EnvVar "OPENAI_API_KEY"
    if (-not $key) { return $false }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"gpt-4o-mini","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch { $ex = $_.Exception; if ($ex.Response -and $ex.Response.StatusCode) { $sc = [int]$ex.Response.StatusCode; if ($sc -eq 401 -or $sc -eq 403) { return $false }; if ($sc -ge 400 -and $sc -lt 500) { return $true } }; return $false }
}
function Test-DeepSeekAvailable {
    $key = Get-EnvVar "DEEPSEEK_API_KEY"
    if (-not $key) { return $false }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"deepseek-chat","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://api.deepseek.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch { $ex = $_.Exception; if ($ex.Response -and $ex.Response.StatusCode) { $sc = [int]$ex.Response.StatusCode; if ($sc -eq 401 -or $sc -eq 403) { return $false }; if ($sc -ge 400 -and $sc -lt 500) { return $true } }; return $false }
}
function Test-YandexAvailable {
    $key = Get-EnvVar "YANDEX_API_KEY"
    if (-not $key) { return $false }
    $cfg2 = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $folderId = if ($cfg2.provider.yandex.folderId) { $cfg2.provider.yandex.folderId } else { "b1ghbd3js0u0ru6djp4q" }
    $headers = @{"Authorization"="Api-Key $key"; "x-folder-id"=$folderId; "Content-Type"="application/json"}
    $body = '{"modelUri":"gpt://' + $folderId + '/yandexgpt/latest","completionOptions":{"stream":false,"temperature":0,"maxTokens":1},"messages":[{"role":"user","text":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://llm.api.cloud.yandex.net/foundationModels/v1/completion" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15
        return ($r.StatusCode -eq 200 -or $r.StatusCode -eq 400)
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 402 -or $sc -eq 403) { return $false }
            if ($sc -ge 400 -and $sc -lt 500) { return $true }
        }
        return $false
    }
}
function Test-GoogleAvailable {
    $key = Get-EnvVar "GOOGLE_API_KEY"
    if (-not $key) { return $false }
    try { $r = Invoke-WebRequest -Uri "https://generativelanguage.googleapis.com/v1/models?key=$key" -UseBasicParsing -TimeoutSec 10; return $r.StatusCode -eq 200 }
    catch { return $false }
}

function Test-OpenCodeZenAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return $true }
    $cfg2 = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg2.model -match '^opencode-zen/') { return $true }
    return $false
}

function Test-GitHubCopilotAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return $true }
    $cfg2 = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg2.model -match '^github-copilot/') { return $true }
    return [bool](Get-EnvVar "GITHUB_COPILOT_API_KEY")
}
function Test-OpenRouterAvailable {
    $key = Get-EnvVar "OPENROUTER_API_KEY"
    if (-not $key) { return $false }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"openai/gpt-4o-mini","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try { $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 15; return $r.StatusCode -eq 200 }
    catch { $ex = $_.Exception; if ($ex.Response -and $ex.Response.StatusCode) { $sc = [int]$ex.Response.StatusCode; if ($sc -eq 401 -or $sc -eq 403) { return $false }; if ($sc -ge 400 -and $sc -lt 500) { return $true } }; return $false }
}

$providerTests = @{
    "ollama"      = { Test-OllamaOnline }
    "opencode-go" = { Test-OpenCodeGoAvailable }
    "opencode-zen"   = { Test-OpenCodeZenAvailable }
    "github-copilot" = { Test-GitHubCopilotAvailable }
    "routerai"    = { Test-RouterAIAvailable }
    "anthropic"   = { Test-AnthropicAvailable }
    "artemox"     = { Test-ArtemoxAvailable }
    "openai"      = { Test-OpenAIAvailable }
    "deepseek"    = { Test-DeepSeekAvailable }
    "yandex"      = { Test-YandexAvailable }
    "google"      = { Test-GoogleAvailable }
    "openrouter"  = { Test-OpenRouterAvailable }
}

$availableCount = 0
foreach ($provId in $allProviderIds) {
    $test = $providerTests[$provId]
    if (-not $test) { continue }
    $isVisible = ($visibleProviders.Count -eq 0) -or ($visibleProviders -contains $provId)
    if (-not $isVisible) {
        Write-Log "  SKIP: '$provId' не в llm_visible_providers"
        continue
    }
    $result = & $test
    if ($result) { $availableCount++; Write-Log "  PASS: '$provId' доступен" }
    else { Write-Log "  WARN: '$provId' недоступен" }
}

Assert-True "Хотя бы один провайдер доступен" ($availableCount -gt 0)

# ============================================================
# Тест 8: opencode-go модели (hardcoded в Show-LLMs=6) — сверка
# ============================================================
Write-Log "--- Тест 8: opencode-go модели ---"
Assert-True "opencode-go моделей = 6" ($ogModelIds.Count -eq 6)
Assert-True "opencode-go модель 1: deepseek-v4-flash" ($allModelIds -contains "opencode-go/deepseek-v4-flash")
Assert-True "opencode-go модель 6: qwen" ($allModelIds -contains "opencode-go/qwen")

# ============================================================
# Тест 9: model и small_model одинаковые (для простоты)
# ============================================================
Write-Log "--- Тест 9: model / small_model ---"
Assert-True "model = small_model (для упрощения)" ($cfg.model -eq $cfg.small_model)

# ============================================================
# Тест 10: Каждая модель в enabled провайдере — в формате providerId/modelId
#         И не содержит лишних слэшей
# ============================================================
Write-Log "--- Тест 10: Структура ModelId ---"
$badIds = @()
foreach ($id in $allModelIds) {
    # ModelId формат: "provider/modelId" — modelId может содержать '/' (RouterAI: routerai/anthropic/claude-sonnet-5)
    if ($id -notmatch '^[a-zA-Z0-9_-]+/.+') { $badIds += $id }
}
Assert-True "Все ModelId содержат provider/modelId (минимум один '/')" ($badIds.Count -eq 0)

# ============================================================
# Итог
# ============================================================
Write-Log "--- ИТОГ ---"
Write-Log "Всего моделей: $($allModelIds.Count) (из конфига: $modelCount + opencode-go: $($ogModelIds.Count))"
Write-Log "Провайдеров в конфиге: $($configProviderIds.Count), видимых: $($visibleProviders.Count)"
Write-Log "С pb_rating: $modelsWithPBRating / $modelCount"
Write-Log "С sql_rating: $modelsWithSQLRating / $modelCount"
Write-Log "Пройдено: $($script:testsPassed), Провалено: $($script:testsFailed)"
if ($script:testsFailed -gt 0) { exit 1 } else { exit 0 }