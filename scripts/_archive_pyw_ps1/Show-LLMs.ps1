param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

# Set-MetroTheme (с защитой)
$themePath = Join-Path $PSScriptRoot "Set-MetroTheme.ps1"
if (Test-Path $themePath) { . $themePath }

$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot "opencode.jsonc"

# ============================================================
# Чтение конфигов (user-конфиг имеет приоритет над проектным)
# ============================================================

$cfgText = Get-Content $configPath -Raw -Encoding UTF8
$cfg = $cfgText | ConvertFrom-Json

$userConfigPath = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".config\opencode\opencode.jsonc"
$userCfg = $null
if (Test-Path $userConfigPath) {
    try { $userCfg = Get-Content $userConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
$currentModelId = if ($userCfg -and $userCfg.model) { $userCfg.model } elseif ($cfg.model) { $cfg.model } else { "" }

# Мержим провайдеров из user-конфига в проектный
# (opencode-zen, github-copilot и др. — их нет в проектном конфиге)
if ($userCfg -and $userCfg.provider) {
    if (-not $cfg.provider) { $cfg | Add-Member -NotePropertyName "provider" -NotePropertyValue ([PSCustomObject]@{}) -Force }
    $userCfg.provider.PSObject.Properties | ForEach-Object {
        $provId = $_.Name
        $userProv = $_.Value
        if (-not ($cfg.provider.PSObject.Properties.Name -contains $provId)) {
            try { $cfg.provider | Add-Member -NotePropertyName $provId -NotePropertyValue $userProv -Force } catch { }
        }
    }
}

# ============================================================
# Splash-окно загрузки (показывается пока идёт подготовка)
# ============================================================

$splash = New-Object Windows.Window
$splash.Width = 420; $splash.Height = 160
$splash.WindowStartupLocation = "CenterScreen"
$splash.Topmost = $true
$splash.AllowsTransparency = $true; $splash.WindowStyle = "None"
$splash.Background = "Transparent"
$splash.ShowInTaskbar = $false

$splashBorder = New-Object Windows.Controls.Border
$splashBorder.CornerRadius = 16; $splashBorder.BorderBrush = "#1A3A60"
$splashBorder.BorderThickness = "2"; $splashBorder.Background = "White"

$splashGrid = New-Object Windows.Controls.Grid
$splashGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$splashGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$splashGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$splashGrid.Margin = "20,16,20,16"

$splashTitle = New-Object Windows.Controls.TextBlock
$splashTitle.Text = "DLLM — подготовка к работе"
$splashTitle.FontSize = 14; $splashTitle.FontWeight = "Bold"
$splashTitle.Foreground = "#1A3A60"; $splashTitle.HorizontalAlignment = "Center"
$splashTitle.Margin = "0,0,0,8"
[Windows.Controls.Grid]::SetRow($splashTitle, 0)
[void]$splashGrid.Children.Add($splashTitle)

$splashStatus = New-Object Windows.Controls.TextBlock
$splashStatus.Text = "Инициализация..."
$splashStatus.FontSize = 11; $splashStatus.Foreground = "#4A5568"
$splashStatus.HorizontalAlignment = "Center"
$splashStatus.Margin = "0,0,0,10"
[Windows.Controls.Grid]::SetRow($splashStatus, 1)
[void]$splashGrid.Children.Add($splashStatus)

$splashPb = New-Object Windows.Controls.ProgressBar
$splashPb.IsIndeterminate = $true; $splashPb.Height = 6
$splashPb.Margin = "0,4,0,0"
[Windows.Controls.Grid]::SetRow($splashPb, 2)
[void]$splashGrid.Children.Add($splashPb)

$splashBorder.Child = $splashGrid
$splash.Content = $splashBorder

# DragMove для splash
$splashBorder.Add_MouseLeftButtonDown({ try { $splash.DragMove() } catch {} })

$splash.Show()

# Функция обновления статуса splash (принудительная перерисовка)
function Update-Splash {
    param([string]$Text)
    $splashStatus.Text = $Text
    $splash.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

Update-Splash -Text "Инициализация..."

# ============================================================
# Функции-помощники для env-переменных
# ============================================================

function Get-EnvVar {
    param([string]$Name)
    $v = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $v
}

# ============================================================
# Функции проверки доступности провайдеров
# Каждая возвращает $true/$false. причина берётся из $providerTests.NoKeyReason.
# ============================================================

function Test-OllamaOnline {
    try { Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5 | Out-Null; return @{Available=$true; Code=200; Reason=""} }
    catch { return @{Available=$false; Code=0; Reason="Ollama не запущен (localhost:11434)"} }
}

function Test-OpenCodeGoAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return @{Available=$true; Code=0; Reason=""} }
    if ($currentModelId -match '^opencode-go/') { return @{Available=$true; Code=0; Reason=""} }
    if ($cfg.model -match '^opencode-go/' -or $cfg.small_model -match '^opencode-go/') { return @{Available=$true; Code=0; Reason=""} }
    try {
        $resolver = [System.Net.Dns]::BeginGetHostEntry("api.opencode-go.ai", $null, $null)
        if ($resolver.AsyncWaitHandle.WaitOne(3000)) {
            [System.Net.Dns]::EndGetHostEntry($resolver) | Out-Null
            return @{Available=$true; Code=0; Reason=""}
        }
        return @{Available=$false; Code=0; Reason="API opencode-go недоступен (таймаут DNS)"}
    }    catch { return @{Available=$false; Code=0; Reason="API opencode-go недоступен (блокируется firewall)"} }
}

function Test-RouterAIAvailable {
    $key = Get-EnvVar "ROUTERAI_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа ROUTERAI_API_KEY"} }
    try {
        $r = Invoke-WebRequest -Uri "https://routerai.ru/api/v1/models" -Method Get -Headers @{Authorization="Bearer $key"} -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -eq 200) { return @{Available=$true; Code=200; Reason=""} }
        return @{Available=$false; Code=[int]$r.StatusCode; Reason="HTTP $($r.StatusCode)"}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-AnthropicAvailable {
    $key = Get-EnvVar "ANTHROPIC_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа ANTHROPIC_API_KEY"} }
    if ($key.Length -le 20) { return @{Available=$false; Code=0; Reason="Ключ ANTHROPIC_API_KEY слишком короткий"} }
    $headers = @{"x-api-key"=$key; "anthropic-version"="2023-06-01"; "Content-Type"="application/json"}
    $body = '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://api.anthropic.com/v1/messages" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 404) { return @{Available=$false; Code=$sc; Reason="Модель не найдена ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-ArtemoxAvailable {
    $key = Get-EnvVar "ARTEMOX_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа ARTEMOX_API_KEY"} }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"gpt-3.5-turbo","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://api.artemox.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-OpenAIAvailable {
    $key = Get-EnvVar "OPENAI_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа OPENAI_API_KEY"} }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"gpt-4o-mini","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-DeepSeekAvailable {
    $key = Get-EnvVar "DEEPSEEK_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа DEEPSEEK_API_KEY"} }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"deepseek-chat","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://api.deepseek.com/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-YandexAvailable {
    $key = Get-EnvVar "YANDEX_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа YANDEX_API_KEY"} }
    $folderId = if ($cfg.provider.yandex.folderId) { $cfg.provider.yandex.folderId } else { "b1ghbd3js0u0ru6djp4q" }
    $headers = @{"Authorization"="Api-Key $key"; "x-folder-id"=$folderId; "Content-Type"="application/json"}
    $body = '{"modelUri":"gpt://' + $folderId + '/yandexgpt/latest","completionOptions":{"stream":false,"temperature":0,"maxTokens":1},"messages":[{"role":"user","text":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://llm.api.cloud.yandex.net/foundationModels/v1/completion" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-GoogleAvailable {
    $key = Get-EnvVar "GOOGLE_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа GOOGLE_API_KEY"} }
    # Google Generative AI: GET /v1/models
    try {
        $r = Invoke-WebRequest -Uri "https://generativelanguage.googleapis.com/v1/models?key=$key" -UseBasicParsing -TimeoutSec 10
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

function Test-OpenCodeZenAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return @{Available=$true; Code=0; Reason=""} }
    if ($currentModelId -match '^opencode-zen/') { return @{Available=$true; Code=0; Reason=""} }
    if ($cfg.model -match '^opencode-zen/' -or $cfg.small_model -match '^opencode-zen/') { return @{Available=$true; Code=0; Reason=""} }
    return @{Available=$false; Code=0; Reason="OpenCode Zen недоступен"}
}

function Test-GitHubCopilotAvailable {
    $ocClient = Get-EnvVar "OPENCODE_CLIENT"
    if ($ocClient -eq "desktop") { return @{Available=$true; Code=0; Reason=""} }
    if ($currentModelId -match '^github-copilot/') { return @{Available=$true; Code=0; Reason=""} }
    if ($cfg.model -match '^github-copilot/' -or $cfg.small_model -match '^github-copilot/') { return @{Available=$true; Code=0; Reason=""} }
    return @{Available=[bool](Get-EnvVar "GITHUB_COPILOT_API_KEY"); Code=0; Reason=""}
}

function Test-OpenRouterAvailable {
    $key = Get-EnvVar "OPENROUTER_API_KEY"
    if (-not $key) { return @{Available=$false; Code=0; Reason="Нет ключа OPENROUTER_API_KEY"} }
    $headers = @{Authorization = "Bearer $key"; "Content-Type"="application/json"}
    $body = '{"model":"openai/gpt-4o-mini","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}'
    try {
        $r = Invoke-WebRequest -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return @{Available=($r.StatusCode -eq 200); Code=[int]$r.StatusCode; Reason=""}
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{Available=$false; Code=$sc; Reason="Невалидный ключ ($sc)"} }
            if ($sc -eq 402 -or $sc -eq 429) { return @{Available=$false; Code=$sc; Reason="Лимиты исчерпаны ($sc)"} }
            return @{Available=$false; Code=$sc; Reason="HTTP $sc"}
        }
        $msg = $ex.Message
        if ($msg -match "timeout|timed out") { return @{Available=$false; Code=0; Reason="Таймаут"} }
        return @{Available=$false; Code=0; Reason="Сетевая ошибка"}
    }
}

