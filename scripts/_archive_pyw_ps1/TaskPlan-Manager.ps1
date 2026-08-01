<#
.SYNOPSIS
    Менеджер задач TaskPlan — диспетчер множества задач.
.DESCRIPTION
    Создаёт/управляет задачами через реестр task_index.json.
    Каждая задача: имя, промпт, уточнения, статус, даты.
    Поддерживает переключение, остановку, возобновление, удаление.
.PARAMETER Action
    create | list | show | switch | suspend | resume | edit-prompt | delete
.PARAMETER Name
    Имя задачи (при Create — авто-имя, при других — поиск по префиксу)
.PARAMETER Prompt
    Текст промпта (для create, edit-prompt)
.PARAMETER Clarify
    Дополнительные уточнения (create — дописывает к промпту)
.PARAMETER Status
    Новый статус (для resume: active, для suspend: paused)
.PARAMETER ReleaseRoot
    Корень папок задач (авто: SYBASE/SUPRT → C:\AIS\1 Release, иначе → C:\AIS\AI\Prod\tasks)
.PARAMETER Force
    Перезаписать существующую задачу (create) или удалить без подтверждения (delete)
#>
param(
    [ValidateSet('create','list','show','switch','suspend','resume','edit-prompt','delete')]
    [string]$Action = 'list',
    [string]$Name = '',
    [string]$Prompt = '',
    [string]$Clarify = '',
    [ValidateSet('new','active','paused','done')]
    [string]$Status = '',
    [string]$ReleaseRoot = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ===== функции =====

function Get-ReleaseRoot {
    param([string]$TaskName)
    if ($ReleaseRoot) { return $ReleaseRoot }
    if ($TaskName -and $TaskName -match '^(SYBASE|SUPRT)-') { return 'C:\AIS\1 Release' }
    if (-not $ReleaseRoot) { return 'C:\AIS\AI\Prod\tasks' }
    return 'C:\AIS\AI\Prod\tasks'
}

function Get-IndexFile {
    param([string]$Root)
    return Join-Path $Root 'task_index.json'
}

function Read-Index {
    param([string]$Root)
    $idxFile = Get-IndexFile -Root $Root
    if (-not (Test-Path -LiteralPath $idxFile)) {
        return [PSCustomObject]@{ tasks = @(); current = ''; timestamp = '' }
    }
    $raw = Get-Content -LiteralPath $idxFile -Raw -Encoding UTF8
    $raw = $raw.TrimStart([char]0xFEFF)
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
        $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $jss.MaxJsonLength = 10 * 1024 * 1024
        $ht = $jss.DeserializeObject($raw)
        $tasks = @()
        if ($ht.ContainsKey('tasks')) {
            foreach ($t in $ht['tasks']) {
                $tasks += [PSCustomObject]@{
                    id            = if ($t.ContainsKey('id'))            { $t['id'] }            else { '' }
                    name          = if ($t.ContainsKey('name'))          { $t['name'] }          else { '' }
                    prompt        = if ($t.ContainsKey('prompt'))        { $t['prompt'] }        else { '' }
                    clarifications= if ($t.ContainsKey('clarifications')){ $t['clarifications'] } else { '' }
                    status        = if ($t.ContainsKey('status'))        { $t['status'] }        else { 'new' }
                    created       = if ($t.ContainsKey('created'))       { $t['created'] }       else { '' }
                    updated       = if ($t.ContainsKey('updated'))       { $t['updated'] }       else { '' }
                }
            }
        }
        $cur = if ($ht.ContainsKey('current')) { $ht['current'] } else { '' }
        return [PSCustomObject]@{ tasks = $tasks; current = $cur; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss') }
    } catch { return [PSCustomObject]@{ tasks = @(); current = ''; timestamp = '' } }
}

function Write-Index {
    param([string]$Root, $Data)
    $idxFile = Get-IndexFile -Root $Root
    $list = @()
    foreach ($t in $Data.tasks) {
        $list += [ordered]@{
            id             = $t.id
            name           = $t.name
            prompt         = $t.prompt
            clarifications = $t.clarifications
            status         = $t.status
            created        = $t.created
            updated        = $t.updated
        }
    }
    $obj = [ordered]@{
        tasks     = $list
        current   = $Data.current
        timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
    }
    $json = $obj | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $idxFile -Value $json -Encoding UTF8
}

function Resolve-TaskName {
    param([string]$Name, [string]$Root)
    if (-not $Name) { return '' }
    $exact = Join-Path $Root $Name
    if (Test-Path -LiteralPath $exact) { return $Name }
    $found = Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$Name*" } | Select-Object -First 1
    if ($found) { return $found.Name }
    return $Name
}

function Find-TaskInIndex {
    param($Tasks, [string]$Name)
    if (-not $Name) { return $null }
    foreach ($t in $Tasks) {
        if ($t.id -eq $Name -or $t.name -eq $Name) { return $t }
    }
    foreach ($t in $Tasks) {
        if ($t.id -like "$Name*" -or $t.name -like "$Name*") { return $t }
    }
    return $null
}

function Auto-Name {
    param([string]$Root)
    $idx = Read-Index -Root $Root
    $maxN = 0
    foreach ($t in $idx.tasks) {
        if ($t.id -match '^TASK-(\d+)$') {
            $n = [int]$matches[1]
            if ($n -gt $maxN) { $maxN = $n }
        }
    }
    return "TASK-$($maxN + 1)"
}

function Get-TaskFolder {
    param([string]$Name, [string]$Root)
    return Join-Path $Root $Name
}

function Write-PromptFile {
    param([string]$Folder, [string]$Prompt, [string]$Clarify)
    if (-not (Test-Path -LiteralPath $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $promptFile = Join-Path $Folder 'prompt.txt'
    $promptText = if ($Clarify) { "$Prompt`n`n=== УТОЧНЕНИЯ ===`n$Clarify" } else { $Prompt }
    Set-Content -LiteralPath $promptFile -Value $promptText -Encoding UTF8
}

function Read-PromptFile {
    param([string]$Folder)
    $promptFile = Join-Path $Folder 'prompt.txt'
    if (Test-Path -LiteralPath $promptFile) {
        $raw = Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8
        $raw = $raw.TrimStart([char]0xFEFF)
        $lines = $raw -split "`n"
        $prompt = @($lines | Where-Object { $_ -notmatch '^=== УТОЧНЕНИЯ ===' }) -join [Environment]::NewLine
        $inClarify = $false; $clarifyLines = @()
        foreach ($ln in $lines) {
            if ($ln -match '^=== УТОЧНЕНИЯ ===') { $inClarify = $true; continue }
            if ($inClarify) { $clarifyLines += $ln }
        }
        return @{ Prompt = $prompt.Trim(); Clarify = ($clarifyLines -join [Environment]::NewLine).Trim() }
    }
    return @{ Prompt = ''; Clarify = '' }
}

# ===== основная логика =====

# Определяем корень
$root = Get-ReleaseRoot -TaskName $Name
if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }

$idx = Read-Index -Root $root

switch ($Action) {

    'create' {
        if (-not $Prompt) { throw "Укажите -Prompt (текст задачи)" }
        $newName = if ($Name) { $Name } else { Auto-Name -Root $root }
        $taskFolder = Get-TaskFolder -Name $newName -Root $root
        if (Test-Path -LiteralPath $taskFolder) {
            if (-not $Force) { throw "Задача $newName уже существует. Используйте -Force для перезаписи." }
            Remove-Item -LiteralPath $taskFolder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $taskFolder -Force | Out-Null
        Write-PromptFile -Folder $taskFolder -Prompt $Prompt -Clarify $Clarify
        $now = Get-Date -Format 'dd.MM.yyyy HH:mm'
        $newTask = [PSCustomObject]@{
            id             = $newName
            name           = $newName
            prompt         = $Prompt
            clarifications = $Clarify
            status         = 'active'
            created        = $now
            updated        = $now
        }
        $list = @($idx.tasks) + $newTask
        $idx = [PSCustomObject]@{ tasks = $list; current = $newName; timestamp = $now }
        Write-Index -Root $root -Data $idx
        Write-Host "Задача создана: $newName" -ForegroundColor Green
        Write-Host "Папка: $taskFolder" -ForegroundColor Cyan
        Write-Host "Статус: active" -ForegroundColor Yellow
    }

    'list' {
        if ($idx.tasks.Count -eq 0) {
            Write-Host "Нет задач в $root" -ForegroundColor Yellow
            exit 0
        }
        Write-Host "=== ЗАДАЧИ ($root) ===" -ForegroundColor Cyan
        Write-Host ""
        foreach ($t in $idx.tasks) {
            $mark = if ($t.id -eq $idx.current) { '→' } else { ' ' }
            $color = switch ($t.status) { 'active' {'Green'} 'paused' {'Yellow'} 'done' {'Gray'} default {'White'} }
            $promptShort = $t.prompt
            if ($promptShort.Length -gt 50) { $promptShort = $promptShort.Substring(0, 47) + '...' }
            Write-Host ("$mark [$($t.status)] $($t.id)") -ForegroundColor $color
            Write-Host ("    $promptShort") -ForegroundColor DarkGray
        }
        Write-Host ""
        if ($idx.current) { Write-Host "Текущая: $($idx.current)" -ForegroundColor Green }
        Write-Host "Всего: $($idx.tasks.Count) | Active: $(@($idx.tasks | Where-Object { $_.status -eq 'active' }).Count) | Paused: $(@($idx.tasks | Where-Object { $_.status -eq 'paused' }).Count) | Done: $(@($idx.tasks | Where-Object { $_.status -eq 'done' }).Count)" -ForegroundColor White
    }

    'show' {
        if (-not $Name -and -not $idx.current) { throw "Укажите -Name (или установите current)" }
        $resolved = if ($Name) { Resolve-TaskName -Name $Name -Root $root } else { $idx.current }
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $resolved
        if (-not $task) { throw "Задача не найдена: $resolved" }
        $folder = Get-TaskFolder -Name $task.id -Root $root
        $pf = Read-PromptFile -Folder $folder
        Write-Host "=== $($task.id) ===" -ForegroundColor Cyan
        Write-Host "Статус: $($task.status)" -ForegroundColor $(if ($task.status -eq 'active') {'Green'} elseif ($task.status -eq 'paused') {'Yellow'} else {'Gray'})
        Write-Host "Создана: $($task.created)" -ForegroundColor White
        Write-Host "Обновлена: $($task.updated)" -ForegroundColor White
        Write-Host "Папка: $folder" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "--- ПРОМПТ ---" -ForegroundColor Yellow
        Write-Host $pf.Prompt
        if ($pf.Clarify) {
            Write-Host ""
            Write-Host "--- УТОЧНЕНИЯ ---" -ForegroundColor Yellow
            Write-Host $pf.Clarify
        }
    }

    'switch' {
        if (-not $Name) { throw "Укажите -Name" }
        $resolved = Resolve-TaskName -Name $Name -Root $root
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $resolved
        if (-not $task) { throw "Задача не найдена: $resolved. Сначала создайте через Action create." }
        $oldCurrent = $idx.current
        $list = @()
        foreach ($t in $idx.tasks) {
            if ($t.id -eq $oldCurrent -and $t.id -ne $task.id) {
                if ($t.status -ne 'done') { $t.status = 'paused' }
            }
            $list += $t
        }
        foreach ($t in $list) {
            if ($t.id -eq $task.id) { $t.status = 'active' }
        }
        $idx = [PSCustomObject]@{ tasks = $list; current = $task.id; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
        Write-Index -Root $root -Data $idx
        if ($oldCurrent -and $oldCurrent -ne $task.id) {
            Write-Host "Переключено: $oldCurrent → $($task.id)" -ForegroundColor Green
            Write-Host "$oldCurrent приостановлена (paused)" -ForegroundColor Yellow
        } else {
            Write-Host "Текущая задача: $($task.id)" -ForegroundColor Green
        }
    }

    'suspend' {
        $target = if ($Name) { Resolve-TaskName -Name $Name -Root $root } else { $idx.current }
        if (-not $target) { throw "Нет активной задачи. Укажите -Name." }
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $target
        if (-not $task) { throw "Задача не найдена: $target" }
        $list = @()
        foreach ($t in $idx.tasks) {
            if ($t.id -eq $task.id) { $t.status = 'paused'; $t.updated = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
            $list += $t
        }
        $newCurrent = if ($idx.current -eq $task.id) { '' } else { $idx.current }
        $idx = [PSCustomObject]@{ tasks = $list; current = $newCurrent; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
        Write-Index -Root $root -Data $idx
        Write-Host "Задача приостановлена: $target" -ForegroundColor Yellow
    }

    'resume' {
        if (-not $Name -and -not $idx.current) { throw "Укажите -Name (нет текущей задачи)" }
        $target = if ($Name) { Resolve-TaskName -Name $Name -Root $root } else { $idx.current }
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $target
        if (-not $task) { throw "Задача не найдена: $target" }
        $list = @()
        $oldCurrent = $idx.current
        foreach ($t in $idx.tasks) {
            if ($t.id -eq $oldCurrent -and $t.id -ne $task.id -and $t.status -ne 'done') { $t.status = 'paused' }
            if ($t.id -eq $task.id) { $t.status = 'active'; $t.updated = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
            $list += $t
        }
        $idx = [PSCustomObject]@{ tasks = $list; current = $task.id; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
        Write-Index -Root $root -Data $idx
        Write-Host "Задача возобновлена: $target (active)" -ForegroundColor Green
    }

    'edit-prompt' {
        $target = if ($Name) { Resolve-TaskName -Name $Name -Root $root } else { $idx.current }
        if (-not $target) { throw "Укажите -Name" }
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $target
        if (-not $task) { throw "Задача не найдена: $target" }
        $folder = Get-TaskFolder -Name $task.id -Root $root
        if ($Prompt) {
            $newClarify = if ($Clarify) { $Clarify } else { '' }
            Write-PromptFile -Folder $folder -Prompt $Prompt -Clarify $newClarify
            $list = @()
            foreach ($t in $idx.tasks) {
                if ($t.id -eq $task.id) {
                    $t.prompt = $Prompt
                    $t.clarifications = $newClarify
                    $t.updated = (Get-Date -Format 'dd.MM.yyyy HH:mm')
                }
                $list += $t
            }
            $idx = [PSCustomObject]@{ tasks = $list; current = $idx.current; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
            Write-Index -Root $root -Data $idx
            Write-Host "Промпт обновлён: $target" -ForegroundColor Green
        } else {
            $pf = Read-PromptFile -Folder $folder
            Write-Host "Текущий промпт $target :" -ForegroundColor Cyan
            Write-Host $pf.Prompt
            Write-Host ""
            Write-Host "Используйте: -Action edit-prompt -Name $target -Prompt `"новый текст`"" -ForegroundColor Yellow
        }
    }

    'delete' {
        if (-not $Name) { throw "Укажите -Name" }
        $resolved = Resolve-TaskName -Name $Name -Root $root
        $task = Find-TaskInIndex -Tasks $idx.tasks -Name $resolved
        if (-not $task) { throw "Задача не найдена: $resolved" }
        $folder = Get-TaskFolder -Name $task.id -Root $root
        if (Test-Path -LiteralPath $folder) {
            if (-not $Force) {
                Write-Host "Удалить $($task.id) и папку $folder ?" -ForegroundColor Red -NoNewline
                Write-Host " Используйте -Force для удаления." -ForegroundColor Yellow
                throw "Требуется -Force"
            }
            Remove-Item -LiteralPath $folder -Recurse -Force
        }
        $list = @()
        foreach ($t in $idx.tasks) {
            if ($t.id -ne $task.id) { $list += $t }
        }
        $newCurrent = if ($idx.current -eq $task.id) { '' } else { $idx.current }
        $idx = [PSCustomObject]@{ tasks = $list; current = $newCurrent; timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm') }
        Write-Index -Root $root -Data $idx
        Write-Host "Задача удалена: $($task.id)" -ForegroundColor Red
    }
}
