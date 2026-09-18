<#
.SYNOPSIS
    Creates a Release RFC in Jira for a given task.
.DESCRIPTION
    Checks if an RFC already exists for the specified task.
    If not, creates a new RFC with:
      - Release start time: current time + 1 hour (hh:00 rounded)
      - Release end time:   start time + 24 hours
    Jira credentials are prompted or passed via parameter.
.PARAMETER TaskName
    Jira task identifier (e.g. SYBASE-19337)
.PARAMETER Force
    Skip confirmation prompt
.PARAMETER JiraUser
    E-mail для Jira (опционально, будет запрошен)
.PARAMETER JiraPassword
    Jira password or API token (optional, prompted if not provided)
.PARAMETER ConfigPath
    Path to config.json
.EXAMPLE
    .\Create-RFC.ps1 -TaskName SYBASE-19337
.EXAMPLE
    .\Create-RFC.ps1 -TaskName SYBASE-19337 -Force
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TaskName,
    [switch]$Force,
    [string]$JiraUser,
    [string]$JiraPassword,
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# РІ"Р‚РІ"Р‚ Config РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚РІ"Р‚
if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$jiraBase   = $cfg.jira.base_url
$jiraProj   = $cfg.jira.project_key
$issueType  = $cfg.jira.issue_type
$cfStart    = $cfg.jira.custom_fields.release_start
$cfEnd      = $cfg.jira.custom_fields.release_end
$linkField  = $cfg.jira.task_link_field

# Аутентификация
if (-not $JiraUser)  { $JiraUser = Read-Host "E-mail для Jira" }
if (-not $JiraPassword) { $JiraPassword = Read-Host "Пароль/токен Jira" -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($JiraPassword); $JiraPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR) }

# PAT (Personal Access Token) — Bearer, иначе Basic Auth
if ($JiraPassword -match '^[a-zA-Z0-9+/=]{20,}$') {
    $authHeader = "Bearer $JiraPassword"
} else {
    $authBytes = [System.Text.Encoding]::ASCII.GetBytes("$($JiraUser):$($JiraPassword)")
    $authHeader = "Basic " + [Convert]::ToBase64String($authBytes)
}
$headers = @{ Authorization = $authHeader; "Content-Type" = "application/json" }

# Получаем accountId текущего пользователя (для Jira Cloud)
$jiraAccountId = $null
try {
    $myselfUri = "$jiraBase/rest/api/3/myself"
    $myselfParams = @{ Uri = $myselfUri; Method = "GET"; Headers = $headers; ContentType = "application/json;charset=utf-8" }
    $myself = Invoke-RestMethod @myselfParams -ErrorAction Stop
    $jiraAccountId = $myself.accountId
    Write-Host "  accountId получен: $jiraAccountId" -ForegroundColor Green
} catch {
    Write-Host "  Не удалось получить accountId через API: $_" -ForegroundColor Yellow
    Write-Host "  Используем name=$JiraUser для assignee" -ForegroundColor Yellow
}

# Helper function for Jira REST calls
function Invoke-Jira {
    param([string]$Method, [string]$Endpoint, $Body)
    $uri = "$jiraBase/rest/api/2/$Endpoint"
    $params = @{Uri=$uri; Method=$Method; Headers=$headers; ContentType="application/json;charset=utf-8"}
    if ($Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 10
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    }
    try { 
        return Invoke-RestMethod @params -ErrorAction Stop 
    } catch {
        $resp = $_.Exception.Response
        $status = $resp.StatusCode
        $statusDesc = $resp.StatusDescription
        $bodyReader = [System.IO.StreamReader]::new($resp.GetResponseStream()).ReadToEnd()
        throw "Ошибка Jira API ($Method $Endpoint): $status $statusDesc`nURI: $uri`nBody: $jsonBody`nResponse: $bodyReader"
    }
}

Write-Host "=== Создание RFC в Jira ===" -ForegroundColor Cyan
Write-Host "Задача: $TaskName"
Write-Host "Jira: $jiraBase/projects/$jiraProj"
Write-Host ""

# Шаг 1: Проверка существующих RFC
Write-Host "[1] Проверка существующих RFC для задачи '$TaskName'..." -ForegroundColor Yellow

$jql = "project = $jiraProj AND (summary ~ '$TaskName' OR description ~ '$TaskName')"
if ($linkField -and $linkField -notmatch 'XXXXX') { $jql += " OR '${linkField}' ~ '$TaskName'" }
$jql += " ORDER BY created DESC"
$search = Invoke-Jira -Method GET -Endpoint "search?jql=$([System.Web.HttpUtility]::UrlEncode($jql))&maxResults=10"