# ============================================================
# Тест конкретной модели (HTTP-запрос к API провайдера)
# Возвращает: @{ Status = "OK"|"Error"|"Skip"; Code = int; Reason = string }
# ============================================================

function Test-SingleModel {
    param(
        [string]$ProvId,
        [string]$ModelId
    )

    if ($ProvId -eq "opencode-go" -or $ProvId -eq "opencode-zen" -or $ProvId -eq "github-copilot") {
        return @{ Status="Skip"; Code=0; Reason="" }
    }
    if ($ProvId -eq "ollama") {
        return @{ Status="Skip"; Code=0; Reason="" }
    }

    # Убираем префикс провайдера из ModelId (напр. "routerai/anthropic/..." → "anthropic/...")
    $apiModelId = $ModelId -replace "^$ProvId/", ""

    $url = $null; $headers = @{}; $body = $null; $timeout = 10
    switch ($ProvId) {
        "routerai" {
            $key = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа ROUTERAI_API_KEY" } }
            $url = "https://routerai.ru/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "anthropic" {
            $key = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User") }
            if (-not $key -or $key.Length -le 20) { return @{ Status="Error"; Code=0; Reason="Нет ключа ANTHROPIC_API_KEY" } }
            $url = "https://api.anthropic.com/v1/messages"
            $headers = @{"x-api-key"=$key; "anthropic-version"="2023-06-01"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "openai" {
            $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа OPENAI_API_KEY" } }
            $url = "https://api.openai.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "deepseek" {
            $key = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа DEEPSEEK_API_KEY" } }
            $url = "https://api.deepseek.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "artemox" {
            $key = [Environment]::GetEnvironmentVariable("ARTEMOX_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ARTEMOX_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа ARTEMOX_API_KEY" } }
            $url = "https://api.artemox.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "yandex" {
            $key = [Environment]::GetEnvironmentVariable("YANDEX_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("YANDEX_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа YANDEX_API_KEY" } }
            $folderId = "b1ghbd3js0u0ru6djp4q"
            $url = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
            $headers = @{"Authorization"="Api-Key $key"; "x-folder-id"=$folderId}
            $body = '{"modelUri":"gpt://' + $folderId + '/' + $apiModelId + '/latest","completionOptions":{"stream":false,"temperature":0,"maxTokens":5},"messages":[{"role":"user","text":"Reply: 1"}]}'
            $timeout = 5
        }
        "openrouter" {
            $key = [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа OPENROUTER_API_KEY" } }
            $url = "https://openrouter.ai/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "google" {
            $key = [Environment]::GetEnvironmentVariable("GOOGLE_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("GOOGLE_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа GOOGLE_API_KEY" } }
            $url = "https://generativelanguage.googleapis.com/v1beta/models/" + $apiModelId + ":generateContent?key=" + $key
            $body = '{"contents":[{"parts":[{"text":"Reply: 1"}]}]}'
        }
        default {
            return @{ Status="Skip"; Code=0; Reason="Провайдер '$ProvId' не поддерживает прямое тестирование" }
        }
    }

    if (-not $url) { return @{ Status="Error"; Code=0; Reason="URL не определён" } }

    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec $timeout
        $content = $r.Content
        $valid = $false
        if ($ProvId -eq "anthropic") {
            $valid = ($content -match '"type"\s*:\s*"message"')
        } elseif ($ProvId -eq "yandex") {
            $valid = ($content -match '"result"')
        } elseif ($ProvId -eq "google") {
            $valid = ($content -match '"candidates"')
        } else {
            $valid = ($content -match '"choices"')
        }
        if ($r.StatusCode -eq 200 -and $valid) {
            return @{ Status="OK"; Code=200; Reason="" }
        }
        if ($r.StatusCode -eq 200 -and -not $valid) {
            return @{ Status="Error"; Code=200; Reason="API 200, но структура ответа не распознана" }
        }
        if ($r.StatusCode -ge 400 -and $content -match '"type"\s*:\s*"error"') {
            $errMsg = ""
            if ($content -match '"message"\s*:\s*"([^"]+)"') { $errMsg = $matches[1] }
            return @{ Status="Error"; Code=$r.StatusCode; Reason=$errMsg }
        }
        return @{ Status="Error"; Code=$r.StatusCode; Reason="HTTP $($r.StatusCode)" }
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{ Status="Error"; Code=$sc; Reason="Невалидный ключ ($sc)" } }
            if ($sc -eq 404) { return @{ Status="Error"; Code=$sc; Reason="Модель не найдена ($sc)" } }
            if ($sc -eq 402 -or $sc -eq 429) { return @{ Status="TomorrowAvail"; Code=$sc; Reason="Лимиты исчерпаны, восстановятся завтра" } }
            if ($sc -ge 400) { return @{ Status="Error"; Code=$sc; Reason="HTTP $sc" } }
            return @{ Status="Error"; Code=$sc; Reason="HTTP $sc" }
        }
        $msg = $_.Exception.Message
        if ($msg -match "timeout|timed out") { return @{ Status="Error"; Code=0; Reason="Таймаут (${timeout}с)" } }
        return @{ Status="Error"; Code=0; Reason="Сетевая ошибка: $msg" }
    }
}

# ============================================================
# Текст-шаблон Test-SingleModel для запуска в runspace pool (устарел, оставлен для совместимости)
# ============================================================

$providerTests = [ordered]@{
    "ollama"      = @{ Test = { Test-OllamaOnline } }
    "opencode-go" = @{ Test = { Test-OpenCodeGoAvailable } }
    "routerai"    = @{ Test = { Test-RouterAIAvailable } }
    "anthropic"   = @{ Test = { Test-AnthropicAvailable } }
    "artemox"     = @{ Test = { Test-ArtemoxAvailable } }
    "openai"      = @{ Test = { Test-OpenAIAvailable } }
    "deepseek"    = @{ Test = { Test-DeepSeekAvailable } }
    "yandex"      = @{ Test = { Test-YandexAvailable } }
    "google"         = @{ Test = { Test-GoogleAvailable } }
    "opencode-zen"   = @{ Test = { Test-OpenCodeZenAvailable } }
    "github-copilot" = @{ Test = { Test-GitHubCopilotAvailable } }
    "openrouter"     = @{ Test = { Test-OpenRouterAvailable } }
}

# ============================================================
# Вычисление статуса всех провайдеров
# — читает enabled_providers из конфига
# — вызывает Test-функцию для каждого
# — результат: $providerStatus[providerId] = @{Available; Reason}
# ============================================================

Update-Splash -Text "Проверка провайдеров..."

$allConfigProviders = @($cfg.provider.PSObject.Properties | ForEach-Object { $_.Name })
$providerStatus = @{}

# opencode-go — встроенный провайдер, нет в cfg.provider, но нужен в статусе
$allProviderIds = $allConfigProviders + @("opencode-go") | Select-Object -Unique

# Фильтр видимых провайдеров: llm_visible_providers из opencode.jsonc
# Если поле отсутствует — показываем всех. enabled_providers НЕ ИСПОЛЬЗУЕТСЯ (это поле OpenCode, не наше).
$visibleProviders = @($cfg.llm_visible_providers)

foreach ($provId in $allProviderIds) {
    $available = $false
    $reason = ""

    # Скрытые провайдеры (не в llm_visible_providers) — показываем, но с пометкой
    $isHidden = $visibleProviders.Count -gt 0 -and ($visibleProviders -notcontains $provId)
    if ($isHidden) {
        $reason = "Скрыт (нет в llm_visible_providers в opencode.jsonc)"
        $providerStatus[$provId] = @{Available=$false; Reason=$reason; Hidden=$true}
        continue
    }

    $test = $providerTests[$provId]
    if ($test) {
        $testResult = & $test.Test
        if ($testResult -is [hashtable] -or $testResult -is [PSCustomObject]) {
            $available = $testResult.Available
            if (-not $available) { $reason = $testResult.Reason }
        } else {
            # Обратная совместимость: старые функции возвращают bool
            $available = $testResult
            if (-not $available) { $reason = "Провайдер недоступен" }
        }
    } else {
        $reason = "Неизвестный провайдер (нет функции проверки в `$providerTests)"
    }

    $providerStatus[$provId] = @{ Available = $available; Reason = $reason }
}

# ============================================================
# Проверка Process-ключей (OpenCode видит только Process)
# ============================================================

Update-Splash -Text "Проверка ключей API..."

$envKeyWarnings = @()
$envKeyMap = @{
    "ROUTERAI_API_KEY" = "RouterAI"
    "ANTHROPIC_API_KEY" = "Anthropic"
    "OPENAI_API_KEY" = "OpenAI"
    "DEEPSEEK_API_KEY" = "DeepSeek"
    "ARTEMOX_API_KEY" = "Artemox"
    "YANDEX_API_KEY" = "Yandex"
    "GOOGLE_API_KEY" = "Google"
    "OPENROUTER_API_KEY" = "OpenRouter"
}

foreach ($envKey in $envKeyMap.Keys) {
    $procKey = [Environment]::GetEnvironmentVariable($envKey, "Process")
    $userKey = [Environment]::GetEnvironmentVariable($envKey, "User")
    if ($userKey -and -not $procKey) {
        $envKeyWarnings += "$($envKeyMap[$envKey]): ключ есть в User, но ОТСУТСТВУЕТ в Process! OpenCode не увидит его -> 401"
    }
}

# Авто-копирование User-ключей в Process (чтобы DLLM-тесты и opencode run видели ключи)
if ($envKeyWarnings.Count -gt 0) {
    foreach ($envKey in $envKeyMap.Keys) {
        $procKey = [Environment]::GetEnvironmentVariable($envKey, "Process")
        $userKey = [Environment]::GetEnvironmentVariable($envKey, "User")
        if ($userKey -and -not $procKey) {
            [Environment]::SetEnvironmentVariable($envKey, $userKey, "Process")
        }
    }
    # Пересчитываем — теперь все должны быть в Process
    $envKeyWarnings = @()
    foreach ($envKey in $envKeyMap.Keys) {
        $procKey = [Environment]::GetEnvironmentVariable($envKey, "Process")
        $userKey = [Environment]::GetEnvironmentVariable($envKey, "User")
        if ($userKey -and -not $procKey) {
            $envKeyWarnings += "$($envKeyMap[$envKey]): ключ есть в User, но ОТСУТСТВУЕТ в Process (не удалось скопировать)"
        }
    }
}

# ============================================================
# Проверка npm-пакетов для провайдеров
# ============================================================

Update-Splash -Text "Проверка npm-пакетов..."

$npmCheckProviders = @{
    "routerai" = "@ai-sdk/openai-compatible"
    "anthropic" = "@ai-sdk/anthropic"
}

$opencodeNpmDir = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".config\opencode\node_modules"
foreach ($provId in $npmCheckProviders.Keys) {
    $pkgName = $npmCheckProviders[$provId]
    $pkgPath = Join-Path $opencodeNpmDir $pkgName
    if (($cfg.provider.PSObject.Properties.Name -contains $provId) -and -not (Test-Path $pkgPath)) {
        $envKeyWarnings += "$($provId): npm-пакет '$pkgName' не установлен! Выполните: npm install $pkgName в ~/.config/opencode"
    }
}

# ============================================================
# Функции-помощники для deriving меток из конфига
# ============================================================

function Get-CleanName {
    param([string]$FullName, [string]$Fallback)
    if ([string]::IsNullOrWhiteSpace($FullName)) { return $Fallback }
    if ($FullName -match '^([^\[]+)') { $r = $matches[1].Trim(); if ($r) { return $r } }
    return $FullName
}

function Get-PriceLabel {
    param($Cost)
    if (-not $Cost) { return "—" }
    if ($Cost.input -eq 0 -and $Cost.output -eq 0) { return "Бесплатная" }
    $in = $Cost.input
    if ($in -le 0.5e-6) { return "Низкая" }
    if ($in -le 3e-6) { return "Средняя" }
    return "Высокая"
}

function Get-LimitsLabel {
    param($Limit)
    if (-not $Limit -or -not $Limit.context) { return "—" }
    $ctx = $Limit.context
    if ($ctx -ge 1048576) { return "1M контекста" }
    return "$([math]::Round($ctx/1024))K контекста"
}

function Get-AllowsLabel {
    param($Modalities)
    if (-not $Modalities -or -not $Modalities.input) { return "—" }
    $labels = @{ "text" = "Текст"; "image" = "изображения"; "audio" = "аудио"; "video" = "видео" }
    $parts = @()
    foreach ($m in @($Modalities.input)) {
        if ($labels[$m]) { $parts += $labels[$m] }
        else { $parts += $m }
    }
    return ($parts -join ", ")
}

function Get-ReasoningLabel {
    param($ModelDef)
    if ($ModelDef.reasoning -and $ModelDef.tool_call) { return "Глубокое" }
    if ($ModelDef.reasoning) { return "Есть" }
    return "Нет"
}

function Get-IntelligenceLabel {
    param($ModelDef)
    if ($ModelDef.reasoning -and $ModelDef.tool_call) { return "Высокая. Код, рассуждения" }
    if ($ModelDef.reasoning) { return "Средняя. Чат, текст" }
    if ($ModelDef.tool_call) { return "Средняя. Инструменты" }
    return "Низкая. Простой чат"
}

function Get-ProdUsageScore {
    param([int]$PB, [int]$SQL, [string]$Reasoning)
    # Шкала 0–100 на основе PB+SQL (макс 20 баллов -> 100)
    $raw = ($PB + $SQL) * 5
    if ($raw -gt 100) { $raw = 100 }
    if ($raw -lt 0)   { $raw = 0 }
    return [int]$raw
}

# ============================================================
# Кэш результатов тестирования моделей (temp/llm_test_results.json)
# ============================================================

$testCachePath = Join-Path $projectRoot "temp\llm_test_results.json"

function Get-TestCache {
    param([string]$Path)
    $cache = @{}
    if (Test-Path $Path) {
        try {
            $raw = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $raw.PSObject.Properties) {
                $cache[$prop.Name] = @{
                    Status = $prop.Value.status
                    Code = if ($prop.Value.code) { $prop.Value.code } else { 0 }
                    Reason = if ($prop.Value.reason) { $prop.Value.reason } else { "" }
                    TestTime = if ($prop.Value.testTime) { $prop.Value.testTime } else { "" }
                }
            }
        } catch { }
    }
    return $cache
}

