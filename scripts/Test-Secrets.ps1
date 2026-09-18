# Test-Secrets.ps1 — проверка и восстановление хранилища секретов ВНЕ репозитория Git
#
# Хранилище: %USERPROFILE%\.ais-secrets  (вне C:\AIS\AI\Prod, в Git не попадает)
# Конфиги OpenCode ссылаются на файлы через {file:~/.ais-secrets/...}
#
# Использование:
#   powershell -NoLogo -File scripts\Test-Secrets.ps1            # проверка (офлайн)
#   powershell -NoLogo -File scripts\Test-Secrets.ps1 -Online    # + сетевые проверки Jira/Confluence
#   powershell -NoLogo -File scripts\Test-Secrets.ps1 -Init      # создать структуру и пустые шаблоны
#
# Значения секретов скрипт НЕ печатает.

Param(
    [switch]$Init,
    [switch]$Online
)

$ErrorActionPreference = "Stop"

$SecretsRoot = Join-Path $env:USERPROFILE ".ais-secrets"
$EwsFile     = Join-Path $env:USERPROFILE ".config\ews-mcp\credentials.env"
$ProjectSecrets = Join-Path $PSScriptRoot "..\config\.local_secrets.json"

# Описание ожидаемых секретов: файл, потребитель, обязателен ли
$SecretDefs = @(
    [PSCustomObject]@{ Name = "jira_token.txt";          Path = Join-Path $SecretsRoot "opencode\jira_token.txt";          Consumer = "MCP atlassian (Jira PAT)";        Required = $true },
    [PSCustomObject]@{ Name = "confluence_password.txt"; Path = Join-Path $SecretsRoot "opencode\confluence_password.txt"; Consumer = "MCP atlassian (Confluence Basic)"; Required = $true },
    [PSCustomObject]@{ Name = "google_api_key.txt";      Path = Join-Path $SecretsRoot "opencode\google_api_key.txt";      Consumer = "provider google";                 Required = $false }
)

function New-SecretsStructure {
    $dirs = @(
        (Join-Path $SecretsRoot "opencode"),
        (Join-Path $SecretsRoot "ews")
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Write-Host "[создано] $d" -ForegroundColor Green
        }
    }
    # Внимание: пишем БЕЗ BOM (Set-Content -Encoding UTF8 в PS 5.1 добавляет BOM,
    # а подстановка {file:...} читает файл как есть — BOM испортит значение).
    $enc = New-Object System.Text.UTF8Encoding($false)
    foreach ($s in $SecretDefs) {
        if (-not (Test-Path $s.Path)) {
            [System.IO.File]::WriteAllText($s.Path, "", $enc)
            Write-Host "[шаблон]  $($s.Path)  — заполните значение ($($s.Consumer))" -ForegroundColor Yellow
        }
    }
}

function Get-SecretValue {
    Param([string]$File)
    if (-not (Test-Path $File)) { return $null }
    $v = [System.IO.File]::ReadAllText($File).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

function Test-SecretsOffline {
    Write-Host ""
    Write-Host "=== Проверка хранилища секретов (офлайн) ===" -ForegroundColor Cyan
    Write-Host "Хранилище: $SecretsRoot"
    $fail = 0
    foreach ($s in $SecretDefs) {
        $val = Get-SecretValue $s.Path
        if ($val) {
            Write-Host ("  [OK]      {0,-24} {1} симв.  ({2})" -f $s.Name, $val.Length, $s.Consumer) -ForegroundColor Green
        } elseif ($s.Required) {
            Write-Host ("  [ОТСУТСТВ] {0,-24} обязателен! ({1})" -f $s.Name, $s.Consumer) -ForegroundColor Red
            $fail++
        } else {
            Write-Host ("  [нет]     {0,-24} необязателен ({1})" -f $s.Name, $s.Consumer) -ForegroundColor DarkYellow
        }
    }
    if (Test-Path $EwsFile) {
        Write-Host "  [OK]      credentials.env          EWS MCP" -ForegroundColor Green
    } else {
        Write-Host "  [нет]     credentials.env          EWS MCP (необязательно)" -ForegroundColor DarkYellow
    }
    if (Test-Path $ProjectSecrets) {
        Write-Host "  [OK]      .local_secrets.json      проектные PS-модули" -ForegroundColor Green
    } else {
        Write-Host "  [нет]     .local_secrets.json      проектные PS-модули (необязательно)" -ForegroundColor DarkYellow
    }
    return $fail
}

function Test-SecretsOnline {
    Write-Host ""
    Write-Host "=== Сетевые проверки (Jira / Confluence) ===" -ForegroundColor Cyan
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $jira = Get-SecretValue (Join-Path $SecretsRoot "opencode\jira_token.txt")
    if ($jira) {
        try {
            $r = Invoke-WebRequest -Uri "https://mytask.renins.com/rest/api/2/myself" -Headers @{ Authorization = "Bearer $jira" } -UseBasicParsing -TimeoutSec 20
            Write-Host ("  [OK] Jira: HTTP {0}" -f $r.StatusCode) -ForegroundColor Green
        } catch {
            Write-Host ("  [ОШИБКА] Jira: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    } else {
        Write-Host "  [пропуск] Jira: нет токена" -ForegroundColor DarkYellow
    }

    $conf = Get-SecretValue (Join-Path $SecretsRoot "opencode\confluence_password.txt")
    if ($conf) {
        $pair = "vchaga:{0}" -f $conf
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        try {
            $r = Invoke-WebRequest -Uri "https://wiki.renins.com/rest/api/user/current" -Headers @{ Authorization = "Basic $b64" } -UseBasicParsing -TimeoutSec 20
            $obj = $r.Content | ConvertFrom-Json
            if ($obj.type -eq "known") {
                Write-Host ("  [OK] Confluence: HTTP {0}, пользователь {1}" -f $r.StatusCode, $obj.username) -ForegroundColor Green
            } else {
                Write-Host ("  [ОШИБКА] Confluence: HTTP {0}, тип '{1}' (не аутентифицирован)" -f $r.StatusCode, $obj.type) -ForegroundColor Red
            }
        } catch {
            Write-Host ("  [ОШИБКА] Confluence: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    } else {
        Write-Host "  [пропуск] Confluence: нет пароля" -ForegroundColor DarkYellow
    }
}

if ($Init) {
    New-SecretsStructure
}

$fails = Test-SecretsOffline
if ($Online) { Test-SecretsOnline }

Write-Host ""
if ($fails -gt 0) {
    Write-Host "ИТОГ: не хватает обязательных секретов: $fails" -ForegroundColor Red
    Write-Host "Восстановление: заполните файлы в $SecretsRoot\opencode (или выполните -Init и впишите значения)."
    exit 1
} else {
    Write-Host "ИТОГ: обязательные секреты на месте." -ForegroundColor Green
    exit 0
}
