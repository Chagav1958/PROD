<#
.SYNOPSIS
    Ядро логики TaskPlan — создание/чтение/обновление ПЛАН_РЕАЛИЗАЦИИ.txt и plan_state.json.
.DESCRIPTION
    Работает с папкой задачи: Describe\ПЛАН_РЕАЛИЗАЦИИ.txt + Describe\plan_state.json.
    Параметры: -Action (new|add|set|show|next|sync)
.PARAMETER Action
    new — создать новый план; add — добавить этапы; set — установить статус;
    show — показать план; next — найти следующий этап; sync — синхр. JSON из txt
.PARAMETER TaskName
    Имя задачи (папка)
.PARAMETER ReleaseRoot
    Корень папок задач
.PARAMETER Goal
    Цель задачи (для new)
.PARAMETER Stages
    Массив этапов
.PARAMETER StageNum
    Номер этапа (для set, next)
.PARAMETER Status
    todo|wip|done|defer (для set)
.PARAMETER DoneBy
    Кто выполнил (LLM/исполнитель)
.PARAMETER Force
    Перезаписать существующий план (new)
#>
param(
    [ValidateSet('new','add','set','show','next','sync','import')]
    [string]$Action = 'show',
    [string]$TaskName = '',
    [string]$ReleaseRoot = '',
    [string]$Goal = '',
    [string[]]$Stages = @(),
    [int]$StageNum = 0,
    [ValidateSet('todo','wip','done','defer','')]
    [string]$Status = '',
    [string]$DoneBy = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ── Определение корня ──
if (-not $ReleaseRoot) {
    if ($TaskName -match '^(SYBASE|SUPRT)-') { $ReleaseRoot = 'C:\AIS\1 Release' }
    else { $ReleaseRoot = 'C:\AIS\AI\Prod\tasks' }
}

# ── Поиск папки задачи ──
function Resolve-TaskFolder {
    param([string]$Name)
    if (-not $Name) { throw "Укажите -TaskName" }
    $exact = Join-Path $ReleaseRoot $Name
    if (Test-Path -LiteralPath $exact) { return $exact }
    $found = Get-ChildItem $ReleaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$Name*" } | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "Папка задачи не найдена: $Name"
}

function Get-PlanFile {
    param([string]$Folder)
    $dir = Join-Path $Folder 'Describe'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'ПЛАН_РЕАЛИЗАЦИИ.txt')
}

function Get-StateFile {
    param([string]$Folder)
    return (Join-Path $Folder 'Describe\plan_state.json')
}

# ── Парсинг ПЛАН_РЕАЛИЗАЦИИ.txt ──
function Read-PlanTxt {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $goal = ''
    $stages = @()
    $inStages = $false
    foreach ($ln in $lines) {
        if ($ln -match '^ЦЕЛЬ:\s*(.+)$') { $goal = $matches[1]; $inStages = $false }
        elseif ($ln -match '^ЭТАПЫ:') { $inStages = $true }
        elseif ($inStages -and $ln -match '^\[([ x~!])\]\s*(\d+)\.\s*(.+?)(?:\s*\((.+)\))?$') {
            $stages += @{
                num = [int]$matches[2]
                text = $matches[3].Trim()
                status = switch ($matches[1]) { ' ' { 'todo' } 'x' { 'done' } '~' { 'wip' } '!' { 'defer' } }
                by = if ($matches[4]) { $matches[4].Trim() } else { '' }
            }
        }
    }
    return @{ goal = $goal; stages = $stages }
}