function Save-TestCache {
    param([string]$Path, [hashtable]$Cache)
    try {
        $dir = Split-Path $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = New-Object PSCustomObject
        foreach ($key in $Cache.Keys) {
            $entry = $Cache[$key]
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue ([PSCustomObject]@{
                status = $entry.Status
                code = $entry.Code
                reason = $entry.Reason
                testTime = $entry.TestTime
            }) -Force
        }
        $obj | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
    } catch { }
}

# Текст-шаблон Test-SingleModel для запуска в runspace pool
$testFnForRunspace = @'
function Test-SingleModel {
    param([string]$ProvId, [string]$ModelId)
    if ($ProvId -eq "opencode-go" -or $ProvId -eq "opencode-zen" -or $ProvId -eq "github-copilot") {
        return @{ Status="Skip"; Code=0; Reason="" }
    }
    if ($ProvId -eq "ollama") {
        return @{ Status="Skip"; Code=0; Reason="" }
    }
    $apiModelId = $ModelId -replace "^$ProvId/", ""
    $url = $null; $headers = @{}; $body = $null; $timeout = 10
    switch ($ProvId) {
        "routerai" {
            $key = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ROUTERAI_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа ROUTERAI_API_KEY" } }
            $url = "https://routerai.ru/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
            $timeout = 15
        }
        "anthropic" {
            $key = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY", "User") }
            if (-not $key -or $key.Length -le 20) { return @{ Status="Error"; Code=0; Reason="Нет ключа ANTHROPIC_API_KEY" } }
            $url = "https://api.anthropic.com/v1/messages"
            $headers = @{"x-api-key"=$key; "anthropic-version"="2023-06-01"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "openai" {
            $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа OPENAI_API_KEY" } }
            $url = "https://api.openai.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "deepseek" {
            $key = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа DEEPSEEK_API_KEY" } }
            $url = "https://api.deepseek.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "artemox" {
            $key = [Environment]::GetEnvironmentVariable("ARTEMOX_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("ARTEMOX_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа ARTEMOX_API_KEY" } }
            $url = "https://api.artemox.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "yandex" {
            $key = [Environment]::GetEnvironmentVariable("YANDEX_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("YANDEX_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа YANDEX_API_KEY" } }
            $folderId = "b1ghbd3js0u0ru6djp4q"
            $url = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
            $headers = @{"Authorization"="Api-Key $key"; "x-folder-id"=$folderId}
            $body = '{"modelUri":"gpt://' + $folderId + '/' + $apiModelId + '/latest","completionOptions":{"stream":false,"temperature":0,"maxTokens":5},"messages":[{"role":"user","text":"Reply: 1"}]}'
            $timeout = 5
        }
        "openrouter" {
            $key = [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа OPENROUTER_API_KEY" } }
            $url = "https://openrouter.ai/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: 1"}]}'
        }
        "google" {
            $key = [Environment]::GetEnvironmentVariable("GOOGLE_API_KEY", "Process")
            if (-not $key) { $key = [Environment]::GetEnvironmentVariable("GOOGLE_API_KEY", "User") }
            if (-not $key) { return @{ Status="Error"; Code=0; Reason="Нет ключа GOOGLE_API_KEY" } }
            $url = "https://generativelanguage.googleapis.com/v1beta/models/" + $apiModelId + ":generateContent?key=" + $key
            $body = '{"contents":[{"parts":[{"text":"Reply: 1"}]}]}'
        }
        default { return @{ Status="Skip"; Code=0; Reason="" } }
    }
    if (-not $url) { return @{ Status="Error"; Code=0; Reason="URL не определён" } }
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec $timeout
        $content = $r.Content
        $valid = $false
        if ($ProvId -eq "anthropic") {
            $valid = ($content -match '"type"\s*:\s*"message"')
        } elseif ($ProvId -eq "yandex") {
            $valid = ($content -match '"result"')
        } elseif ($ProvId -eq "google") {
            $valid = ($content -match '"candidates"')
        } else {
            $valid = ($content -match '"choices"')
        }
        if ($r.StatusCode -eq 200 -and $valid) {
            return @{ Status="OK"; Code=200; Reason="" }
        }
        if ($r.StatusCode -eq 200 -and -not $valid) {
            return @{ Status="Error"; Code=200; Reason="API 200, но структура ответа не распознана" }
        }
        if ($r.StatusCode -ge 400 -and $content -match '"type"\s*:\s*"error"') {
            $errMsg = ""
            if ($content -match '"message"\s*:\s*"([^"]+)"') { $errMsg = $matches[1] }
            return @{ Status="Error"; Code=$r.StatusCode; Reason=$errMsg }
        }
        return @{ Status="Error"; Code=$r.StatusCode; Reason="HTTP $($r.StatusCode)" }
    } catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $sc = [int]$ex.Response.StatusCode
            if ($sc -eq 401 -or $sc -eq 403) { return @{ Status="Error"; Code=$sc; Reason="Невалидный ключ ($sc)" } }
            if ($sc -eq 404) { return @{ Status="Error"; Code=$sc; Reason="Модель не найдена ($sc)" } }
            if ($sc -eq 402 -or $sc -eq 429) { return @{ Status="TomorrowAvail"; Code=$sc; Reason="Лимиты исчерпаны, восстановятся завтра" } }
            if ($sc -ge 400) { return @{ Status="Error"; Code=$sc; Reason="HTTP $sc" } }
            return @{ Status="Error"; Code=$sc; Reason="HTTP $sc" }
        }
        $msg = $_.Exception.Message
        if ($msg -match "timeout|timed out") { return @{ Status="Error"; Code=0; Reason="Таймаут (${timeout}с)" } }
        return @{ Status="Error"; Code=0; Reason="Сетевая ошибка: $msg" }
    }
}
'@