if ($search.total -gt 0) {
    Write-Host "  Найдено $($search.total) существующих RFC:" -ForegroundColor Yellow
    foreach ($issue in $search.issues) {
        $key = $issue.key
        $summary = $issue.fields.summary
        $status = $issue.fields.status.name
        Write-Host "  - $key ($status): $summary" -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "RFC уже существует для задачи '$TaskName' — пропуск создания." -ForegroundColor Green
    exit 0
}

Write-Host "  Существующих RFC не найдено." -ForegroundColor Green

# Шаг 2: Вычисление временных меток релиза
Write-Host "[2] Вычисление временных меток релиза..." -ForegroundColor Yellow

$now = Get-Date
$startTime = $now.AddHours(1)
$startTime = Get-Date -Year $startTime.Year -Month $startTime.Month -Day $startTime.Day -Hour $startTime.Hour -Minute 0 -Second 0
$endTime = $startTime.AddDays(1)

$startStr = $startTime.ToString("yyyy-MM-ddTHH:mm:ss.000") + $startTime.ToString("zzz").Replace(":", "")
$endStr   = $endTime.ToString("yyyy-MM-ddTHH:mm:ss.000") + $endTime.ToString("zzz").Replace(":", "")

Write-Host "  Начало релиза: $($startTime.ToString('yyyy-MM-dd HH:mm'))"
Write-Host "  Окончание:     $($endTime.ToString('yyyy-MM-dd HH:mm'))"

# Шаг 3: Подтверждение
if (-not $Force) {
    Write-Host ""
    $answer = Read-Host "Создать RFC для '$TaskName'? (д/Н)"
    if ($answer -ne "y" -and $answer -ne "Y") { Write-Host "Отменено."; exit 0 }
}

# Шаг 4: Создание RFC
if ($DryRun) {
    Write-Host "  [DRY RUN] Тело запроса:" -ForegroundColor Cyan
    $dryBody = @{
        fields = @{
            project     = @{ key = $jiraProj }
            issuetype   = @{ id = $cfg.jira.issue_type_id }
            summary     = "Разработка - $TaskName"
            description = "RFC сформирована автоматически - AIS Release Preparation"
        }
    }
    if ($cfStart -and $cfStart -notmatch '^customfield_XXXXX$') { $dryBody.fields[$cfStart] = $startStr }
    if ($cfEnd -and $cfEnd -notmatch '^customfield_XXXXX$') { $dryBody.fields[$cfEnd] = $endStr }
    if ($linkField -and $linkField -notmatch '^customfield_XXXXX$') { $dryBody.fields[$linkField] = $TaskName }
    $dryBody.fields["customfield_25953"] = "..."
    $dryBody.fields["customfield_25954"] = "..."
    $dryBody.fields["customfield_13852"] = "Нет"
    $dryBody.fields["customfield_15254"] = "Нет"
    $dryBody.fields["customfield_15255"] = @{ name = $JiraUser }
    $dryBody.fields["customfield_15256"] = @{ name = $JiraUser }
    $dryBody.fields["customfield_15350"] = @( $( if ($jiraAccountId) { @{ accountId = $jiraAccountId } } else { @{ name = $JiraUser } } ) )
    $dryBody.fields["assignee"] = $( if ($jiraAccountId) { @{ accountId = $jiraAccountId } } else { @{ name = $JiraUser } } )
    $dryBody.fields["customfield_15258"] = $startStr
    $dryBody.fields["customfield_15259"] = $endStr
    $dryBody | ConvertTo-Json -Depth 10 | Write-Host
    Write-Host "  [DRY RUN] RFC не создаётся. Проверка параметров выполнена."
    exit 0
}
Write-Host "[3] Создание RFC..." -ForegroundColor Yellow

# Получаем summary задачи из Jira для использования в RFC
$taskSummary = $TaskName
if ($taskInfo -and $taskInfo.fields.summary) {
    $taskSummary = $taskInfo.fields.summary
    Write-Host "  Summary задачи: $taskSummary" -ForegroundColor Cyan
}

$rfcBody = @{
    fields = @{
        project     = @{ key = $jiraProj }
        issuetype   = @{ id = $cfg.jira.issue_type_id }
        summary     = "Разработка - $taskSummary"
        description = "RFC сформирована автоматически - AIS Release Preparation"
    }
}

# assignee: для Jira Cloud — accountId, для Jira Server/Data Center — name
if ($jiraAccountId) {
    $rfcBody.fields.assignee = @{ accountId = $jiraAccountId }
} else {
    $rfcBody.fields.assignee = @{ name = $JiraUser }
    Write-Host "  assignee по name (accountId недоступен): $JiraUser" -ForegroundColor Yellow
}

# Add custom fields if configured (only if not placeholder)
if ($cfStart -and $cfStart -notmatch '^customfield_XXXXX$') {
    $rfcBody.fields[$cfStart] = $startStr
}
if ($cfEnd -and $cfEnd -notmatch '^customfield_XXXXX$') {
    $rfcBody.fields[$cfEnd] = $endStr
}
if ($linkField -and $linkField -notmatch '^customfield_XXXXX$') {
    $rfcBody.fields[$linkField] = $TaskName
}

# Получаем информацию о задаче для заполнения полей RFC
Write-Host "  Получение информации о задаче $TaskName..." -ForegroundColor Cyan
$taskInfo = $null
try {
    $taskInfo = Invoke-Jira -Method GET -Endpoint "issue/$TaskName"
} catch {
    Write-Host "  Не удалось получить информацию о задаче: $_" -ForegroundColor Yellow
}

# Заполняем обязательные поля RFC (стандартные шаблоны из RFC-12336)
# customfield_25953: План проведения работ
$planRabot = "1. «Отпускаем»/добавляем (CheckIn) объекты из списка в комментариях к задаче разработки в локальной сборке`n2. Заходим на сборочную и «подтягиваем» нужные объекты (при необходимости)`n3. Открываем основной объект с версией, переоткрываем pbr и прописываем новую версию и дату (при необходимости)`n4. Запускаем Deploy`n5. Запускаем соответствующий скрипт c:\SRC125\golden125_deploy.bat`n6. Идем на локальную PC и обновляем через Upgrade.cmd и запускаем приложение`n7. Нажимаем Ctrl+Alt+V и добавляем версию в список в статусе «рабочая», а существующую ставим в «допустимая»`n8. Переносим серверные объекты (хранимые процедуры, триггеры, функции, Виды, таблицы) из списка в комментариях к задаче разработки (при необходимости)"
$rfcBody.fields["customfield_25953"] = $planRabot

# customfield_25954: План отката
$rfcBody.fields["customfield_25954"] = "Исправляем появившиеся ошибки и собираем новую версию"

# customfield_13852: Проблемы и риски
$rfcBody.fields["customfield_13852"] = "Нет"

# customfield_15254: Информирование о недоступности
$rfcBody.fields["customfield_15254"] = "Нет"

# customfield_15255: Ответственный за релиз (текущий пользователь)
$rfcBody.fields["customfield_15255"] = @{ name = $JiraUser }

# customfield_15256: Эксперт по продукту (текущий пользователь)
$rfcBody.fields["customfield_15256"] = @{ name = $JiraUser }

# customfield_15350: Проверяющие на бою (автор исходной задачи)
$reporterName = if ($taskInfo -and $taskInfo.fields.reporter) { $taskInfo.fields.reporter.name } else { $JiraUser }
$rfcBody.fields["customfield_15350"] = @( @{ name = $reporterName } )

# customfield_15258: Дата начала внедрения
$rfcBody.fields["customfield_15258"] = $startStr

# customfield_15259: Дата завершения внедрения
$rfcBody.fields["customfield_15259"] = $endStr

# customfield_25955: Системы (IT-компоненты) под влиянием - используем SYSTEM-67
$rfcBody.fields["customfield_25955"] = @("SYSTEM-67")

# customfield_26053: Работы планируются с системой (IT-компонентом)
$rfcBody.fields["customfield_26053"] = @("SYSTEM-67")

$result = Invoke-Jira -Method POST -Endpoint "issue" -Body $rfcBody

$rfcKey = $result.key
$rfcUrl = "$jiraBase/browse/$rfcKey"
Write-Host "  Создан: $rfcUrl" -ForegroundColor Green

# Шаг 5: Связывание RFC с исходной задачей
Write-Host "[4] Связывание RFC с исходной задачей..." -ForegroundColor Yellow
try {
    $linkBody = @{
        type = @{ name = "Mention" }
        inwardIssue = @{ key = $rfcKey }
        outwardIssue = @{ key = $TaskName }
    }
    Invoke-Jira -Method POST -Endpoint "issueLink" -Body $linkBody | Out-Null
    Write-Host "  Связано $rfcKey <-> $TaskName" -ForegroundColor Green
} catch {
    Write-Host "  Не удалось связать (задача '$TaskName' может не существовать в Jira): $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== RFC успешно создан ===" -ForegroundColor Green
Write-Host "  $rfcUrl"
Write-Host "  Окно релиза: $($startTime.ToString('yyyy-MM-dd HH:mm')) — $($endTime.ToString('yyyy-MM-dd HH:mm'))"
exit 0