# ── Запись ПЛАН_РЕАЛИЗАЦИИ.txt ──
function Write-PlanTxt {
    param([string]$Path, [string]$Goal, $Stages)
    $sb = New-Object Text.StringBuilder
    $null = $sb.AppendLine("=== ПЛАН РЕАЛИЗАЦИИ ===")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ЦЕЛЬ: $Goal")
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("ЭТАПЫ:")
    foreach ($s in $Stages) {
        $mark = switch ($s.status) { 'todo' {'[ ]'} 'wip' {'[~]'} 'done' {'[x]'} 'defer' {'[!]'} default {'[ ]'} }
        $byStr = if ($s.by) { " ($($s.by))" } else { '' }
        $null = $sb.AppendLine("$mark $($s.num). $($s.text)$byStr")
    }
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("---")
    Set-Content -LiteralPath $Path -Value $sb.ToString() -Encoding UTF8
}

# ── Чтение plan_state.json ──
function Read-StateJson {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction SilentlyContinue
    $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $jss.MaxJsonLength = 10 * 1024 * 1024
    return $jss.DeserializeObject($raw)
}

# ── Запись plan_state.json (зеркало txt) ──
function Write-StateJson {
    param([string]$Path, [string]$Goal, $Stages)
    $done = @($Stages | Where-Object { $_.status -eq 'done' }).Count
    $wip = @($Stages | Where-Object { $_.status -eq 'wip' }).Count
    $defer = @($Stages | Where-Object { $_.status -eq 'defer' }).Count
    $total = $Stages.Count
    $pct = if ($total -gt 0) { [math]::Round(($done + $wip * 0.5) / $total * 100) } else { 0 }
    $stageList = @()
    foreach ($s in $Stages) {
        $stageList += @{
            num = $s.num; text = $s.text; status = $s.status; by = if ($s.by) { $s.by } else { '' }
        }
    }
    $obj = @{
        task_name = $TaskName
        goal = $Goal
        stages = $stageList
        total = $total; done = $done; wip = $wip; defer = $defer
        pct = $pct
        timestamp = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
    }
    Set-Content -LiteralPath $Path -Value ($obj | ConvertTo-Json -Depth 5) -Encoding UTF8
}

# ── ОСНОВНАЯ ЛОГИКА ──

