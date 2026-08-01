[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ModelName
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Parse provider/model from ModelName (e.g. "routerai/openai/gpt-4o-mini")
$parts = $ModelName.Split('/')
if ($parts.Length -lt 2) {
    Write-Output "Error $ModelName : format must be provider/model"
    exit 1
}
$providerID = $parts[0]
$modelID = $parts[1..($parts.Length-1)] -join '/'

# Safe filename from ModelName
$safeName = $ModelName -replace '[/\\:<>"|?*]', '_'
$resultDir = Join-Path $PSScriptRoot "..\temp\llm_test"
if (-not (Test-Path $resultDir)) {
    $nul = New-Item -ItemType Directory -Path $resultDir -Force
}
$resultFile = Join-Path $resultDir "$safeName.log"

# Read config for provider settings
$configDir = Join-Path $PSScriptRoot "..\config"
$configPath = Join-Path $configDir "config.json"
$config = @{}
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Read opencode.jsonc for provider model configs
$opencodeConfigPath = Join-Path $PSScriptRoot "..\opencode.jsonc"
$opencodeConfig = @{}
if (Test-Path $opencodeConfigPath) {
    $opencodeConfig = Get-Content $opencodeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-EnvVar {
    param([string]$Name)
    $v = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "User") }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, "Machine") }
    return $v
}

