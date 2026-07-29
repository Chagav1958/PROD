<#
.SYNOPSIS
    Helper script to discover Jira custom field IDs for RFC time fields.
    Run this once to configure the custom_field IDs in config.json.
.EXAMPLE
    .\Find-JiraFields.ps1
#>

param(
    [string]$JiraUser,
    [string]$JiraPassword,
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$jiraBase = $cfg.jira.base_url

# Auth
if (-not $JiraUser)  { $JiraUser = Read-Host "E-mail для Jira" }
if (-not $JiraPassword) {
    $secPass = Read-Host "Пароль/токен Jira" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
    $JiraPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}
# PAT (Personal Access Token) — Bearer, иначе Basic Auth
if ($JiraPassword -match '^[a-zA-Z0-9+/=]{20,}$') {
    $authHeader = "Bearer $JiraPassword"
} else {
    $authBytes = [System.Text.Encoding]::ASCII.GetBytes("$($JiraUser):$($JiraPassword)")
    $authHeader = "Basic " + [Convert]::ToBase64String($authBytes)
}
$headers = @{ Authorization = $authHeader; "Content-Type" = "application/json" }

Write-Host "=== Поиск кастомных полей Jira ===" -ForegroundColor Cyan
Write-Host "Jira: $jiraBase" -ForegroundColor Cyan
Write-Host ""

# Get all custom fields
Write-Host "Загрузка кастомных полей..." -ForegroundColor Yellow
$fields = Invoke-RestMethod -Uri "$jiraBase/rest/api/2/field" -Method GET -Headers $headers -ErrorAction Stop

Write-Host "Поиск полей, содержащих 'релиз', 'release', 'start', 'end', 'RFC'..." -ForegroundColor Yellow
Write-Host ""

$candidates = $fields | Where-Object {
    $n = $_.name.ToLower()
    $_.custom -eq $true -and (
        $n -match 'релиз' -or
        $n -match 'release' -or
        $n -match 'start' -or
        $n -match 'end' -or
        $n -match 'время' -or
        $n -match 'time' -or
        $n -match 'date'
    )
}

if ($candidates.Count -eq 0) {
    Write-Host "Подходящие кастомные поля не найдены. Показаны ВСЕ кастомные поля:" -ForegroundColor Yellow
    $candidates = $fields | Where-Object { $_.custom -eq $true }
}

Write-Host ("{0,-45} {1,-30} {2}" -f "ID поля", "Имя", "Тип") -ForegroundColor Cyan
Write-Host ("="*90)
foreach ($f in $candidates | Sort-Object Name) {
    Write-Host ("{0,-45} {1,-30} {2}" -f $f.id, $f.name, $f.schema.type)
}

Write-Host ""
Write-Host "Для настройки обновите config.json с правильными ID кастомных полей:" -ForegroundColor Green
Write-Host '  "custom_fields": {' -ForegroundColor Gray
Write-Host '    "release_start": "customfield_XXXXX",   <-- "Начало релиза"' -ForegroundColor Gray
Write-Host '    "release_end": "customfield_XXXXX"      <-- "Завершение релиза"' -ForegroundColor Gray
Write-Host '  }' -ForegroundColor Gray
Write-Host '  "task_link_field": "customfield_XXXXX"    <-- Поле для связи задач' -ForegroundColor Gray