switch ($Action) {

    'new' {
        if (-not $TaskName) { throw "Укажите -TaskName" }
        $taskFolder = if ($TaskName -match '^(SYBASE|SUPRT)-') { Join-Path $ReleaseRoot $TaskName } else { Join-Path $ReleaseRoot $TaskName }
        if (-not (Test-Path $taskFolder)) { New-Item -ItemType Directory -Path (Join-Path $taskFolder 'Describe') -Force | Out-Null }
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if ((Test-Path $planFile) -and (-not $Force)) { throw "План уже существует. Используйте -Force для перезаписи." }
        if (-not $Goal) { throw "Укажите -Goal" }
        if ($Stages.Count -eq 0) { throw "Укажите -Stages (массив этапов)" }
        $parsedStages = @()
        $num = 1
        foreach ($s in $Stages) {
            $by = ''
            $text = $s
            if ($s -match '^(.+)\|(.+)$') { $text = $matches[1].Trim(); $by = $matches[2].Trim() }
            $parsedStages += @{ num = $num; text = $text; status = 'todo'; by = $by }
            $num++
        }
        Write-PlanTxt -Path $planFile -Goal $Goal -Stages $parsedStages
        Write-StateJson -Path $stateFile -Goal $Goal -Stages $parsedStages
        Write-Host "План создан: $TaskName (этапов: $($parsedStages.Count))" -ForegroundColor Green
    }

    'add' {
        $taskFolder = Resolve-TaskFolder -Name $TaskName
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if (-not (Test-Path $planFile)) { throw "План не найден. Сначала создайте через Action new." }
        $plan = Read-PlanTxt -Path $planFile
        $parsedStages = $plan.stages
        $num = $parsedStages.Count + 1
        foreach ($s in $Stages) {
            $by = ''
            $text = $s
            if ($s -match '^(.+)\|(.+)$') { $text = $matches[1].Trim(); $by = $matches[2].Trim() }
            $parsedStages += @{ num = $num; text = $text; status = 'todo'; by = $by }
            $num++
        }
        Write-PlanTxt -Path $planFile -Goal $plan.goal -Stages $parsedStages
        Write-StateJson -Path $stateFile -Goal $plan.goal -Stages $parsedStages
        Write-Host "Этапы добавлены: $($Stages.Count)" -ForegroundColor Green
    }

    'set' {
        $taskFolder = Resolve-TaskFolder -Name $TaskName
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if (-not (Test-Path $planFile)) { throw "План не найден." }
        if ($StageNum -le 0) { throw "Укажите -StageNum (номер этапа)" }
        if (-not $Status) { throw "Укажите -Status (todo|wip|done|defer)" }
        $plan = Read-PlanTxt -Path $planFile
        $changed = $false
        foreach ($s in $plan.stages) {
            if ($s.num -eq $StageNum) {
                $s.status = $Status
                if ($DoneBy) { $s.by = $DoneBy }
                $changed = $true
            }
        }
        if (-not $changed) { throw "Этап $StageNum не найден" }
        Write-PlanTxt -Path $planFile -Goal $plan.goal -Stages $plan.stages
        Write-StateJson -Path $stateFile -Goal $plan.goal -Stages $plan.stages
        Write-Host "Статус этапа $StageNum установлен: $Status" -ForegroundColor Green
    }

    'show' {
        $taskFolder = Resolve-TaskFolder -Name $TaskName
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if (-not (Test-Path $planFile)) { throw "План не найден." }
        $plan = Read-PlanTxt -Path $planFile
        Write-Host "=== ПЛАН ЗАДАЧИ: $TaskName ===" -ForegroundColor Cyan
        Write-Host "ЦЕЛЬ: $($plan.goal)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "--- ЭТАПЫ ---" -ForegroundColor Gray
        foreach ($s in $plan.stages) {
            $mark = switch ($s.status) { 'todo' {'[ ]'} 'wip' {'[~]'} 'done' {'[x]'} 'defer' {'[!]'} }
            $byStr = if ($s.by) { " ($($s.by))" } else { '' }
            Write-Output "$mark $($s.num). $($s.text)$byStr"
        }
        $done = @($plan.stages | Where-Object { $_.status -eq 'done' }).Count
        $total = $plan.stages.Count
        Write-Host ""
        Write-Host "Готово: $done/$total" -ForegroundColor White
    }

    'next' {
        $taskFolder = Resolve-TaskFolder -Name $TaskName
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if (-not (Test-Path $planFile)) { throw "План не найден." }
        $plan = Read-PlanTxt -Path $planFile
        $next = $plan.stages | Where-Object { $_.status -ne 'done' } | Select-Object -First 1
        if ($next) {
            Write-Output "$($next.num)"
        } else {
            Write-Output "0"
        }
    }

    'import' {
        $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
        $importScript = Join-Path $scriptDir 'TaskPlan-Import.ps1'
        if (-not (Test-Path $importScript)) { throw "TaskPlan-Import.ps1 не найден" }
        if (-not $TaskName) { throw "Укажите -TaskName" }
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoLogo -File `"$importScript`" -TaskName `"$TaskName`""
        if ($ReleaseRoot) { $psi.Arguments += " -ReleaseRoot `"$ReleaseRoot`"" }
        if ($Force) { $psi.Arguments += " -Force" }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $null = $p.WaitForExit(60000)
        Write-Host ($out -replace '^True\s*','')
        if ($err) { Write-Host "STDERR: $err" -ForegroundColor Red }
    }

    'sync' {
        $taskFolder = Resolve-TaskFolder -Name $TaskName
        $planFile = Get-PlanFile -Folder $taskFolder
        $stateFile = Get-StateFile -Folder $taskFolder
        if (-not (Test-Path $planFile)) { throw "План не найден." }
        $plan = Read-PlanTxt -Path $planFile
        Write-StateJson -Path $stateFile -Goal $plan.goal -Stages $plan.stages
        Write-Host "JSON синхронизирован из txt" -ForegroundColor Green
    }
}