$result = ""
try {
    $url = $null; $headers = @{}; $body = $null; $timeout = 30
    $apiModelId = $modelID

    switch ($providerID) {
        "routerai" {
            $key = Get-EnvVar "ROUTERAI_API_KEY"
            if (-not $key) { throw "Нет ключа ROUTERAI_API_KEY" }
            $url = "https://routerai.ru/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"; "Content-Type"="application/json"}
            # RouterAI needs full model ID (e.g., anthropic/claude-haiku-4.5)
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "anthropic" {
            $key = Get-EnvVar "ANTHROPIC_API_KEY"
            if (-not $key -or $key.Length -le 20) { throw "Нет ключа ANTHROPIC_API_KEY" }
            $url = "https://api.anthropic.com/v1/messages"
            $headers = @{"x-api-key"=$key; "anthropic-version"="2023-06-01"; "Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "openai" {
            $key = Get-EnvVar "OPENAI_API_KEY"
            if (-not $key) { throw "Нет ключа OPENAI_API_KEY" }
            $url = "https://api.openai.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"; "Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "deepseek" {
            $key = Get-EnvVar "DEEPSEEK_API_KEY"
            if (-not $key) { throw "Нет ключа DEEPSEEK_API_KEY" }
            $url = "https://api.deepseek.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"; "Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "artemox" {
            $key = Get-EnvVar "ARTEMOX_API_KEY"
            if (-not $key) { throw "Нет ключа ARTEMOX_API_KEY" }
            $url = "https://api.artemox.com/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"; "Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "yandex" {
            $key = Get-EnvVar "YANDEX_API_KEY"
            if (-not $key) { throw "Нет ключа YANDEX_API_KEY" }
            $folderId = if ($opencodeConfig.provider.yandex.folderId) { $opencodeConfig.provider.yandex.folderId } else { "b1ghbd3js0u0ru6djp4q" }
            $url = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
            $headers = @{"Authorization"="Api-Key $key"; "x-folder-id"=$folderId; "Content-Type"="application/json"}
            $body = '{"modelUri":"gpt://' + $folderId + '/' + $apiModelId + '/latest","completionOptions":{"stream":false,"temperature":0,"maxTokens":5},"messages":[{"role":"user","text":"Reply: Ok"}]}'
            $timeout = 5
        }
        "google" {
            $key = Get-EnvVar "GOOGLE_API_KEY"
            if (-not $key) { throw "Нет ключа GOOGLE_API_KEY" }
            $url = "https://generativelanguage.googleapis.com/v1beta/models/" + $apiModelId + ":generateContent?key=" + $key
            $headers = @{"Content-Type"="application/json"}
            $body = '{"contents":[{"parts":[{"text":"Reply: Ok"}]}]}'
        }
        "openrouter" {
            $key = Get-EnvVar "OPENROUTER_API_KEY"
            if (-not $key) { throw "Нет ключа OPENROUTER_API_KEY" }
            $url = "https://openrouter.ai/api/v1/chat/completions"
            $headers = @{Authorization="Bearer $key"; "Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","max_tokens":5,"temperature":0,"messages":[{"role":"user","content":"Reply: Ok"}]}'
        }
        "ollama" {
            $url = "http://localhost:11434/api/chat"
            $headers = @{"Content-Type"="application/json"}
            $body = '{"model":"' + $apiModelId + '","messages":[{"role":"user","content":"Reply: Ok"}],"stream":false}'
            $timeout = 10
        }
        "opencode-zen" {
            $url = "cli://opencode"
            $serverUrl = "http://localhost:4096"
            $user = "opencode"
            $pass = $env:OPENCODE_SERVER_PASSWORD
            $cmd = "& `"$env:APPDATA\npm\opencode.ps1`" run --attach $serverUrl -u $user -p $pass -m $apiModelId -- 'Reply: Ok'"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -Command `"$cmd`"" -Wait -PassThru -RedirectStandardOutput "$env:TEMP\opencode_test_$safeName.out" -RedirectStandardError "$env:TEMP\opencode_test_$safeName.err"
            $output = Get-Content "$env:TEMP\opencode_test_$safeName.out" -Raw -ErrorAction SilentlyContinue
            $err = Get-Content "$env:TEMP\opencode_test_$safeName.err" -Raw -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0 -and $output -match "Ok") {
                $result = "Ok"
            } elseif ($output -match "Model not found") {
                $result = "Error: Model not found in server"
            } elseif ($err -match "402|429|rate limit|quota|limit exceeded|limit reached|limit exceeded|insufficient credits|credit balance|too many requests") {
                $result = "TomorrowAvail: Лимит исчерпан, восстановятся завтра"
            } else {
                $result = "Error: ExitCode=$($proc.ExitCode) Output=$output Err=$err"
            }
        }
        "opencode-go" {
            $url = "cli://opencode"
            $serverUrl = "http://localhost:4096"
            $user = "opencode"
            $pass = $env:OPENCODE_SERVER_PASSWORD
            $cmd = "& `"$env:APPDATA\npm\opencode.ps1`" run --attach $serverUrl -u $user -p $pass -m $apiModelId -- 'Reply: Ok'"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -Command `"$cmd`"" -Wait -PassThru -RedirectStandardOutput "$env:TEMP\opencode_test_$safeName.out" -RedirectStandardError "$env:TEMP\opencode_test_$safeName.err"
            $output = Get-Content "$env:TEMP\opencode_test_$safeName.out" -Raw -ErrorAction SilentlyContinue
            $err = Get-Content "$env:TEMP\opencode_test_$safeName.err" -Raw -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0 -and $output -match "Ok") {
                $result = "Ok"
            } elseif ($output -match "Model not found") {
                $result = "Error: Model not found in server"
            } elseif ($err -match "402|429|rate limit|quota|limit exceeded|limit reached|limit exceeded|insufficient credits|credit balance|too many requests") {
                $result = "TomorrowAvail: Лимит исчерпан, восстановятся завтра"
            } else {
                $result = "Error: ExitCode=$($proc.ExitCode) Output=$output Err=$err"
            }
        }
        "github-copilot" {
            $url = "cli://opencode"
            $serverUrl = "http://localhost:4096"
            $user = "opencode"
            $pass = $env:OPENCODE_SERVER_PASSWORD
            $cmd = "& `"$env:APPDATA\npm\opencode.ps1`" run --attach $serverUrl -u $user -p $pass -m $apiModelId -- 'Reply: Ok'"
            $proc = Start-Process powershell -ArgumentList "-NoProfile -Command `"$cmd`"" -Wait -PassThru -RedirectStandardOutput "$env:TEMP\opencode_test_$safeName.out" -RedirectStandardError "$env:TEMP\opencode_test_$safeName.err"
            $output = Get-Content "$env:TEMP\opencode_test_$safeName.out" -Raw -ErrorAction SilentlyContinue
            $err = Get-Content "$env:TEMP\opencode_test_$safeName.err" -Raw -ErrorAction SilentlyContinue
            if ($proc.ExitCode -eq 0 -and $output -match "Ok") {
                $result = "Ok"
            } elseif ($output -match "Model not found") {
                $result = "Error: Model not found in server"
            } elseif ($err -match "402|429|rate limit|quota|limit exceeded|limit reached|limit exceeded|insufficient credits|credit balance|too many requests") {
                $result = "TomorrowAvail: Лимит исчерпан, восстановятся завтра"
            } else {
                $result = "Error: ExitCode=$($proc.ExitCode) Output=$output Err=$err"
            }
        }
        default {
            throw "Провайдер '$providerID' не поддерживает прямое тестирование"
        }
    }

    # Skip HTTP request for providers tested via opencode CLI
    if ($providerID -in @("opencode-zen","opencode-go","github-copilot")) {
        # Result already set in switch block
    } else {
        if (-not $url) { throw "URL не определён" }

        $r = Invoke-WebRequest -Uri $url -Method Post -Body $body -ContentType "application/json" -Headers $headers -UseBasicParsing -TimeoutSec $timeout
        $content = $r.Content
        $valid = $false

    if ($providerID -eq "anthropic") {
        $valid = ($content -match '"type"\s*:\s*"message"')
    } elseif ($providerID -eq "ollama") {
        $valid = ($content -match '"message"')
    } else {
        $valid = ($content -match '"choices"')
    }

    if ($r.StatusCode -eq 200 -and $valid) {
        $result = "Ok"
    } elseif ($r.StatusCode -eq 200 -and -not $valid) {
        $result = "Error: API 200, но структура ответа не распознана"
    } elseif ($r.StatusCode -ge 400 -and $content -match '"type"\s*:\s*"error"') {
        $errMsg = ""
        if ($content -match '"message"\s*:\s*"([^"]+)"') { $errMsg = $matches[1] }
        $result = "Error: HTTP $($r.StatusCode) - $errMsg"
    } else {
        $result = "Error: HTTP $($r.StatusCode)"
    }
}  # End of else block for HTTP providers
} catch {
    $errMsg = $_.Exception.Message.Trim()
    $sc = 0
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $sc = [int]$_.Exception.Response.StatusCode
        if ($sc -eq 401 -or $sc -eq 403) { $result = "Error: Невалидный ключ ($sc)" }
        elseif ($sc -eq 404) { $result = "Error: Модель не найдена ($sc)" }
        elseif ($sc -eq 402 -or $sc -eq 429) { $result = "TomorrowAvail: Лимиты исчерпаны, восстановятся завтра" }
        elseif ($sc -ge 400) { $result = "Error: HTTP $sc" }
        else { $result = "Error: HTTP $sc" }
    } else {
        if ($errMsg.Length -gt 200) { $errMsg = $errMsg.Substring(0,200) + "..." }
        $result = "Error: $errMsg"
    }
}

# Write result - just "Ok" or "Error: ..."
Set-Content -Path $resultFile -Value $result -NoNewline -Encoding UTF8