# ============================================================
# Построение списка моделей ($llmData) — ИЗ КОНФИГА
# ============================================================

$llmData = @()

Update-Splash -Text "Загрузка моделей..."

# --- opencode-go (hardcoded — встроенный провайдер, нет в opencode.jsonc) ---
$ogModels = @(
    @{Name="DeepSeek V4 Flash";Id="opencode-go/deepseek-v4-flash";Int="Высокая. Код, рассуждения, сложные задачи";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="DeepSeek V4 PRO";Id="opencode-go/deepseek-v4-pro";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="GLM-5.1";Id="opencode-go/glm-5.1";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="GLM-5.2";Id="opencode-go/glm-5.2";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="Kimi K2.6";Id="opencode-go/kimi-k2.6";Int="Высокая. Анализ, рассуждения, код";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=8;Spd="сервер"}
    @{Name="Kimi K2.7 Code";Id="opencode-go/kimi-k2.7-code";Int="Высокая. Код, анализ";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=8;Spd="сервер"}
    @{Name="MiniMax-M2.7";Id="opencode-go/minimax-m2.7";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Есть";PB=6;SQL=6;Spd="сервер"}
    @{Name="MiniMax-M3";Id="opencode-go/minimax-m3";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="MiMo V2.5";Id="opencode-go/mimo-v2.5";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=5;SQL=5;Spd="сервер"}
    @{Name="MiMo V2.5 Pro";Id="opencode-go/mimo-v2.5-pro";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="Qwen3.6 Plus";Id="opencode-go/qwen3.6-plus";Int="Высокая. Код, анализ";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=7;Spd="сервер"}
    @{Name="Qwen3.7 Plus";Id="opencode-go/qwen3.7-plus";Int="Высокая. Код, анализ, изображения";Price="Средняя";Limits="1M контекста";Allows="Текст, изображения, видео";Reason="Chain-of-Thought";PB=9;SQL=8;Spd="сервер"}
    @{Name="Qwen3.7 Max";Id="opencode-go/qwen3.7-max";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="1M контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=9;Spd="сервер"}
)
$ocDesktop = ((Get-EnvVar "OPENCODE_CLIENT") -eq "desktop")
$ogStatus = $providerStatus["opencode-go"]
if (-not $ogStatus) { $ogStatus = @{Available=$ocDesktop; Reason=""} }
foreach ($m in $ogModels) {
        $llmData += [PSCustomObject]@{
            Name = (Get-CleanName $m.Name -Fallback $m.Id); ModelId = $m.Id; Provider = "opencode-go"; ProviderId = "opencode-go"
            Available = if ($ogStatus.Available -or $ocDesktop) { "Работоспособна" } else { "Недоступна" }
            NotAvailableReason = $ogStatus.Reason; LastTested = ""
            Intelligence = $m.Int; Price = $m.Price; Limits = $m.Limits
            Allows = $m.Allows; Reasoning = $m.Reason; PBRating=$m.PB; SQLRating=$m.SQL; Speed=$m.Spd
            ProdUsage = (Get-ProdUsageScore -PB $m.PB -SQL $m.SQL -Reasoning $m.Reason)
        }
}

# --- opencode-zen (hardcoded — для моделей, которых нет в конфиге) ---
$ozStatus = $providerStatus["opencode-zen"]
if (-not $ozStatus) { $ozStatus = @{Available=$ocDesktop; Reason=""} }

$ozHardcoded = @(
    @{Name="Big Pickle";Id="opencode-zen/big-pickle";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=5;SQL=5;Spd="сервер"}
    @{Name="Claude Fable 5";Id="opencode-zen/claude-fable-5";Int="Высокая. Анализ, креатив";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=8;Spd="сервер"}
    @{Name="Claude Haiku 4.5";Id="opencode-zen/claude-haiku-4-5";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="Claude Opus 4.1";Id="opencode-zen/claude-opus-4-1";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Claude Opus 4.5";Id="opencode-zen/claude-opus-4-5";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Claude Opus 4.6";Id="opencode-zen/claude-opus-4-6";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Claude Opus 4.7";Id="opencode-zen/claude-opus-4-7";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Claude Opus 4.8";Id="opencode-zen/claude-opus-4-8";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=11;SQL=11;Spd="сервер"}
    @{Name="Claude Sonnet 4";Id="opencode-zen/claude-sonnet-4";Int="Высокая. Код, рассуждения, сложные задачи";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="Claude Sonnet 4.5";Id="opencode-zen/claude-sonnet-4-5";Int="Высокая. Код, рассуждения, сложные задачи";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="Claude Sonnet 4.6";Id="opencode-zen/claude-sonnet-4-6";Int="Очень высокая. Код, рассуждения";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Claude Sonnet 5";Id="opencode-zen/claude-sonnet-5";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="DeepSeek V4 Flash";Id="opencode-zen/deepseek-v4-flash";Int="Высокая. Код, рассуждения, чат";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=8;Spd="сервер"}
    @{Name="DeepSeek V4 Flash Free";Id="opencode-zen/deepseek-v4-flash-free";Int="Высокая. Код, рассуждения, чат";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=8;Spd="сервер"}
    @{Name="DeepSeek V4 Pro";Id="opencode-zen/deepseek-v4-pro";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Gemini 3 Flash";Id="opencode-zen/gemini-3-flash";Int="Средняя. Чат, анализ";Price="Низкая";Limits="128K контекста";Allows="Текст, изображения";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="Gemini 3.1 Pro Preview";Id="opencode-zen/gemini-3.1-pro";Int="Высокая. Анализ, код, рассуждения";Price="Средняя";Limits="1M контекста";Allows="Текст, изображения";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="Gemini 3.5 Flash";Id="opencode-zen/gemini-3.5-flash";Int="Средняя. Чат, анализ";Price="Низкая";Limits="128K контекста";Allows="Текст, изображения";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="GLM-5";Id="opencode-zen/glm-5";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="GLM-5.1";Id="opencode-zen/glm-5.1";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="GLM-5.2";Id="opencode-zen/glm-5.2";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="GPT-5";Id="opencode-zen/gpt-5";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="GPT-5 Codex";Id="opencode-zen/gpt-5-codex";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5 Nano";Id="opencode-zen/gpt-5-nano";Int="Низкая. Простой чат";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=4;SQL=4;Spd="сервер"}
    @{Name="GPT-5.1";Id="opencode-zen/gpt-5.1";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.1 Codex";Id="opencode-zen/gpt-5.1-codex";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.1 Codex Max";Id="opencode-zen/gpt-5.1-codex-max";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="128K контекста";Allows="Текст, код";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="GPT-5.1 Codex Mini";Id="opencode-zen/gpt-5.1-codex-mini";Int="Средняя. Код, чат";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="GPT-5.2";Id="opencode-zen/gpt-5.2";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.2 Codex";Id="opencode-zen/gpt-5.2-codex";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.3 Codex";Id="opencode-zen/gpt-5.3-codex";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.3 Codex Spark";Id="opencode-zen/gpt-5.3-codex-spark";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.4";Id="opencode-zen/gpt-5.4";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.4 Mini";Id="opencode-zen/gpt-5.4-mini";Int="Средняя. Чат, код";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="GPT-5.4 Nano";Id="opencode-zen/gpt-5.4-nano";Int="Средняя. Чат, код";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="GPT-5.4 Pro";Id="opencode-zen/gpt-5.4-pro";Int="Высокая. Код, рассуждения";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="GPT-5.5";Id="opencode-zen/gpt-5.5";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="1M контекста";Allows="Текст, изображения";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="GPT-5.5 Pro";Id="opencode-zen/gpt-5.5-pro";Int="Очень высокая. Любые задачи";Price="Высокая";Limits="1M контекста";Allows="Текст, изображения";Reason="Глубокое";PB=10;SQL=10;Spd="сервер"}
    @{Name="Grok Build 0.1";Id="opencode-zen/grok-build-0.1";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="Hy3 Free";Id="opencode-zen/hy3-free";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=5;SQL=5;Spd="сервер"}
    @{Name="Kimi K2.5";Id="opencode-zen/kimi-k2.5";Int="Высокая. Анализ, рассуждения, код";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=8;Spd="сервер"}
    @{Name="Kimi K2.6";Id="opencode-zen/kimi-k2.6";Int="Высокая. Анализ, рассуждения, код";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=8;Spd="сервер"}
    @{Name="Kimi K2.7 Code";Id="opencode-zen/kimi-k2.7-code";Int="Высокая. Код, анализ";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=8;Spd="сервер"}
    @{Name="MiMo V2.5 Free";Id="opencode-zen/mimo-v2.5-free";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=5;SQL=5;Spd="сервер"}
    @{Name="MiniMax-M2.5";Id="opencode-zen/minimax-m2.5";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Нет";PB=5;SQL=5;Spd="сервер"}
    @{Name="MiniMax-M2.7";Id="opencode-zen/minimax-m2.7";Int="Средняя. Чат, генерация";Price="Низкая";Limits="128K контекста";Allows="Текст";Reason="Есть";PB=6;SQL=6;Spd="сервер"}
    @{Name="MiniMax-M3";Id="opencode-zen/minimax-m3";Int="Высокая. Анализ, генерация";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="Nemotron 3 Ultra Free";Id="opencode-zen/nemotron-3-ultra-free";Int="Высокая. Код, рассуждения, сложные задачи";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=9;SQL=9;Spd="сервер"}
    @{Name="North Mini Code Free";Id="opencode-zen/north-mini-code-free";Int="Средняя. Код, чат";Price="Низкая";Limits="128K контекста";Allows="Текст, код";Reason="Нет";PB=6;SQL=6;Spd="сервер"}
    @{Name="Qwen3.5 Plus";Id="opencode-zen/qwen3.5-plus";Int="Высокая. Код, анализ";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Есть";PB=7;SQL=7;Spd="сервер"}
    @{Name="Qwen3.6 Plus";Id="opencode-zen/qwen3.6-plus";Int="Высокая. Код, анализ";Price="Средняя";Limits="128K контекста";Allows="Текст, код";Reason="Chain-of-Thought";PB=8;SQL=7;Spd="сервер"}
)
foreach ($ozm in $ozHardcoded) {
    if (-not ($llmData | Where-Object { $_.ModelId -eq $ozm.Id })) {
        $llmData += [PSCustomObject]@{
            Name = $ozm.Name; ModelId = $ozm.Id; Provider = "OpenCode Zen"; ProviderId = "opencode-zen"
            Available = if ($ozStatus.Available -or $ocDesktop) { "Работоспособна" } else { "Недоступна" }
            NotAvailableReason = $ozStatus.Reason; LastTested = ""
            Intelligence = $ozm.Int; Price = $ozm.Price; Limits = $ozm.Limits
            Allows = $ozm.Allows; Reasoning = $ozm.Reason; PBRating=$ozm.PB; SQLRating=$ozm.SQL; Speed=$ozm.Spd
            ProdUsage = (Get-ProdUsageScore -PB $ozm.PB -SQL $ozm.SQL -Reasoning $ozm.Reason)
        }
    }
}

# Big Pickle: если лимиты исчерпаны — "До завтра" (обрабатывается в блоке кэша при HTTP 402/429)

# --- Конфигурационные провайдеры: читаем ВСЕ из opencode.jsonc ---
# Итерация по всем провайдерам в $cfg.provider.
# Характеристики берутся из конфига (pb_rating, sql_rating, speed, cost, limit, modalities, reasoning, tool_call).
# Доступность — из $providerStatus (единственный источник, зависящий от $providerTests и enabled_providers).

# Для Ollama (если онлайн) — получить список установленных моделей
$installedOllamaModels = @()
$ollamaStatus = $providerStatus["ollama"]
if ($ollamaStatus -and $ollamaStatus.Available) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
        $installedOllamaModels = @(($r.Content | ConvertFrom-Json).models | ForEach-Object { $_.name })
    } catch { }
}

foreach ($provId in $allConfigProviders) {
    # opencode-go и opencode-zen уже обработаны как hardcoded — пропускаем
    if ($provId -eq "opencode-go" -or $provId -eq "opencode-zen") { continue }
    $prov = $cfg.provider.$provId
    if (-not $prov -or -not $prov.models) { continue }

    $provName = if ($prov.name) { $prov.name } else { $provId }
    $status = $providerStatus[$provId]
    if (-not $status) { $status = @{ Available = $false; Reason = "Статус не вычислен" } }

    foreach ($modelProp in $prov.models.PSObject.Properties) {
        $modelId = $modelProp.Name
        $modelDef = $modelProp.Value

        # Доступность — из статуса провайдера (если нет — "Не проверено")
        $avail = "Не проверено"
        $reason = "Нажмите «Проверить все» для тестирования"
        if ($status.Available) {
            $avail = "Работоспособна"
            $reason = ""
        } elseif ($status.Reason) {
            $avail = "Недоступна"
            $reason = $status.Reason
        }

        # Ollama — если модель установлена локально, она работоспособна
        if ($provId -eq "ollama" -and $status.Available) {
            $isInstalled = $installedOllamaModels -contains $modelId
            if ($isInstalled) { $avail = "Работоспособна"; $reason = "" }
        }

        # Характеристики из конфига (fallback на значения по умолчанию)
        $pbR = if ($modelDef.pb_rating -ne $null) { $modelDef.pb_rating } else { 0 }
        $sqlR = if ($modelDef.sql_rating -ne $null) { $modelDef.sql_rating } else { 0 }
        $spd = if ($modelDef.speed) { $modelDef.speed } else { "—" }
        if ($spd -eq "сервер") { $spd = "сервер" }

        $llmData += [PSCustomObject]@{
            Name = (Get-CleanName $modelDef.name -Fallback $modelId)
            ModelId = "$provId/$modelId"
            Provider = $provName
            ProviderId = $provId
            Available = $avail
            NotAvailableReason = $reason
            LastTested = ""
            Intelligence = Get-IntelligenceLabel $modelDef
            Price = Get-PriceLabel $modelDef.cost
            Limits = Get-LimitsLabel $modelDef.limit
            Allows = Get-AllowsLabel $modelDef.modalities
            Reasoning = Get-ReasoningLabel $modelDef
            PBRating = $pbR
            SQLRating = $sqlR
            Speed = $spd
            ProdUsage = (Get-ProdUsageScore -PB $pbR -SQL $sqlR -Reasoning (Get-ReasoningLabel $modelDef))
        }
    }
}

# ============================================================
# Применение кэша результатов тестирования моделей
# ============================================================

Update-Splash -Text "Применение кэша..."

# Очистка устаревшего кэша (старше 24ч)
try {
    if (Test-Path $testCachePath) {
        $lastWrite = (Get-Item $testCachePath).LastWriteTime
        if (((Get-Date) - $lastWrite).TotalHours -gt 24) { Remove-Item $testCachePath -Force }
    }
} catch { }

$testCache = Get-TestCache -Path $testCachePath
$cacheMaxAge = 0.25

foreach ($m in $llmData) {
    if (-not $m.ProviderId) { continue }
    $cached = $testCache[$m.ModelId]
    if (-not $cached -or -not $cached.TestTime) { continue }

    $age = 0
    try { $age = ((Get-Date) - [datetime]$cached.TestTime).TotalMinutes } catch { continue }
    if ($age -gt ($cacheMaxAge * 60)) { continue }

    $ageLabel = if ($age -lt 1) { "только что" } else { "$([math]::Round($age)) мин назад" }

    if ($cached.Status -eq "OK") {
        $m.Available = "Работоспособна"
        $m.NotAvailableReason = ""
        $m.LastTested = $ageLabel
    } elseif ($cached.Status -eq "TomorrowAvail") {
        $m.Available = "До завтра"
        $m.NotAvailableReason = $cached.Reason
        $m.LastTested = $ageLabel
    } elseif ($cached.Status -eq "Error" -and $cached.Reason) {
        $m.Available = "Недоступна"
        $m.NotAvailableReason = $cached.Reason
        $m.LastTested = $ageLabel
    }
}

# ============================================================
# Авто-тест моделей при запуске DLLM
# — текущая модель (если не локальная/встроенная)
# — все модели с устаревшим кэшем (до 10 шт.)
# ============================================================

Update-Splash -Text "Тестирование моделей..."

function Update-ModelFromTest {
    param($Model, $TestResult, $Cache, $ModelId)
    $now = Get-Date
    if ($TestResult.Status -eq "OK") {
        $Model.Available = "Работоспособна"
        $Model.NotAvailableReason = ""
        $Model.LastTested = "только что"
        $Cache[$ModelId] = @{ Status="OK"; Code=200; Reason=""; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
    } elseif ($TestResult.Status -eq "TomorrowAvail") {
        $Model.Available = "До завтра"
        $Model.NotAvailableReason = $TestResult.Reason
        $Model.LastTested = "только что"
        $Cache[$ModelId] = @{ Status="TomorrowAvail"; Code=$TestResult.Code; Reason=$TestResult.Reason; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
    } elseif ($TestResult.Status -eq "Error") {
        $Model.Available = "Недоступна"
        $Model.NotAvailableReason = $TestResult.Reason
        $Model.LastTested = "только что"
        $Cache[$ModelId] = @{ Status="Error"; Code=$TestResult.Code; Reason=$TestResult.Reason; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
    }
}

$testableProviders = @("anthropic","openai","deepseek","artemox","yandex","google","openrouter")
$maxAutoTests = 10
$autoTestCount = 0

# --- 1. Текущая модель ---
if ($currentModelId -and $currentModelId -notmatch '^(opencode-go|opencode-zen|github-copilot|ollama)/') {
    $currentModelParts = $currentModelId -split '/', 2
    if ($currentModelParts.Count -ge 2) {
        $currentProvId = $currentModelParts[0]
        $currentModelInList = $null
        foreach ($m in $llmData) {
            if ($m.ModelId -eq $currentModelId) { $currentModelInList = $m; break }
        }
        if ($currentModelInList) {
            $testResult = Test-SingleModel -ProvId $currentProvId -ModelId $currentModelId
            Update-ModelFromTest -Model $currentModelInList -TestResult $testResult -Cache $testCache -ModelId $currentModelId
            $autoTestCount++
        }
    }
}

# --- 2. Модели с устаревшим кэшем (провайдеры с прямым тестированием) ---
if ($autoTestCount -lt $maxAutoTests) {
    foreach ($m in $llmData) {
        if ($autoTestCount -ge $maxAutoTests) { break }
        if (-not $m.ProviderId -or $m.ProviderId -notin $testableProviders) { continue }
        if ($m.ModelId -eq $currentModelId) { continue }
        
        $cached = $testCache[$m.ModelId]
        $needTest = $false
        if (-not $cached -or -not $cached.TestTime) {
            $needTest = $true
        } else {
            $age = 0
            try { $age = ((Get-Date) - [datetime]$cached.TestTime).TotalMinutes } catch { }
            if ($age -gt ($cacheMaxAge * 60)) { $needTest = $true }
        }
        
        if ($needTest) {
            $testResult = Test-SingleModel -ProvId $m.ProviderId -ModelId $m.ModelId
            if ($testResult.Status -ne "Skip") {
                Update-ModelFromTest -Model $m -TestResult $testResult -Cache $testCache -ModelId $m.ModelId
                $autoTestCount++
            }
        }
    }
}

if ($autoTestCount -gt 0) {
    Save-TestCache -Path $testCachePath -Cache $testCache
}

Update-Splash -Text "Запуск интерфейса..."
$splash.Close()

$llmData = $llmData | Sort-Object { $_.Available -in @("Работоспособна","До завтра") }, Name -Descending
$availableData = $llmData | Where-Object { $_.Available -in @("Работоспособна","До завтра") }

# WPF окно APPL2
$window = New-Object Windows.Window
$window.Title = "DLLM: все модели ($($llmData.Count))"; $window.Width = 1350; $window.Height = 640
$window.WindowStartupLocation = "CenterScreen"; $window.Topmost = $true
$window.AllowsTransparency = $true; $window.WindowStyle = "None"
$window.Background = "Transparent"; $window.ResizeMode = "CanResizeWithGrip"

$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60; $outerBorder.BorderBrush = "#1A3A60"
$outerBorder.BorderThickness = 1; $outerBorder.Background = "#33FFFFFF"
$shadow = New-Object Windows.Media.Effects.DropShadowEffect
$shadow.Color = "#404040"; $shadow.Direction = 270; $shadow.ShadowDepth = 4; $shadow.BlurRadius = 10; $shadow.Opacity = 0.5
$outerBorder.Effect = $shadow

$cg = New-Object Windows.Controls.Grid
$cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

$tb = New-Object Windows.Controls.Border
$tb.CornerRadius = 10; $tb.Background = "#05FFFFFF"
$tb.Padding = "20,2,20,0"; $tb.Margin = [Windows.Thickness]::new(25,1,25,0)
[Windows.Controls.Grid]::SetRow($tb, 0)
$tb.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

$tg = New-Object Windows.Controls.Grid
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$tl = New-Object Windows.Controls.Grid; $tl.VerticalAlignment = "Center"
$t1 = New-Object Windows.Controls.TextBlock
$t1.Text = "DLLM: модели ($($llmData.Count))"; $t1.FontSize = 16; $t1.FontWeight = "Bold"
$t1.Foreground = "White"; $t1.Margin = [Windows.Thickness]::new(1,1,0,0)
[void]$tl.Children.Add($t1)
$t2 = New-Object Windows.Controls.TextBlock
$t2.Text = "DLLM: модели ($($llmData.Count))"; $t2.FontSize = 16; $t2.FontWeight = "Bold"
$t2.Foreground = "#1A3A60"
[void]$tl.Children.Add($t2)
[Windows.Controls.Grid]::SetColumn($tl, 0); [void]$tg.Children.Add($tl)

function Add-TitleButton {
    param($Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose)
    $b = New-Object Windows.Controls.Button
    $gc = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.TextBlock; $ca.Text=$Text; $ca.FontSize=16; $ca.FontWeight="Bold"
    $ca.Foreground="White"; $ca.Margin=[Windows.Thickness]::new(1,1,0,0); $ca.HorizontalAlignment="Center"; $ca.VerticalAlignment="Center"
    [void]$gc.Children.Add($ca)
    $cb = New-Object Windows.Controls.TextBlock; $cb.Text=$Text; $cb.FontSize=16; $cb.FontWeight="Bold"
    $cb.Foreground="#1A3A60"; $cb.HorizontalAlignment="Center"; $cb.VerticalAlignment="Center"
    [void]$gc.Children.Add($cb)
    $b.Content=$gc; $b.Width=40; $b.Height=34; $b.Cursor="Hand"
    $b.BorderThickness=[Windows.Thickness]::new(3); $b.BorderBrush="#1A3A60"
    $b.HorizontalContentAlignment="Center"; $b.VerticalContentAlignment="Center"; $b.Padding=[Windows.Thickness]::new(0)
    $bg = New-Object Windows.Media.LinearGradientBrush; $bg.StartPoint="0,0"; $bg.EndPoint="0,1"
    [void]$bg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70),0.0)))
    [void]$bg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60),0.5)))
    [void]$bg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50),1.0)))
    $b.Background=$bg; $b.FontSize=16; $b.FontWeight="Bold"; $b.Foreground="#1A3A60"
    $x = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border Name="border" CornerRadius="6" BorderThickness="3" BorderBrush="#1A3A60" Background="{TemplateBinding Background}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate>'
    try { $r = New-Object System.Xml.XmlNodeReader ([xml]$x).DocumentElement; $b.Template = [Windows.Markup.XamlReader]::Load($r) } catch {}
    [Windows.Controls.Grid]::SetColumn($b,$Col)
    $b.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose){"#40E81123"}else{"#401A3A60"})) })
    $b.Add_MouseLeave({
        $b2 = New-Object Windows.Media.LinearGradientBrush; $b2.StartPoint="0,0"; $b2.EndPoint="0,1"
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70),0.0)))
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60),0.5)))
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50),1.0)))
        $this.Background = $b2
    })
    if ($Click) { $b.Add_Click($Click) }
    return $b
}

$minB = Add-TitleButton -Text "━" -Col 1 -Click { $window.WindowState = "Minimized" }
$maxB = Add-TitleButton -Text "▣" -Col 2 -Click { if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal" } else { $window.WindowState = "Maximized" } }
$cloB = Add-TitleButton -Text "✕" -Col 3 -Click { $window.Close() } -IsClose
[void]$tg.Children.Add($minB); [void]$tg.Children.Add($maxB); [void]$tg.Children.Add($cloB)
$tb.Child = $tg; [void]$cg.Children.Add($tb)

$cw = New-Object Windows.Controls.Border
$cw.Background="#1A3A60"; $cw.CornerRadius=46; $cw.Margin=[Windows.Thickness]::new(4,0,4,4)
[Windows.Controls.Grid]::SetRow($cw, 1)

$mb = New-Object Windows.Controls.Border
$mb.CornerRadius=42; $mb.Background="White"; $mb.Padding="20,16,20,22"; $mb.Margin=[Windows.Thickness]::new(4)

$grid = New-Object Windows.Controls.Grid
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

$pbTest = New-Object Windows.Controls.ProgressBar
$pbTest.Minimum = 0; $pbTest.Maximum = 100; $pbTest.Value = 0
$pbTest.Visibility = "Collapsed"; $pbTest.Margin = [Windows.Thickness]::new(0,0,0,6)
Apply-GlossyProgressStyle -ProgressBar $pbTest -BarColorTop "#1A3A60" -BarColorBottom "#2B6CB0"
[Windows.Controls.Grid]::SetRow($pbTest, 2); [void]$grid.Children.Add($pbTest)

$info = New-Object Windows.Controls.TextBlock
$avail = ($llmData | Where-Object { $_.Available -in @("Работоспособна","До завтра") }).Count
$notAvail = $llmData.Count - $avail
$info.Text = "Всего: $($llmData.Count) | Работоспособно: $avail | Недоступно: $notAvail | Текущая: $currentModelId"
if ($envKeyWarnings.Count -gt 0) {
    $info.Text += " | Process-ключи: " + ($envKeyWarnings -join "; ")
    $info.Foreground = "#E53E3E"
    $info.FontWeight = "Bold"
}
$info.FontSize = 11; $info.Foreground = "#4A5568"; $info.Margin = [Windows.Thickness]::new(0,0,0,2)

function Sort-ML { param($D,$L)
    if ($L.Count -eq 0) { return $D | Sort-Object { $_.Available -in @("Работоспособна","До завтра") }, Name -Descending }
    # Добавляем временное свойство для сортировки вместо [scriptblock]::Create
    $pM = $priceM; $iM = $intM
    $temp = $D | ForEach-Object {
        $keys = @()
        for ($j = 0; $j -lt $L.Count; $j++) {
            $fd = $L[$j].Field; $dc = $L[$j].Desc
            $v = $null
            if ($fd -eq "Price") { $v = $pM[$_.Price] }
            elseif ($fd -eq "Intelligence") { $v = $iM[$_.Intelligence] }
            elseif ($fd -eq "Reasoning") { $v = $iM[$_.Reasoning] }
            else { $v = $_.$fd }
            if ($v -eq $null) { $v = "" }
            if ($dc -and $v -is [int]) { $v = -$v }
            elseif ($dc -and $v -is [string]) { $v = [char]::MaxValue + $v }  # для обратной сортировки строк
            $keys += $v
        }
        $_ | Add-Member -NotePropertyName "_sortKeys" -NotePropertyValue $keys -Force -PassThru
    }
    $sorted = $temp | Sort-Object { $_._sortKeys[0] }, { $_._sortKeys[1] }, { $_._sortKeys[2] }
    # Удаляем временное свойство
    $sorted | ForEach-Object { $_.PSObject.Properties.Remove("_sortKeys"); $_ }
}

# --- Многоуровневая сортировка ---
$sfOpts = @(@{L="Название";F="Name"},@{L="Провайдер";F="Provider"},@{L="Цена";F="Price"},
            @{L="Мощность";F="Intelligence"},@{L="Рассуждение";F="Reasoning"},@{L="PB";F="PBRating"},
            @{L="SQL";F="SQLRating"},@{L="Скорость";F="Speed"},@{L="PROD";F="ProdUsage"},@{L="Статус";F="Available"})
$priceM = @{"Бесплатная"=0;"Низкая"=1;"Средняя"=2;"Высокая"=3;"Очень высокая"=4}
$intM = @{"Нет"=0;"Есть"=1;"Chain-of-Thought"=2;"Глубокое"=3}
$sfCbs = @(); $sdCbs = @()
$sb = New-Object Windows.Controls.Border; $sb.Background="#EDF2F7"; $sb.CornerRadius=4; $sb.Padding="6,2,6,2"
$sp = New-Object Windows.Controls.StackPanel; $sp.Orientation="Horizontal"
$lbl = New-Object Windows.Controls.TextBlock; $lbl.Text="Сорт:"; $lbl.FontWeight="Bold"; $lbl.VerticalAlignment="Center"; $lbl.Margin="0,0,4,0"
[void]$sp.Children.Add($lbl)
for ($i = 0; $i -lt 3; $i++) {
    $cf = New-Object Windows.Controls.ComboBox; $cf.ItemsSource=$sfOpts.L; $cf.SelectedIndex=$i
    $cf.Width=115; $cf.FontSize=10; $cf.Margin="1,0,1,0"
    $cd = New-Object Windows.Controls.ComboBox; $cd.ItemsSource=@("↑","↓"); $cd.SelectedIndex=0
    $cd.Width=36; $cd.FontSize=10; $cd.Margin="1,0,4,0"
    $sfCbs+=$cf; $sdCbs+=$cd; [void]$sp.Children.Add($cf); [void]$sp.Children.Add($cd)
}
$st = New-Object Windows.Controls.TextBlock; $st.FontSize=10; $st.Foreground="#718096"
$st.VerticalAlignment="Center"; $st.Margin="4,0,4,0"; [void]$sp.Children.Add($st)
$bS = New-Object Windows.Controls.Button; $bS.Content="Сорт"; $bS.Width=44; $bS.Height=22; $bS.FontSize=10
$bS.Add_Click({
    try {
        $levels = @(); $parts = @()
        for ($i = 0; $i -lt 3; $i++) {
            $idx = $sfCbs[$i].SelectedIndex; if ($idx -lt 0) { continue }
            $f = $sfOpts[$idx].F; $d = ($sdCbs[$i].SelectedIndex -eq 1)
            $levels += @{Field=$f;Desc=$d}; $parts += "$($sfOpts[$idx].L)$(if($d){'↓'}else{'↑'})"
        }
        $sa = @(Sort-ML -D $llmData -L $levels)
        $sv = @($sa | Where-Object { $_.Available -in @("Работоспособна","До завтра") })
        $dgAll.ItemsSource = $null; $dgAvailable.ItemsSource = $null  # Сброс перед установкой
        $dgAll.ItemsSource = $sa; $dgAvailable.ItemsSource = $sv
        try { [Windows.Data.CollectionViewSource]::GetDefaultView($dgAll.ItemsSource).SortDescriptions.Clear() } catch {}
        try { [Windows.Data.CollectionViewSource]::GetDefaultView($dgAvailable.ItemsSource).SortDescriptions.Clear() } catch {}
        $tabAvailable.Header = "Работоспособные ($($sv.Count))"; $tabAll.Header = "Все модели ($($sa.Count))"
        $info.Text = "Всего: $($sa.Count) | Работоспособно: $($sv.Count) | Недоступно: $($sa.Count - $sv.Count) | Текущая: $currentModelId"
        if ($envKeyWarnings.Count -gt 0) { $info.Text += " | Process-ключи: " + ($envKeyWarnings -join "; "); $info.Foreground="#E53E3E"; $info.FontWeight="Bold" }
        if ($parts.Count -gt 0) { $st.Text = "Сортировка: " + ($parts -join " > ") } else { $st.Text = "" }
    } catch {
        $st.Text = "Ошибка: $_"
        $st.Foreground = "#E53E3E"
    }
})
[void]$sp.Children.Add($bS); $sb.Child = $sp
$ts = New-Object Windows.Controls.StackPanel; $ts.Orientation="Vertical"
[void]$ts.Children.Add($info); [void]$ts.Children.Add($sb)
[Windows.Controls.Grid]::SetRow($ts, 0); [void]$grid.Children.Add($ts)

$tabControl = New-Object Windows.Controls.TabControl
$tabControl.Margin = [Windows.Thickness]::new(0,0,0,4); $tabControl.FontSize = 11
[Windows.Controls.Grid]::SetRow($tabControl, 1); [void]$grid.Children.Add($tabControl)

$colDefs = @(
    @("Название LLM","Name",180),@("Провайдер","Provider",110),
    @("PB","PBRating",45),@("SQL","SQLRating",45),
    @("PROD","ProdUsage",55),@("tok/s","Speed",65),
    @("Цена","Price",110),@("Разрешено","Allows",120),
    @("Лимиты","Limits",100),@("Мощность","Intelligence",200),
    @("Рассуждение","Reasoning",90),@("ID модели","ModelId",180),
    @("Статус","Available",90),@("Проверено","LastTested",100),@("Причина","NotAvailableReason",350)
)

function New-LLMDataGrid {
    param($Data)
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true
    $dg.HeadersVisibility = "All"; $dg.RowHeaderWidth = 0
    $dg.AlternatingRowBackground = "#F5F7FA"; $dg.FontSize = 11
    $dg.Background = "Transparent"; $dg.RowBackground = "White"
    $dg.BorderThickness = [Windows.Thickness]::new(1); $dg.BorderBrush = "#CBD5E0"
    $dg.CanUserResizeRows = $true; $dg.CanUserSortColumns = $true; $dg.GridLinesVisibility = "None"
    $dg.SelectionMode = "Single"; $dg.SelectionUnit = "FullRow"
    $dg.VerticalScrollBarVisibility = "Visible"; $dg.HorizontalScrollBarVisibility = "Visible"
        foreach ($cd in $colDefs) {
            $col = New-Object Windows.Controls.DataGridTextColumn
            $col.Header = $cd[0]; $col.Binding = [Windows.Data.Binding]::new($cd[1]); $col.Width = $cd[2]
            $col.ElementStyle = New-Object Windows.Style([Windows.Controls.TextBlock])
            $col.ElementStyle.Setters.Add((New-Object Windows.Setter([Windows.Controls.TextBlock]::TextWrappingProperty, [Windows.TextWrapping]::Wrap)))
            [void]$dg.Columns.Add($col)
        }
    $dg.ItemsSource = $Data
    $dg.Add_LoadingRow({
        $row = $_.Row; $item = $row.DataContext
        if ($item -and $item.Available -notin @("Работоспособна","До завтра")) {
            $row.Foreground = "#718096"
            $row.FontStyle = "Italic"
        }
    })
    $dg.Add_Loaded({
        $dg2 = $this; $src = $dg2.ItemsSource
        if (-not $src) { return }
        for ($i = 0; $i -lt $src.Count; $i++) {
            if ($src[$i].ModelId -eq $currentModelId) { $dg2.SelectedIndex = $i; $dg2.ScrollIntoView($dg2.Items[$i]); break }
        }
    })
    return $dg
}

$tabAvailable = New-Object Windows.Controls.TabItem
$tabAvailable.Header = "Доступные ($($availableData.Count))"
$tabAvailable.FontSize = 12; $tabAvailable.FontWeight = "Bold"
$dgAvailable = New-LLMDataGrid -Data $availableData
$tabAvailable.Content = $dgAvailable
[void]$tabControl.Items.Add($tabAvailable)

$tabAll = New-Object Windows.Controls.TabItem
$tabAll.Header = "Все модели ($($llmData.Count))"
$tabAll.FontSize = 12; $tabAll.FontWeight = "Bold"
$dgAll = New-LLMDataGrid -Data $llmData
$tabAll.Content = $dgAll
[void]$tabControl.Items.Add($tabAll)

function Get-ActiveDataGrid {
    if ($tabControl.SelectedIndex -eq 0) { return $dgAvailable }
    return $dgAll
}

$tabControl.Add_SelectionChanged({
    $dg = Get-ActiveDataGrid; $data = $dg.ItemsSource
    for ($i = 0; $i -lt $data.Count; $i++) { 
        if ($data[$i].ModelId -eq $currentModelId) { 
            # Временно переключаем на FullRow для выделения текущей модели
            $oldUnit = $dg.SelectionUnit
            $dg.SelectionUnit = "FullRow"
            $dg.SelectedIndex = $i
            $dg.ScrollIntoView($dg.Items[$i])
            $dg.SelectionUnit = $oldUnit
            break 
        } 
    }
})

$bp = New-Object Windows.Controls.StackPanel
$bp.Orientation = "Horizontal"; $bp.HorizontalAlignment = "Center"; $bp.Margin = [Windows.Thickness]::new(0,6,0,0)

$bSw = New-Object Windows.Controls.Button
$bSw.Content = "Переключиться на выбранную LLM"; $bSw.Width = 300; $bSw.Height = 36
$bSw.Margin = [Windows.Thickness]::new(0,0,8,0); $bSw.IsDefault = $true
Apply-GlossyButtonStyle -Button $bSw
$bSw.Add_Click({
    $dg = Get-ActiveDataGrid
    # Получаем выбранный элемент независимо от режима выделения
    $sel = $null
    if ($dg.SelectedItem) {
        $sel = $dg.SelectedItem
    } elseif ($dg.SelectedCells.Count -gt 0) {
        $sel = $dg.SelectedCells[0].Item
    }
    if (-not $sel) { [System.Windows.MessageBox]::Show("Выберите LLM из списка.", "Нет выбора", "OK", "Information"); return }
    if ($sel.Available -eq "Не проверено") {
        $checkResult = [System.Windows.MessageBox]::Show("Модель '$($sel.Name)' не проверена.`nВыполнить быструю проверку перед переключением?", "Не проверено", "YesNo", "Question")
        if ($checkResult -eq "Yes") {
            $provId = ($sel.ModelId -split '/')[0]
            $testResult = Test-SingleModel -ProvId $provId -ModelId $sel.ModelId
            if ($testResult.Status -eq "OK") {
                $sel.Available = "Работоспособна"
                $sel.NotAvailableReason = ""
                $dg.ItemsSource = $dg.ItemsSource
            } elseif ($testResult.Status -eq "TomorrowAvail") {
                $sel.Available = "До завтра"
                $sel.NotAvailableReason = $testResult.Reason
                $dg.ItemsSource = $dg.ItemsSource
            } else {
                $sel.Available = "Недоступна"
                $sel.NotAvailableReason = $testResult.Reason
                $dg.ItemsSource = $dg.ItemsSource
                [System.Windows.MessageBox]::Show("Модель '$($sel.Name)' недоступна: $($testResult.Reason)", "Ошибка проверки", "OK", "Error")
                return
            }
        } else {
            return
        }
    }
    if ($sel.Available -notin @("Работоспособна","До завтра")) { [System.Windows.MessageBox]::Show("Модель '$($sel.Name)' недоступна: $($sel.NotAvailableReason)", "Недоступна", "OK", "Error"); return }
    $newModelId = $sel.ModelId; $newName = $sel.Name
    $confirm = [System.Windows.MessageBox]::Show("Переключиться на '$newName' ($newModelId)?`nПотребуется перезапуск сессии в OpenCode.", "Подтверждение", "YesNo", "Question")
    if ($confirm -ne "Yes") { return }
    try {
        $content = Get-Content $configPath -Raw -Encoding UTF8
        $replaceModel = '"model": "' + $newModelId + '"'
        $replaceSmall = '"small_model": "' + $newModelId + '"'
        $newContent = $content -replace '"model"\s*:\s*"[^"]*"', $replaceModel
        $newContent = $newContent -replace '"small_model"\s*:\s*"[^"]*"', $replaceSmall
        Set-Content -Path $configPath -Value $newContent -Encoding UTF8
        [System.Windows.MessageBox]::Show("Модель переключена на '$newName'.`nПерезапустите OpenCode для применения.", "Готово", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка: $_", "Ошибка", "OK", "Error") }
})
[void]$bp.Children.Add($bSw)

$bCh = New-Object Windows.Controls.Button
$bCh.Content = "Проверить все"; $bCh.Width = 150; $bCh.Height = 36
$bCh.Margin = [Windows.Thickness]::new(0,0,8,0)
Apply-GlossyButtonStyle -Button $bCh -ColorTop "#2A5080" -ColorBottom "#87CEEB"
$bCh.Add_Click({
    $bCh.IsEnabled = $false; $bSw.IsEnabled = $false
    $bCh.Content = "Проверка..."
    $pbTest.Visibility = "Visible"; $pbTest.Value = 0

    # Clean test results dir
    $resultDir = Join-Path $projectRoot "temp\llm_test"
    if (Test-Path $resultDir) { Remove-Item "$resultDir\*" -Force -ErrorAction SilentlyContinue }
    else { New-Item -ItemType Directory -Path $resultDir -Force | Out-Null }

    # Start Test-LLM.ps1 for each model in parallel
    $jobs = @()
    foreach ($m in $llmData) {
        if (-not $m.ProviderId) { continue }
        # Skip config providers (opencode-go, opencode-zen, github-copilot) - tested via opencode run
        if ($m.ProviderId -in @("opencode-go","opencode-zen","github-copilot","ollama")) { continue }
        $scriptPath = Join-Path $PSScriptRoot "Test-LLM.ps1"
        $providerId = $m.ProviderId
        $modelId = $m.ModelId
        $cleanModelId = $modelId -replace "^$providerId/", ""
        $modelArg = "$providerId/$cleanModelId"
        $proc = Start-Process powershell -ArgumentList "-NoLogo -STA -File `"$scriptPath`" -ModelName `"$modelArg`"" -PassThru -WindowStyle Minimized
        $jobs += @{ Proc=$proc; Model=$m }
    }

    if ($jobs.Count -eq 0) {
        $pbTest.Visibility = "Collapsed"
        $bCh.Content = "Проверить все"
        $bCh.IsEnabled = $true; $bSw.IsEnabled = $true
        return
    }

    $pbTest.Maximum = $jobs.Count; $pbTest.Value = 0
    $completed = 0
    $timeout = 120
    $endTime = [DateTime]::Now.AddSeconds($timeout)

    while ($completed -lt $jobs.Count -and [DateTime]::Now -lt $endTime) {
        foreach ($job in $jobs) {
            if (-not $job.Completed -and $job.Proc.HasExited) {
                $job.Completed = $true
                $completed++
                $pbTest.Value = $completed
                $info.Text = "Проверено $completed/$($jobs.Count)..."
            }
        }
        if ($completed -ge $jobs.Count) { break }
        # Неблокирующее ожидание: обрабатываем сообщения UI (DragMove, клики)
        $frame = New-Object Windows.Threading.DispatcherFrame
        $timer = New-Object Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $timer.Tag = $frame
        $timer.Add_Tick({
            $timer.Stop()
            $timer.Tag.Continue = $false
        })
        $timer.Start()
        [Windows.Threading.Dispatcher]::PushFrame($frame)
    }

    # Kill any still running
    foreach ($job in $jobs) {
        if (-not $job.Proc.HasExited) { $job.Proc.Kill() }
    }

    # Collect results
    $testCacheNew = @{}
    $now = Get-Date
    foreach ($job in $jobs) {
        $m = $job.Model
        $safeName = ($m.ProviderId + "/" + ($m.ModelId -replace "^$($m.ProviderId)/", "")) -replace '[/\\:<>"|?*]', '_'
        $resultFile = Join-Path $resultDir "$safeName.log"
        if (Test-Path $resultFile) {
            $content = Get-Content $resultFile -Raw -Encoding UTF8
            if ($content -eq "Ok") {
                $m.Available = "Работоспособна"
                $m.NotAvailableReason = ""
                $testCacheNew[$m.ModelId] = @{ Status="OK"; Code=200; Reason=""; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
            } elseif ($content -like "TomorrowAvail*") {
                $m.Available = "До завтра"
                $m.NotAvailableReason = $content -replace "^TomorrowAvail:\s*", ""
                $testCacheNew[$m.ModelId] = @{ Status="TomorrowAvail"; Code=429; Reason=$m.NotAvailableReason; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
            } else {
                $m.Available = "Недоступна"
                $m.NotAvailableReason = $content -replace "^Error:\s*", ""
                $testCacheNew[$m.ModelId] = @{ Status="Error"; Code=0; Reason=$m.NotAvailableReason; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
            }
        } else {
            $m.Available = "Недоступна"
            $m.NotAvailableReason = "Таймаут"
            $testCacheNew[$m.ModelId] = @{ Status="Error"; Code=0; Reason="Таймаут"; TestTime=$now.ToString("yyyy-MM-dd HH:mm:ss") }
        }
    }

    # Preserve cached results for skipped providers (opencode-go, opencode-zen, github-copilot)
    foreach ($m in $llmData) {
        if (-not $m.ProviderId) { continue }
        if ($m.ProviderId -in @("opencode-go","opencode-zen","github-copilot")) {
            $cached = $testCache[$m.ModelId]
            if ($cached) { $testCacheNew[$m.ModelId] = $cached }
        }
    }

    $testCache = $testCacheNew
    Save-TestCache -Path $testCachePath -Cache $testCacheNew

    $sortedAll = @($llmData | Sort-Object { $_.Available -in @("Работоспособна","До завтра") }, Name -Descending)
    $sortedAvail = @($sortedAll | Where-Object { $_.Available -in @("Работоспособна","До завтра") })
    $dgAll.ItemsSource = $sortedAll; $dgAvailable.ItemsSource = $sortedAvail
    $tabAvailable.Header = "Работоспособные ($($sortedAvail.Count))"
    $tabAll.Header = "Все модели ($($sortedAll.Count))"
    $info.Text = "Всего: $($sortedAll.Count) | Работоспособно: $($sortedAvail.Count) | Недоступно: $($sortedAll.Count - $sortedAvail.Count) | Текущая: $currentModelId | Проверено: $(Get-Date -Format 'HH:mm')"
    if ($envKeyWarnings.Count -gt 0) {
        $info.Text += " | Process-ключи: " + ($envKeyWarnings -join "; ")
        $info.Foreground = "#E53E3E"
        $info.FontWeight = "Bold"
    }

    $pbTest.Visibility = "Collapsed"
    $bCh.Content = "Проверить все"
    $bCh.IsEnabled = $true; $bSw.IsEnabled = $true
})
[void]$bp.Children.Add($bCh)

$bFixKeys = New-Object Windows.Controls.Button
$bFixKeys.Content = "Исправить ключи"; $bFixKeys.Width = 150; $bFixKeys.Height = 36
$bFixKeys.Margin = [Windows.Thickness]::new(0,0,8,0)
Apply-GlossyButtonStyle -Button $bFixKeys -ColorTop "#2A5080" -ColorBottom "#87CEEB"
$bFixKeys.Add_Click({
    $fixScript = Join-Path $PSScriptRoot "Copy-ApiKeysToMachine.ps1"
    if (Test-Path $fixScript) {
        $result = [System.Windows.MessageBox]::Show("Запустить исправление API-ключей?`nТребуются права администратора для Machine-уровня.", "Исправить ключи", "YesNo", "Question")
        if ($result -eq "Yes") {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoLogo -File `"$fixScript`"" -Wait
            [System.Windows.MessageBox]::Show("Ключи скопированы. Перезапустите DLLM для проверки.", "Готово", "OK", "Information")
        }
    } else {
        [System.Windows.MessageBox]::Show("Скрипт Copy-ApiKeysToMachine.ps1 не найден.", "Ошибка", "OK", "Error")
    }
})
[void]$bp.Children.Add($bFixKeys)

$bCl = New-Object Windows.Controls.Button
$bCl.Content = "Закрыть"; $bCl.Width = 120; $bCl.Height = 36
Apply-GlossyButtonStyle -Button $bCl -ColorTop "#606060" -ColorBottom "#808080"
$bCl.Add_Click({ $window.Close() })
[void]$bp.Children.Add($bCl)

[Windows.Controls.Grid]::SetRow($bp, 3); [void]$grid.Children.Add($bp)

$mb.Child = $grid; $cw.Child = $mb
[void]$cg.Children.Add($cw)
$outerBorder.Child = $cg; $window.Content = $outerBorder
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
[void]$window.ShowDialog()