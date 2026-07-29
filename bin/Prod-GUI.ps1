<#
.SYNOPSIS
    GUI launcher for AIS release preparation scripts.
.DESCRIPTION
    WPF window with modern design for selecting and running release scripts.
    Password field supports show/hide toggle.
    All errors are logged to file and displayed to user.
.EXAMPLE
    .\Prod-GUI.ps1
#>

. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"

# Global error handling - log everything
$logFile = Join-Path $env:TEMP "ais_gui_debug.log"
"=== GUI Started at $(Get-Date) ===" | Out-File $logFile -Append

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    "Assemblies loaded" | Out-File $logFile -Append
} catch {
    [System.Windows.MessageBox]::Show("Failed to load WPF assemblies: $_", "Fatal Error", "OK", "Error")
    exit 1
}

$ErrorActionPreference = "Continue"

# Determine project root (parent of bin/ directory)
# При запуске через .bat-лаунчер $PSScriptRoot = $null, используем fallback
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot }
              elseif ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path -Parent }
              else { (Get-Location).Path }
$ProjectRoot = if ($scriptRoot -match '[\\/]bin$') { Split-Path $scriptRoot -Parent } else { $scriptRoot }
if (-not $ProjectRoot) { $ProjectRoot = 'C:\AIS\AI\Prod' }
$LogoPath = Join-Path $ProjectRoot "docs\renins_logo.png"
"Project root: $ProjectRoot" | Out-File $logFile -Append
"Logo path: $LogoPath" | Out-File $logFile -Append
"Logo exists: $(Test-Path $LogoPath)" | Out-File $logFile -Append

# Load config for VSS defaults
$configPath = Join-Path $ProjectRoot "config\config.json"
$script:vssDefaults = @{ user = "User"; db_path = ""; project = "$/"; ss_exe = "C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe" }
$script:localRoot = ""
$script:vssHistoryMax = 100
$script:taskNameHistoryMax = 100
$script:uiTimeoutSeconds = 60
$script:tortoiseMergePath = ""
$script:loadingAnimationIndex = 1
$script:fixedLogPath = Join-Path $ProjectRoot "temp\last_output.log"
$script:compareAllMax = 5
if (Test-Path $configPath) {
    try {
        $configJson = Get-Content $configPath -Raw -Encoding UTF8
        $config = $configJson | ConvertFrom-Json
        if ($config.vss) {
            $script:vssDefaults.user    = if ($config.vss.user)    { $config.vss.user }    else { "User" }
            $script:vssDefaults.db_path = if ($config.vss.db_path) { $config.vss.db_path } else { "" }
            $script:vssDefaults.project = if ($config.vss.project) { $config.vss.project } else { "$/" }
            $script:vssDefaults.ss_exe  = if ($config.vss.ss_exe)  { $config.vss.ss_exe }  else { "C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe" }
        }
        # Local root for PBT path mapping (local → VSS)
        $script:localRoot = if ($config.paths.pb_main_source) { $config.paths.pb_main_source } else { "" }
        # VSS history max objects
        $script:vssHistoryMax = if ($config.vss.history_max -gt 0) { $config.vss.history_max } else { 100 }
        # Output timeout
        $script:uiTimeoutSeconds = if ($config.gui.output_timeout_seconds -gt 0) { $config.gui.output_timeout_seconds } else { 60 }
        # TaskName history max
        $script:taskNameHistoryMax = if ($config.task_name_history_max -gt 0) { $config.task_name_history_max } else { 100 }
        # TortoiseMerge path for diff dialog
        $script:tortoiseMergePath = if ($config.paths.tortoise_merge) { $config.paths.tortoise_merge } else { "" }
        # Loading animation index
        $script:loadingAnimationIndex = if ($config.gui.loading_animation -ge 1 -and $config.gui.loading_animation -le 10) { $config.gui.loading_animation } else { 1 }
        $script:compareAllMax = if ($config.gui.compare_all_max -ge 1 -and $config.gui.compare_all_max -le 10) { $config.gui.compare_all_max } else { 5 }
        # PBT name
        $script:pbtName = if ($config.paths.pbt_name) { $config.paths.pbt_name } else { "gold" }
        "VSS defaults loaded from config" | Out-File $logFile -Append
    } catch {
        "Config load error: $_" | Out-File $logFile -Append
    }
}

# AutoRun support
$script:autoRun = $false
$script:autoRunOpName = ""
$script:autoRunTaskName = ""
$script:autoRunOutputFile = ""
$script:autoRunCompleted = $false
$script:autoRunSelecting = $false
$script:autoRunPassword = ""
if ($args -contains "-AutoRun") {
    $script:autoRun = $true
    for ($i = 0; $i -lt $args.Length; $i++) {
        if ($args[$i] -eq "-OpName" -and $i + 1 -lt $args.Length) {
            $script:autoRunOpName = $args[$i + 1]
        }
        elseif ($args[$i] -eq "-TaskName" -and $i + 1 -lt $args.Length) {
            $script:autoRunTaskName = $args[$i + 1]
        }
        elseif ($args[$i] -eq "-OutputFile" -and $i + 1 -lt $args.Length) {
            $script:autoRunOutputFile = $args[$i + 1]
        }
        elseif ($args[$i] -eq "-Password" -and $i + 1 -lt $args.Length) {
            $script:autoRunPassword = $args[$i + 1]
        }
    }
    "AutoRun: OpName='$script:autoRunOpName', TaskName='$script:autoRunTaskName', OutputFile='$script:autoRunOutputFile', Password='***'" | Out-File $logFile -Append
}

# Resolve short object name to full VSS path
function Resolve-VssObjectPath {
    param(
        [string]$ObjectName,
        [string]$ProjectRoot
    )
    # If already full path (starts with $/), return as-is
    if ($ObjectName.StartsWith("$/")) {
        return $ObjectName
    }
    
    # Get PBT name and search roots from config
    $configPath = Join-Path $ProjectRoot "config\config.json"
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $pbtName = if ($config.paths.pbt_name) { $config.paths.pbt_name } else { "gold" }
    $searchRoots = @(
        $config.paths.pb_main_export,
        $config.paths.pb_current_export
    )
    
    # Determine extension
    $hasExtension = $ObjectName.Contains(".")
    $searchPattern = if ($hasExtension) { $ObjectName } else { "$ObjectName.*" }
    
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        $matches = Get-ChildItem -Path $root -Recurse -File -Filter $searchPattern -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            # Check if file name matches (with or without extension)
            $fileName = $match.Name
            $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $inputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ObjectName)
            if ($fileBaseName -eq $inputBaseName) {
                # Found! Get PBL library name (parent folder name)
                $pblName = $match.Directory.Name
                # Build full VSS path
                $fullPath = "$/SRC125/$pbtName/$pblName/$fileName"
                return $fullPath
            }
        }
    }
    
    # Not found, return original (will fail in VSS but user will see error)
    return $ObjectName
}

# Load VSS object history
$historyFile = Join-Path $ProjectRoot "config\vss_object_history.json"
$script:vssHistory = @{}
if (Test-Path $historyFile) {
    try {
        $historyJson = Get-Content $historyFile -Raw -Encoding UTF8
        $parsed = $historyJson | ConvertFrom-Json
        # Convert PSCustomObject to hashtable
        if ($parsed -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $script:vssHistory[$prop.Name] = @($prop.Value)
            }
        }
        "VSS history loaded: $($script:vssHistory.Count) operations" | Out-File $logFile -Append
    } catch {
        "History load error: $_" | Out-File $logFile -Append
    }
}

# Load TaskName history
$taskHistoryFile = Join-Path $ProjectRoot "config\task_name_history.json"
$script:taskNameHistory = @{}
if (Test-Path $taskHistoryFile) {
    try {
        $historyJson = Get-Content $taskHistoryFile -Raw -Encoding UTF8
        $parsed = $historyJson | ConvertFrom-Json
        if ($parsed -is [System.Management.Automation.PSCustomObject]) {
            foreach ($prop in $parsed.PSObject.Properties) {
                $script:taskNameHistory[$prop.Name] = @($prop.Value)
            }
        }
        "TaskName history loaded: $($script:taskNameHistory.Count) operations" | Out-File $logFile -Append
    } catch {
        "TaskName history load error: $_" | Out-File $logFile -Append
    }
}
# Загружаем последний использованный TaskName
$script:sharedTaskName = if ($script:taskNameHistory.ContainsKey("TaskName_Shared") -and $script:taskNameHistory["TaskName_Shared"].Count -gt 0) { $script:taskNameHistory["TaskName_Shared"][0] } else { "" }
"Shared TaskName: '$($script:sharedTaskName)'" | Out-File $logFile -Append

# Инициализация sharedDestPath из config
$script:sharedDestPath = ""
try {
    $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.export_service.dest_path) { $script:sharedDestPath = $cfg.export_service.dest_path }
} catch { }
"Shared DestPath: '$($script:sharedDestPath)'" | Out-File $logFile -Append

# Инициализация sharedCollectPath из config
$script:sharedCollectPath = ""
try {
    $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($cfg.collect_prod.dest_path) { $script:sharedCollectPath = $cfg.collect_prod.dest_path }
} catch { }
"Shared CollectPath: '$($script:sharedCollectPath)'" | Out-File $logFile -Append

$script:sharedVssUser = if ($script:vssHistory.ContainsKey("VssUser_Shared") -and $script:vssHistory["VssUser_Shared"].Count -gt 0) { $script:vssHistory["VssUser_Shared"][0] } else { "" }
$script:sharedPbtFile = if ($script:vssHistory.ContainsKey("PbtFile_Shared") -and $script:vssHistory["PbtFile_Shared"].Count -gt 0) { $script:vssHistory["PbtFile_Shared"][0] } else { "" }

function Update-VssProjectCombo {
    param([string]$OpName)
    try {
        $historyFile = Join-Path $ProjectRoot "config\vss_object_history.json"
        if (Test-Path $historyFile) {
            $history = Get-Content $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $items = if ($history.$OpName) { @($history.$OpName) } else { @() }
            foreach ($child in $script:uiParamsPanel.Children) {
                if ($child -is [System.Windows.Controls.StackPanel]) {
                    foreach ($inner in $child.Children) {
                        if ($inner -is [System.Windows.Controls.ComboBox] -and $inner.Tag -eq 'Project') {
                            $currentText = $inner.Text
                            $inner.Items.Clear()
                            $maxItems = if ($script:vssHistoryMax) { $script:vssHistoryMax } else { 100 }
                            $display = if ($items.Count -gt $maxItems) { $items[0..($maxItems-1)] } else { $items }
                            foreach ($item in $display) { $inner.Items.Add($item) | Out-Null }
                            $inner.Text = $currentText
                            return
                        }
                    }
                }
            }
        }
    } catch { "Combo refresh error: $_" | Out-File $logFile -Append }
}

function Save-VssHistory {
    try {
        $historyFile = Join-Path $ProjectRoot "config\vss_object_history.json"
        # Convert hashtable to ordered dictionary for proper JSON serialization
        $ordered = [ordered]@{}
        foreach ($key in $script:vssHistory.Keys) {
            $ordered[$key] = @($script:vssHistory[$key])
        }
        $historyJson = $ordered | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($historyFile, $historyJson, [System.Text.Encoding]::UTF8)
    } catch {
        "History save error: $_" | Out-File $logFile -Append
    }
}

function Save-TaskNameHistory {
    try {
        $historyFile = Join-Path $ProjectRoot "config\task_name_history.json"
        $ordered = [ordered]@{}
        foreach ($key in $script:taskNameHistory.Keys) {
            $ordered[$key] = @($script:taskNameHistory[$key])
        }
        $historyJson = $ordered | ConvertTo-Json -Depth 3
        [System.IO.File]::WriteAllText($historyFile, $historyJson, [System.Text.Encoding]::UTF8)
    } catch {
        "TaskName history save error: $_" | Out-File $logFile -Append
    }
}

# ── 3D-стилизация для всех окон ──
function Apply-3DStyle {
    param($Window, [switch]$NoButtons)
    try {
        $g = New-Object Windows.Media.LinearGradientBrush
        $g.StartPoint = "0,0"; $g.EndPoint = "0,1"
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xE8,0xE8,0xE8), 0.0)))
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xD0,0xD0,0xD0), 1.0)))
        $Window.Background = $g
        $ws = New-Object Windows.Media.Effects.DropShadowEffect
        $ws.Color = [Windows.Media.Color]::FromRgb(0x60,0x60,0x60)
        $ws.Direction = 270; $ws.ShadowDepth = 5; $ws.BlurRadius = 12; $ws.Opacity = 0.4
        $Window.Effect = $ws
        if (-not $NoButtons) {
            $btShadow = New-Object Windows.Media.Effects.DropShadowEffect
            $btShadow.Color = [Windows.Media.Color]::FromRgb(0x80,0x80,0x80)
            $btShadow.Direction = 270; $btShadow.ShadowDepth = 2; $btShadow.BlurRadius = 4; $btShadow.Opacity = 0.35
            $btGrad = New-Object Windows.Media.LinearGradientBrush
            $btGrad.StartPoint = "0,0"; $btGrad.EndPoint = "0,1"
            [void]$btGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xF0,0xF0,0xF0), 0.0)))
            [void]$btGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xD0,0xD0,0xD0), 1.0)))
        }
    } catch { }
}

function Get-OperationResult {
    param(
        [string]$OpName,
        [string]$Output,
        [int]$ExitCode,
        $Params
    )
    $vssUser = if ($Params -and $Params.VssUser) { $Params.VssUser } else { "" }
    switch -Regex ($OpName) {
        'VSS: Who Is Using|VSS: Кто использует' {
            if ($Output -match 'не извлечён никем|No checked out') { return "Никто" }
            if ($vssUser -and $Output -match "\b$vssUser\b") { return "Вы" }
            if ($Output -match '(?:Exc|Out)\s+(\w+)\s') { return $matches[1] }
            return "Не определено"
        }
        'VSS: Check Status|VSS: Проверить статус' {
            if ($Output -match 'не найдены|No checked out|Свободен') { return "Свободен" }
            if ($Output -match 'найдено|Занят|Exc|Out') {
                $users = @()
                $checkedFiles = 0
                foreach ($l in ($Output -split "`r`n|`n")) {
                    if ($l -match '^\s{2}(\S+)\s+(Exc|Out)\s') { $users += $matches[1]; $checkedFiles++ }
                }
                $unique = $users | Select-Object -Unique
                if ($unique.Count -eq 1) { return "Занят: $($unique[0]) ($checkedFiles)" }
                if ($unique.Count -gt 1) { return "Занят: $($unique -join ', ') ($checkedFiles)" }
                return "Занят"
            }
            if ($ExitCode -eq 0) { return "Свободен" } else { return "Занят" }
        }
        'VSS: Get Latest|VSS: Checkout|VSS: Checkin|VSS: Undo Check Out' {
            if ($Output -match 'загрузка завершена|Объект извлечён|Объект сохранён|Резервирование снято|Исполнено') { return "Исполнено" }
            if ($Output -match 'невозможно|ERROR|Ошибка') { return "Невозможно" }
            if ($ExitCode -eq 0) { return "Исполнено" } else { return "Невозможно" }
        }
        'SQL: Экспорт полный|SQL_exp_param|SQL Export' {
            if ($Output -match '###SQL_TASK_NONE###') { return "Нет SQL-объектов для задачи" }
            if ($ExitCode -ne 0) { return "Ошибка" }
            $sqlSb = New-Object System.Text.StringBuilder
            $lines = $Output -split "`r`n|`n"
            # Поддерживаем оба формата: старый BAT (Procs: found=...) и новый (Процедур: N)
            $sqlTypes = @(
                @{Pat='Procs:\s+found=(\d+)\s+ok=(\d+)';  Label='Процедур'; Fmt='{0} (OK: {1})'},
                @{Pat='Процедур:\s+(\d+)';                 Label='Процедур';Fmt='{0}'},
                @{Pat='Funcs:\s+found=(\d+)\s+ok=(\d+)';  Label='Функций';  Fmt='{0} (OK: {1})'},
                @{Pat='Функций:\s+(\d+)';                  Label='Функций'; Fmt='{0}'},
                @{Pat='Trigs:\s+found=(\d+)\s+ok=(\d+)';  Label='Триггеров';Fmt='{0} (OK: {1})'},
                @{Pat='Триггеров:\s+(\d+)';                Label='Триггеров';Fmt='{0}'},
                @{Pat='Tables:\s+ok';                     Label='Таблицы';  Fmt='OK'},
                @{Pat='Таблиц:\s+(\d+)';                   Label='Таблицы'; Fmt='{0}'},
                @{Pat='Indexes:\s+ok';                    Label='Индексы';  Fmt='OK'},
                @{Pat='PK:\s+ok';                         Label='Первичные ключи';Fmt='OK'},
                @{Pat='FK:\s+ok';                         Label='Внешние ключи';  Fmt='OK'},
                @{Pat='Grants:\s+ok';                     Label='Гранты';   Fmt='OK'}
            )
            $seenTypes = @{}
            $objNamesByType = @{ Proc = @(); Func = @(); Trig = @(); Other = @() }
            $currentType = "Other"
            foreach ($l in $lines) {
                if ($l -match '(Папка выгрузки|Сервер|База|Подключение):\s+(.+)') {
                    if (-not $seenTypes.ContainsKey($matches[1])) {
                        $seenTypes[$matches[1]] = $true
                        [void]$sqlSb.AppendLine($l.Trim())
                    }
                }
                if ($l -match '\[\d\] EXPORT (PROCEDURES|FUNCTIONS|TRIGGERS)') {
                    $currentType = switch ($matches[1]) { 'PROCEDURES' { 'Proc' }; 'FUNCTIONS' { 'Func' }; 'TRIGGERS' { 'Trig' }; default { 'Other' } }
                }
                if ($l -match '^\s+Exporting (proc|func|trig):\s+(\S+)') {
                    $objNamesByType[$currentType] += $matches[2]
                }
                foreach ($t in $sqlTypes) {
                    if ($l -match $t.Pat -and -not $seenTypes.ContainsKey($t.Label)) {
                        $seenTypes[$t.Label] = $true
                        if ($t.Fmt -eq 'OK') { [void]$sqlSb.AppendLine("$($t.Label): OK") }
                        elseif ($matches.Count -ge 3) { [void]$sqlSb.AppendLine("$($t.Label): $($t.Fmt -f $matches[1], $matches[2])") }
                        else { [void]$sqlSb.AppendLine("$($t.Label): $($matches[1])") }
                    }
                }
                if ($l -match '^Всего:\s+(\d+)' -and -not $seenTypes.ContainsKey('Всего')) {
                    $seenTypes['Всего'] = $true
                    [void]$sqlSb.AppendLine($l.Trim())
                }
            }
            # Добавляем имена объектов в подробный результат (первые 15 каждого типа)
            $typeLabels = @{ Proc = 'Процедуры'; Func = 'Функции'; Trig = 'Триггеры' }
            foreach ($t in @('Proc','Func','Trig')) {
                if ($objNamesByType[$t].Count -gt 0) {
                    [void]$sqlSb.AppendLine("")
                    [void]$sqlSb.AppendLine("--- $($typeLabels[$t]) ---")
                    $names = $objNamesByType[$t]
                    $showCount = [Math]::Min(15, $names.Count)
                    for ($i = 0; $i -lt $showCount; $i++) { [void]$sqlSb.AppendLine($names[$i]) }
                    if ($names.Count -gt 15) { [void]$sqlSb.AppendLine("... и ещё $($names.Count - 15)") }
                }
            }
            $summary = $sqlSb.ToString().TrimEnd()
            if ($summary) { return "$summary`r`n`r`nЗавершено" }
            return "Завершено"
        }
        'SQL: Экспорт одного|SQL_exp_single' {
            if ($ExitCode -eq 0) { return "Завершено" } else { return "Ошибка" }
        }
        'SQL: Экспорт из Ready|SQL_exp_ready' {
            if ($ExitCode -eq 0) { return "Завершено" } else { return "Ошибка" }
        }
        'SQL: Сравнение|Compare-Export|Compare-SQL' {
            if ($Output -match 'ГОТОВО:\s*\d+\s*/\s*НЕ ГОТОВО:\s*0\s*/\s*ВСЕГО') { return "Готово" }
            if ($Output -match 'НЕ ГОТОВО|NOT_READY|Различаются|DIFF') { return "Не готово" }
            if ($ExitCode -eq 0) { return "Готово" } else { return "Не готово" }
        }
        'PB: Сравнение|Compare-PB' {
            if ($Output -match 'Совпадает|SAME|READY') { return "Готово" }
            if ($Output -match 'Различаются|DIFF|NOT_READY') { return "Не готово" }
            if ($ExitCode -eq 0) { return "Готово" } else { return "Не готово" }
        }
        'Export PB|Выгрузка PB' {
            if ($ExitCode -ne 0) { return "Ошибка" }
            $summarySb = New-Object System.Text.StringBuilder
            $lines = $Output -split "`r`n|`n"
            $skipNext = $false
            foreach ($l in $lines) {
                if ($l -match '^\s*Источник:\s+\S') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^\s*PBT-файл:\s+\S') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^Выгружено библиотек:\s+\d') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^Всего объектов:\s+\d') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^Ошибок:\s+\d') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^Пропущено:\s+\d') { [void]$summarySb.AppendLine($l) }
                if ($l -match '^Назначение:\s+\S') { [void]$summarySb.AppendLine($l) }
            }
            $summary = $summarySb.ToString().TrimEnd()
            if ($summary) { return "$summary`r`n`r`nГотово" }
            return "Готово"
        }
        'Run Tests|test_sql_export' {
            if ($Output -match 'ВСЕ ТЕСТЫ ПРОЙДЕНЫ|ALL TESTS PASSED') { return "Тесты пройдены" }
            if ($ExitCode -eq 0) { return "Тесты пройдены" } else { return "Ошибка" }
        }
        'Jira Release Comment|Комментарий в Jira' {
            if ($Output -match 'комментарий успешно добавлен|Comment added') { return "Комментарий добавлен" }
            if ($ExitCode -eq 0) { return "Таблица сформирована" } else { return "Ошибка" }
        }
        'Collect PROD Objects|Собрать объекты' {
            if ($Output -match 'Не указан Task Name') { return "Не указан Task Name" }
            if ($Output -match '###PROD_NONE###') { return "Нет объектов" }
            if ($Output -match '###PROD_OBJ###') { return "Готово" }
            if ($ExitCode -eq 0) { return "Готово" } else { return "Ошибка" }
        }
        default {
            if ($ExitCode -eq 0) { return "Завершено" } else { return "Ошибка" }
        }
    }
}
# ── Вспомогательная функция для APPL2 title bar ──
function Add-TitleButton {
    param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$Width = 40, [int]$Height = 34, [int]$FontSize = 16)
    $b = New-Object Windows.Controls.Button
    $btnContentGrid = New-Object Windows.Controls.Grid
    $btnContentA = New-Object Windows.Controls.TextBlock
    $btnContentA.Text = $Text; $btnContentA.FontSize = $FontSize; $btnContentA.FontWeight = "Bold"
    $btnContentA.Foreground = [Windows.Media.Brushes]::White
    $btnContentA.Margin = New-Object Windows.Thickness(1,1,0,0)
    $btnContentA.HorizontalAlignment = "Center"; $btnContentA.VerticalAlignment = "Center"
    [void]$btnContentGrid.Children.Add($btnContentA)
    $btnContentB = New-Object Windows.Controls.TextBlock
    $btnContentB.Text = $Text; $btnContentB.FontSize = $FontSize; $btnContentB.FontWeight = "Bold"
    $btnContentB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $btnContentB.HorizontalAlignment = "Center"; $btnContentB.VerticalAlignment = "Center"
    [void]$btnContentGrid.Children.Add($btnContentB)
    $b.Content = $btnContentGrid; $b.Width = $Width; $b.Height = $Height
    $b.FontWeight = "Bold"; $b.FontSize = $FontSize
    $b.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $b.Cursor = "Hand"
    $b.HorizontalContentAlignment = "Center"
    $b.VerticalContentAlignment = "Center"
    $b.Padding = New-Object Windows.Thickness(0)
    $b.BorderThickness = New-Object Windows.Thickness(3)
    $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $transGrad = New-Object Windows.Media.LinearGradientBrush
    $transGrad.StartPoint = "0,0"; $transGrad.EndPoint = "0,1"
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
    $b.Background = $transGrad
    try {
        $xaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
'@
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
        $b.Template = [Windows.Markup.XamlReader]::Load($reader)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($b, $Col)
    $b.Add_Click($Click)
    $b.Add_MouseEnter({
        $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"}))
    })
    $b.Add_MouseLeave({
        $tg = New-Object Windows.Media.LinearGradientBrush
        $tg.StartPoint = "0,0"; $tg.EndPoint = "0,1"
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
        $this.Background = $tg
    })
    return $b
}
# ── HELPER: APPL2 wrapper ──
function Add-Appl2Wrapper {
    param($Window, $ContentElement, $Title)
    $outerBorder = New-Object Windows.Controls.Border
    $outerBorder.CornerRadius = 60
    $outerBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $outerBorder.BorderThickness = 1
    $outerBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")
    $borderShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $borderShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $borderShadow.Direction = 270; $borderShadow.ShadowDepth = 4; $borderShadow.BlurRadius = 10; $borderShadow.Opacity = 0.5
    $outerBorder.Effect = $borderShadow
    $contentGrid = New-Object Windows.Controls.Grid
    $contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $titleBorder = New-Object Windows.Controls.Border
    $titleBorder.CornerRadius = 10
    $titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
    $titleBorder.Padding = "20,2,20,0"
    $titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
    [System.Windows.Controls.Grid]::SetRow($titleBorder, 0)
    $titleBorder.Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
    $titleGrid = New-Object Windows.Controls.Grid
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleLayer = New-Object Windows.Controls.Grid
    $titleLayer.VerticalAlignment = "Center"
    $titleTextA = New-Object Windows.Controls.TextBlock
    $titleTextA.Text = $Title; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
    $titleTextA.Foreground = [Windows.Media.Brushes]::White
    $titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
    [void]$titleLayer.Children.Add($titleTextA)
    $titleTextB = New-Object Windows.Controls.TextBlock
    $titleTextB.Text = $Title; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
    $titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    [void]$titleLayer.Children.Add($titleTextB)
    [System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
    [void]$titleGrid.Children.Add($titleLayer)
    $minBtn = Add-TitleButton -Text "━" -Col 1 -Click { $Window.WindowState = [Windows.WindowState]::Minimized }
    $maxBtn = Add-TitleButton -Text "▣" -Col 2 -Click { if ($Window.WindowState -eq "Maximized") { $Window.WindowState = "Normal"; $maxBtn.Content = "▣" } else { $Window.WindowState = "Maximized"; $maxBtn.Content = "❐" } } -FontSize 18
    $closeBtn = Add-TitleButton -Text "✕" -Col 3 -Click { $Window.Close() } -IsClose
    [void]$titleGrid.Children.Add($minBtn); [void]$titleGrid.Children.Add($maxBtn); [void]$titleGrid.Children.Add($closeBtn)
    $titleBorder.Child = $titleGrid
    [void]$contentGrid.Children.Add($titleBorder)
    $contentWrapper = New-Object Windows.Controls.Border
    $contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $contentWrapper.CornerRadius = 46
    $contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
    [System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)
    $mainBorder = New-Object Windows.Controls.Border
    $mainBorder.CornerRadius = 42
    $mainBorder.Background = [Windows.Media.Brushes]::White
    $mainBorder.Padding = "20,16,20,22"
    $mainBorder.Margin = New-Object Windows.Thickness(4)
    $mainBorder.Child = $ContentElement
    $contentWrapper.Child = $mainBorder
    [void]$contentGrid.Children.Add($contentWrapper)
    $outerBorder.Child = $contentGrid
    $Window.Content = $outerBorder
}

function Show-ResultPopup {
    param(
        [string]$OpName = "",
        [string]$Result = "",
        [string]$Output = ""
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
    $window = New-Object Windows.Window
    $window.Title = "Результат: $OpName"
    $window.Width = 620
    $window.SizeToContent = "Height"
    $window.WindowStartupLocation = "Manual"
    if ($script:mainWindow) {
        $mw = $script:mainWindow
        $winLeft = $mw.Left + ($mw.Width - 620) / 2
        $winTop  = [Math]::Max(0, $mw.Top - 250)
        $window.Left = $winLeft
        $window.Top  = $winTop
    } else {
        $window.WindowStartupLocation = "CenterScreen"
    }
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $fontFamily = New-Object Windows.Media.FontFamily("Consolas")
    # Главный грид
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    # Белое овальное поле сообщений
    $msgBorder = New-Object Windows.Controls.Border
    $msgBorder.CornerRadius = 12
    $msgBorder.Background = [Windows.Media.Brushes]::White
    $msgBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
    $msgGrid = New-Object Windows.Controls.Grid
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    # Result phrase
    $resultBlock = New-Object Windows.Controls.TextBlock
    $resultBlock.Text = $Result
    $resultBlock.FontWeight = "Bold"
    $resultBlock.HorizontalAlignment = "Stretch"
    $resultBlock.FontFamily = New-Object Windows.Media.FontFamily("Consolas")
    $lineCount = ($Result -split "`r`n|`n").Count
    if ($lineCount -gt 2) {
        $resultBlock.FontSize = 13
        $resultScroll = New-Object Windows.Controls.ScrollViewer
        $resultScroll.VerticalScrollBarVisibility = "Auto"
        $resultScroll.MaxHeight = 300
        $resultScroll.Content = $resultBlock
        [void]$msgGrid.Children.Add($resultScroll)
    } else {
        $resultBlock.FontSize = 20
        [void]$msgGrid.Children.Add($resultBlock)
    }
    # Table data
    $tableText = Get-TableData -OpName $OpName -Output $Output
    if ($tableText) {
        $headerBlock = New-Object Windows.Controls.TextBlock
        $headerBlock.Text = "Подробно:"
        $headerBlock.FontSize = 13
        $headerBlock.FontWeight = "SemiBold"
        $headerBlock.Margin = New-Object Windows.Thickness(0,8,0,6)
        $headerBlock.Foreground = [Windows.Media.Brushes]::Black
        [System.Windows.Controls.Grid]::SetRow($headerBlock, 1)
        [void]$msgGrid.Children.Add($headerBlock)
        $scrollViewer = New-Object Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = "Auto"
        $scrollViewer.MaxHeight = 400
        $textBox = New-Object Windows.Controls.TextBox
        $textBox.Text = $tableText
        $textBox.FontFamily = $fontFamily
        $textBox.FontSize = 12
        $textBox.IsReadOnly = $true
        $textBox.TextWrapping = "NoWrap"
        $textBox.Background = [Windows.Media.Brushes]::White
        $textBox.BorderThickness = New-Object Windows.Thickness(1)
        $textBox.BorderBrush = [Windows.Media.Brushes]::LightGray
        $textBox.Padding = New-Object Windows.Thickness(8)
        $scrollViewer.Content = $textBox
        [System.Windows.Controls.Grid]::SetRow($scrollViewer, 1)
        [void]$msgGrid.Children.Add($scrollViewer)
    }
    $msgBorder.Child = $msgGrid
    [void]$mainGrid.Children.Add($msgBorder)
    # Кнопки — прозрачный фон
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel
    $okBtn = New-Object Windows.Controls.Button
    $okBtn.Content = "OK"
    $okBtn.Width = 80
    $okBtn.Height = 36
    $okBtn.Margin = "0,0,0,0"
    $okBtn.IsDefault = $true
    Apply-GlossyButtonStyle -Button $okBtn
    $okBtn.Add_Click({ $window.Close() })
    [void]$btnPanel.Children.Add($okBtn)
    [void]$mainGrid.Children.Add($btnBorder)
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

function Show-ValidationErrorWindow {
    param([string]$Output = "")
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
    
    $errors = @()
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###VALIDATION_ERROR###\s*(.+)\|(.+)\|(.+)\|(.+)$') {
            $errors += [PSCustomObject]@{
                Selected = $false
                ObjectName = $matches[1]
                Reason     = $matches[2]
                ReadyPath  = $matches[3]
                CurrentPath = $matches[4]
            }
        }
    }
    if ($errors.Count -eq 0) { return }
    
    $window = New-Object Windows.Window
    $script:validationWindow = $window
    $window.Title = "Ошибки валидации: $($errors.Count) объектов"
    $window.Width = 800; $window.Height = 500
    $window.WindowStartupLocation = "CenterScreen"
    $window.Topmost = $false
    $window.AllowsTransparency = $false
    $window.WindowStyle = [Windows.WindowStyle]::SingleBorderWindow
    $window.Background = [Windows.Media.Brushes]::White
    $window.ResizeMode = [Windows.ResizeMode]::CanResizeWithGrip
    
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    
    $headerBorder = New-Object Windows.Controls.Border
    $headerBorder.Background = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0xF8, 0xE4, 0xE4))
    $headerBorder.CornerRadius = 8
    $headerBorder.Padding = "12,8"
    [System.Windows.Controls.Grid]::SetRow($headerBorder, 0)
    
    $headerText = New-Object Windows.Controls.TextBlock
    $headerText.Text = "ОБНАРУЖЕНЫ ОШИБКИ ВАЛИДАЦИИ"
    $headerText.FontSize = 16; $headerText.FontWeight = "Bold"
    $headerText.Foreground = [Windows.Media.Brushes]::DarkRed
    $headerBorder.Child = $headerText
    [void]$mainGrid.Children.Add($headerBorder)
    
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false
    $dg.IsReadOnly = $false
    $dg.HeadersVisibility = 'All'
    $dg.RowHeaderWidth = 0
    $dg.AlternatingRowBackground = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0xFF, 0xF0, 0xF0))
    $dg.FontSize = 12
    $dg.VerticalScrollBarVisibility = 'Auto'
    $dg.HorizontalScrollBarVisibility = 'Auto'
    $dg.SelectionMode = 'Extended'
    $dg.SelectionUnit = 'FullRow'
    $dg.Background = [Windows.Media.Brushes]::White
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $dg.Margin = New-Object Windows.Thickness(0, 12, 0, 12)
    
    # Чекбокс колонка с двусторонним binding
    $cSel = New-Object Windows.Controls.DataGridCheckBoxColumn
    $cSel.Header = 'Выбрать'
    $cSel.Width = 60
    $binding = [Windows.Data.Binding]::new('Selected')
    $binding.Mode = [Windows.Data.BindingMode]::TwoWay
    $binding.UpdateSourceTrigger = [Windows.Data.UpdateSourceTrigger]::PropertyChanged
    $cSel.Binding = $binding
    [void]$dg.Columns.Add($cSel)
    
    $c1 = New-Object Windows.Controls.DataGridTextColumn
    $c1.Header = 'Объект'; $c1.Binding = [Windows.Data.Binding]::new('ObjectName'); $c1.Width = 150; $c1.IsReadOnly = $true
    [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn
    $c2.Header = 'Причина'; $c2.Binding = [Windows.Data.Binding]::new('Reason'); $c2.Width = 140; $c2.IsReadOnly = $true
    [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn
    $c3.Header = 'Ready (latest)'; $c3.Binding = [Windows.Data.Binding]::new('ReadyPath'); $c3.Width = 220; $c3.IsReadOnly = $true
    [void]$dg.Columns.Add($c3)
    $c4 = New-Object Windows.Controls.DataGridTextColumn
    $c4.Header = 'Current'; $c4.Binding = [Windows.Data.Binding]::new('CurrentPath'); $c4.Width = 220; $c4.IsReadOnly = $true
    [void]$dg.Columns.Add($c4)
    
    $dg.ItemsSource = $errors
    $script:validationDataGrid = $dg
    [void]$mainGrid.Children.Add($dg)
    
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,0,0,8"
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 2)
    
    $btnMerge = New-Object Windows.Controls.Button
    $btnMerge.Content = "Merge в Current"
    $btnMerge.Width = 140; $btnMerge.Height = 36
    $btnMerge.Margin = New-Object Windows.Thickness(4)
    $btnMerge.Background = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(0x4C, 0xAF, 0x50))
    $btnMerge.Foreground = [Windows.Media.Brushes]::White
    $btnMerge.FontWeight = "Bold"
    $script:validationDataGrid = $dg
    $btnMerge.Add_Click({
        param($sender, $e)
        try {
            if ($null -eq $script:validationDataGrid) {
                [System.Windows.MessageBox]::Show("Ошибка: DataGrid не инициализирован", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }
            $script:validationDataGrid.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row, $true)
            $selected = @()
            foreach ($row in $script:validationDataGrid.Items) {
                if ($row.Selected -eq $true) { $selected += $row }
            }
            if ($selected.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Выберите объекты для Merge.", "Merge", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }
            $count = 0; $mergedFiles = @()
            foreach ($item in $selected) {
                if ($item.ReadyPath -and $item.CurrentPath -and (Test-Path $item.ReadyPath)) {
                    try {
                        Copy-Item -Path $item.ReadyPath -Destination $item.CurrentPath -Force -ErrorAction Stop
                        $count++
                        $mergedFiles += @{ReadyPath = $item.ReadyPath; CurrentPath = $item.CurrentPath}
                    } catch {
                        [System.Windows.MessageBox]::Show("Ошибка при копировании: $_", "Merge Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                    }
                }
            }
            if ($mergedFiles.Count -gt 0) {
                $tortoiseMerge = $script:tortoiseMergePath
                if (-not $tortoiseMerge -or -not (Test-Path $tortoiseMerge)) {
                    $tortoiseMerge = "C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe"
                }
                if (Test-Path $tortoiseMerge) {
                    foreach ($file in $mergedFiles) {
                        Start-Process -FilePath $tortoiseMerge -ArgumentList "/base:`"$($file.ReadyPath)`" /mine:`"$($file.CurrentPath)`"" -ErrorAction SilentlyContinue
                    }
                } else {
                    [System.Windows.MessageBox]::Show("TortoiseMerge не найден: $tortoiseMerge", "Merge Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                }
            }
        } catch {
            [System.Windows.MessageBox]::Show("Ошибка Merge: $_", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        } finally {
            if ($script:validationWindow -and $script:validationWindow.IsLoaded) {
                try { $script:validationWindow.Close() } catch {}
            }
        }
    })
    [void]$btnPanel.Children.Add($btnMerge)
    
    $btnClose = New-Object Windows.Controls.Button
    $btnClose.Content = "Закрыть"
    $btnClose.Width = 100; $btnClose.Height = 36
    $btnClose.Margin = New-Object Windows.Thickness(4)
    $btnClose.IsDefault = $true
    $btnClose.Add_Click({ param($s, $e); if ($script:validationWindow.IsLoaded) { $script:validationWindow.Close() } })
    [void]$btnPanel.Children.Add($btnClose)
    
    [void]$mainGrid.Children.Add($btnPanel)
    $window.Content = $mainGrid
    $window.Add_KeyDown({ param($s, $e) if ($e.Key -eq "Escape") { $window.Close() } })
    
    # В AutoRun режиме используем ShowDialog чтобы окно не закрылось сразу
    if ($script:autoRun) {
        [void]$window.ShowDialog()
    } else {
        $window.Show()
        $window.Activate()
    }
}
function Show-VssStatusTableWindow {
    param(
        [string]$Output = "",
        [string]$VssPath = "",
        [string]$VssUser = "",
        [string]$VssPass = ""
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
    $data = @()
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###VSS_STATUS###\s+([^|]+)\|([^|]*)\|([^|]+)\|([^|]*)\|(.*)$') {
            $statusCode = $matches[3]
            $user = $matches[4]
            $source = $matches[5]
            switch ($statusCode) {
                'F' { $statusText = 'Свободен' }
                'B' { $statusText = "Занят: $user" }
                'NF' { $statusText = 'Не найден в PB_Main/PB_Current' }
                'E' { $statusText = 'Ошибка' }
                default { $statusText = $statusCode }
            }
            $srcText = switch ($source) {
                'R' { 'Ready' }
                'T' { 'Test' }
                'G' { 'Git' }
                default { '' }
            }
            $data += [PSCustomObject]@{
                ObjectName = $matches[1]
                VssPath = $matches[2]
                StatusCode = $statusCode
                StatusText = $statusText
                User = $user
                Source = $srcText
            }
        }
    }
    if ($data.Count -eq 0) { return }
    $freeCount = ($data | Where-Object { $_.StatusCode -eq 'F' }).Count
    $busyCount = ($data | Where-Object { $_.StatusCode -eq 'B' }).Count
    $nfCount = ($data | Where-Object { $_.StatusCode -eq 'NF' }).Count
    $errCount = ($data | Where-Object { $_.StatusCode -eq 'E' }).Count
    $window = New-Object Windows.Window
    $window.Title = "VSS Статус: $($data.Count) объектов"
    $window.Width = 800
    $window.Height = 550
    $window.WindowStartupLocation = "CenterScreen"
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    $msgBorder = New-Object Windows.Controls.Border
    $msgBorder.CornerRadius = 12
    $msgBorder.Background = [Windows.Media.Brushes]::White
    $msgBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
    $msgGrid = New-Object Windows.Controls.Grid
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $summary = New-Object Windows.Controls.TextBlock
    $summary.Text = "Всего: $($data.Count)  |  Свободно: $freeCount  |  Занято: $busyCount  |  Не найдено: $nfCount  |  Ошибок: $errCount"
    $summary.FontSize = 13; $summary.FontWeight = 'SemiBold'; $summary.Margin = New-Object Windows.Thickness(0,0,0,8)
    [void]$msgGrid.Children.Add($summary)
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true; $dg.HeadersVisibility = 'All'
    $dg.RowHeaderWidth = 0; $dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $dg.FontSize = 12; $dg.VerticalScrollBarVisibility = 'Auto'; $dg.HorizontalScrollBarVisibility = 'Auto'
    $dg.SelectionMode = 'Extended'; $dg.SelectionUnit = 'FullRow'
    $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header = 'Объект'; $c1.Binding = [Windows.Data.Binding]::new('ObjectName'); $c1.Width = 200; [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header = 'Статус'; $c2.Binding = [Windows.Data.Binding]::new('StatusText'); $c2.Width = 250; [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header = 'Источник'; $c3.Binding = [Windows.Data.Binding]::new('Source'); $c3.Width = 80; [void]$dg.Columns.Add($c3)
    $dg.ItemsSource = $data
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $dg.Margin = New-Object Windows.Thickness(0,0,0,6)
    [void]$msgGrid.Children.Add($dg)
    $ap = New-Object Windows.Controls.StackPanel; $ap.Orientation = 'Horizontal'; $ap.HorizontalAlignment = 'Center'; $ap.Margin = New-Object Windows.Thickness(0,0,0,6)
    $btnCo = New-Object Windows.Controls.Button; $btnCo.Content = 'Извлечь (Checkout)'; $btnCo.Width = 150; $btnCo.Height = 36; $btnCo.Margin = New-Object Windows.Thickness(4); $btnCo.IsEnabled = $false
    Apply-GlossyButtonStyle -Button $btnCo
    $btnUndo = New-Object Windows.Controls.Button; $btnUndo.Content = 'Снять резервирование (Undo)'; $btnUndo.Width = 200; $btnUndo.Height = 36; $btnUndo.Margin = New-Object Windows.Thickness(4); $btnUndo.IsEnabled = $false
    Apply-GlossyButtonStyle -Button $btnUndo -ColorTop "#C0A040" -ColorBottom "#A08020"
    [void]$ap.Children.Add($btnCo); [void]$ap.Children.Add($btnUndo)
    [System.Windows.Controls.Grid]::SetRow($ap, 2); [void]$msgGrid.Children.Add($ap)

    $dg.Add_SelectionChanged({
        param($sender, $e)
        $selected = $sender.SelectedItems
        if ($selected.Count -gt 0) {
            $hasFree = ($selected | Where-Object { $_.StatusCode -eq 'F' }).Count -gt 0
            $btnCo.IsEnabled = $hasFree
            $hasBusy = ($selected | Where-Object { $_.StatusCode -eq 'B' }).Count -gt 0
            $btnUndo.IsEnabled = $hasBusy
        } else {
            $btnCo.IsEnabled = $false
            $btnUndo.IsEnabled = $false
        }
    })

    $btnCo.Add_Click({
        $selected = $dg.SelectedItems
        if ($null -eq $selected -or $selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Выберите объекты для извлечения", "VSS Checkout", "OK", "Info")
            return
        }
        $freeObjs = $selected | Where-Object { $_.StatusCode -eq 'F' }
        if ($freeObjs.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Выбраны объекты, не доступные для извлечения. Возможно они уже заняты.", "VSS Checkout", "OK", "Warning")
            return
        }
        $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
        . $vssModule -VssPath $VssPath -Username $VssUser -Password $VssPass -Quiet
        $results = @()
        $errors = @()
        foreach ($obj in $freeObjs) {
            $out = Set-VssCheckout -Project $obj.VssPath -Comment "Checked out via AIS Release GUI"
            $results += $out
            if ($LASTEXITCODE -ne 0) { $errors += $obj.ObjectName }
        }
        if ($errors.Count -gt 0) {
            [System.Windows.MessageBox]::Show("Ошибка при извлечении: $($errors -join ', ')", "VSS Checkout Error", "OK", "Error")
        } else {
            [System.Windows.MessageBox]::Show("Извлечено объектов: $($freeObjs.Count)", "VSS Checkout", "OK", "Info")
        }
        foreach ($obj in $freeObjs) {
            $obj.StatusCode = 'B'
            $obj.StatusText = "Занят: $VssUser"
            $obj.User = $VssUser
        }
        $dg.Items.Refresh()
        $btnCo.IsEnabled = $false
        $btnUndo.IsEnabled = $true
    })

    $btnUndo.Add_Click({
        $selected = $dg.SelectedItems
        if ($null -eq $selected -or $selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Выберите объекты для отмены резервирования", "VSS Undo", "OK", "Info")
            return
        }
        $busyObjs = $selected | Where-Object { $_.StatusCode -eq 'B' }
        if ($busyObjs.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Нет занятых объектов для отмены резервирования", "VSS Undo", "OK", "Info")
            return
        }
        $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
        . $vssModule -VssPath $VssPath -Username $VssUser -Password $VssPass -Quiet
        $results = @()
        $errors = @()
        foreach ($obj in $busyObjs) {
            $out = Set-VssUndoCheckout -Project $obj.VssPath -Comment "Undo via AIS Release GUI"
            $results += $out
            if ($LASTEXITCODE -ne 0) { $errors += $obj.ObjectName }
        }
        if ($errors.Count -gt 0) {
            [System.Windows.MessageBox]::Show("Ошибка при отмене: $($errors -join ', ')", "VSS Undo Error", "OK", "Error")
        } else {
            [System.Windows.MessageBox]::Show("Резервирование снято с: $($busyObjs.Count)", "VSS Undo", "OK", "Info")
        }
        foreach ($obj in $busyObjs) {
            $obj.StatusCode = 'F'
            $obj.StatusText = 'Свободен'
            $obj.User = ''
        }
        $dg.Items.Refresh()
        $btnCo.IsEnabled = $true
        $btnUndo.IsEnabled = $false
    })

    $msgBorder.Child = $msgGrid
    [void]$mainGrid.Children.Add($msgBorder)
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel
    $closeBtn = New-Object Windows.Controls.Button
    $closeBtn.Content = 'Закрыть'; $closeBtn.Width = 100; $closeBtn.Height = 36
    $closeBtn.IsDefault = $true
    Apply-GlossyButtonStyle -Button $closeBtn
    $closeBtn.Add_Click({ $window.Close() })
    [void]$btnPanel.Children.Add($closeBtn)
    [void]$mainGrid.Children.Add($btnBorder)
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

function Show-PbObjectTableWindow {
    param([string]$Output = "")
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
    $data = @()
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###PB_OBJ###\s+(.+)\|(.+)\|(.+)$') {
            $data += [PSCustomObject]@{
                ObjectName = $matches[1]
                Library = $matches[2]
                FileName = $matches[3]
            }
        }
    }
    if ($data.Count -eq 0) { return }
    $window = New-Object Windows.Window
    $window.Title = "Объекты PB к выпуску: $($data.Count)"
    $window.Width = 650
    $window.Height = 400
    $window.WindowStartupLocation = "CenterScreen"
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    $msgBorder = New-Object Windows.Controls.Border
    $msgBorder.CornerRadius = 12
    $msgBorder.Background = [Windows.Media.Brushes]::White
    $msgBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
    $msgGrid = New-Object Windows.Controls.Grid
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $summary = New-Object Windows.Controls.TextBlock
    $summary.Text = "Всего объектов PB: $($data.Count)"
    $summary.FontSize = 13; $summary.FontWeight = 'SemiBold'; $summary.Margin = New-Object Windows.Thickness(0,0,0,8)
    [void]$msgGrid.Children.Add($summary)
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true; $dg.HeadersVisibility = 'All'
    $dg.RowHeaderWidth = 0; $dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $dg.FontSize = 12; $dg.VerticalScrollBarVisibility = 'Auto'; $dg.HorizontalScrollBarVisibility = 'Auto'
    $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header = 'Объект'; $c1.Binding = [Windows.Data.Binding]::new('ObjectName'); $c1.Width = 200; [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header = 'Библиотека'; $c2.Binding = [Windows.Data.Binding]::new('Library'); $c2.Width = 150; [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header = 'Файл'; $c3.Binding = [Windows.Data.Binding]::new('FileName'); $c3.Width = 200; [void]$dg.Columns.Add($c3)
    $dg.ItemsSource = $data
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $dg.Margin = New-Object Windows.Thickness(0,0,0,6)
    [void]$msgGrid.Children.Add($dg)
    $msgBorder.Child = $msgGrid
    [void]$mainGrid.Children.Add($msgBorder)
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel
    $closeBtn = New-Object Windows.Controls.Button; $closeBtn.Content = 'Закрыть'; $closeBtn.Width = 100; $closeBtn.Height = 36
    $closeBtn.IsDefault = $true
    Apply-GlossyButtonStyle -Button $closeBtn
    $closeBtn.Add_Click({ $window.Close() })
    [void]$btnPanel.Children.Add($closeBtn)
    [void]$mainGrid.Children.Add($btnBorder)
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

# ── Окно результата сборки PROD ──
function Show-ProdCompareResult {
    param([string]$Output = "")
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

    $hasNone = $Output -match '###PROD_NONE###'
    $items = @()
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###PROD_OBJ###\s*(.+)\|(.+)\|(.+)\|(.+)\|(.+)$') {
            $items += [PSCustomObject]@{
                Object = $matches[1]
                Type   = $matches[2]
                Status = $matches[3]
                Path   = $matches[4]
                VssStatus = $matches[5]
            }
        }
    }

    $window = New-Object Windows.Window
    $window.Topmost = $true
    $window.WindowStartupLocation = "CenterScreen"
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    if ($hasNone -or $items.Count -eq 0) {
        $window.Title = "Сборка PROD"
        $window.Width = 400; $window.Height = 150
        $msgBorder = New-Object Windows.Controls.Border
        $msgBorder.CornerRadius = 12
        $msgBorder.Background = [Windows.Media.Brushes]::White
        $msgBorder.Padding = "16,12,16,16"
        [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = if ($hasNone) { "Нет объектов для вывода" } else { "Нет данных" }
        $tb.FontSize = 16; $tb.FontWeight = 'Bold'
        $tb.Foreground = [Windows.Media.Brushes]::DarkOrange
        $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
        $tb.TextWrapping = 'Wrap'
        $msgBorder.Child = $tb
        [void]$mainGrid.Children.Add($msgBorder)
    } else {
        $okCount = ($items | Where-Object { $_.Status -eq 'OK' }).Count
        $errCount = $items.Count - $okCount
        $window.Title = "Сборка PROD: $($items.Count) объектов (OK: $okCount, прочее: $errCount)"
        $window.Width = 900; $window.Height = 450
        $msgBorder = New-Object Windows.Controls.Border
        $msgBorder.CornerRadius = 12
        $msgBorder.Background = [Windows.Media.Brushes]::White
        $msgBorder.Padding = "16,12,16,16"
        [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
        $msgGrid = New-Object Windows.Controls.Grid
        $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
        $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
        $summary = New-Object Windows.Controls.TextBlock
        $summary.Text = "Объектов: $($items.Count)  |  OK: $okCount  |  Требуют внимания: $errCount"
        $summary.FontSize = 13; $summary.FontWeight = 'SemiBold'; $summary.Margin = New-Object Windows.Thickness(0,0,0,8)
        [void]$msgGrid.Children.Add($summary)
        $dg = New-Object Windows.Controls.DataGrid
        $dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true; $dg.HeadersVisibility = 'All'
        $dg.RowHeaderWidth = 0; $dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
        $dg.FontSize = 12; $dg.VerticalScrollBarVisibility = 'Auto'; $dg.HorizontalScrollBarVisibility = 'Auto'
        $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header = 'Объект'; $c1.Binding = [Windows.Data.Binding]::new('Object'); $c1.Width = 180; [void]$dg.Columns.Add($c1)
        $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header = 'Тип'; $c2.Binding = [Windows.Data.Binding]::new('Type'); $c2.Width = 40; [void]$dg.Columns.Add($c2)
        $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header = 'Статус'; $c3.Binding = [Windows.Data.Binding]::new('Status'); $c3.Width = 120; [void]$dg.Columns.Add($c3)
        $c5 = New-Object Windows.Controls.DataGridTextColumn; $c5.Header = 'VSS'; $c5.Binding = [Windows.Data.Binding]::new('VssStatus'); $c5.Width = 130; [void]$dg.Columns.Add($c5)
        $c4 = New-Object Windows.Controls.DataGridTextColumn; $c4.Header = 'Адрес'; $c4.Binding = [Windows.Data.Binding]::new('Path'); $c4.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::Star); [void]$dg.Columns.Add($c4)
        $dg.ItemsSource = $items
        [System.Windows.Controls.Grid]::SetRow($dg, 1)
        $dg.Margin = New-Object Windows.Thickness(0,0,0,6)
        [void]$msgGrid.Children.Add($dg)
        $msgBorder.Child = $msgGrid
        [void]$mainGrid.Children.Add($msgBorder)
    }
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel
    $closeBtn = New-Object Windows.Controls.Button; $closeBtn.Content = 'Закрыть'; $closeBtn.Width = 100; $closeBtn.Height = 36
    $closeBtn.IsDefault = $true
    Apply-GlossyButtonStyle -Button $closeBtn
    $closeBtn.Add_Click({ $window.Close() })
    [void]$btnPanel.Children.Add($closeBtn)
    [void]$mainGrid.Children.Add($btnBorder)
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

# ── Диалог выбора объектов для сравнения (Compare & Verify) ──
function Show-DiffSelectWindow {
    param(
        [string]$Output = "",
        [string]$TmPath = ""
    )
    if (-not $TmPath -or -not (Test-Path $TmPath)) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

    # Парсинг структурированных данных
    $data = @()
    $seen = @{}
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###DIFF_OBJECT###\s*(.+)\|(.+)\|(.+)\|(.+)\|(.+)$') {
            $objName = $matches[1]
            $basePath = $matches[3]
            $readyPath = $matches[4]
            $key = "$objName|$basePath"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $libName = if ($basePath) { [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($basePath)) } else { "" }
            $objNameWithExt = if ($basePath) { [System.IO.Path]::GetFileName($basePath) } else { $objName }
            $baseDir = if ($basePath) { [System.IO.Path]::GetDirectoryName($basePath) } else { "" }
            $readyDir = if ($readyPath) { [System.IO.Path]::GetDirectoryName($readyPath) } else { "" }
            $reason = $matches[2] -replace '\s+', ' ' -replace '^\s+|\s+$', ''
            $data += [PSCustomObject]@{
                ObjectName = $objName
                ObjectNameWithExt = $objNameWithExt
                Reason = $reason
                BasePath = $basePath
                BaseDir = $baseDir
                ReadyPath = $readyPath
                ReadyDir = $readyDir
                CompareType = $matches[5]
                Library = $libName
                Selected = $false
            }
        }
    }
    if ($data.Count -eq 0) { return }

    $window = New-Object Windows.Window
    $window.Title = "Сравнение объектов: $($data.Count) шт."
    $window.Width = 900
    $window.Height = 500
    $window.WindowStartupLocation = "CenterScreen"
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    $msgBorder = New-Object Windows.Controls.Border
    $msgBorder.CornerRadius = 12
    $msgBorder.Background = [Windows.Media.Brushes]::White
    $msgBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
    $msgGrid = New-Object Windows.Controls.Grid
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $header = New-Object Windows.Controls.TextBlock
    $header.Text = "Выберите объекты для сравнения через TortoiseMerge:"
    $header.FontSize = 14; $header.FontWeight = 'SemiBold'; $header.Margin = New-Object Windows.Thickness(0,0,0,8)
    [void]$msgGrid.Children.Add($header)
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.HeadersVisibility = 'All'
    $dg.RowHeaderWidth = 0; $dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $dg.FontSize = 12; $dg.VerticalScrollBarVisibility = 'Auto'; $dg.HorizontalScrollBarVisibility = 'Auto'
    $dg.SelectionMode = 'Extended'; $dg.SelectionUnit = 'FullRow'
    $cSel = New-Object Windows.Controls.DataGridCheckBoxColumn
    $cSel.Header = 'Сравнить'; $cSel.Binding = [Windows.Data.Binding]::new('Selected'); $cSel.Width = 65
    [void]$dg.Columns.Add($cSel)
    $c1 = New-Object Windows.Controls.DataGridTextColumn
    $c1.Header = 'Наименование объекта'; $c1.Binding = [Windows.Data.Binding]::new('ObjectNameWithExt')
    $c1.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::SizeToCells)
    $c1.MinWidth = 120; $c1.IsReadOnly = $true
    [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn
    $c2.Header = 'Причина'; $c2.Binding = [Windows.Data.Binding]::new('Reason'); $c2.Width = 120; $c2.IsReadOnly = $true
    [void]$dg.Columns.Add($c2)
    $cLib = New-Object Windows.Controls.DataGridTextColumn
    $cLib.Header = 'Библиотека'; $cLib.Binding = [Windows.Data.Binding]::new('Library')
    $cLib.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::SizeToCells)
    $cLib.MinWidth = 80; $cLib.IsReadOnly = $true
    [void]$dg.Columns.Add($cLib)
    $c3 = New-Object Windows.Controls.DataGridTextColumn
    $c3.Header = 'Базовый файл'; $c3.Binding = [Windows.Data.Binding]::new('BaseDir')
    $c3.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::Star)
    $c3.MinWidth = 100; $c3.IsReadOnly = $true
    [void]$dg.Columns.Add($c3)
    $c4 = New-Object Windows.Controls.DataGridTextColumn
    $c4.Header = 'Готовый файл (Ready)'; $c4.Binding = [Windows.Data.Binding]::new('ReadyDir')
    $c4.Width = New-Object Windows.Controls.DataGridLength(2, [Windows.Controls.DataGridLengthUnitType]::Star)
    $c4.MinWidth = 100; $c4.IsReadOnly = $true
    [void]$dg.Columns.Add($c4)
    $dg.ItemsSource = $data
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $dg.Margin = New-Object Windows.Thickness(0,0,0,6)
    [void]$msgGrid.Children.Add($dg)
    $msgBorder.Child = $msgGrid
    [void]$mainGrid.Children.Add($msgBorder)
    # PreviewMouseLeftButtonDown handler
    $dg.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        $source = $e.OriginalSource
        $el = $source
        $isCheckboxClick = $false
        while ($el -and -not ($el -is [System.Windows.Controls.DataGridRow])) {
            if ($el -is [System.Windows.Controls.CheckBox]) { $isCheckboxClick = $true; break }
            $el = [System.Windows.Media.VisualTreeHelper]::GetParent($el)
        }
        if (-not $isCheckboxClick) { return }
        $element = $source
        while ($element -and -not ($element -is [System.Windows.Controls.DataGridRow])) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if ($element -and $element.DataContext) {
            $item = $element.DataContext
            if ($item.PSObject.Properties['Selected']) {
                $item.Selected = -not $item.Selected
                $e.Handled = $true
            }
        }
    })
    # Buttons
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel
    $btnCompareSel = New-Object Windows.Controls.Button
    $btnCompareSel.Content = 'Сравнить выбранные'; $btnCompareSel.Width = 160; $btnCompareSel.Height = 36
    $btnCompareSel.Margin = New-Object Windows.Thickness(4)
    Apply-GlossyButtonStyle -Button $btnCompareSel
    [void]$btnPanel.Children.Add($btnCompareSel)
    $btnCompareAll = New-Object Windows.Controls.Button
    $btnCompareAll.Content = 'Сравнить всё'; $btnCompareAll.Width = 120; $btnCompareAll.Height = 36
    $btnCompareAll.Margin = New-Object Windows.Thickness(4)
    Apply-GlossyButtonStyle -Button $btnCompareAll
    [void]$btnPanel.Children.Add($btnCompareAll)
    $btnClose = New-Object Windows.Controls.Button
    $btnClose.Content = 'Закрыть'; $btnClose.Width = 100; $btnClose.Height = 36
    $btnClose.Margin = New-Object Windows.Thickness(4)
    $btnClose.IsDefault = $true
    Apply-GlossyButtonStyle -Button $btnClose
    [void]$btnPanel.Children.Add($btnClose)
    [void]$mainGrid.Children.Add($btnBorder)
    # Compare selected handler
    $btnCompareSel.Add_Click({
        $selItems = $dg.Items
        $launched = 0; $skipped = 0
        foreach ($item in $selItems) {
            if ($item.Selected) {
                if ([string]::IsNullOrEmpty($item.BasePath) -or [string]::IsNullOrEmpty($item.ReadyPath)) {
                    $skipped++
                    continue
                }
                $diffArgs = @("/base", $item.BasePath, "/mine", $item.ReadyPath)
                try {
                    Start-Process -FilePath $TmPath -ArgumentList $diffArgs
                    $launched++
                } catch {}
            }
        }
        if ($launched -eq 0 -and $skipped -eq 0) {
            [System.Windows.MessageBox]::Show("Не выбрано ни одного объекта. Отметьте галочками объекты для сравнения.", "Нет выбора", "OK", "Information")
        } elseif ($skipped -gt 0) {
            [System.Windows.MessageBox]::Show("Запущено: $launched`nПропущено (нет файла): $skipped", "Результат", "OK", "Information")
        }
    })
    # Compare all handler
    $btnCompareAll.Add_Click({
        $validItems = @()
        foreach ($item in $dg.Items) {
            if (-not [string]::IsNullOrEmpty($item.BasePath) -and -not [string]::IsNullOrEmpty($item.ReadyPath)) {
                $validItems += $item
            }
        }
        if ($validItems.Count -gt $script:compareAllMax) {
            [System.Windows.MessageBox]::Show("Слишком много объектов ($($validItems.Count)). Максимум: $($script:compareAllMax)`nОтметьте объекты вручную.", "Превышен лимит", "OK", "Warning")
            return
        }
        $launched = 0
        foreach ($item in $validItems) {
            $diffArgs = @("/base", $item.BasePath, "/mine", $item.ReadyPath)
            try { Start-Process -FilePath $TmPath -ArgumentList $diffArgs; $launched++ } catch {}
        }
    })
    # Close handler
    $btnClose.Add_Click({ $window.Close() })
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

function Show-SqlTaskCompareWindow {
    param(
        [string]$Output = "",
        [string]$MainPath = ""
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

    $data = @()
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###SQL_TASK_OBJECT###\s*(.+)\|(.+)\|(.+)\|(.+)\|(.+)$') {
            $objName = $matches[1]
            $type = $matches[2]
            $folder = $matches[3]
            $status = $matches[4] -replace '\s+', ' ' -replace '^\s+|\s+$', ''
            $filePath = $matches[5]
            $statusMap = @{
                'DIFF'='Различаются'; 'NOT_IN_MAIN'='Нет в Main';
                'NOT_IN_CURRENT'='Нет в Current'; 'NOT_EXPORTED'='Не выгружен'; 'SAME'='Совпадают'
            }
            $statusRu = $statusMap[$status]
            if (-not $statusRu) { $statusRu = $status }
            $data += [PSCustomObject]@{
                ObjectName = $objName
                Type = $type
                Folder = $folder
                Status = $statusRu
                RawStatus = $status
                FilePath = $filePath
                Selected = $false
            }
        }
    }
    if ($data.Count -eq 0) { return }

    $today = Get-Date -Format 'yyyy_MM_dd'

    $window = New-Object Windows.Window
    $window.Title = "Объекты задачи SQL: $($data.Count) шт."
    $window.Width = 920
    $window.Height = 520
    $window.WindowStartupLocation = "CenterScreen"
    $window.Topmost = $true
    $window.AllowsTransparency = $true
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.Brushes]::Transparent
    $window.ResizeMode = [Windows.ResizeMode]::NoResize
    $mainGrid = New-Object Windows.Controls.Grid
    $mainGrid.Margin = New-Object Windows.Thickness(12)
    $r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
    $r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "*"; [void]$mainGrid.RowDefinitions.Add($r2)
    $r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r3)
    $msgBorder = New-Object Windows.Controls.Border
    $msgBorder.CornerRadius = 12
    $msgBorder.Background = [Windows.Media.Brushes]::White
    $msgBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($msgBorder, 0)
    $msgGrid = New-Object Windows.Controls.Grid
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $msgGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $header = New-Object Windows.Controls.TextBlock
    $header.Text = "Объекты задачи. Выберите действие: перенести в Ready_$today или удалить в Delete_$today."
    $header.FontSize = 14; $header.FontWeight = 'SemiBold'; $header.Margin = New-Object Windows.Thickness(0,0,0,8)
    [void]$msgGrid.Children.Add($header)
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.HeadersVisibility = 'All'
    $dg.RowHeaderWidth = 0; $dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $dg.FontSize = 12; $dg.VerticalScrollBarVisibility = 'Auto'; $dg.HorizontalScrollBarVisibility = 'Auto'
    $dg.SelectionMode = 'Extended'; $dg.SelectionUnit = 'FullRow'
    $cSel = New-Object Windows.Controls.DataGridCheckBoxColumn
    $cSel.Header = 'Выбрать'; $cSel.Binding = [Windows.Data.Binding]::new('Selected'); $cSel.Width = 65
    [void]$dg.Columns.Add($cSel)
    $c1 = New-Object Windows.Controls.DataGridTextColumn
    $c1.Header = 'Объект'; $c1.Binding = [Windows.Data.Binding]::new('ObjectName')
    $c1.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::SizeToCells)
    $c1.MinWidth = 180; $c1.IsReadOnly = $true
    [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn
    $c2.Header = 'Тип'; $c2.Binding = [Windows.Data.Binding]::new('Type'); $c2.Width = 90; $c2.IsReadOnly = $true
    [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn
    $c3.Header = 'Папка'; $c3.Binding = [Windows.Data.Binding]::new('Folder')
    $c3.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::SizeToCells)
    $c3.MinWidth = 140; $c3.IsReadOnly = $true
    [void]$dg.Columns.Add($c3)
    $c4 = New-Object Windows.Controls.DataGridTextColumn
    $c4.Header = 'Статус'; $c4.Binding = [Windows.Data.Binding]::new('Status')
    $c4.Width = New-Object Windows.Controls.DataGridLength(2, [Windows.Controls.DataGridLengthUnitType]::Star)
    $c4.MinWidth = 120; $c4.IsReadOnly = $true
    [void]$dg.Columns.Add($c4)
    $dg.ItemsSource = $data
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $dg.Margin = New-Object Windows.Thickness(0,0,0,6)
    [void]$msgGrid.Children.Add($dg)
    $msgBorder.Child = $msgGrid
    [void]$mainGrid.Children.Add($msgBorder)
    $dg.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        $source = $e.OriginalSource
        $el = $source
        $isCheckboxClick = $false
        while ($el -and -not ($el -is [System.Windows.Controls.DataGridRow])) {
            if ($el -is [System.Windows.Controls.CheckBox]) { $isCheckboxClick = $true; break }
            $el = [System.Windows.Media.VisualTreeHelper]::GetParent($el)
        }
        if (-not $isCheckboxClick) { return }
        $element = $source
        while ($element -and -not ($element -is [System.Windows.Controls.DataGridRow])) {
            $element = [System.Windows.Media.VisualTreeHelper]::GetParent($element)
        }
        if ($element -and $element.DataContext) {
            $item = $element.DataContext
            if ($item.PSObject.Properties['Selected']) {
                $item.Selected = -not $item.Selected
                $e.Handled = $true
            }
        }
    })
    $btnBorder = New-Object Windows.Controls.Border
    $btnBorder.Background = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderBrush = [Windows.Media.Brushes]::Transparent
    $btnBorder.BorderThickness = "0,1,0,0"
    [System.Windows.Controls.Grid]::SetRow($btnBorder, 2)
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Center"
    $btnPanel.Margin = "0,8,0,0"
    $btnBorder.Child = $btnPanel

    $btnMove = New-Object Windows.Controls.Button
    $btnMove.Content = "Перенести в Ready_$today"; $btnMove.Width = 220; $btnMove.Height = 36
    $btnMove.Margin = New-Object Windows.Thickness(4)
    Apply-GlossyButtonStyle -Button $btnMove
    [void]$btnPanel.Children.Add($btnMove)

    $btnDelete = New-Object Windows.Controls.Button
    $btnDelete.Content = "Удалить в Delete_$today"; $btnDelete.Width = 220; $btnDelete.Height = 36
    $btnDelete.Margin = New-Object Windows.Thickness(4)
    Apply-GlossyButtonStyle -Button $btnDelete
    [void]$btnPanel.Children.Add($btnDelete)

    $btnMerge = New-Object Windows.Controls.Button
    $btnMerge.Content = 'Сравнить'; $btnMerge.Width = 120; $btnMerge.Height = 36
    $btnMerge.Margin = New-Object Windows.Thickness(4)
    $btnMerge.ToolTip = "Вызвать TortoiseMerge: слева — текущий файл, справа — исходный (Main)"
    Apply-GlossyButtonStyle -Button $btnMerge
    [void]$btnPanel.Children.Add($btnMerge)

    $btnClose = New-Object Windows.Controls.Button
    $btnClose.Content = 'Закрыть'; $btnClose.Width = 100; $btnClose.Height = 36
    $btnClose.Margin = New-Object Windows.Thickness(4)
    $btnClose.IsDefault = $true
    Apply-GlossyButtonStyle -Button $btnClose
    [void]$btnPanel.Children.Add($btnClose)
    [void]$mainGrid.Children.Add($btnBorder)

    function Move-TaskFile {
        param($Item, [string]$TargetFolderName)
        $src = $Item.FilePath
        if (-not (Test-Path $src)) {
            [System.Windows.MessageBox]::Show("Файл не найден: $src", "Ошибка", "OK", "Warning")
            return $false
        }
        $dir = Split-Path $src -Parent
        while ($dir -and (Split-Path $dir -Leaf) -ne $Item.Folder) { $dir = Split-Path $dir -Parent }
        if (-not $dir) { $dir = Split-Path $src -Parent }
        $taskRoot = Split-Path $dir -Parent
        $relInside = $src.Substring($dir.Length).TrimStart('\')
        $targetBase = Join-Path $taskRoot $TargetFolderName
        $dest = Join-Path $targetBase $relInside
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        try {
            Move-Item -LiteralPath $src $dest -Force
            return $true
        } catch {
            [System.Windows.MessageBox]::Show("Не удалось переместить $src : $_", "Ошибка", "OK", "Error")
            return $false
        }
    }

    $btnMerge.Add_Click({
        $selItem = $null
        foreach ($item in $dg.Items) { if ($item.Selected) { $selItem = $item; break } }
        if (-not $selItem) {
            [System.Windows.MessageBox]::Show("Выберите объект для сравнения.", "Нет выбора", "OK", "Information")
            return
        }
        $typeFolderMap = @{ 'Procedure'='Procedure'; 'Function'='Functions'; 'Trigger'='Triggers'; 'Table'='Tables'; 'View'='Views'; 'Index'='Indexes'; 'PK'='PK'; 'FK'='FK'; 'Grant'='Grants' }
        $tf = $typeFolderMap[$selItem.Type]
        if (-not $tf) { $tf = 'Procedure' }
        $baseFile = ""
        $mineFile = ""
        $currentPath = ""
        $mainPathVal = ""
        try {
            $cfgInner = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
            $mainPathVal = $cfgInner.paths.bd_main_export
            $currentPath = $cfgInner.paths.bd_current_export
        } catch {}
        if ($mainPathVal) { $baseFile = Join-Path $mainPathVal ($tf + "\$($selItem.ObjectName).sql") }
        if ($currentPath) { $mineFile = Join-Path $currentPath ($tf + "\$($selItem.ObjectName).sql") }
        if (-not $baseFile -or -not (Test-Path $baseFile)) {
            [System.Windows.MessageBox]::Show("Исходный файл (Main) не найден:`n$baseFile", "Ошибка", "OK", "Warning")
            return
        }
        if (-not $mineFile -or -not (Test-Path $mineFile)) {
            [System.Windows.MessageBox]::Show("Файл Current не найден:`n$mineFile", "Ошибка", "OK", "Warning")
            return
        }
        if (-not $script:tortoiseMergePath -or -not (Test-Path $script:tortoiseMergePath)) {
            [System.Windows.MessageBox]::Show("TortoiseMerge не найден. Проверьте настройки.", "Ошибка", "OK", "Warning")
            return
        }
        try {
            Start-Process -FilePath $script:tortoiseMergePath -ArgumentList @("/base", $mineFile, "/mine", $baseFile)
        } catch {
            [System.Windows.MessageBox]::Show("Ошибка запуска TortoiseMerge:`n$_", "Ошибка", "OK", "Error")
        }
    })

    $btnMove.Add_Click({
        $selItems = @()
        foreach ($item in $dg.Items) { if ($item.Selected) { $selItems += $item } }
        if ($selItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Не выбрано ни одного объекта.", "Нет выбора", "OK", "Information")
            return
        }
        $moved = 0
        foreach ($item in $selItems) {
            if (Move-TaskFile -Item $item -TargetFolderName "Ready_$today") { $moved++ }
        }
        [System.Windows.MessageBox]::Show("Перенесено в Ready_$today`: $moved", "Результат", "OK", "Information")
        $window.Close()
    })
    $btnDelete.Add_Click({
        $selItems = @()
        foreach ($item in $dg.Items) { if ($item.Selected) { $selItems += $item } }
        if ($selItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Не выбрано ни одного объекта.", "Нет выбора", "OK", "Information")
            return
        }
        $removed = 0
        foreach ($item in $selItems) {
            if (Move-TaskFile -Item $item -TargetFolderName "Delete_$today") { $removed++ }
        }
        [System.Windows.MessageBox]::Show("Удалено в Delete_$today`: $removed", "Результат", "OK", "Information")
        $window.Close()
    })
    $btnClose.Add_Click({ $window.Close() })
    Add-Appl2Wrapper -Window $window -ContentElement $mainGrid -Title $window.Title
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    [void]$window.ShowDialog()
}

function Show-PbCompareInline {
    param([string]$Output = "")
    $data = @()
    $seen = @{}
    $hasDiff = $false
    "Show-PbCompareInline: called, Output length=$($Output.Length)" | Out-File $logFile -Append
    foreach ($l in ($Output -split "`r`n|`n")) {
        if ($l -match '^###PB_COMPARE_TABLE###\s*(.+)\|(.+)$') {
            $objFull = $matches[1].Trim()
            $status = $matches[2].Trim()
            $parts = $objFull.Split('\')
            $lib = if ($parts.Count -ge 2) { $parts[0] } else { "" }
            $objName = if ($parts.Count -ge 2) { $parts[1] } else { $objFull }
            $key = "$lib|$objName"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $statusRu = @{"DIFF"="Различаются"; "SAME"="Совпадают"; "NOT_IN_MAIN"="Нет в Main"; "NOT_IN_CURRENT"="Нет в Current"}[$status]
            if (-not $statusRu) { $statusRu = $status }
            if ($status -eq 'DIFF') { $hasDiff = $true }
            $data += [PSCustomObject]@{ Library = $lib; Object = $objName; Status = $statusRu; RawStatus = $status }
        }
    }
    "Show-PbCompareInline: unique objects: $($data.Count)" | Out-File $logFile -Append
    if ($data.Count -eq 0) { return }
    
    $dg = $window.FindName("CompareResultGrid")
    if (-not $dg) { return }
    
    $dg.ItemsSource = $null
    $dg.Columns.Clear()
    
    $c1 = New-Object Windows.Controls.DataGridTextColumn
    $c1.Header = 'Библиотека'; $c1.Binding = [Windows.Data.Binding]::new('Library')
    $c1.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::SizeToCells)
    $c1.MinWidth = 80; $c1.IsReadOnly = $true; [void]$dg.Columns.Add($c1)
    
    $c2 = New-Object Windows.Controls.DataGridTextColumn
    $c2.Header = 'Объект'; $c2.Binding = [Windows.Data.Binding]::new('Object')
    $c2.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::Star)
    $c2.MinWidth = 120; $c2.IsReadOnly = $true; [void]$dg.Columns.Add($c2)
    
    $c3 = New-Object Windows.Controls.DataGridTextColumn
    $c3.Header = 'Статус'; $c3.Binding = [Windows.Data.Binding]::new('Status')
    $c3.Width = 130; $c3.IsReadOnly = $true; [void]$dg.Columns.Add($c3)
    
    $dg.ItemsSource = $data
    
    # Update title with count
    $title = $window.FindName("CompareResultTitle")
    if ($title) { $title.Text = "Сравнение PB: $($data.Count) объектов" }
    
    # Show/hide diff button
    $btnDiff = $window.FindName("BtnShowDiff")
    if ($btnDiff) { $btnDiff.Visibility = if ($hasDiff) { "Visible" } else { "Collapsed" } }
    
    # Show the panel
    $border = $window.FindName("CompareResultBorder")
    if ($border) { $border.Visibility = "Visible" }
}

function Show-ResultInline {
    param([string]$Output = "", [string]$OpName = "", [string]$ResultPhrase = "")
    $dg = $window.FindName("CompareResultGrid")
    if (-not $dg) { return }
    $dg.ItemsSource = $null; $dg.Columns.Clear()
    $c1 = New-Object Windows.Controls.DataGridTextColumn
    $c1.Header = 'Проверка'; $c1.Binding = [Windows.Data.Binding]::new('Test')
    $c1.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::Star)
    $c1.MinWidth = 120; $c1.IsReadOnly = $true; [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn
    $c2.Header = 'Статус'; $c2.Binding = [Windows.Data.Binding]::new('Status')
    $c2.Width = 120; $c2.IsReadOnly = $true; [void]$dg.Columns.Add($c2)
    $items = @()
    if ($Output -match '\[(PASS|FAIL)\]') {
        foreach ($l in ($Output -split "`r`n|`n")) {
            if ($l -match '^\[(PASS|FAIL)\]\s*(.+)') {
                $status = $matches[1]
                $desc = $matches[2].Trim()
                $statusRu = if ($status -eq 'PASS') { 'Пройден' } else { 'Ошибка' }
                $items += [PSCustomObject]@{ Test = $desc; Status = $statusRu; Raw = $status }
            }
        }
    } elseif ($ResultPhrase) {
        $items += [PSCustomObject]@{ Test = $ResultPhrase; Status = 'Завершено'; Raw = 'DONE' }
    }
    $dg.ItemsSource = $items
    $title = $window.FindName("CompareResultTitle")
    if ($title) {
        $title.Text = if ($ResultPhrase) { "Результат: $ResultPhrase" } else { "Результат: Завершено" }
    }
    $btnDiff = $window.FindName("BtnShowDiff")
    if ($btnDiff) { $btnDiff.Visibility = "Collapsed" }
    $border = $window.FindName("CompareResultBorder")
    if ($border) { $border.Visibility = "Visible" }
}

function Get-TableData {
    param(
        [string]$OpName = "",
        [string]$Output = ""
    )
    if ($OpName -match '^VSS:') {
        $lines = $Output -split "`r`n|`n"
        $tableLines = @()
        $currentFile = ""
        foreach ($line in $lines) {
            if ($line -match '^\$/.+') {
                $currentFile = $line.Trim()
            }
            elseif ($line -match '^\s{2}(\S+)\s+(Exc|Out)\s') {
                $user = $matches[1]
                if ($currentFile) {
                    $tableLines += "$user  |  $currentFile"
                } else {
                    $tableLines += $line.TrimEnd()
                }
            }
        }
        if ($tableLines.Count -gt 0) {
            return ($tableLines -join "`r`n")
        }
    }
    return $null
}
# ── Анимация загрузки (GIF) ──
$script:currentAnimationTimer = $null
$script:animGifDir = Join-Path $ProjectRoot "docs\animations"
$script:animGifFiles = @(
    "01_spinner.gif", "02_dots.gif", "03_pulse.gif", "04_wave.gif", "05_blocks.gif",
    "06_rings.gif", "07_orbit.gif", "08_heartbeat.gif", "09_rainbow.gif", "10_flip.gif"
)

function Show-LoadingAnimation {
    param([int]$AnimIndex = 1, [string]$LabelText = "Выполняется")
    $loadingOverlay.Visibility = "Visible"
    if ($script:currentAnimationTimer) {
        try { $script:currentAnimationTimer.Stop() } catch {}
        $script:currentAnimationTimer = $null
    }
    $animElement = Build-LoadingAnimation -AnimIndex $AnimIndex -LabelText $LabelText
    if ($animElement) {
        $loadingContent.Content = $animElement
    }
}

# Таблица перевода имён фаз с английского на русский
$script:phaseNames = @{
    'Procedures'  = 'Процедуры'
    'Functions'   = 'Функции'
    'Triggers'    = 'Триггеры'
    'Tables'      = 'Таблицы'
    'Indexes'     = 'Индексы'
    'PrimaryKeys' = 'Первичные ключи'
    'ForeignKeys' = 'Внешние ключи'
    'Grants'      = 'Гранты'
    'SQLObjects'      = 'SQL-объекты'
    'PBLibraries'     = 'PB-библиотеки'
    'CompareCurrent'  = 'Сравнение Current → Main'
    'CompareMain'     = 'Сравнение Main → Current'
    'VSS-версия'      = 'Поиск в истории VSS'
}

function Show-OverlayProgress {
    $script:pbPhaseName = ""
    $script:pbPhaseCurrent = 0
    $script:pbPhaseMax = 0
    $script:pbPhaseIndex = 0
    $script:uiProcessDone = $false
    $pbPhase.Value = 0
    $pbStep.Value = 0
    $pbPhaseLabel.Text = "Инициализация..."
    $pbStepLabel.Text = ""
    $pbProgressWrap.Visibility = "Visible"
    $pbPhase.Visibility = "Visible"
    $pbStep.Visibility = "Visible"
}

function Hide-LoadingAnimation {
    if ($script:currentAnimationTimer) {
        try { $script:currentAnimationTimer.Stop() } catch {}
        $script:currentAnimationTimer = $null
    }
    $pbPhase.Visibility = "Collapsed"
    $pbStep.Visibility = "Collapsed"
    $pbProgressWrap.Visibility = "Collapsed"
    $loadingContent.Content = $null
    $loadingOverlay.Visibility = "Collapsed"
}

function Build-LoadingAnimation {
    param([int]$AnimIndex = 1, [string]$LabelText = "Выполняется")
    
    $root = New-Object Windows.Controls.StackPanel
    $root.HorizontalAlignment = "Center"
    $root.VerticalAlignment = "Center"
    
    $idx = [Math]::Max(0, [Math]::Min($AnimIndex - 1, $script:animGifFiles.Count - 1))
    $gifFile = Join-Path $script:animGifDir $script:animGifFiles[$idx]
    
    if (Test-Path $gifFile) {
        $img = New-Object Windows.Controls.Image
        $img.Width = 80; $img.Height = 80
        $img.Margin = "0,0,0,16"
        $img.Stretch = "None"
        
        $gifUri = New-Object System.Uri($gifFile)
        $img.Source = New-Object Windows.Media.Imaging.BitmapImage($gifUri)
        
        [void]$root.Children.Add($img)
    } else {
        $text = New-Object Windows.Controls.TextBlock
        $text.Text = "Выполняется..."
        $text.FontSize = 14
        $text.Foreground = [Windows.Media.Brushes]::DarkSlateGray
        $text.Margin = "0,20,0,0"
        [void]$root.Children.Add($text)
    }
    
    $statusText = New-Object Windows.Controls.TextBlock
    $statusText.Text = "${LabelText}..."
    $statusText.FontSize = 16
    $statusText.FontWeight = "SemiBold"
    $statusText.Foreground = [Windows.Media.Brushes]::DarkSlateGray
    $statusText.HorizontalAlignment = "Center"
    [void]$root.Children.Add($statusText)
    
    $subText = New-Object Windows.Controls.TextBlock
    $subText.Text = "пожалуйста, подождите"
    $subText.FontSize = 12
    $subText.Foreground = [Windows.Media.Brushes]::Gray
    $subText.HorizontalAlignment = "Center"
    $subText.Margin = "0,4,0,0"
    [void]$root.Children.Add($subText)
    
    return $root
}

# ── XAML ──
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ПРОД-GUI"
        Width="720" Height="720"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        AllowsTransparency="True"
        WindowStyle="None"
        Background="Transparent">
    <Window.Resources>
        <Style x:Key="LabelStyle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Foreground" Value="#4A5568"/>
            <Setter Property="Margin" Value="0,0,0,4"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style x:Key="InputStyle" TargetType="TextBox">
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderBrush" Value="#CBD5E0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style x:Key="PasswordStyle" TargetType="PasswordBox">
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderBrush" Value="#CBD5E0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style x:Key="ComboStyle" TargetType="ComboBox">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#CBD5E0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style x:Key="RunBtnStyle" TargetType="Button">
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="24,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>

    <Border x:Name="OuterWindowBorder" CornerRadius="60" Background="#33FFFFFF">
        <Border.Effect>
            <DropShadowEffect Color="#404040" Direction="270" ShadowDepth="4" BlurRadius="10" Opacity="0.5"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Border x:Name="AppTitleBar" Grid.Row="0" CornerRadius="10" Background="#05FFFFFF" Padding="20,2,20,0" Margin="25,1,25,0" Visibility="Collapsed"/>
            <Border Grid.Row="1" Background="#1A3A60" CornerRadius="46" Margin="4,0,4,4">
                <Border Background="White" CornerRadius="42" Margin="4">
                    <Grid VerticalAlignment="Stretch" HorizontalAlignment="Stretch">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                    <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <Grid Margin="24,20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>   <!-- 0: Header -->
            <RowDefinition Height="Auto"/>   <!-- 1: Operation -->
            <RowDefinition Height="Auto"/>   <!-- 2: Run button -->
            <RowDefinition Height="Auto"/>   <!-- 3: Compare result (ОП 2) -->
            <RowDefinition Height="Auto"/>   <!-- 4: Parameters -->
            <RowDefinition Height="Auto"/>   <!-- 5: Password -->
            <RowDefinition Height="*"/>       <!-- 6: Output -->
            <RowDefinition Height="Auto"/>   <!-- 7: Stop -->
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#3182CE" CornerRadius="12" Padding="20,14" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <!-- Logo (WPF-элементы: градиент + треугольник + текст) -->
                <Border x:Name="LogoBorder" Grid.Column="0" Width="180" Height="54" Margin="0,0,20,0" CornerRadius="6"/>
                
                <!-- Title (по центру оставшегося пространства) -->
                <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock Text="AIS Release Preparation" FontSize="20" FontWeight="Bold" Foreground="White" TextAlignment="Center"/>
                    <TextBlock Text="SQL &amp; PowerBuilder export, compare, RFC" FontSize="12" Foreground="#BEE3F8" Margin="0,4,0,0" TextAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Operation selector -->
        <StackPanel Grid.Row="1" Margin="0,0,0,12">
            <TextBlock Text="Операция" Style="{StaticResource LabelStyle}" FontSize="14"/>
            <ComboBox x:Name="CmbOperation" Style="{StaticResource ComboStyle}" Height="34"/>
            <TextBlock x:Name="TxtDescription" FontSize="12" Foreground="#718096" Margin="0,6,0,0" TextWrapping="Wrap" FontStyle="Italic"/>
        </StackPanel>

        <!-- Run button (для обычных операций) -->
        <Border x:Name="BtnRunBorder" Grid.Row="2" Margin="0,0,0,12" Background="#EBF4FF" CornerRadius="12" Padding="16,10" BorderBrush="#BEE3F8" BorderThickness="1">
            <Button x:Name="BtnRun" Content="Run" Style="{StaticResource RunBtnStyle}" Width="200" Height="44" FontSize="16" HorizontalAlignment="Center"/>
        </Border>

        <!-- Settings buttons (только для Настройки параметров, скрыто по умолчанию) -->
        <Border x:Name="BtnSettingsBorder" Grid.Row="2" Margin="0,0,0,12" Background="#EBF4FF" CornerRadius="12" Padding="16,10" BorderBrush="#BEE3F8" BorderThickness="1" Visibility="Collapsed">
            <WrapPanel x:Name="BtnSettingsPanel" HorizontalAlignment="Center">
                <Button x:Name="BtnSaveSettings" Content="Сохранить" Width="100" Margin="0,0,8,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="White" Background="#3182CE" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="BtnResetSettings" Content="Сбросить" Width="100" Margin="0,0,8,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                <Button x:Name="BtnValidatePaths" Content="Проверить пути" Width="120" Margin="0,0,8,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                <Button x:Name="BtnExportSettings" Content="Экспорт" Width="80" Margin="0,0,8,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                <Button x:Name="BtnImportSettings" Content="Импорт" Width="80" Margin="0,0,0,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                <Button x:Name="BtnSettingsHistory" Content="Журнал изменений" Width="140" Margin="8,0,0,0" Height="36" FontSize="14" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
            </WrapPanel>
        </Border>

        <!-- Compare PB result panel (скрыто по умолчанию, показывается для ОП 2) -->
        <Border x:Name="CompareResultBorder" Grid.Row="3" Background="White" CornerRadius="12" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,12" Visibility="Collapsed">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" x:Name="CompareResultTitle" Text="Сравнение PowerBuilder: Current vs Main" Style="{StaticResource LabelStyle}" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                    <Button Grid.Column="1" x:Name="BtnShowDiff" Content="Сравнить выбранные" Width="160" Height="28" FontSize="12" FontWeight="SemiBold" Foreground="White" Background="#3182CE" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0" Visibility="Collapsed"/>
                    <Button Grid.Column="2" x:Name="BtnHideCompareResult" Content="Скрыть" Width="80" Height="28" FontSize="12" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                </Grid>
                <DataGrid x:Name="CompareResultGrid" Grid.Row="1" AutoGenerateColumns="False" HeadersVisibility="All" RowHeaderWidth="0" AlternatingRowBackground="LightGray" FontSize="12" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" SelectionMode="Extended" SelectionUnit="FullRow" MinHeight="80" MaxHeight="300"/>
            </Grid>
        </Border>

        <!-- Parameters area -->
        <Border x:Name="ParamsBorder" Grid.Row="4" Background="White" CornerRadius="12" Padding="20,16" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,12">
            <StackPanel x:Name="ParamsPanel"/>
        </Border>

        <!-- Password area -->
        <Border x:Name="PasswordBorder" Grid.Row="5" Background="White" CornerRadius="12" Padding="20,16" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock x:Name="PwdLabel" Text="Пароль Sybase" Style="{StaticResource LabelStyle}" FontSize="13"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <PasswordBox x:Name="PwdBox" Grid.Column="0" Style="{StaticResource PasswordStyle}" FontSize="13"/>
                    <TextBox x:Name="PwdText" Grid.Column="0" Style="{StaticResource InputStyle}" FontSize="13" Visibility="Collapsed"/>
                    <Button x:Name="BtnTogglePwd" Grid.Column="1" Content="Show" Margin="8,0,0,0" Width="48" FontSize="12" VerticalAlignment="Center" HorizontalAlignment="Center" Background="Transparent" BorderThickness="0" Cursor="Hand" Foreground="#3182CE"/>
                </Grid>
            </StackPanel>
        </Border>

        <!-- Loading overlay (поверх области вывода) -->
        <Border x:Name="LoadingOverlay" Grid.Row="6" Panel.ZIndex="10" Background="#CCF0F4FF" CornerRadius="12" Visibility="Collapsed" IsHitTestVisible="False" Margin="0,0,0,16">
            <ContentControl x:Name="LoadingContent" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>

        <!-- Log area -->
        <Border Grid.Row="6" Background="White" CornerRadius="12" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,16" MinHeight="200">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Output" Style="{StaticResource LabelStyle}" VerticalAlignment="Center" FontSize="14" FontWeight="Bold"/>
                    <StackPanel Grid.Column="2" Orientation="Horizontal">
                        <Button x:Name="BtnStop" Content="Stop" Width="80" Height="28" FontSize="12" FontWeight="SemiBold" Foreground="#E53E3E" Background="White" BorderBrush="#E53E3E" BorderThickness="1" Cursor="Hand" Visibility="Collapsed" Margin="0,0,8,0"/>
                        <Button x:Name="BtnExportLog" Content="Export Log" Width="90" Height="28" FontSize="12" FontWeight="SemiBold" Foreground="#3182CE" Background="White" BorderBrush="#3182CE" BorderThickness="1" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                <TextBox x:Name="TxtLog" Grid.Row="1" IsReadOnly="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Background="#F7FAFC" BorderThickness="0" Foreground="#2D3748" AcceptsReturn="True" Padding="8"/>
            </Grid>
        </Border>
    </Grid>
    </ScrollViewer>
    <Border x:Name="PbProgressWrap" Grid.Row="1" Background="#E2E8F0" BorderThickness="0,1,0,0" BorderBrush="#CBD5E0" Height="44" Visibility="Collapsed">
        <StackPanel Margin="8,2,8,2">
            <Grid Height="18" Margin="0,0,0,2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="140"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="PbPhaseLabel" Grid.Column="0" VerticalAlignment="Center" FontSize="11" Foreground="#4A5568" TextTrimming="CharacterEllipsis" Margin="0,0,4,0"/>
                <ProgressBar x:Name="PbPhase" Grid.Column="1" Minimum="0" Maximum="100" Height="12" Margin="0,3,0,3" Foreground="#2B6CB0" Background="#E2E8F0" BorderThickness="0"/>
            </Grid>
            <Grid Height="18">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="140"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="PbStepLabel" Grid.Column="0" VerticalAlignment="Center" FontSize="11" Foreground="#4A5568" Margin="0,0,4,0"/>
                <ProgressBar x:Name="PbStep" Grid.Column="1" Minimum="0" Maximum="100" Height="12" Margin="0,3,0,3" Foreground="#3182CE" Background="#E2E8F0" BorderThickness="0"/>
            </Grid>
        </StackPanel>
    </Border>
    </Grid>
                </Border>
            </Border>
        </Grid>
    </Border>
</Window>
"@

"XAML defined" | Out-File $logFile -Append

# ── Load XAML ──
try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $script:mainWindow = $window
    "Window loaded" | Out-File $logFile -Append
} catch {
    [System.Windows.MessageBox]::Show("Failed to load GUI: $_", "Fatal Error", "OK", "Error")
    exit 1
}

if ($null -eq $window) {
    [System.Windows.MessageBox]::Show("GUI window is null.", "Fatal Error", "OK", "Error")
    exit 1
}

# ── Get controls ──
$cmbOp        = $window.FindName("CmbOperation")
$paramsPanel  = $window.FindName("ParamsPanel")
$pwdBox   = $window.FindName("PwdBox")
$pwdText  = $window.FindName("PwdText")
$btnTogglePwd = $window.FindName("BtnTogglePwd")
# Принудительная английская раскладка на полях пароля (без Win32 P/Invoke, через управляемый .NET API)
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
$script:prevLayout = $null
$pwdBox.Add_GotFocus({
    $script:prevLayout = [System.Windows.Forms.InputLanguage]::CurrentInputLanguage
    $en = [System.Windows.Forms.InputLanguage]::FromCulture([System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
    if ($en) { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $en }
})
$pwdBox.Add_LostFocus({
    if ($script:prevLayout) { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $script:prevLayout }
})
$pwdText.Add_GotFocus({
    $script:prevLayout = [System.Windows.Forms.InputLanguage]::CurrentInputLanguage
    $en = [System.Windows.Forms.InputLanguage]::FromCulture([System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
    if ($en) { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $en }
})
$pwdText.Add_LostFocus({
    if ($script:prevLayout) { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $script:prevLayout }
})
$pwdBorder    = $window.FindName("PasswordBorder")
$pwdLabel     = $window.FindName("PwdLabel")
$btnRun       = $window.FindName("BtnRun")
$btnStop      = $window.FindName("BtnStop")
$txtLog       = $window.FindName("TxtLog")
$btnExportLog = $window.FindName("BtnExportLog")
$pbPhase      = $window.FindName("PbPhase")
$pbStep       = $window.FindName("PbStep")
# Применить дизайн APPL2 для прогресс-баров
Apply-GlossyProgressStyle -ProgressBar $pbPhase -BarColorTop "#1A3A60" -BarColorBottom "#2B6CB0"
Apply-GlossyProgressStyle -ProgressBar $pbStep -BarColorTop "#0F2440" -BarColorBottom "#1A5276"
$pbPhaseLabel = $window.FindName("PbPhaseLabel")
$pbStepLabel  = $window.FindName("PbStepLabel")
$pbProgressWrap = $window.FindName("PbProgressWrap")
$txtDesc      = $window.FindName("TxtDescription")
$logoBorder = $window.FindName("LogoBorder")
$paramsBorder     = $window.FindName("ParamsBorder")
$btnRunBorder      = $window.FindName("BtnRunBorder")
$btnSettingsBorder = $window.FindName("BtnSettingsBorder")
$btnSaveSettings   = $window.FindName("BtnSaveSettings")
$btnResetSettings  = $window.FindName("BtnResetSettings")
$btnValidatePaths  = $window.FindName("BtnValidatePaths")
$btnExportSettings = $window.FindName("BtnExportSettings")
$btnImportSettings = $window.FindName("BtnImportSettings")
$btnSettingsHistory = $window.FindName("BtnSettingsHistory")
$loadingOverlay   = $window.FindName("LoadingOverlay")
$loadingContent   = $window.FindName("LoadingContent")
"Controls: txtDesc=$($null -ne $txtDesc)" | Out-File $logFile -Append

"Controls found: cmbOp=$($null -ne $cmbOp), params=$($null -ne $paramsPanel), pwdBox=$($null -ne $pwdBox)" | Out-File $logFile -Append


. "C:\AIS\AI\Prod\scripts\Settings-Module.ps1"

# ── Operation definitions ──
$operations = @(
    @{
        Name = "Settings"
        RusName = "Настройки параметров"
        Description = "Просмотр и редактирование путей, логинов и параметров проекта"
        NeedsPassword = $false
        HasCustomUI = $true
        Fields = @()
        Script = {
            param($params, $password)
            # Custom UI handled separately
        }
    },
    @{
        Name = "Run Tests (Run-Tests.ps1)"
        RusName = "Запуск тестов"
        Description = "Автотестирование проекта: парсер PS-файлов, кодировка UTF-8 BOM, наличие операций, английский текст в Write-Host, критичные пути."
        NeedsPassword = $false
        Fields = @()
        Checkboxes = @(
            @{ Name="QuickMode"; Label="Быстрый режим (только парсер + кодировка)"; Hint="Skip slow checks" }
        )
        Script = {
            param($params, $password, $checks)
            $ps = "C:\AIS\AI\Prod\scripts\Run-Tests.ps1"
            if ($checks.QuickMode) {
                & powershell -ExecutionPolicy Bypass -File $ps -Quick 2>&1
            } else {
                & powershell -ExecutionPolicy Bypass -File $ps 2>&1
            }
        }
    },
    @{
        Name = "Export Service"
        RusName = "Export Service (выгрузка проекта)"
        Description = "Выгрузка проекта: функционал (bin, scripts), настройки (config), документация (docs), правила (rules, .opencode). Исключаются архивы, журналы, копии объектов (BD, PB_Current, PB_Main). Пароли и токены заменяются на заглушки."
        NeedsPassword = $false
        Fields = @(
            @{ Name="DestPath"; Label="Путь выгрузки"; Default=""; Hint="Путь к папке выгрузки (оставьте пустым для значения из Настроек)" }
        )
        Script = {
            param($params)
            $ps = "C:\AIS\AI\Prod\scripts\Export-Service.ps1"
            $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
            $src = if ($cfg.export_service.source_path) { $cfg.export_service.source_path } else { "C:\AIS\AI\Prod" }
            $dst = if ($params.DestPath) { $params.DestPath } elseif ($cfg.export_service.dest_path) { $cfg.export_service.dest_path } else { "Z:\AI\Prod" }
            & powershell -ExecutionPolicy Bypass -File $ps -SourcePath $src -DestPath $dst -Force 2>&1
        }
    },
    @{
        Name = "Collect PROD Objects"
        RusName = "Собрать объекты для вывода в ПРОД"
        Description = "Копирование объектов PB и SQL из актуальных источников в папку PROD задачи, затем сравнение с последней папкой Ready."
        NeedsPassword = $false
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default="";  Hint="Имя задачи Jira для поиска Ready_* папок"; Required=$true },
            @{ Name="CollectPath"; Label="Путь для сбора объектов для выгрузки в ПРОД"; Default=""; Hint="Путь к папке сбора объектов для PROD (оставьте пустым для значения из Настроек)" }
        )
        Script = {
            param($params)
            $cfgPath = "C:\AIS\AI\Prod\config\config.json"
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pbCurrent = $cfg.paths.pb_current_export       # C:\AIS\AI\Prod\PB_Current
            $bdCurrent = $cfg.paths.bd_current_export        # C:\AIS\AI\Prod\BD\dev_golden\golden
            $releaseRoot = $cfg.paths.release_root           # C:\AIS\1 Release
            $TaskName = $params.TaskName
            if (-not $TaskName) { throw "Не указан Task Name" }

            # Поиск папки задачи: сначала префикс (самая длинная), потом точное совпадение
            $taskPath = Join-Path $releaseRoot $TaskName
            $prefixMatch = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
            if ($prefixMatch) {
                $taskPath = $prefixMatch.FullName
            } elseif (-not (Test-Path $taskPath)) {
                throw "Папка задачи не найдена: $taskPath"
            }
            Write-Host "Задача: $taskPath"

            # Сбор объектов из Ready_* (latest версия на baseName)
            $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
            if (-not $readyDirs) { throw "Папки Ready_* не найдены в $taskPath" }
            $latestReadyDir = $readyDirs | Select-Object -First 1
            Write-Host "Последняя Ready: $($latestReadyDir.Name)"

            $pbLatest = @{}; $sqlLatest = @{}
            foreach ($rd in $readyDirs) {
                Get-ChildItem $rd.FullName -Recurse -File | ForEach-Object {
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                    if ($_.Extension -match '^\.sr') {
                        if (-not $pbLatest.ContainsKey($base)) {
                            $pbLatest[$base] = @{ BaseName = $base; FileName = $_.Name; ReadyDir = $rd.Name; FullPath = $_.FullName }
                        }
                    } elseif ($_.Extension -eq '.sql') {
                        if (-not $sqlLatest.ContainsKey($base)) {
                            $sqlLatest[$base] = @{ BaseName = $base; FileName = $_.Name; ReadyDir = $rd.Name; FullPath = $_.FullName }
                        }
                    }
                }
            }
            Write-Host "Найдено: PB=$($pbLatest.Count), SQL=$($sqlLatest.Count)"

            # Определение библиотеки PB по baseName
            function Get-PbLibrary {
                param([string]$ObjectName)
                foreach ($dir in @($pbCurrent, $cfg.paths.pb_main_export)) {
                    if (Test-Path $dir) {
                        $f = Get-ChildItem $dir -Recurse -File -Filter "$ObjectName.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($f) { return $f.Directory.Name }
                    }
                }
                return "UNKNOWN"
            }

            # Создание папки PROD
            $prodPath = Join-Path $taskPath "PROD"
            if (-not (Test-Path $prodPath)) { New-Item -ItemType Directory -Path $prodPath -Force | Out-Null }
            Write-Host "Папка PROD: $prodPath"

            # === Копирование PB объектов ===
            $pbErrors = @()
            $pbMismatch = @()
            if ($pbLatest.Count -gt 0) {
                $pbProdDir = Join-Path $prodPath "PB"
                if (-not (Test-Path $pbProdDir)) { New-Item -ItemType Directory -Path $pbProdDir -Force | Out-Null }
                foreach ($key in $pbLatest.Keys) {
                    $lib = Get-PbLibrary -ObjectName $key
                    $libDir = Join-Path $pbProdDir $lib
                    if (-not (Test-Path $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }
                    $srcFile = Get-ChildItem $pbCurrent -Recurse -File -Filter "$key.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($srcFile) {
                        # PB_Current должен совпадать с самым свежим объектом из всех Ready_*
                        $readyFile = $pbLatest[$key].FullPath
                        $curHash   = (Get-FileHash -Algorithm MD5 $srcFile.FullName).Hash
                        $readyHash = (Get-FileHash -Algorithm MD5 $readyFile).Hash
                        if ($curHash -eq $readyHash) {
                            Copy-Item $srcFile.FullName (Join-Path $libDir $srcFile.Name) -Force
                            Write-Host "PB: $key -> PROD\PB\$lib\$($srcFile.Name)"
                        } else {
                            $pbMismatch += $key
                            Write-Host "PB: $key НЕ совпадает с последним Ready ($($pbLatest[$key].ReadyDir)) — в ПРОД НЕ выложен" -ForegroundColor Red
                            Write-Host "###PB_MISMATCH###$key|PB_Current=$($srcFile.FullName)|Ready=$readyFile"
                        }
                    } else {
                        $pbErrors += $key
                        Write-Host "ОШИБКА: $key не найден в PB_Current" -ForegroundColor Red
                    }
                }
            }

            # === Копирование SQL объектов ===
            $sqlErrors = @()
            if ($sqlLatest.Count -gt 0) {
                $sqlProdDir = Join-Path $prodPath "SQL"
                if (-not (Test-Path $sqlProdDir)) { New-Item -ItemType Directory -Path $sqlProdDir -Force | Out-Null }
                foreach ($key in $sqlLatest.Keys) {
                    $srcFile = Get-ChildItem $bdCurrent -Recurse -File -Filter "$key.sql" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($srcFile) {
                        Copy-Item $srcFile.FullName (Join-Path $sqlProdDir $srcFile.Name) -Force
                        Write-Host "SQL: $key -> PROD\SQL\$($srcFile.Name)"
                    } else {
                        $sqlErrors += $key
                        Write-Host "ОШИБКА: $key не найден в BD Current" -ForegroundColor Red
                    }
                }
            }

            # === VSS статус для PB объектов ===
            $vssMap = @{}
            $vssAttempted = $false
            try {
                $vssExe = $cfg.vss.ss_exe
                $vssDb  = $cfg.vss.db_path
                $vssUser2 = $cfg.vss.user
                if ($vssExe -and (Test-Path $vssExe) -and $vssDb) {
                    $vssAttempted = $true
                    $vssPassPlain = if ($params.VssPass) { $params.VssPass } else { "" }

                    # Устанавливаем окружение VSS (как VSS-Utils.ps1)
                    $vssDir = $vssDb
                    if ($vssDir -match 'srcsafe\.ini$') { $vssDir = [System.IO.Path]::GetDirectoryName($vssDir) }
                    $env:SSDIR = $vssDir

                    # Сканируем каждый PB объект по полному VSS-пути
                    Write-Host "  VSS: проверка $($pbLatest.Keys.Count) объектов..." -ForegroundColor Gray
                    foreach ($key in $pbLatest.Keys) {
                        $lib = Get-PbLibrary -ObjectName $key
                        $fn = [System.IO.Path]::GetFileName($pbLatest[$key].FullPath)
                        $vssPath = "$/SRC125/gold/$lib/$fn"
                        Write-Host "  VSS: $vssPath" -ForegroundColor Gray
                        $vssOut = & $vssExe Status $vssPath -I-Y -Y"$vssUser2,$vssPassPlain" 2>&1 | Out-String
                        if ($vssOut -match 'No checked|не найдены|не извлеч') {
                            $vssMap[$fn] = "Свободен"
                        } elseif ($vssOut -match '\s(\w+)\s+(Exc|Out)\s') {
                            $vssMap[$fn] = "Занят: $($matches[1])"
                        } else {
                            $vssMap[$fn] = "Свободен"
                        }
                    }
                }
            } catch { Write-Host "  VSS: ошибка ($($_.Exception.Message))" -ForegroundColor Yellow }

            # === Сравнение PROD vs Ready и сборка результатов ===
            Write-Host ""
            Write-Host "=== Результаты сборки PROD ===" -ForegroundColor Cyan
            $allResults = @()

            # PB результаты
            foreach ($key in $pbLatest.Keys) {
                $lib = Get-PbLibrary -ObjectName $key
                $prodFile = Get-ChildItem (Join-Path $prodPath "PB\$lib") -File -Filter "$key.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                $readyFile = $pbLatest[$key].FullPath
                $readyFileName = $pbLatest[$key].FileName
                $vssStatus = if ($vssMap.ContainsKey($readyFileName)) { $vssMap[$readyFileName] } elseif ($vssAttempted) { "VSS недоступен" } else { "VSS не проверен" }
                $prodDir = if ($prodFile) { [System.IO.Path]::GetDirectoryName($prodFile.FullName) } else { "ОШИБКА: не скопирован" }
                if (-not $prodFile) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "PB"; Status = "Нет в PROD"; Path = $prodDir; VssStatus = $vssStatus }
                    Write-Host "  PB $key : Нет в PROD  VSS: $vssStatus" -ForegroundColor Red
                    continue
                }
                if (-not (Test-Path $readyFile)) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "PB"; Status = "Нет в Ready"; Path = $prodDir; VssStatus = $vssStatus }
                    Write-Host "  PB $key : Нет в Ready (уже скопирован)  VSS: $vssStatus" -ForegroundColor Yellow
                    continue
                }
                $ph = (Get-FileHash $prodFile.FullName -Algorithm MD5).Hash
                $rh = (Get-FileHash $readyFile -Algorithm MD5).Hash
                if ($ph -eq $rh) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "PB"; Status = "Совпадает с Ready"; Path = $prodDir; VssStatus = $vssStatus }
                    Write-Host "  PB $key : Совпадает с Ready  VSS: $vssStatus  $prodDir" -ForegroundColor Green
                } else {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "PB"; Status = "НЕ СОВПАДАЕТ"; Path = $prodDir; VssStatus = $vssStatus }
                    Write-Host "  PB $key : НЕ СОВПАДАЕТ  VSS: $vssStatus" -ForegroundColor Red
                }
            }

            # SQL результаты
            foreach ($key in $sqlLatest.Keys) {
                $prodFile = Get-ChildItem (Join-Path $prodPath "SQL") -File -Filter "$key.sql" -ErrorAction SilentlyContinue | Select-Object -First 1
                $readyFile = $sqlLatest[$key].FullPath
                $prodDir = if ($prodFile) { [System.IO.Path]::GetDirectoryName($prodFile.FullName) } else { "ОШИБКА: не скопирован" }
                if (-not $prodFile) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "SQL"; Status = "Нет в PROD"; Path = $prodDir; VssStatus = "-" }
                    Write-Host "  SQL $key : Нет в PROD" -ForegroundColor Red
                    continue
                }
                if (-not (Test-Path $readyFile)) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "SQL"; Status = "Нет в Ready"; Path = $prodDir; VssStatus = "-" }
                    Write-Host "  SQL $key : Нет в Ready (уже скопирован)" -ForegroundColor Yellow
                    continue
                }
                $ph = (Get-FileHash $prodFile.FullName -Algorithm MD5).Hash
                $rh = (Get-FileHash $readyFile -Algorithm MD5).Hash
                if ($ph -eq $rh) {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "SQL"; Status = "Совпадает с Ready"; Path = $prodDir; VssStatus = "-" }
                    Write-Host "  SQL $key : Совпадает с Ready  $prodDir" -ForegroundColor Green
                } else {
                    $allResults += [PSCustomObject]@{ Object = $key; Type = "SQL"; Status = "НЕ СОВПАДАЕТ"; Path = $prodDir; VssStatus = "-" }
                    Write-Host "  SQL $key : НЕ СОВПАДАЕТ" -ForegroundColor Red
                }
            }

            # Вывод итога
            $totalObjects = $pbLatest.Count + $sqlLatest.Count
            $errorCount = $pbErrors.Count + $sqlErrors.Count
            Write-Host ""
            Write-Host "=== ИТОГО ===" -ForegroundColor Cyan
            Write-Host "Всего объектов: $totalObjects"
            if ($errorCount -gt 0) { Write-Host "Ошибок копирования: $errorCount" -ForegroundColor Red }
            if ($pbMismatch.Count -gt 0) {
                Write-Host "Расхождение PB_Current и последнего Ready (НЕ выложено в ПРОД): $($pbMismatch.Count) -> $($pbMismatch -join ', ')" -ForegroundColor Red
            }

            # Маркеры для GUI
            if ($totalObjects -eq 0) {
                Write-Host "###PROD_NONE###Нет объектов для вывода"
            } else {
                foreach ($r in $allResults) {
                    Write-Host ("###PROD_OBJ###{0}|{1}|{2}|{3}|{4}" -f $r.Object, $r.Type, $r.Status, $r.Path, $r.VssStatus)
                }
            }
        }
    },
    @{
        Name = "Export PB: Current or Main"
        RusName = "Выгрузка PB: Current или Main"
        Description = "Выгрузка объектов PowerBuilder из PBL-файлов с помощью pbldump. Если указана задача — выгружаются только объекты из Ready_* папок этой задачи."
        NeedsPassword = $false
        Fields = @(
            @{ Name="Source"; Label="Источник"; Default="Current"; Hint="Источник: Current (C:\Work\gold) или Main (C:\SRC125\gold). Путь настраивается в Настройки параметров."; Items=@("Current","Main") }
            @{ Name="ExportPath"; Label="Путь выгрузки"; Default=""; Hint="Путь к папке выгрузки (определяется источником). Настраивается в Настройки параметров."; ReadOnly=$true }
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Оставьте пустым для выгрузки всех объектов" }
        )
        Script = {
            param($params)
            $ps = "C:\AIS\AI\Prod\scripts\Export-PB.ps1"
            $cmdArgs = @("-Source", $params.Source)
            if ($params.TaskName) { $cmdArgs += @("-TaskName", $params.TaskName) }
            & powershell -ExecutionPolicy Bypass -File $ps @cmdArgs 2>&1
        }
    },
    @{
        Name = "Compare PB: Current and Main"
        RusName = "Сравнение PB: Current и Main"
        Description = "Сравнение PowerBuilder-объектов Current и Main (MD5-хеши). Если указана задача — сравниваются только объекты из Ready_* папок этой задачи."
        NeedsPassword = $false
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default="";  Hint="Оставьте пустым для сравнения всех объектов" }
            @{ Name="OutputFile"; Label="Файл отчёта"; Default="C:\AIS\AI\Prod\compare_pb_report.txt";  Hint="Output file (optional)" }
        )
        Script = {
            param($params)
            $ps = "C:\AIS\AI\Prod\scripts\Compare-PB.ps1"
            $cmdArgs = @("-OutputFile", $params.OutputFile)
            if ($params.TaskName) { $cmdArgs += @("-TaskName", $params.TaskName) }
            & powershell -ExecutionPolicy Bypass -File $ps @cmdArgs 2>&1
        }
    },
    @{
        Name = "SQL Export"
        RusName = "Выгрузка SQL"
        Description = "Экспорт объектов БД. Если задача не указана — выгружаются все типы SQL. Если задача указана — только объекты из её папок Ready_* и Git_*."
        NeedsPassword = $true
        Fields = @(
            @{ Name="Source";     Label="Источник"; Default="Current";  Hint="Current / Main"; Items=@("Current","Main") }
            @{ Name="Server";     Label="Сервер"; Default="dev_golden";  Hint="galaxy / dev_golden" }
            @{ Name="Db";         Label="База данных"; Default="golden";  Hint="Имя БД" }
            @{ Name="ObjectType"; Label="Тип объекта"; Default="";  Hint="Пусто — все типы"; Items=@("","Procedure","Functions","Triggers","Tables","Views","Indexes","PK","FK","Grants") }
            @{ Name="BdExportPath"; Label="Путь для выгрузки"; Default="";  Hint="Путь выгрузки (зависит от Источника)" }
            @{ Name="TaskName";   Label="Имя задачи (Jira)"; Default="";  Hint="Пусто — все типы. Указано — только объекты из Ready_*/Git_* задачи" }
        )
        Script = {
            param($params, $password)
            $source = $params.Source
            $server = $params.Server
            $db = if ($params.Db) { $params.Db } else { "golden" }
            $taskName = $params.TaskName
            
            # Создаём необходимые директории заранее, чтобы избежать ошибок "путь не найден"
            $configPath = "C:\AIS\AI\Prod\config\config.json"
            $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            @($cfg.paths.bd_current_export, $cfg.paths.bd_main_export, $cfg.paths.ready_merged_root, "C:\Temp\ReadyMerged") | ForEach-Object {
                if ($_ -and -not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
            }
            @("Procedure","Functions","Triggers","Tables","Views","Indexes","PK","FK","Grants","LOGS") | ForEach-Object {
                $p = Join-Path $cfg.paths.bd_current_export $_; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                $p = Join-Path $cfg.paths.bd_main_export $_; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
            }
            
            # Если задача не указана — полный экспорт всех типов
            if (-not $taskName) {
                $bat = "C:\AIS\AI\Prod\bin\SQL_exp_param.bat"
                if ($source -eq "Main" -or $source -eq "main") { $srv = "galaxy" }
                else { $srv = "dev_golden" }
                $exportPath = if ($params.BdExportPath) { $params.BdExportPath.Trim() } else { "" }
                $objectType = if ($params.ObjectType) { $params.ObjectType.Trim() } else { "" }
                $quotedArgs = @($srv, $db, $password, "", $exportPath) | ForEach-Object { "`"$_`"" }
                $quotedArgs += "`"$objectType`""
                & cmd /c "`"$bat`" $($quotedArgs -join ' ') 2>&1"
                return
            }
            
            # Если задача указана — ищем SQL-объекты в её папках
            $configPath = "C:\AIS\AI\Prod\config\config.json"
            $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $releaseRoot = $cfg.paths.release_root
            
            $taskPath = Join-Path $releaseRoot $taskName
            $prefixMatch = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue `
                | Where-Object { $_.Name -like "$taskName*" } | Sort-Object Name -Descending | Select-Object -First 1
            if ($prefixMatch) {
                $taskPath = $prefixMatch.FullName
            } elseif (-not (Test-Path $taskPath)) {
                throw "Папка задачи не найдена: $taskPath"
            }
            
            # Сервер/БД/тип для выгрузки
            if ($source -eq "Main" -or $source -eq "main") { $srv = "galaxy" } else { $srv = "dev_golden" }
            $singleType = if ($params.ObjectType) { $params.ObjectType.Trim() } else { "" }

            # Собираем объекты ТОЛЬКО из папок Ready_* и Git_* (исключаем Merge/Test/Describe)
            # имена + тип (по CREATE в файле), без дубликатов
            $bat = "C:\AIS\AI\Prod\bin\SQL_exp_single.bat"

            $sqlTypePatterns = @(
                @{ Regex = 'CREATE\s+PROC(?:EDURE)?\b';  Bat = 'Procedure'; Rus = 'Процедура' }
                @{ Regex = 'CREATE\s+FUNCTION\b';        Bat = 'Function';  Rus = 'Функция' }
                @{ Regex = 'CREATE\s+TRIGGER\b';         Bat = 'Trigger';   Rus = 'Триггер' }
                @{ Regex = 'CREATE\s+TABLE\b';           Bat = 'Table';     Rus = 'Таблица' }
                @{ Regex = 'CREATE\s+VIEW\b';            Bat = 'View';      Rus = 'Представление' }
            )

            $taskObjects = @{}
            foreach ($prefix in @('Ready_*','Git_*')) {
                Get-ChildItem $taskPath -Directory -Filter $prefix -ErrorAction SilentlyContinue | ForEach-Object {
                    $folderDir = $_.FullName
                    Get-ChildItem $folderDir -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue | ForEach-Object {
                        $sqlFile = $_
                        $firstLines = Get-Content $sqlFile.FullName -TotalCount 20 -ErrorAction SilentlyContinue
                        $sqlText = $firstLines -join "`n"
                        $targetType = $null; $typeRus = ""; $objName = $null
                        foreach ($pattern in $sqlTypePatterns) {
                            $m = [regex]::Match($sqlText, $pattern.Regex)
                            if ($m.Success) {
                                $targetType = $pattern.Bat; $typeRus = $pattern.Rus
                                $rest = $sqlText.Substring($m.Index + $m.Length).Trim()
                                $nameMatch = [regex]::Match($rest, '^(?:\w+\.)?(\w+)')
                                if ($nameMatch.Success) { $objName = $nameMatch.Groups[1].Value }
                                break
                            }
                        }
                        if (-not $targetType) { return }
                        if (-not $objName) { $objName = [System.IO.Path]::GetFileNameWithoutExtension($sqlFile.Name) }
                        if ($singleType -and $singleType -ne $targetType) { return }
                        if (-not $taskObjects.ContainsKey($objName)) {
                            $taskObjects[$objName] = @{ Type = $targetType; Rus = $typeRus; File = $sqlFile.FullName }
                        }
                    }
                }
            }

            if ($taskObjects.Count -eq 0) {
                Write-Host "###SQL_TASK_NONE###Нет SQL-объектов для задачи $taskName (Ready_*/Git_*)"
                return
            }

            # Базовая папка выгрузки (совпадает с тем, куда пишет SQL_exp_single.bat)
            $basedir = if ($source -eq "Main" -or $source -eq "main") { $cfg.paths.bd_main_export } else { $cfg.paths.bd_current_export }

            Write-Host "=== Выборочный экспорт SQL (из БД): $taskName ===" -ForegroundColor Cyan
            Write-Host "Источник: $srv / $db" -ForegroundColor Gray
            Write-Host "Папка выгрузки: $basedir" -ForegroundColor Gray
            Write-Host "Объектов к выгрузке: $($taskObjects.Count)" -ForegroundColor Yellow

            $typeFolder = @{ Procedure='Procedure'; Function='Functions'; Trigger='Triggers'; Table='Tables'; View='Views'; Index='Indexes'; PK='PK'; FK='FK'; Grant='Grants' }
            $exported = 0; $failed = 0; $idx = 0
            foreach ($key in ($taskObjects.Keys | Sort-Object)) {
                $idx++
                $obj = $taskObjects[$key]
                $objType = $obj.Type; $objName = $key; $typeRus = $obj.Rus
                Write-Host "###PHASE###Export|$($taskObjects.Count)|$idx###"
                $quotedArgs = @($objType, $objName, $srv, $db, $password) | ForEach-Object { "`"$_`"" }
                $out = & cmd /c "`"$bat`" $($quotedArgs -join ' ') 2>&1"
                $errLine = @($out | Where-Object { $_ -match '\[ERROR\]' })
                if ($errLine.Count -gt 0) { $errLine | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Red } }
                $tf = $typeFolder[$objType]
                $outFile = Join-Path $basedir ($tf + "\$objName.sql")
                if (Test-Path $outFile) {
                    $exported++
                    Write-Host ("  OK: $objName ($typeRus) -> $tf") -ForegroundColor Green
                } else {
                    $failed++
                    Write-Host ("  ОШИБКА выгрузки: $objName ($typeRus)") -ForegroundColor Red
                }
                Write-Host "###STEP###"
            }

            Write-Host ""
            Write-Host "=== EXPORT SUMMARY ===" -ForegroundColor Cyan
            Write-Host "Успешно: $exported" -ForegroundColor Green
            Write-Host "Ошибок: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Cyan' })
            Write-Host "Всего объектов: $($taskObjects.Count)" -ForegroundColor Cyan
        }
    },
    @{
        Name = "Compare SQL: Current and Main"
        RusName = "Сравнение SQL: Current и Main"
        Description = "Сравнение SQL-объектов задачи между БД Current и Main. Собираются имена объектов из папок Git_/Ready_/Test_ задачи, перед сравнением они выгружаются (обновляются) из БД Current и Main, затем сравниваются. Ready_ объекты — всегда; Git_/Test_ — только при различии. Диалог предлагает удалить объект или перенести в Ready_."
        NeedsPassword = $true
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Пусто — сравнение всех объектов" }
        )
        Script = {
            param($params, $password)
            $ps = "C:\AIS\AI\Prod\scripts\Compare-SQL-Task.ps1"
            $quotedArgs = @("-ExecutionPolicy", "Bypass", "-File", $ps, "-TaskName", $params.TaskName, "-Password", $password) | ForEach-Object { "`"$_`"" }
            & powershell $quotedArgs 2>&1
        }
    },
    @{
        Name = "Compare & Verify (Compare-Export.ps1)"
        RusName = "Сравнение и проверка (Compare & Verify)"
        Description = "Сравнение выгрузок SQL, создание отчёта готовности и RFC в Jira"
        NeedsPassword = $true
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }
        )
        Checkboxes = @(
            @{ Name="ShowDiff";   Label="Показать различия";          Hint="Show differences (TortoiseMerge)" }
            @{ Name="CreateRFC";  Label="Создать RFC в Jira";         Hint="Create RFC in Jira" }
        )
        Script = {
            param($params, $password, $checks)
            $ps = "C:\AIS\AI\Prod\scripts\Compare-Export.ps1"
            $cmdArgs = @("-Password", $password, "-TaskName", $params.TaskName)
            if ($checks.ShowDiff)  { $cmdArgs += "-ShowDiff" }
            if ($checks.CreateRFC) { $cmdArgs += "-CreateRFC" }
            & powershell -ExecutionPolicy Bypass -File $ps @cmdArgs 2>&1
        }
    },
    @{
        Name = "Create RFC in Jira"
        RusName = "Создание RFC в Jira"
        Description = "Создание задачи RFC в Jira для указанной задачи без сравнения экспортов"
        NeedsPassword = $true
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }
        )
        Script = {
            param($params, $password)
            if (-not $password) { Write-Host "ОШИБКА: Не указан пароль/токен Jira. Заполните поле 'Токен' или настройте токен в Настройках параметров."; return }
            $ps = "C:\AIS\AI\Prod\scripts\Create-RFC.ps1"
            $jrUser = try { (Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json).jira.jira_email } catch { "" }
            & powershell -ExecutionPolicy Bypass -File $ps -TaskName $params.TaskName -JiraUser $jrUser -JiraPassword $password -Force 2>&1
        }
    },
    @{
        Name = "Jira Release Comment"
        RusName = "Комментарий в Jira: таблица объектов PB и SQL"
        Description = "Сканирует папки Ready_* задачи, собирает объекты PB и SQL, добавляет комментарий в задачу Jira с таблицей объектов к выпуску в ПРОД."
        NeedsPassword = $true
        Fields = @(
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }
            @{ Name="ProjectName"; Label="Проект PowerBuilder"; Default="AIS" }
        )
        Script = {
            param($params, $password)
            $ps = "C:\AIS\AI\Prod\scripts\Add-ReleaseComment.ps1"
            & powershell -ExecutionPolicy Bypass -File $ps -TaskName "$($params.TaskName)" -ProjectName "$($params.ProjectName)" -JiraPassword $password -Force 2>&1
        }
    },
    @{
        Name = "VSS: Get Latest Version"
        RusName = "VSS: Получить последнюю версию"
        Description = "Обновление объектов VSS: если указан TaskName — обновить объекты задачи; иначе — из PBT-файла или одного объекта. Пароль VSS из настроек."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB path or directory with srcsafe.ini" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Если указать — обновить объекты только этой задачи" }
            @{ Name="Project";  Label="Объект VSS (файл или библиотека)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/App.pbl or $/SRC125" }
            @{ Name="PbtFile";  Label="PBT-файл (для всех библиотек)";     Default=(Join-Path $script:localRoot "$($script:pbtName).pbt");  Hint="PowerBuilder Target .pbt — обновит все PBL из него" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно (только для одного объекта)"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            $projectRoot = "C:\AIS\AI\Prod"
            
            if ($params.TaskName) {
                # Task mode: update objects from Ready_* folders
                $cfg = Get-Content (Join-Path $projectRoot "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
                $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
                if ($matchDir) {
                    $taskPath = $matchDir.FullName
                } else {
                    $taskPath = Join-Path $cfg.paths.release_root $params.TaskName
                }
                if (-not (Test-Path $taskPath)) { Write-Host "ОШИБКА: Папка задачи не найдена: $taskPath"; return }
                $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
                if (-not $readyDirs) { Write-Host "ОШИБКА: Папки Ready_* не найдены в $taskPath"; return }
                Write-Host "Задача: $($params.TaskName), папок Ready: $($readyDirs.Count)"
                $objects = @{}
                foreach ($rd in $readyDirs) {
                    Get-ChildItem $rd.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                        if (-not $objects.ContainsKey($base)) { $objects[$base] = $_.Name }
                    }
                }
                Write-Host "Найдено объектов: $($objects.Count)"
                $updatedCount = 0; $errorCount = 0
                foreach ($baseName in $objects.Keys | Sort-Object) {
                    $ext = [System.IO.Path]::GetExtension($objects[$baseName])
                    $vssLib = ""
                    foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
                        $f = Get-ChildItem $dir -Recurse -File -Filter "${baseName}.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($f) { $vssLib = $f.Directory.Name; break }
                    }
                    if (-not $vssLib) { Write-Host "  ? $baseName — библиотека не определена"; $errorCount++; continue }
                    $vssObjPath = "`$/SRC125/gold/$vssLib/${baseName}${ext}"
                    Write-Host "  $vssObjPath"
                    Get-VssLatest -Project $vssObjPath
                    $updatedCount++
                }
                Write-Host "Обновлено: $updatedCount, ошибок: $errorCount"
            } elseif ($params.PbtFile -and (Test-Path $params.PbtFile)) {
                # Batch mode: parse .pbt and get latest for each PBL
                $cfg = Get-Content (Join-Path $projectRoot "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
                $localRoot = if ($cfg.paths.pb_main_source) { $cfg.paths.pb_main_source } else { "C:\SRC125\gold" }
                $vssRoot = $script:vssDefaults.project
                Write-Host "Чтение PBT: $($params.PbtFile)"
                Write-Host "Локальный корень: $localRoot → VSS: $vssRoot"
                $pblCount = 0
                Get-Content $params.PbtFile | ForEach-Object {
                    if ($_ -match '^Library:\s+(.+\.pbl)$') {
                        $localPath = $matches[1].Trim()
                        $vssPath = $localPath -replace [regex]::Escape($localRoot), $vssRoot
                        $vssPath = $vssPath -replace '\\', '/'
                        Write-Host "  Получение: $vssPath"
                        Get-VssLatest -Project $vssPath
                        $pblCount++
                    }
                }
                Write-Host "Обновлено $pblCount библиотек из PBT"
            } else {
                # Single object mode
                Get-VssLatest -Project $params.Project -Recursive:$checks.Recursive
            }
        }
    },
    @{
        Name = "VSS: Check Status"
        RusName = "VSS: Проверить статус"
        Description = "Проверка статуса объектов VSS. Если указан TaskName — анализирует объекты из папок Ready_* по задаче и показывает таблицу с возможностью Checkout / Undo Checkout."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB Path (srcsafe.ini)" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="Project";  Label="Объект VSS (файл или проект)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/File.pbl or $/SRC125" }
            @{ Name="TaskName"; Label="Имя задачи (Jira)";     Default="";  Hint="Заполните для проверки объектов из Ready_* папок задачи" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            
            if ($params.TaskName) {
                $projectRoot = "C:\AIS\AI\Prod"
                $cfgPath = Join-Path $projectRoot "config\config.json"
                $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
                if ($matchDir) {
                    $taskPath = $matchDir.FullName
                } else {
                    $taskPath = Join-Path $cfg.paths.release_root $params.TaskName
                }
                if (-not (Test-Path $taskPath)) { "ОШИБКА: Папка задачи не найдена: $taskPath"; return }
                $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
                if (-not $allDirs) { "ОШИБКА: Папки Ready_*/Test_*/Git_* не найдены в $taskPath"; return }
                "TASK_STATUS: Task=$($params.TaskName) Folders=$($allDirs.Count)"
                $objects = @{}
                foreach ($d in $allDirs) {
                    $source = if ($d.Name -like 'Ready_*') { 'R' } elseif ($d.Name -like 'Test_*') { 'T' } else { 'G' }
                    Get-ChildItem $d.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                        if (-not $objects.ContainsKey($base)) { $objects[$base] = @{ Name = $_.Name; Source = $source } }
                    }
                }
                "TASK_STATUS: Objects=$($objects.Count)"
                $resolved = 0
                foreach ($baseName in $objects.Keys) {
                    $obj = $objects[$baseName]
                    $fileName = $obj.Name
                    $source = $obj.Source
                    $sPattern = if ($fileName.Contains('.')) { $fileName } else { "$baseName.*" }
                    $vssPath = ''
                    foreach ($root in @($cfg.paths.pb_main_export, $cfg.paths.pb_current_export)) {
                        if (-not (Test-Path $root)) { continue }
                        $gci = Get-ChildItem $root -Recurse -File -Filter $sPattern -ErrorAction SilentlyContinue
                        foreach ($m in $gci) {
                            $fb = [System.IO.Path]::GetFileNameWithoutExtension($m.Name)
                            if ($fb -eq $baseName) { $vssPath = "$/SRC125/gold/$($m.Directory.Name)/$($m.Name)"; break }
                        }
                        if ($vssPath) { break }
                    }
                    if (-not $vssPath) { "###VSS_STATUS### $baseName||NF||$source"; continue }
                    $resolved++
                    $statusOut = Invoke-VssCommand -Command "Status" -Project $vssPath | Out-String
                    if ($statusOut -match 'No checked|не найдены|не извлеч') { "###VSS_STATUS### $baseName|$vssPath|F||$source" }
                    elseif ($statusOut -match '\s(\w+)\s+(Exc|Out)\s') { "###VSS_STATUS### $baseName|$vssPath|B|$($matches[1])|$source" }
                    elseif ($LASTEXITCODE -eq 0) { "###VSS_STATUS### $baseName|$vssPath|F||$source" }
                    else { "###VSS_STATUS### $baseName|$vssPath|E||$source" }
                }
                "TASK_STATUS: Resolved=$resolved/$($objects.Count)"
            } else {
                Get-VssStatus -Project $params.Project -Recursive:$checks.Recursive
            }
        }
    },
    @{
        Name = "VSS: Who Is Using"
        RusName = "VSS: Кто использует"
        Description = "Просмотр информации о том, кто извлёк объект из VSS. Если указан TaskName — анализирует объекты из папок Ready_*/Test_*/Git_* задачи."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB Path (srcsafe.ini)" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="Project";  Label="Объект VSS (файл или проект)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/File.pbl or $/SRC125" }
            @{ Name="TaskName"; Label="Имя задачи (Jira)";     Default="";  Hint="Заполните для проверки объектов из Ready_*/Test_*/Git_* папок задачи" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            
            if ($params.TaskName) {
                $projectRoot = "C:\AIS\AI\Prod"
                $cfgPath = Join-Path $projectRoot "config\config.json"
                $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
                if ($matchDir) {
                    $taskPath = $matchDir.FullName
                } else {
                    $taskPath = Join-Path $cfg.paths.release_root $params.TaskName
                }
                if (-not (Test-Path $taskPath)) { "ОШИБКА: Папка задачи не найдена: $taskPath"; return }
                $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
                if (-not $allDirs) { "ОШИБКА: Папки Ready_*/Test_*/Git_* не найдены в $taskPath"; return }
                "TASK_STATUS: Task=$($params.TaskName) Folders=$($allDirs.Count)"
                $objects = @{}
                foreach ($d in $allDirs) {
                    $source = if ($d.Name -like 'Ready_*') { 'R' } elseif ($d.Name -like 'Test_*') { 'T' } else { 'G' }
                    Get-ChildItem $d.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                        if (-not $objects.ContainsKey($base)) { $objects[$base] = @{ Name = $_.Name; Source = $source } }
                    }
                }
                "TASK_STATUS: Objects=$($objects.Count)"
                $resolved = 0
                foreach ($baseName in $objects.Keys) {
                    $obj = $objects[$baseName]
                    $fileName = $obj.Name; $source = $obj.Source
                    $sPattern = if ($fileName.Contains('.')) { $fileName } else { "$baseName.*" }
                    $vssPath = ''
                    foreach ($root in @($cfg.paths.pb_main_export, $cfg.paths.pb_current_export)) {
                        if (-not (Test-Path $root)) { continue }
                        $gci = Get-ChildItem $root -Recurse -File -Filter $sPattern -ErrorAction SilentlyContinue
                        foreach ($m in $gci) {
                            $fb = [System.IO.Path]::GetFileNameWithoutExtension($m.Name)
                            if ($fb -eq $baseName) { $vssPath = "$/SRC125/gold/$($m.Directory.Name)/$($m.Name)"; break }
                        }
                        if ($vssPath) { break }
                    }
                    if (-not $vssPath) { "--- $baseName [${source}] -> Не найден в PB_Main/PB_Current"; continue }
                    $resolved++
                    $whoOut = Invoke-VssCommand -Command "Status" -Project $vssPath | Out-String
                    if ($whoOut -match 'Checked out to\s*:\s*(\S+)') { "+++ $baseName ($vssPath) [$source] -> Извлечён: $($matches[1])" }
                    elseif ($whoOut -match '\s(\w+)\s+(Exc|Out)\s') { "+++ $baseName ($vssPath) [$source] -> Извлечён: $($matches[1])" }
                    elseif ($whoOut -match 'No checked|не найдены|не извлеч') { "--- $baseName ($vssPath) [$source] -> Свободен" }
                    elseif ($LASTEXITCODE -eq 0) { "--- $baseName ($vssPath) [$source] -> Свободен" }
                    else { "??? $baseName ($vssPath) [$source] -> Ошибка: $whoOut" }
                }
                "TASK_STATUS: Resolved=$resolved/$($objects.Count)"
            } else {
                Get-VssWhoIsUsing -Project $params.Project -Recursive:$checks.Recursive
            }
        }
    },
    @{
        Name = "VSS: Checkout"
        RusName = "VSS: Checkout (Извлечь / Зарезервировать для Вас)"
        Description = "Извлечение объектов из VSS для редактирования с указанием комментария. Пароль VSS берётся из настроек."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB Path (srcsafe.ini)" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="Project";  Label="Объект VSS (файл или проект)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/File.pbl or $/SRC125" }
            @{ Name="Comment";  Label="Комментарий извлечения";  Default="Checked out via AIS Release GUI";  Hint="Checkout Comment" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            Set-VssCheckout -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
        }
    },
    @{
        Name = "VSS: Checkin"
        RusName = "VSS: Checkin (Сохранить / Зафиксировать Ваши изменения)"
        Description = "Сохранение изменённых объектов в VSS с указанием комментария. Пароль VSS берётся из настроек."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB Path (srcsafe.ini)" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="Project";  Label="Объект VSS (файл или проект)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/File.pbl or $/SRC125" }
            @{ Name="Comment";  Label="Комментарий сохранения";  Default="Checked in via AIS Release GUI";  Hint="Checkin Comment" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            if ([string]::IsNullOrWhiteSpace($params.Comment)) {
                throw "Комментарий обязателен для операции Checkin. Укажите комментарий в поле 'Комментарий сохранения'."
            }
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            Set-VssCheckin -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
        }
    },
    @{
        Name = "VSS: Undo Check Out"
        RusName = "VSS: Undo Check Out (Снять резервирование. Вернуть без изменений)"
        Description = "Отмена извлечения объектов в VSS — снятие резервирования, возврат в исходное состояние. Пароль VSS берётся из настроек."
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="VSS DB Path (srcsafe.ini)" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="VSS Username" }
            @{ Name="Project";  Label="Объект VSS (файл или проект)";  Default=$script:vssDefaults.project;  Hint="VSS path: $/SRC125/File.pbl or $/SRC125" }
            @{ Name="Comment";  Label="Комментарий";  Default="Undo via AIS Release GUI";  Hint="Комментарий к отмене резервирования" }
        )
        Checkboxes = @(
            @{ Name="Recursive"; Label="Рекурсивно"; Hint="Recursive" }
        )
        Script = {
            param($params, $password, $checks)
            $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
            $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
            Set-VssUndoCheckout -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
        }
    },
    @{
        Name = "VSS: Object History"
        RusName = "VSS: История объекта"
        Description = "Показать все версии объекта в VSS с возможностью сравнения через TortoiseMerge и поиска текста по истории"
        NeedsPassword = $false
        Fields = @(
            @{ Name="VssPath";  Label="Путь к БД VSS";         Default=$script:vssDefaults.db_path;  Hint="" }
            @{ Name="VssUser";  Label="Пользователь VSS";     Default=$script:vssDefaults.user;  Hint="" }
            @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Необязательно. Если указать, будет предложен выбор объекта из задачи" }
            @{ Name="Project";  Label="Объект VSS";  Default="";  Hint="Имя объекта (w_...), с расширением или без. Библиотека определяется автоматически" }
        )
        Script = {
            param($params, $password)
            $ps = "C:\AIS\AI\Prod\scripts\VSS-History-Show.ps1"
            $vssArgs = @()
            $vssArgs += "-VssDb", $params.VssPath
            $vssArgs += "-VssUser", $params.VssUser
            $vssArgs += "-VssPass", $params.VssPass
            if ($params.Project) { $vssArgs += "-VssPath", $params.Project }
            if ($params.TaskName) { $vssArgs += "-TaskName", $params.TaskName }
            $argStr = ($vssArgs | ForEach-Object { "`"$_`"" }) -join " "
            $vssTempOutput = Join-Path $env:TEMP "morda_vss_output_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            if (Test-Path $vssTempOutput) { Remove-Item $vssTempOutput -Force }
            $script:currentTempOutput = $vssTempOutput
            $script:uiLastOutputLength = 0
            # Используем .bat-лаунчер (защита от AV) + wrapper.cmd для перехвата stdout
            # Start-Process плохо перехватывает stdout из .bat файлов
            $vssBat = $ps -replace '\.ps1$', '.bat'
            if (Test-Path $vssBat) {
                $vssWrapper = Join-Path $env:TEMP "morda_vss_wrapper_$(Get-Date -Format 'yyyyMMdd_HHmmss').cmd"
                $wrapperContent = '@echo off' + "`r`n" + '"' + $vssBat + '" ' + $argStr + ' > "' + $vssTempOutput + '" 2>&1' + "`r`n"
                [System.IO.File]::WriteAllText($vssWrapper, $wrapperContent, [System.Text.Encoding]::Default)
                $script:currentVssWrapper = $vssWrapper
                Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $vssWrapper -WindowStyle Normal
            } else {
                # Fallback: прямой вызов .ps1
                $vssStartArgs = '-NoProfile', '-STA', '-File', $ps, '-ShowHistory', '-Automated', '-RedirectStandardOutput', $vssTempOutput
                Start-Process powershell -ArgumentList $vssStartArgs -WindowStyle Normal
            }
        }
    }
)
"Operations defined: $($operations.Count)" | Out-File $logFile -Append

# ─ Helper: create input field ──
function New-ParamField {
    param([string]$Label, [string]$Default, [string]$FieldName, [string]$Hint, [bool]$Required = $false, [switch]$IsReadOnly, [switch]$IsPassword)

    "New-ParamField: START Label=$Label, Default=$Default, FieldName=$FieldName" | Out-File $logFile -Append

    try {
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = "0,0,0,4"
        "New-ParamField: StackPanel created" | Out-File $logFile -Append

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $Label
        $lbl.FontSize = 13
        $lbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4A5568")
        $lbl.FontWeight = "SemiBold"
        $lbl.Margin = "0,0,0,0"
        $sp.Children.Add($lbl) | Out-Null
        "New-ParamField: Label added" | Out-File $logFile -Append

        if ($IsPassword) {
            $grid = New-Object System.Windows.Controls.Grid
            $col1 = New-Object System.Windows.Controls.ColumnDefinition
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = New-Object System.Windows.Controls.ColumnDefinition
            $col2.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1) | Out-Null
            $grid.ColumnDefinitions.Add($col2) | Out-Null

            $pwdBox = New-Object System.Windows.Controls.PasswordBox
            $pwdBox.Password = $Default
            $pwdBox.FontSize = 13
            $pwdBox.Padding = "8,4"
            $pwdBox.Name = "fld_$FieldName"
            $pwdBox.Tag = $FieldName
            $pwdBox.Visibility = "Visible"
            [System.Windows.Controls.Grid]::SetColumn($pwdBox, 0)
            $grid.Children.Add($pwdBox) | Out-Null

            $pwdText = New-Object System.Windows.Controls.TextBox
            $pwdText.Text = $Default
            $pwdText.FontSize = 13
            $pwdText.Padding = "8,4"
            $pwdText.Name = "txt_$FieldName"
            $pwdText.Tag = $FieldName
            $pwdText.Visibility = "Collapsed"
            [System.Windows.Controls.Grid]::SetColumn($pwdText, 0)
            $grid.Children.Add($pwdText) | Out-Null

            if ($Required) {
                $whiteBrush = [System.Windows.Media.Brushes]::White
                $pinkBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xFF, 0xE0, 0xE0))
                if ([string]::IsNullOrEmpty($pwdBox.Password)) { $pwdBox.Background = $pinkBrush; $pwdText.Background = $pinkBrush }
                else { $pwdBox.Background = $whiteBrush; $pwdText.Background = $whiteBrush }
                $pwdBox.Add_PasswordChanged({
                    if ([string]::IsNullOrEmpty($this.Password)) { $this.Background = $pinkBrush } else { $this.Background = $whiteBrush }
                })
                $pwdText.Add_TextChanged({
                    if ([string]::IsNullOrEmpty($this.Text)) { $this.Background = $pinkBrush } else { $this.Background = $whiteBrush }
                })
            }

            $btnToggle = New-Object System.Windows.Controls.Button
            $btnToggle.Content = "Show"
            $btnToggle.Width = 50
            $btnToggle.FontSize = 12
            $btnToggle.Margin = "4,0,0,0"
            $btnToggle.Tag = $FieldName
            [System.Windows.Controls.Grid]::SetColumn($btnToggle, 1)
            $grid.Children.Add($btnToggle) | Out-Null

            $btnToggle.Add_Click({
                param($s, $e)
                $parentGrid = $s.Parent
                $ctrlPwdBox = $null; $ctrlPwdText = $null
                foreach ($ch in $parentGrid.Children) {
                    if ($ch -is [System.Windows.Controls.PasswordBox]) { $ctrlPwdBox = $ch }
                    if ($ch -is [System.Windows.Controls.TextBox] -and $ch.Name -like "txt_*") { $ctrlPwdText = $ch }
                }
                if ($ctrlPwdBox -and $ctrlPwdText) {
                    if ($ctrlPwdBox.Visibility -eq "Visible") {
                        $ctrlPwdText.Text = $ctrlPwdBox.Password
                        $ctrlPwdBox.Visibility = "Collapsed"
                        $ctrlPwdText.Visibility = "Visible"
                        $s.Content = "Hide"
                    } else {
                        $ctrlPwdBox.Password = $ctrlPwdText.Text
                        $ctrlPwdText.Visibility = "Collapsed"
                        $ctrlPwdBox.Visibility = "Visible"
                        $s.Content = "Show"
                    }
                }
            })

            $sp.Children.Add($grid) | Out-Null
        } else {
            "New-ParamField: creating TextBox" | Out-File $logFile -Append
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Text = $Default
            $tb.FontSize = 13
            $tb.Padding = "8,4"
            $tb.Name = "fld_$FieldName"
            $tb.Tag = $FieldName
            "New-ParamField: TextBox created" | Out-File $logFile -Append

            if ($IsReadOnly) {
                $tb.IsReadOnly = $true
                $tb.Background = "#F5F7FA"
                $tb.Foreground = "#4A5568"
            }
            $sp.Children.Add($tb) | Out-Null

            if ($Required) {
                $whiteBrush = [System.Windows.Media.Brushes]::White
                $pinkBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xFF, 0xE0, 0xE0))
                if ([string]::IsNullOrEmpty($tb.Text)) { $tb.Background = $pinkBrush } else { $tb.Background = $whiteBrush }
                $tb.Add_TextChanged({
                    if ([string]::IsNullOrEmpty($this.Text)) { $this.Background = $pinkBrush } else { $this.Background = $whiteBrush }
                })
            }
        }

        "New-ParamField: END" | Out-File $logFile -Append
        return $sp
    } catch {
        "New-ParamField ERROR: $($_.Exception.Message)" | Out-File $logFile -Append
        "New-ParamField ERROR Full: $_" | Out-File $logFile -Append
        throw
    }
}

# ── Helper: find TextBox in visual tree (BFS) ─
function Get-InnerTextBox {
    param($Element)
    try {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue($Element)
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($current)
            for ($i = 0; $i -lt $count; $i++) {
                $child = [System.Windows.Media.VisualTreeHelper]::GetChild($current, $i)
                if ($child -is [System.Windows.Controls.TextBox] -or $child -is [System.Windows.Controls.Primitives.TextBoxBase]) {
                    return $child
                }
                $queue.Enqueue($child)
            }
        }
    } catch {}
    return $null
}

function Get-ComboBoxText {
    param($ComboBox)
    # 1. Visual tree search (works even without template applied)
    $tb = Get-InnerTextBox -Element $ComboBox
    if ($tb) {
        if ([string]::IsNullOrEmpty($tb.Text)) { "Get-ComboBoxText: visual tree empty" | Out-File $logFile -Append; return "" }
        "Get-ComboBoxText: visual tree -> '$($tb.Text)'" | Out-File $logFile -Append; return $tb.Text
    }
    # 2. Try Template.FindName
    try { if ($ComboBox.Template) { $tb = $ComboBox.Template.FindName("PART_EditableTextBox", $ComboBox); if ($tb) { if ([string]::IsNullOrEmpty($tb.Text)) { return "" }; return $tb.Text } } } catch {}
    try { $null = $ComboBox.ApplyTemplate(); if ($ComboBox.Template) { $tb = $ComboBox.Template.FindName("PART_EditableTextBox", $ComboBox); if ($tb) { if ([string]::IsNullOrEmpty($tb.Text)) { return "" }; return $tb.Text } } } catch {}
    # 3. Fallback (только если TextBox не найден — для read-only ComboBox)
    if ($ComboBox.Text) { "Get-ComboBoxText: .Text -> '$($ComboBox.Text)'" | Out-File $logFile -Append; return $ComboBox.Text }
    if ($ComboBox.SelectedItem) { "Get-ComboBoxText: SelectedItem -> '$($ComboBox.SelectedItem)'" | Out-File $logFile -Append; return $ComboBox.SelectedItem.ToString() }
    "Get-ComboBoxText: empty" | Out-File $logFile -Append
    return ""
}

# ── Helper: create combo field with history and autocomplete ─
function New-ParamComboField {
    param([string]$Label, [string]$Default, [string]$FieldName, [string]$Hint, [string[]]$Items, [bool]$Required = $false)

    try {
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = "0,0,0,4"

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $Label
        $lbl.FontSize = 13
        $lbl.Foreground = [System.Windows.Media.Brushes]::Black
        $lbl.FontWeight = "SemiBold"
        $lbl.Margin = "0,0,0,0"
        $sp.Children.Add($lbl) | Out-Null

        $cb = New-Object System.Windows.Controls.ComboBox
        $cb.IsEditable = $true
        $cb.IsTextSearchEnabled = $false
        $cb.FontSize = 13
        $cb.Padding = "8,4"
        $cb.Name = "fld_$FieldName"
        $cb.Tag = $FieldName

        # Store all items for filtering
        $allItems = @()
        if ($Items) {
            $allItems = @($Items | Where-Object { $_ })
        }
        # Show last N items (configurable)
        $maxHistory = if ($script:vssHistoryMax) { $script:vssHistoryMax } else { 100 }
        $displayItems = if ($allItems.Count -gt $maxHistory) { $allItems[0..($maxHistory - 1)] } else { $allItems }
        foreach ($item in $displayItems) {
            $cb.Items.Add($item) | Out-Null
        }

        # Set default value
        if ($Default) {
            $cb.Items.Add($Default) | Out-Null
            $cb.SelectedItem = $Default
        }

        # Border-обёртка для всех ComboBox (с серой рамкой)
        $cbBorder = New-Object System.Windows.Controls.Border
        $cbBorder.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $cbBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
        $cbBorder.BorderThickness = "1"
        $cb.BorderThickness = "0"
        $cbBorder.Child = $cb
        $sp.Children.Add($cbBorder) | Out-Null

        # Помечаем Required-поля через Tag на Border (для общей предзапусковой валидации)
        if ($Required) {
            $cbBorder.Tag = "Required"
        }

        return $sp
    } catch {
        "New-ParamComboField ERROR: $($_.Exception.Message)" | Out-File $logFile -Append
        throw
    }
}

# ── Helper: create checkbox ──
function New-ParamCheckbox {
    param([string]$Label, [string]$FieldName, [string]$Hint)

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = "0,2,16,2"

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $Label
    $cb.FontSize = 13
    $cb.Foreground = [System.Windows.Media.Brushes]::Black
    $cb.Margin = "0,0,0,0"
    $cb.Name = "chk_$FieldName"
    $cb.Tag = $FieldName
    $sp.Children.Add($cb) | Out-Null

    # Hint disabled due to WPF Text property issue in PowerShell 5.1
    # if ($Hint) { ... }

    return $sp
}

# ── APPL: скруглённые углы для полей ввода ──
function Set-InputRoundedStyle {
    param($Control, [int]$Radius = 8, [string]$BgColor = "#FFFFFF")
    if (-not $Control) { return }
    try {
        if ($Control -is [System.Windows.Controls.TextBox]) {
            # НЕ устанавливаем Template — это ломает Background-биндинг в PowerShell 5.1
            # Вместо этого добавляем внешний Border с цветом и скруглёнными углами
            $parent = $Control.Parent
            if ($parent -and $parent -is [System.Windows.Controls.Panel]) {
                # Проверяем, не обёрнут ли уже в Border
                if ($Control.Parent -is [System.Windows.Controls.Border]) { return }
                $idx = $parent.Children.IndexOf($Control)
                if ($idx -lt 0) { return }
                $border = New-Object System.Windows.Controls.Border
                $border.CornerRadius = [System.Windows.CornerRadius]::new($Radius)
                $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
                $border.BorderThickness = "1"
                $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($BgColor)
                $border.Padding = "1"
                $parent.Children.RemoveAt($idx) | Out-Null
                $border.Child = $Control
                $parent.Children.Insert($idx, $border) | Out-Null
                $Control.BorderThickness = "0"
                $Control.Background = [System.Windows.Media.Brushes]::Transparent
            }
        } elseif ($Control -is [System.Windows.Controls.PasswordBox]) {
            $parent = $Control.Parent
            if ($parent -and $parent -is [System.Windows.Controls.Panel]) {
                # Проверяем, не обёрнут ли уже в Border
                if ($Control.Parent -is [System.Windows.Controls.Border]) { return }
                $idx = $parent.Children.IndexOf($Control)
                if ($idx -lt 0) { return }
                $border = New-Object System.Windows.Controls.Border
                $border.CornerRadius = [System.Windows.CornerRadius]::new($Radius)
                $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
                $border.BorderThickness = "1"
                $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($BgColor)
                $border.Padding = "1"
                $parent.Children.RemoveAt($idx) | Out-Null
                $border.Child = $Control
                $parent.Children.Insert($idx, $border) | Out-Null
                $Control.BorderThickness = "0"
                $Control.Background = [System.Windows.Media.Brushes]::Transparent
            }
        }
    } catch { Write-Host "Ошибка Set-InputRoundedStyle: $_" -ForegroundColor Red }
}

# ── Build params panel ──
function BuildParams {
    try {
        $idx = $cmbOp.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $operations.Count) { return }
        $op = $operations[$idx]
        "BuildParams: op=$($op.Name), fields=$($op.Fields.Count), hasCustomUI=$($op.HasCustomUI)" | Out-File $logFile -Append

        # Сохраняем текущие дети на случай ошибки — восстанавливаем
        $savedChildren = @($paramsPanel.Children | ForEach-Object { $_ })
        $paramsPanel.Children.Clear()

        try {
            # Handle HasCustomUI operations (e.g. Settings) — build custom panel immediately
            if ($op.HasCustomUI) {
                $btnRunBorder.Visibility = "Collapsed"
                $btnSettingsBorder.Visibility = "Visible"
                $script:settingsPanel = $paramsPanel
                $script:configPath = $configPath
                $script:projectRoot = $ProjectRoot
                Build-SettingsUI -Panel $paramsPanel -ConfigPath $configPath -ProjectRoot $ProjectRoot
                Attach-SettingsHandlers -Panel $paramsPanel -ConfigPath $configPath -ProjectRoot $ProjectRoot
                Validate-AllPaths -Panel $paramsPanel -ProjectRoot $ProjectRoot
                "BuildParams: Custom UI built for $($op.Name)" | Out-File $logFile -Append
            } else {
                $btnRunBorder.Visibility = "Visible"
                $btnSettingsBorder.Visibility = "Collapsed"
                $fieldIdx = 0
                foreach ($f in $op.Fields) {
                    $fieldIdx++
                    "BuildParams: field $fieldIdx = $($f.Name)" | Out-File $logFile -Append
                    # VSS Project field: use ComboBox with shared history
                    $isVssProject = ($op.Name -match '^VSS:' -and $f.Name -eq 'Project')
                    # TaskName field: use ComboBox with history
                    $isTaskName = ($f.Name -eq 'TaskName')
                    # Source field: ComboBox with fixed items (Current/Main/Ready)
                    $isSource = ($f.Name -eq 'Source')
                    # ObjectType field: ComboBox with fixed items (типы SQL)
                    $isObjectType = ($f.Name -eq 'ObjectType')
                    # Db field: ComboBox with history (для SQL Export)
                    $isDb = ($f.Name -eq 'Db')
                    if ($isVssProject) {
                        $historyKey = "VSS_Project_Shared"
                        $historyItems = @()
                        if ($script:vssHistory.ContainsKey($historyKey)) {
                            $historyItems = $script:vssHistory[$historyKey]
                        }
                        # Если история пуста — сканировать PB_Current для списка объектов
                        if ($historyItems.Count -eq 0) {
                            try {
                                $cfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                $pbCur = $cfg.paths.pb_current_source
                                if ($pbCur -and (Test-Path $pbCur)) {
                                    $pbFiles = Get-ChildItem $pbCur -Recurse -File -ErrorAction SilentlyContinue |
                                        Where-Object { $_.Name -match '\.srw$|\.sru$|\.srd$' } |
                                        Select-Object -ExpandProperty Name -Unique |
                                        Sort-Object
                                    $historyItems = @($pbFiles)
                                }
                            } catch {}
                        }
                        # Для VSS: Object History — поле пустое по умолчанию (объект указывается пользователем)
                        $useCurrentProject = $script:currentVssProject -and ($op.Name -ne 'VSS: Object History')
                        $defaultValue = if ($useCurrentProject) { $script:currentVssProject } else { $f.Default }
                        $paramsPanel.Children.Add((New-ParamComboField -Label $f.Label -Default $defaultValue -FieldName $f.Name -Hint $f.Hint -Items $historyItems)) | Out-Null
                    } elseif ($isDb) {
                        $historyKey = "Db_History"
                        $historyItems = @()
                        if ($script:vssHistory.ContainsKey($historyKey)) {
                            $historyItems = $script:vssHistory[$historyKey]
                        }
                        $paramsPanel.Children.Add((New-ParamComboField -Label $f.Label -Default $f.Default -FieldName $f.Name -Hint $f.Hint -Items $historyItems)) | Out-Null
                    } elseif ($isTaskName) {
                        $historyKey = "TaskName_Shared"
                        $historyItems = @()
                        if ($script:taskNameHistory.ContainsKey($historyKey)) {
                            $historyItems = $script:taskNameHistory[$historyKey]
                        }
                        # Используем sharedTaskName (если задан) или Default из поля
                        $defaultValue = if ($script:sharedTaskName) { $script:sharedTaskName } else { $f.Default }
                        $isReq = if ($f.ContainsKey('Required')) { $f.Required -eq $true } else { $false }
                        $paramsPanel.Children.Add((New-ParamComboField -Label $f.Label -Default $defaultValue -FieldName $f.Name -Hint $f.Hint -Items $historyItems -Required:$isReq)) | Out-Null
                    } elseif ($f.Name -eq 'DestPath') {
                        # Читаем актуальное значение из config (Settings могло изменить)
                        $destVal = $script:sharedDestPath
                        try {
                            $cfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($cfg.export_service.dest_path) { $destVal = $cfg.export_service.dest_path }
                        } catch { }
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $destVal -FieldName $f.Name -Hint $f.Hint)) | Out-Null
                    } elseif ($f.Name -eq 'CollectPath') {
                        # Читаем актуальное значение из config (Settings могло изменить)
                        $collectVal = $script:sharedCollectPath
                        try {
                            $cfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($cfg.collect_prod.dest_path) { $collectVal = $cfg.collect_prod.dest_path }
                        } catch { }
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $collectVal -FieldName $f.Name -Hint $f.Hint)) | Out-Null
                    } elseif ($isSource) {
                        $sourceItems = if ($f.ContainsKey('Items')) { $f.Items } else { @("Current","Main","Ready") }
                        $sourceStack = New-ParamComboField -Label $f.Label -Default $f.Default -FieldName $f.Name -Hint $f.Hint -Items $sourceItems
                        # Автоподстановка сервера при смене источника (SQL Export)
                        if ($op.Name -eq "SQL Export") {
                            $sourceCombo = $null
                            foreach ($child in $sourceStack.Children) {
                                if ($child -is [System.Windows.Controls.ComboBox]) {
                                    $sourceCombo = $child
                                    break
                                }
                            }
                            if ($sourceCombo) {
                                $sourceCombo.Add_SelectionChanged({
                                    try {
                                        $val = $this.SelectedItem
                                        if (-not $val) { return }
                                        # Обновляем поле Сервер (ищем ComboBox с Tag='Server')
                                        foreach ($child in $paramsPanel.Children) {
                                            if ($child -is [System.Windows.Controls.StackPanel]) {
                                                foreach ($inner in $child.Children) {
                                                    if ($inner.Tag -eq 'Server') {
                                                        if ($inner -is [System.Windows.Controls.TextBox]) {
                                                            if ($val -eq 'Main') { $inner.Text = 'galaxy' }
                                                            elseif ($val -eq 'Current') { $inner.Text = 'dev_golden' }
                                                        } elseif ($inner -is [System.Windows.Controls.ComboBox]) {
                                                            if ($val -eq 'Main') { $inner.Text = 'galaxy' }
                                                            elseif ($val -eq 'Current') { $inner.Text = 'dev_golden' }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        # Обновляем поле ReadyFolder в зависимости от Источника
                                        $cfgPaths = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                        $rfPanel = $null; $rfLabel = $null; $rfTextBox = $null
                                        foreach ($child in $paramsPanel.Children) {
                                            if ($child -is [System.Windows.Controls.StackPanel]) {
                                                foreach ($inner in $child.Children) {
                                                    if ($inner -is [System.Windows.Controls.TextBlock] -and $child.Children[0] -eq $inner) { $rfLabel = $inner }
                                                    if ($inner.Tag -eq 'ReadyFolder' -and $inner -is [System.Windows.Controls.TextBox]) { $rfTextBox = $inner }
                                                }
                                                if ($rfTextBox) { $rfPanel = $child; break }
                                            }
                                        }
                                        if ($rfPanel -and $rfLabel -and $rfTextBox) {
                                            $rfPanel.Visibility = "Visible"
                                            if ($val -eq 'Ready') {
                                                $rfLabel.Text = 'Путь к папке Ready'
                                                $rfTextBox.Text = 'C:\Temp\ReadyMerged\'
                                            } elseif ($val -eq 'Main') {
                                                $rfLabel.Text = 'SQL Main export'
                                                $rfTextBox.Text = $cfgPaths.paths.bd_main_export
                                            } elseif ($val -eq 'Current') {
                                                $rfLabel.Text = 'SQL Current export'
                                                $rfTextBox.Text = $cfgPaths.paths.bd_current_export
                                            }
                                        }
                                    } catch {
                                        "Source Changed ERROR: $($_.Exception.Message)" | Out-File $script:logFile -Append
                                    }
                                })
                            }
                        }
                        # Общий обработчик: обновление ExportPath при смене Источника
                        $genCombo = $null
                        foreach ($child in $sourceStack.Children) {
                            $cbTarget = $null
                            if ($child -is [System.Windows.Controls.ComboBox]) { $cbTarget = $child }
                            elseif ($child -is [System.Windows.Controls.Border] -and $child.Child -is [System.Windows.Controls.ComboBox]) { $cbTarget = $child.Child }
                            if ($cbTarget) { $genCombo = $cbTarget; break }
                        }
                        if ($genCombo) {
                            $genCombo.Add_SelectionChanged({
                                try {
                                    $val = $this.SelectedItem
                                    if (-not $val) { return }
                                    $genCfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                    $newPath = if ($val -eq 'Main') { $genCfg.paths.pb_main_export } else { $genCfg.paths.pb_current_export }
                                    # Ищем ExportPath TextBox и обновляем его
                                    foreach ($child in $paramsPanel.Children) {
                                        if ($child -is [System.Windows.Controls.StackPanel]) {
                                            foreach ($inner in $child.Children) {
                                                if ($inner.Tag -eq 'ExportPath' -and $inner -is [System.Windows.Controls.TextBox]) {
                                                    $inner.Text = $newPath
                                                }
                                            }
                                        }
                                    }
                                } catch {
                                    "Source Changed ExportPath ERROR: $($_.Exception.Message)" | Out-File $script:logFile -Append
                                }
                            })
                        }
                        $paramsPanel.Children.Add($sourceStack) | Out-Null
                    } elseif ($isObjectType) {
                        $typeItems = if ($f.ContainsKey('Items')) { $f.Items } else { @() }
                        $paramsPanel.Children.Add((New-ParamComboField -Label $f.Label -Default $f.Default -FieldName $f.Name -Hint $f.Hint -Items $typeItems)) | Out-Null
                    } elseif ($f.Name -eq 'ExportPath') {
                        # ReadOnly поле — отображает путь выгрузки из config в зависимости от выбранного Источника
                        $epCfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $epSource = "Current"
                        foreach ($child in $paramsPanel.Children) {
                            if ($child -is [System.Windows.Controls.StackPanel]) {
                                foreach ($inner in $child.Children) {
                                    # ComboBox может быть напрямую или внутри Border
                                    $cbTarget = $null
                                    if ($inner.Tag -eq 'Source' -and $inner -is [System.Windows.Controls.ComboBox]) { $cbTarget = $inner }
                                    elseif ($inner -is [System.Windows.Controls.Border] -and $inner.Child -is [System.Windows.Controls.ComboBox] -and $inner.Child.Tag -eq 'Source') { $cbTarget = $inner.Child }
                                    if ($cbTarget) { $epSource = $cbTarget.SelectedItem; break }
                                }
                            }
                            if ($epSource) { break }
                        }
                        $epPath = if ($epSource -eq 'Main') { $epCfg.paths.pb_main_export } else { $epCfg.paths.pb_current_export }
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $epPath -FieldName $f.Name -Hint $f.Hint -IsReadOnly)) | Out-Null
                    } elseif ($op.Name -match '^VSS:' -and $f.Name -eq 'VssUser' -and $script:sharedVssUser) {
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $script:sharedVssUser -FieldName $f.Name -Hint $f.Hint)) | Out-Null
                    } elseif ($f.Name -eq 'PbtFile' -and $script:sharedPbtFile) {
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $script:sharedPbtFile -FieldName $f.Name -Hint $f.Hint)) | Out-Null
                    } elseif ($f.Name -eq 'BdExportPath') {
                        $epCfg = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $epDefault = $epCfg.paths.bd_current_export
                        $epCmb = $null
                        foreach ($child in $paramsPanel.Children) {
                            if ($child -is [System.Windows.Controls.StackPanel]) {
                                foreach ($inner in $child.Children) {
                                    if ($inner -is [System.Windows.Controls.Border] -and $inner.Child -is [System.Windows.Controls.ComboBox] -and $inner.Child.Tag -eq 'Source') { $epCmb = $inner.Child; break }
                                }
                            }
                            if ($epCmb) { break }
                        }
                        if ($epCmb) {
                            $srcVal = $epCmb.SelectedItem
                            if ($srcVal -eq 'Main') { $epDefault = $epCfg.paths.bd_main_export }
                        }
                        $epPanel = New-ParamField -Label 'Путь для выгрузки' -Default $epDefault -FieldName $f.Name -Hint $f.Hint
                        $paramsPanel.Children.Add($epPanel) | Out-Null
                        # Обновление пути при смене Источника
                        $epBox = $null
                        foreach ($inner in $epPanel.Children) {
                            if ($inner.Tag -eq 'BdExportPath' -and $inner -is [System.Windows.Controls.TextBox]) { $epBox = $inner; break }
                        }
                        if ($epCmb -and $epBox) {
                            $epCmb.Add_SelectionChanged({
                                try {
                                    $val = $this.SelectedItem
                                    if (-not $val) { return }
                                    $epCfg2 = Get-Content $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                    $newPath = if ($val -eq 'Main') { $epCfg2.paths.bd_main_export } else { $epCfg2.paths.bd_current_export }
                                    foreach ($c in $paramsPanel.Children) {
                                        if ($c -is [System.Windows.Controls.StackPanel]) {
                                            foreach ($i in $c.Children) {
                                                if ($i.Tag -eq 'BdExportPath' -and $i -is [System.Windows.Controls.TextBox]) { $i.Text = $newPath }
                                            }
                                        }
                                    }
                                } catch { }
                            })
                        }
                    } else {
                        $isRequired = if ($f.ContainsKey('Required')) { $f.Required -eq $true } else { $false }
                        $paramsPanel.Children.Add((New-ParamField -Label $f.Label -Default $f.Default -FieldName $f.Name -Hint $f.Hint -Required:$isRequired)) | Out-Null
                    }
                }

                if ($op.Checkboxes) {
                    $cbPanel = New-Object System.Windows.Controls.WrapPanel
                    $cbPanel.Margin = "0,4,0,0"
                    foreach ($c in $op.Checkboxes) {
                        $cbPanel.Children.Add((New-ParamCheckbox -Label $c.Label -FieldName $c.Name -Hint $c.Hint)) | Out-Null
                    }
                    $paramsPanel.Children.Add($cbPanel) | Out-Null
                }
            }

            if ($op.NeedsPassword) {
                $pwdBorder.Visibility = "Visible"
                # Меняем заголовок поля Password в зависимости от операции
                if ($op.Name -eq "Jira Release Comment" -or $op.Name -eq "Create RFC in Jira") {
                    $pwdLabel.Text = "Токен"
                } else {
                    $pwdLabel.Text = "Пароль Sybase"
                }
                $whiteBrush = [System.Windows.Media.Brushes]::White
                $pinkBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xFF, 0xE0, 0xE0))
                # Автоподстановка токена Jira или пароля Sybase из Settings
                $cfg_pwd = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $mk = Get-MasterKey -ConfigPath $configPath
                $autoPwd = ""
                if ($op.Name -eq "Jira Release Comment" -or $op.Name -eq "Create RFC in Jira") {
                    if ($mk) {
                        try {
                            if ($cfg_pwd.jira.api_token_encrypted) { $autoPwd = Decrypt-Password -Encrypted $cfg_pwd.jira.api_token_encrypted -Key $mk }
                            elseif ($cfg_pwd.jira.token_encrypted) { $autoPwd = Decrypt-Password -Encrypted $cfg_pwd.jira.token_encrypted -Key $mk }
                        } catch { }
                    }
                } elseif ($op.Name -eq "SQL Export" -or $op.Name -eq "SQL_exp_param") {
                    if ($mk -and $cfg_pwd.PSObject.Properties['sybase'] -and $cfg_pwd.sybase.password_encrypted) {
                        try { $autoPwd = Decrypt-Password -Encrypted $cfg_pwd.sybase.password_encrypted -Key $mk } catch { }
                    }
                }
                if ($autoPwd) {
                    $pwdBox.Password = $autoPwd
                    $pwdText.Text = $autoPwd
                    $pwdBox.Background = $whiteBrush
                    $pwdText.Background = $whiteBrush
                } elseif ($script:autoRunPassword) {
                    $pwdBox.Password = $script:autoRunPassword
                    $pwdText.Text = $script:autoRunPassword
                    $pwdBox.Background = $whiteBrush
                    $pwdText.Background = $whiteBrush
                } else {
                    $pwdBox.Background = $pinkBrush
                    $pwdText.Background = $pinkBrush
                }
                # Розовый фон при пустом пароле, белый при вводе
                $pwdBox.Add_PasswordChanged({
                    if ([string]::IsNullOrEmpty($this.Password)) { $this.Background = $pinkBrush }
                    else { $this.Background = $whiteBrush }
                })
                $pwdText.Add_TextChanged({
                    if ([string]::IsNullOrEmpty($this.Text)) { $this.Background = $pinkBrush }
                    else { $this.Background = $whiteBrush }
                })
            } else {
                $pwdBorder.Visibility = "Collapsed"
            }

            # Update description
            if ($txtDesc) {
                $txtDesc.Text = $op.Description
            }
            
            # Enter на любом поле ввода → Run
            $btnRunRef = $window.FindName("BtnRun")
            if ($btnRunRef) {
                function Add-EnterToRun {
                    param($p)
                    for ($i = 0; $i -lt $p.Children.Count; $i++) {
                        $c = $p.Children[$i]
                        if ($c -is [System.Windows.Controls.TextBox] -or $c -is [System.Windows.Controls.ComboBox]) {
                            $c.Add_KeyDown({
                                if ($_.Key -eq "Return" -or $_.Key -eq "Enter") {
                                    $btnRunRef.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                                    $_.Handled = $true
                                }
                            }.GetNewClosure())
                        }
                        if ($c -is [System.Windows.Controls.Panel] -or $c -is [System.Windows.Controls.Border]) {
                            Add-EnterToRun $c
                        }
                    }
                }
                Add-EnterToRun $paramsPanel
            }
        } catch {
            # Восстанавливаем предыдущие дети и показываем ошибку
            $paramsPanel.Children.Clear()
            foreach ($child in $savedChildren) { $paramsPanel.Children.Add($child) | Out-Null }
            $errMsg = "BuildParams error: $_"
            $errMsg | Out-File $logFile -Append
            [System.Windows.MessageBox]::Show("Ошибка построения панели параметров: $_`nПодробности в логе.", "BuildParams Error", "OK", "Error")
        }
        
        "BuildParams: done op=$($op.Name)" | Out-File $logFile -Append
    } catch {
        "BuildParams outer error: $_" | Out-File $logFile -Append
    }
}

# ─ Populate ComboBox ──
for ($i = 0; $i -lt $operations.Count; $i++) {
    $op = $operations[$i]
    $cmbOp.Items.Add("$($i+1). $($op.RusName)") | Out-Null
}
$cmbOp.SelectedIndex = 0

"ComboBox populated" | Out-File $logFile -Append

# ─ Events ──
$cmbOp.Add_SelectionChanged({
    "SelectionChanged: index=$($cmbOp.SelectedIndex), item=$($cmbOp.SelectedItem)" | Out-File $logFile -Append
    if ($script:autoRunSelecting) {
        "SelectionChanged: skipped (AutoRun selecting)" | Out-File $logFile -Append
        return
    }
    try {
        BuildParams
    } catch {
        "SelectionChanged ERROR: $($_.Exception.Message)" | Out-File $logFile -Append
        "Stack: $($_.ScriptStackTrace)" | Out-File $logFile -Append
    }
})

# Password toggle
$script:pwdIsVisible = $false
$btnTogglePwd.Add_Click({
    try {
        if ($script:pwdIsVisible) {
            $script:pwdIsVisible = $false
            $pwdBox.Password = $pwdText.Text
            $pwdText.Visibility = [System.Windows.Visibility]::Collapsed
            $pwdBox.Visibility = [System.Windows.Visibility]::Visible
            $btnTogglePwd.Content = "Show"
            $pwdBox.Focus()
        } else {
            $script:pwdIsVisible = $true
            $pwdText.Text = $pwdBox.Password
            $pwdBox.Visibility = [System.Windows.Visibility]::Collapsed
            $pwdText.Visibility = [System.Windows.Visibility]::Visible
            $btnTogglePwd.Content = "Hide"
            $pwdText.Focus()
            $pwdText.SelectAll()
        }
    } catch {
        "Password toggle error: $_" | Out-File $logFile -Append
    }
})

# Run button
$btnRun.Add_Click({
    try {
        # Скрыть панель результатов сравнения (если была видна)
        $crb = $window.FindName("CompareResultBorder")
        if ($crb) { $crb.Visibility = "Collapsed" }
        
        "Run clicked" | Out-File $logFile -Append
        
        $idx = $cmbOp.SelectedIndex
        "Selected index: $idx" | Out-File $logFile -Append
        if ($idx -lt 0) { return }
        $op = $operations[$idx]
        "Operation: $($op.Name)" | Out-File $logFile -Append

        # Settings operation — already loaded in BuildParams
        if ($op.HasCustomUI) {
            $txtLog.Clear()
            $txtLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Панель настроек отображается выше. Нажмите 'Сохранить' для применения изменений.
")
            $txtLog.ScrollToEnd()
            return
        }

        # Force focus loss on editable ComboBoxes to commit pending text edits.
        $txtLog.Focus()
        
        $params = @{}
        foreach ($child in $paramsPanel.Children) {
            if ($child -is [System.Windows.Controls.StackPanel]) {
                foreach ($inner in $child.Children) {
                    if ($inner.Tag) {
                        if ($inner -is [System.Windows.Controls.TextBox]) {
                            $params[$inner.Tag] = $inner.Text
                        } elseif ($inner -is [System.Windows.Controls.ComboBox]) {
                            $params[$inner.Tag] = Get-ComboBoxText -ComboBox $inner
                        } elseif ($inner -is [System.Windows.Controls.Border] -and $inner.Child -is [System.Windows.Controls.ComboBox]) {
                            $cb = $inner.Child
                            $params[$cb.Tag] = Get-ComboBoxText -ComboBox $cb
                            "Param: $($cb.Tag) = $($params[$cb.Tag]) (inside Border, Tag match)" | Out-File $logFile -Append
                        }
                    } elseif ($inner -is [System.Windows.Controls.Border] -and $inner.Child -is [System.Windows.Controls.ComboBox] -and $inner.Child.Tag) {
                        $cb = $inner.Child
                        $params[$cb.Tag] = Get-ComboBoxText -ComboBox $cb
                        "Param: $($cb.Tag) = $($params[$cb.Tag]) (inside Border)" | Out-File $logFile -Append
                    } elseif ($inner -is [System.Windows.Controls.Grid]) {
                        foreach ($gc in $inner.Children) {
                            if ($gc -is [System.Windows.Controls.PasswordBox] -and $gc.Tag) {
                                $params[$gc.Tag] = $gc.Password
                                "Param: $($gc.Tag) = *** (PasswordBox)" | Out-File $logFile -Append
                            }
                            if ($gc -is [System.Windows.Controls.TextBox] -and $gc.Tag -and $gc.Name -like "txt_*" -and $gc.Visibility -eq "Visible") {
                                $params[$gc.Tag] = $gc.Text
                                "Param: $($gc.Tag) = '$($gc.Text)' (visible TextBox)" | Out-File $logFile -Append
                            }
                        }
                    }
                }
            }
        }

        $checks = @{}
        foreach ($child in $paramsPanel.Children) {
            if ($child -is [System.Windows.Controls.WrapPanel]) {
                foreach ($inner in $child.Children) {
                    if ($inner -is [System.Windows.Controls.CheckBox] -and $inner.Tag) {
                        $checks[$inner.Tag] = $inner.IsChecked
                        "Check: $($inner.Tag) = $($inner.IsChecked)" | Out-File $logFile -Append
                    } elseif ($inner -is [System.Windows.Controls.StackPanel]) {
                        foreach ($spChild in $inner.Children) {
                            if ($spChild -is [System.Windows.Controls.CheckBox] -and $spChild.Tag) {
                                $checks[$spChild.Tag] = $spChild.IsChecked
                                "Check: $($spChild.Tag) = $($spChild.IsChecked) (inside StackPanel)" | Out-File $logFile -Append
                            }
                        }
                    }
                }
            }
        }

        # Resolve short object name to full VSS path for VSS operations
        # (skip when TaskName is specified — Project field is ignored)
        if ($op.Name -match '^VSS:' -and $params.ContainsKey('Project') -and $params['Project'] `
            -and (-not $params.ContainsKey('TaskName') -or -not $params['TaskName'])) {
            $resolvedPath = Resolve-VssObjectPath -ObjectName $params['Project'] -ProjectRoot $ProjectRoot
            if ($resolvedPath -ne $params['Project']) {
                "Resolved VSS path: $($params['Project']) -> $resolvedPath" | Out-File $logFile -Append
                $params['Project'] = $resolvedPath
            }
        }
        
        # Inject VSS password from config (Settings) for VSS operations
        if ($op.Name -match '^VSS:' -or $op.Name -eq 'Collect PROD Objects') {
            $vssPwd = ""
            try {
                $mk = Get-MasterKey -ConfigPath $configPath
                if ($mk) {
                    $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($cfg.vss.password_encrypted) {
                        $vssPwd = Decrypt-Password -Encrypted $cfg.vss.password_encrypted -Key $mk
                    }
                }
            } catch {
                "VSS password decrypt error: $_" | Out-File $logFile -Append
            }
            $params['VssPass'] = $vssPwd
            "Param: VssPass (from config) = $(if ($vssPwd) { '***' } else { '(empty)' })" | Out-File $logFile -Append
        }

        # Save VSS Project only when TaskName is NOT specified (it should be ignored with TaskName)
        if ($op.Name -match '^VSS:' -and $params['Project'] `
            -and (-not $params.ContainsKey('TaskName') -or -not $params['TaskName'])) {
            $historyKey = "VSS_Project_Shared"
            if (-not $script:vssHistory.ContainsKey($historyKey)) {
                $script:vssHistory[$historyKey] = @()
            }
            $existing = $script:vssHistory[$historyKey] | Where-Object { $_ -eq $params['Project'] }
            if (-not $existing) {
                $script:vssHistory[$historyKey] = @($params['Project']) + $script:vssHistory[$historyKey]
            } else {
                $script:vssHistory[$historyKey] = @($params['Project']) + ($script:vssHistory[$historyKey] | Where-Object { $_ -ne $params['Project'] })
            }
            # Keep last N items (configurable)
            $maxHistory = if ($script:vssHistoryMax) { $script:vssHistoryMax } else { 100 }
            if ($script:vssHistory[$historyKey].Count -gt $maxHistory) {
                $script:vssHistory[$historyKey] = $script:vssHistory[$historyKey][0..($maxHistory - 1)]
            }
            Save-VssHistory
            # Preserve current value for next VSS operation
            $script:currentVssProject = $params['Project']
        }
        
        # Save TaskName to history for any operation with TaskName field
        if ($params.ContainsKey('TaskName') -and $params['TaskName']) {
            $taskHistoryKey = "TaskName_Shared"
            if (-not $script:taskNameHistory.ContainsKey($taskHistoryKey)) {
                $script:taskNameHistory[$taskHistoryKey] = @()
            }
            $existing = $script:taskNameHistory[$taskHistoryKey] | Where-Object { $_ -eq $params['TaskName'] }
            if (-not $existing) {
                $script:taskNameHistory[$taskHistoryKey] = @($params['TaskName']) + $script:taskNameHistory[$taskHistoryKey]
            } else {
                # Move existing item to front
                $script:taskNameHistory[$taskHistoryKey] = @($params['TaskName']) + ($script:taskNameHistory[$taskHistoryKey] | Where-Object { $_ -ne $params['TaskName'] })
            }
            $maxHistory = if ($script:taskNameHistoryMax) { $script:taskNameHistoryMax } else { 100 }
            if ($script:taskNameHistory[$taskHistoryKey].Count -gt $maxHistory) {
                $script:taskNameHistory[$taskHistoryKey] = $script:taskNameHistory[$taskHistoryKey][0..($maxHistory - 1)]
            }
            Save-TaskNameHistory
            $script:sharedTaskName = $params['TaskName']
        }
        
        # Save shared DestPath для Export Service
        if ($params.ContainsKey('DestPath') -and $params['DestPath']) {
            $script:sharedDestPath = $params['DestPath']
        }
        
        # Save shared CollectPath для Collect PROD Objects
        if ($params.ContainsKey('CollectPath') -and $params['CollectPath']) {
            $script:sharedCollectPath = $params['CollectPath']
        }
        
        # Save shared VssUser for VSS operations
        if ($op.Name -match '^VSS:' -and $params.ContainsKey('VssUser') -and $params['VssUser']) {
            $vssUserKey = "VssUser_Shared"
            if (-not $script:vssHistory.ContainsKey($vssUserKey)) { $script:vssHistory[$vssUserKey] = @() }
            $existing = $script:vssHistory[$vssUserKey] | Where-Object { $_ -eq $params['VssUser'] }
            if (-not $existing) {
                $script:vssHistory[$vssUserKey] = @($params['VssUser']) + $script:vssHistory[$vssUserKey]
            } else {
                $script:vssHistory[$vssUserKey] = @($params['VssUser']) + ($script:vssHistory[$vssUserKey] | Where-Object { $_ -ne $params['VssUser'] })
            }
            $maxHistory = if ($script:vssHistoryMax) { $script:vssHistoryMax } else { 100 }
            if ($script:vssHistory[$vssUserKey].Count -gt $maxHistory) { $script:vssHistory[$vssUserKey] = $script:vssHistory[$vssUserKey][0..($maxHistory - 1)] }
            Save-VssHistory
            $script:sharedVssUser = $params['VssUser']
        }
        
        # Save shared PbtFile
        if ($params.ContainsKey('PbtFile') -and $params['PbtFile']) {
            $pbtKey = "PbtFile_Shared"
            if (-not $script:vssHistory.ContainsKey($pbtKey)) { $script:vssHistory[$pbtKey] = @() }
            $existing = $script:vssHistory[$pbtKey] | Where-Object { $_ -eq $params['PbtFile'] }
            if (-not $existing) {
                $script:vssHistory[$pbtKey] = @($params['PbtFile']) + $script:vssHistory[$pbtKey]
            } else {
                $script:vssHistory[$pbtKey] = @($params['PbtFile']) + ($script:vssHistory[$pbtKey] | Where-Object { $_ -ne $params['PbtFile'] })
            }
            $maxHistory = if ($script:vssHistoryMax) { $script:vssHistoryMax } else { 100 }
            if ($script:vssHistory[$pbtKey].Count -gt $maxHistory) { $script:vssHistory[$pbtKey] = $script:vssHistory[$pbtKey][0..($maxHistory - 1)] }
            Save-VssHistory
            $script:sharedPbtFile = $params['PbtFile']
        }
        
        # VSS test log
        if ($op.Name -match '^VSS:' -and $params['Project']) {
            $vssTestLog = Join-Path $ProjectRoot "reports\vss_test.log"
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Operation: $($op.Name)" | Out-File $vssTestLog -Append -Encoding UTF8
            "  VssPath: $($params['VssPath'])" | Out-File $vssTestLog -Append -Encoding UTF8
            "  VssUser: $($params['VssUser'])" | Out-File $vssTestLog -Append -Encoding UTF8
            "  Project: $($params['Project'])" | Out-File $vssTestLog -Append -Encoding UTF8
            if ($params['PbtFile']) { "  PbtFile: $($params['PbtFile'])" | Out-File $vssTestLog -Append -Encoding UTF8 }
            if ($params['Comment']) { "  Comment: $($params['Comment'])" | Out-File $vssTestLog -Append -Encoding UTF8 }
            "  Recursive: $($checks['Recursive'])" | Out-File $vssTestLog -Append -Encoding UTF8
            "---" | Out-File $vssTestLog -Append -Encoding UTF8
        }

        $password = if ($script:pwdIsVisible) { $pwdText.Text } else { $pwdBox.Password }
        "Password length: $($password.Length)" | Out-File $logFile -Append

            # Валидация: TaskName обязателен для Create RFC, Jira Comment и Collect PROD Objects
            if (($op.Name -eq 'Create RFC in Jira' -or $op.Name -eq 'Jira Release Comment' -or $op.Name -eq 'Collect PROD Objects') -and [string]::IsNullOrWhiteSpace($params.TaskName)) {
                [System.Windows.MessageBox]::Show("Task Name (Jira) обязателен для операции '$($op.RusName)'. Заполните поле Task Name.", "Ошибка", "OK", "Warning")
                return
            }
            if ($op.NeedsPassword -and [string]::IsNullOrWhiteSpace($password)) {
                [System.Windows.MessageBox]::Show("Укажите пароль для доступа к БД", "Внимание", "OK", "Warning")
                return
            }
            
            # Общая валидация обязательных полей
            $emptyRequired = @()
            $requiredGroups = @{}
            foreach ($f in $op.Fields) {
                $fHasRequired = $f.ContainsKey('Required')
                $fHasGroup = $f.ContainsKey('RequiredGroup')
                if ($fHasRequired -and $f.Required) {
                    $fVal = $params[$f.Name]
                    if ([string]::IsNullOrWhiteSpace($fVal)) {
                        if ($fHasGroup -and $f.RequiredGroup) {
                            $groupName = $f.RequiredGroup
                            if (-not $requiredGroups.ContainsKey($groupName)) { $requiredGroups[$groupName] = @{ Label = $f.Label; Fields = @(); Filled = $false } }
                            $requiredGroups[$groupName].Fields += $f.Label
                        } else {
                            $emptyRequired += $f.Label
                        }
                    } else {
                        if ($fHasGroup -and $f.RequiredGroup) {
                            $groupName = $f.RequiredGroup
                            if (-not $requiredGroups.ContainsKey($groupName)) { $requiredGroups[$groupName] = @{ Label = $f.Label; Fields = @(); Filled = $true } }
                            $requiredGroups[$groupName].Filled = $true
                        }
                    }
                }
            }
            # Проверка групп: если группа не заполнена — все поля группы считаются пустыми
            foreach ($g in $requiredGroups.Values) {
                if (-not $g.Filled) { $emptyRequired += $g.Fields }
            }
            if ($emptyRequired.Count -gt 0) {
                $msg = "Заполните обязательные поля:`n`n"
                $msg += ($emptyRequired | ForEach-Object { "• $_" }) -join "`n"
                [System.Windows.MessageBox]::Show($msg, "Внимание: обязательные поля", "OK", "Warning")
                return
            }

        $txtLog.Clear()
        $txtLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Starting: $($op.Name)`r`n")
        $txtLog.AppendText("[$(Get-Date -Format 'HH:mm:ss')] Please wait...`r`n")
        $txtLog.ScrollToEnd()

        $btnRun.IsEnabled = $false
        $btnStop.Visibility = "Visible"
        $btnStop.IsEnabled = $true

        # Показать анимацию загрузки для операций с ДО
        if ($op.Name -match '^Compare PB') {
            Show-LoadingAnimation -AnimIndex 1 -LabelText "Идет обработка"
        } else {
            Show-OverlayProgress
        }

        # Create temp script
        $tempDir = [System.IO.Path]::GetTempPath()
        $guid = [guid]::NewGuid().ToString('N').Substring(0,8)
        $tempScript = Join-Path $tempDir "ais_gui_${guid}.ps1"
        $tempParams = Join-Path $tempDir "ais_params_${guid}.json"
        $tempChecks = Join-Path $tempDir "ais_checks_${guid}.json"
        "Temp files: $tempScript" | Out-File $logFile -Append

        $paramsJson = $params | ConvertTo-Json -Depth 5 -Compress
        $checksJson = $checks | ConvertTo-Json -Depth 5 -Compress
        [System.IO.File]::WriteAllText($tempParams, $paramsJson, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($tempChecks, $checksJson, [System.Text.Encoding]::UTF8)

        $sbText = $op.Script.ToString()
        $sbText = $sbText -replace '^\s*param\s*\([^)]*\)\s*', ''
        "Script text length: $($sbText.Length)" | Out-File $logFile -Append


        # Create temp file for output
        $tempOutput = Join-Path $tempDir "ais_output_${guid}.txt"

        # Fixed log file for analysis (перезаписывается при каждом запуске)
        $fixedLog = $script:fixedLogPath
        $fixedLogDir = Split-Path $fixedLog -Parent
        if (-not (Test-Path $fixedLogDir)) { New-Item -ItemType Directory -Path $fixedLogDir -Force | Out-Null }

        # Escape single quotes in password and sbText to prevent script breakage
        $escapedPassword = $password -replace "'", "''"
        $escapedSbText = $sbText

        # Build params string for header
        $sessionId = [guid]::NewGuid().ToString().Substring(0, 8)
        $paramLines = @()
        foreach ($k in $params.Keys) { $paramLines += "  $k = $($params[$k])" }
        foreach ($k in $checks.Keys) { $paramLines += "  [check] $k = $($checks[$k])" }
        $paramStr = $paramLines -join "`r`n"
        $headerText = @"
=== AIS Output Log ===
Операция: $($op.Name)
Время: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Сессия: $sessionId
Хост: $($env:COMPUTERNAME)
PS: $($PSVersionTable.PSVersion.ToString())
Рабочая папка: $((Get-Location).Path)
Скрипт: $($op.Name)
Параметры:
$paramStr
========================
"@

        # Write header to fixed log (clear old content)
        [System.IO.File]::WriteAllText($fixedLog, $headerText, [System.Text.Encoding]::UTF8)

        # Create wrapper that executes script and saves output to BOTH files
        $wrapperWithOutput = @"
`$ErrorActionPreference = 'Continue'
`$outputFile = '$tempOutput'
`$fixedLog   = '$fixedLog'
# Устанавливаем кодировку вывода UTF-8
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

"--- Запуск выполнения ---" | Out-File -FilePath `$outputFile -Encoding UTF8

try {
    `$params = Get-Content '$tempParams' -Raw | ConvertFrom-Json
    `$password = '$escapedPassword'
    `$checks = if (Test-Path '$tempChecks') { Get-Content '$tempChecks' -Raw | ConvertFrom-Json } else { @{} }
    
    # Execute the script and stream output line by line to BOTH files
    `$sb = {
        $escapedSbText
    }
    `$sw = New-Object System.IO.StreamWriter(`$outputFile, `$true, [System.Text.Encoding]::UTF8)
    `$swFixed = New-Object System.IO.StreamWriter(`$fixedLog, `$true, [System.Text.Encoding]::UTF8)
    try {
        # *>&1 захватывает все потоки (включая Write-Host из stream 6)
        & `$sb *>&1 | ForEach-Object {
            # InformationRecord (Write-Host) → извлекаем текст
            `$line = if (`$_ -is [System.Management.Automation.InformationRecord]) {
                `$md = `$_.MessageData
                if (`$md -is [string]) { `$md }
                elseif (`$md -is [System.Management.Automation.HostInformationMessage]) { `$md.Message }
                else { "`$md" }
            } else { "`$_" }
            `$sw.WriteLine(`$line); `$sw.Flush()
            `$swFixed.WriteLine(`$line); `$swFixed.Flush()
        }
    } finally {
        `$sw.Close()
        `$swFixed.Close()
    }
} catch {
    "ERROR: `$_" | Out-File -FilePath `$outputFile -Append -Encoding UTF8
    "ERROR: `$_" | Out-File -FilePath `$fixedLog -Append -Encoding UTF8
    `$_.ScriptStackTrace | Out-File -FilePath `$outputFile -Append -Encoding UTF8
    `$_.ScriptStackTrace | Out-File -FilePath `$fixedLog -Append -Encoding UTF8
} finally {
    Remove-Item '$tempParams' -Force -ErrorAction SilentlyContinue
    Remove-Item '$tempChecks' -Force -ErrorAction SilentlyContinue
    "--- Выполнение завершено ---" | Out-File -FilePath `$outputFile -Append -Encoding UTF8
}
"@
        [System.IO.File]::WriteAllText($tempScript, $wrapperWithOutput, [System.Text.Encoding]::UTF8)
        "Temp script saved: $tempScript" | Out-File $logFile -Append

        # Run process
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$tempScript`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        "Starting process..." | Out-File $logFile -Append
        
        $process.Start() | Out-Null
        "Process started: PID=$($process.Id)" | Out-File $logFile -Append

        # Store for Stop button and timer
        $script:currentProcess = $process
        $script:currentTempScript = $tempScript
        $script:currentTempOutput = $tempOutput

        # Store UI controls in script scope for timer access
        $script:uiTxtLog = $txtLog
        $script:uiBtnRun = $btnRun
        $script:uiBtnStop = $btnStop
        $script:uiParamsPanel = $paramsPanel
        $script:uiLastOutputLength = 0
        $script:uiLastDataTime = [System.Diagnostics.Stopwatch]::StartNew()
        $script:uiOpName = $op.Name
        $script:uiScriptParams = $params

        # Define timer callback at script scope
        $script:uiTimerCallback = {
            try {
                # Read new output from file
                if (Test-Path $script:currentTempOutput) {
                    $content = Get-Content $script:currentTempOutput -Raw -ErrorAction SilentlyContinue
                    if ($content -and $content.Length -gt $script:uiLastOutputLength) {
                        $newContent = $content.Substring($script:uiLastOutputLength)
                        $script:uiTxtLog.AppendText($newContent)
                        $script:uiTxtLog.ScrollToEnd()
                        $script:uiLastOutputLength = $content.Length
                        $script:uiLastDataTime.Restart()
                        # Для операций с собственным UI (VSS: Object History) — не обновляем ПБ в МОРДЕ
                        $skipPbForOp = $script:uiOpName -eq 'VSS: Object History'
                        if (-not $skipPbForOp) {
                        # Парсинг ###PHASE### с разделением шагов
                        $lastPhasePos = $newContent.LastIndexOf('###PHASE###')
                        if ($lastPhasePos -ge 0) {
                            # Шаги до ###PHASE### — в старую фазу
                            $beforePhase = $newContent.Substring(0, $lastPhasePos)
                            $oldSteps = [regex]::Matches($beforePhase, '###STEP###').Count
                            if ($oldSteps -gt 0 -and $script:pbPhaseMax -gt 0) {
                                $script:pbPhaseCurrent += $oldSteps
                                $dispOld = [Math]::Min($script:pbPhaseCurrent, $script:pbPhaseMax)
                                $pbStep.Value = [Math]::Round($dispOld / $script:pbPhaseMax * 100)
                                $pbStepLabel.Text = "($dispOld - $script:pbPhaseMax)"
                            }
                            # Новая фаза
                            $pmNew = [regex]::Match($newContent.Substring($lastPhasePos), '###PHASE###(.+?)\|(\d+)')
                            if ($pmNew.Success) {
                                $script:pbPhaseName = $pmNew.Groups[1].Value
                                $script:pbPhaseMax = [int]$pmNew.Groups[2].Value
                                $script:pbPhaseCurrent = 0
                                $script:pbPhaseIndex++
                                $displayName = if ($script:phaseNames.ContainsKey($script:pbPhaseName)) { $script:phaseNames[$script:pbPhaseName] } else { $script:pbPhaseName }
                                $pbPhaseLabel.Text = $displayName
                                $stepPct = [Math]::Min(90, $script:pbPhaseIndex * 10)
                                if ($stepPct -gt $pbPhase.Value) { $pbPhase.Value = $stepPct }
                                $pbStep.Value = 0
                                $pbStepLabel.Text = "(0 - $script:pbPhaseMax)"
                            }
                            # Шаги после ###PHASE### — в новую фазу
                            $afterPhase = ""
                            if ($pmNew.Success) { $afterPhase = $newContent.Substring($lastPhasePos + $pmNew.Length) }
                            $newSteps = [regex]::Matches($afterPhase, '###STEP###').Count
                            if ($newSteps -gt 0) {
                                $script:pbPhaseCurrent += $newSteps
                                if ($script:pbPhaseMax -gt 0) {
                                    $pbStep.Value = [Math]::Min(100, [Math]::Round($script:pbPhaseCurrent / $script:pbPhaseMax * 100))
                                }
                                $dispNew = [Math]::Min($script:pbPhaseCurrent, $script:pbPhaseMax)
                                $pbStepLabel.Text = "($dispNew - $script:pbPhaseMax)"
                            }
                        } else {
                            # Нет ###PHASE### — все шаги в текущую фазу
                            $stepMatches = [regex]::Matches($newContent, '###STEP###')
                            if ($stepMatches.Count -gt 0) {
                                $script:pbPhaseCurrent += $stepMatches.Count
                                if ($script:pbPhaseMax -gt 0) {
                                    $pbStep.Value = [Math]::Min(100, [Math]::Round($script:pbPhaseCurrent / $script:pbPhaseMax * 100))
                                }
                                $dispNoPhase = [Math]::Min($script:pbPhaseCurrent, $script:pbPhaseMax)
                                $pbStepLabel.Text = "($dispNoPhase - $script:pbPhaseMax)"
                            }
                        }
                        # Парсинг ###PB### — смена метки + шаг верхнего ПБ, без сброса счётчика
                        $pbLabelMatches = [regex]::Matches($newContent, '###PB###(.+)')
                        foreach ($pm in $pbLabelMatches) {
                            $script:pbPhaseName = $pm.Groups[1].Value.Trim()
                            $displayName = if ($script:phaseNames.ContainsKey($script:pbPhaseName)) { $script:phaseNames[$script:pbPhaseName] } else { $script:pbPhaseName }
                            $pbPhaseLabel.Text = $displayName
                            $script:pbPhaseIndex++
                            $stepPct = [Math]::Min(90, $script:pbPhaseIndex * 10)
                            if ($stepPct -gt $pbPhase.Value) { $pbPhase.Value = $stepPct }
                        }
                        # Верхний ПБ: байтовый до первого ###PHASE### (cap 5%), после — только фазы
                        if ($script:pbPhaseIndex -eq 0) {
                            $fillProgress = [Math]::Min(5, [Math]::Round($script:uiLastOutputLength / 500))
                            if ($fillProgress -gt $pbPhase.Value) { $pbPhase.Value = $fillProgress }
                        }
                        } # конец if (-not $skipPbForOp)
                    }
                }

                    if ($script:currentProcess.HasExited) {
                        if ($script:uiProcessDone) { "Skip: already handled by Stop" | Out-File $logFile -Append; return }
                        $script:uiTimer.Stop()
                        $exitCode = $script:currentProcess.ExitCode
                        "Timer: Process exited with code=$exitCode" | Out-File $logFile -Append
                        
                        # Read any remaining output
                    if (Test-Path $script:currentTempOutput) {
                        $content = Get-Content $script:currentTempOutput -Raw -ErrorAction SilentlyContinue
                        if ($content -and $content.Length -gt $script:uiLastOutputLength) {
                            $newContent = $content.Substring($script:uiLastOutputLength)
                            $script:uiTxtLog.AppendText($newContent)
                            $script:uiTxtLog.ScrollToEnd()
                        }
                    }
                    
                    $pbPhase.Value = 100
                    $pbStep.Value = 100
                    $pbPhaseLabel.Text = "Готово"
                    $pbStepLabel.Text = ""
                    $script:uiTxtLog.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] Done (exit: $($script:currentProcess.ExitCode))`r`n")
                    $script:uiTxtLog.ScrollToEnd()
                    # Set result phrase or show status table / diff dialog
                    if ($script:uiOpName) {
                            $fullText = $script:uiTxtLog.Text
                            $hasVssMarkers = $fullText -match '###VSS_STATUS###'
                            $hasDiffMarkers = $fullText -match '###DIFF_OBJECT###'
                            $hasValidationErrors = $fullText -match '###VALIDATION_ERROR###'
                            $hasPbObjMarkers = $fullText -match '###PB_OBJ###'
                            $hasProdObjMarkers = $fullText -match '###PROD_OBJ###'
                            $hasProdNoneMarkers = $fullText -match '###PROD_NONE###'
                            $hasPbCompareMarkers = $fullText -match '###PB_COMPARE_TABLE###'
                            $hasSqlTaskMarkers = $fullText -match '###SQL_TASK_OBJECT###'
                            if ($hasValidationErrors -and -not $script:autoRun) {
                                Show-ValidationErrorWindow -Output $fullText
                            } elseif ($script:uiOpName -match '^Compare' -and $hasPbCompareMarkers) {
                                Show-PbCompareInline -Output $fullText
                                if ($hasDiffMarkers -and -not $script:autoRun) { Show-DiffSelectWindow -Output $fullText -TmPath $script:tortoiseMergePath }
                              } elseif ($script:uiOpName -match '^Compare' -and $hasSqlTaskMarkers) {
                                  $cfgForMerge = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
                                  if (-not $script:autoRun) { Show-SqlTaskCompareWindow -Output $fullText -MainPath $cfgForMerge.paths.bd_main_export }
                              } elseif ($script:uiOpName -eq 'VSS: Check Status' -and $hasVssMarkers) {
                             if (-not $script:autoRun) { Show-VssStatusTableWindow -Output $fullText -VssPath $script:uiScriptParams.VssPath -VssUser $script:uiScriptParams.VssUser -VssPass $script:uiScriptParams.VssPass }
                         } elseif ($script:uiOpName -match '^Compare' -and $hasDiffMarkers) {
                             $resultPhrase = Get-OperationResult -OpName $script:uiOpName -Output $fullText -ExitCode $script:currentProcess.ExitCode -Params $script:uiScriptParams
                             Show-ResultInline -Output $fullText -OpName $script:uiOpName -ResultPhrase $resultPhrase
                             if (-not $script:autoRun) {
                                 $confirmMatch = [regex]::Match($fullText, '###CONFIRM_DIFF###(\d+)')
                                 if ($confirmMatch.Success) {
                                     $count = $confirmMatch.Groups[1].Value
                                     $answer = [System.Windows.MessageBox]::Show("Найдено $count отличающихся объектов. Использовать программу сравнения?", "Подтверждение", "YesNo", "Question")
                                     if ($answer -eq "Yes") { Show-DiffSelectWindow -Output $fullText -TmPath $script:tortoiseMergePath }
                                 } else {
                                     Show-DiffSelectWindow -Output $fullText -TmPath $script:tortoiseMergePath
                                 }
                             }
                          } elseif ($script:uiOpName -eq 'Jira Release Comment' -and $hasPbObjMarkers) {
                             $resultPhrase = Get-OperationResult -OpName $script:uiOpName -Output $fullText -ExitCode $script:currentProcess.ExitCode -Params $script:uiScriptParams
                             Show-ResultInline -Output $fullText -OpName $script:uiOpName -ResultPhrase $resultPhrase
                             if (-not $script:autoRun) { Show-PbObjectTableWindow -Output $fullText }
                        } elseif ($script:uiOpName -eq 'Collect PROD Objects' -and ($hasProdObjMarkers -or $hasProdNoneMarkers)) {
                            Show-ProdCompareResult -Output $fullText
                        } elseif ($script:uiOpName -eq 'VSS: Object History') {
                            # Диалоговые операции сами показывают результат
                            $vssErrors = @()
                            if ($fullText -match '###VSS_ERROR###(.+?)(?:\r?\n|$)') {
                                $vssErrors = [regex]::Matches($fullText, '###VSS_ERROR###(.+?)(?:\r?\n|$)') | ForEach-Object { $_.Groups[1].Value.Trim() }
                            }
                            $vssCancelled = $fullText -match '###VSS_CANCELLED###'
                            if ($script:currentProcess.ExitCode -ne 0 -or $vssErrors.Count -gt 0) {
                                if ($vssErrors.Count -gt 0) {
                                    $errorText = "Ошибки VSS History:`r`n" + ($vssErrors | ForEach-Object { "  - $_" }) -join "`r`n"
                                    $resultPhrase = "Ошибка: " + $vssErrors[0]
                                } else {
                                    $resultPhrase = Get-OperationResult -OpName $script:uiOpName -Output $fullText -ExitCode $script:currentProcess.ExitCode -Params $script:uiScriptParams
                                }
                                Show-ResultInline -Output $errorText -OpName $script:uiOpName -ResultPhrase $resultPhrase
                                [System.Windows.MessageBox]::Show($errorText, "VSS: История объекта - ошибка", "OK", "Error") | Out-Null
                            } elseif ($vssCancelled) {
                                # Пользователь закрыл ДО выбора без выбора объекта
                                Set-Status 'VSS: История объекта - выбор отменён'
                            } elseif ($fullText -match 'TASK_SCANNED|GET_HISTORY|###WPF_DIALOG|###VSS_DIALOG|###VSS_HISTORY') {
                                # Скрипт отработал, показал диалог
                                Set-Status 'VSS: История объекта - диалог показан'
                            }
                            # Если ничего не подошло - молча (без MessageBox)
                        } elseif ($script:uiOpName -match '^Run Tests') {
                            # Показать результат тестов в inline-панели
                            Show-ResultInline -Output $fullText -OpName $script:uiOpName
                        } else {
                            $resultPhrase = Get-OperationResult -OpName $script:uiOpName -Output $fullText -ExitCode $script:currentProcess.ExitCode -Params $script:uiScriptParams
                            Show-ResultInline -Output $fullText -OpName $script:uiOpName -ResultPhrase $resultPhrase
                        }
                    }
                    # Refresh VSS history combo if applicable
                    if ($script:uiOpName -and $script:uiOpName -match '^VSS:') {
                        Update-VssProjectCombo -OpName $script:uiOpName
                    }
                    Hide-LoadingAnimation
                    $script:uiBtnRun.IsEnabled = $true
                    $script:uiBtnStop.Visibility = "Collapsed"
                    Remove-Item $script:currentTempScript -Force -ErrorAction SilentlyContinue
                    "Process completed" | Out-File $logFile -Append
                    $script:autoRunCompleted = $true
                } elseif ($script:uiLastDataTime.Elapsed.TotalSeconds -gt $script:uiTimeoutSeconds) {
                    $script:uiTimer.Stop()
                    $script:uiTxtLog.AppendText("`r`n[TIMEOUT - нет вывода более $($script:uiTimeoutSeconds) сек]`r`n")
                    # Для диалоговых операций inline не показываем
                    $isDialogOp = $script:uiOpName -eq 'VSS: Object History'
                    if (-not $isDialogOp) {
                        Show-ResultInline -Output $script:uiTxtLog.Text -OpName $script:uiOpName -ResultPhrase "Таймаут"
                    }
                    try { $script:currentProcess.Kill() } catch {}
                    Hide-LoadingAnimation
                    $script:uiBtnRun.IsEnabled = $true
                    $script:uiBtnStop.Visibility = "Collapsed"
                    "Process timeout ($($script:uiTimeoutSeconds)s)" | Out-File $logFile -Append
                }
            } catch {
                "Timer error: $_" | Out-File $logFile -Append
            }
        }

        # Simple timer to check completion
        $script:uiTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:uiTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:uiTimer.add_Tick($script:uiTimerCallback)

        $script:uiTimer.Start()
        "Timer started" | Out-File $logFile -Append

    } catch {
        $errMsg = "Run error: $_`n`n$($_.ScriptStackTrace)"
        $txtLog.AppendText("`r`n$errMsg`r`n")
        "Run handler error: $errMsg" | Out-File $logFile -Append
        Hide-LoadingAnimation
        $btnRun.IsEnabled = $true
        $btnStop.Visibility = "Collapsed"
    }
})

# Stop button
$btnStop.Add_Click({
    try {
        if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
            $script:currentProcess.Kill()
            $txtLog.AppendText("`r`n[Stopped by user]`r`n")
        }
    } catch {}
    if ($script:uiTimer) { try { $script:uiTimer.Stop() } catch {} }
    $script:uiProcessDone = $true
    Hide-LoadingAnimation
    try {
        $stopOpName = if ($script:uiOpName) { $script:uiOpName } else { "" }
        Show-ResultInline -Output $txtLog.Text -OpName $stopOpName -ResultPhrase "Обработка остановлена"
    } catch {}
    $btnRun.IsEnabled = $true
    $btnStop.Visibility = "Collapsed"
    $script:uiOpName = $null
})

# Export log
$btnExportLog.Add_Click({
    try {
        $logText = $txtLog.Text
        if ([string]::IsNullOrWhiteSpace($logText)) {
            [System.Windows.MessageBox]::Show("Log is empty.", "Info", "OK", "Information")
            return
        }
        
        $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
        $saveDialog.Filter = "Text files (*.txt)|*.txt"
        $saveDialog.FileName = "gui_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        
        if ($saveDialog.ShowDialog() -eq $true) {
            [System.IO.File]::WriteAllText($saveDialog.FileName, $logText, [System.Text.Encoding]::UTF8)
            [System.Windows.MessageBox]::Show("Exported to: $($saveDialog.FileName)", "Success", "OK", "Information")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Export error: $_", "Error", "OK", "Error")
    }
})

# ── Compare PB inline panel handlers ──
$btnHideCompare = $window.FindName("BtnHideCompareResult")
if ($btnHideCompare) {
    $btnHideCompare.Add_Click({
        $crb = $window.FindName("CompareResultBorder")
        if ($crb) { $crb.Visibility = "Collapsed" }
    })
}

$btnShowDiff = $window.FindName("BtnShowDiff")
if ($btnShowDiff) {
    $btnShowDiff.Add_Click({
        $dg = $window.FindName("CompareResultGrid")
        if (-not $dg) { return }
        $selected = @($dg.SelectedItems)
        if ($selected.Count -eq 0) { return }
        # Запустить TortoiseMerge для выбранных объектов
        $tmPath = $script:tortoiseMergePath
        if (-not (Test-Path $tmPath)) {
            [System.Windows.MessageBox]::Show("TortoiseMerge не найден: $tmPath", "Ошибка", "OK", "Error")
            return
        }
        $output = $script:uiFullText
        foreach ($item in $selected) {
            $objFull = "$($item.Library)\$($item.Object)"
            $regex = [regex]::Escape($objFull)
            $lineMatch = [regex]::Match($output, "###DIFF_OBJECT###\s*$regex")
            if ($lineMatch.Success) {
                $line = $output.Substring($lineMatch.Index)
                $lineEnd = $line.IndexOf("`n")
                if ($lineEnd -gt 0) { $line = $line.Substring(0, $lineEnd) }
                # Разбираем: ###DIFF_OBJECT###Name|Reason|BasePath|ReadyPath|CompareType
                $parts = ($line -replace '^###DIFF_OBJECT###\s*','').Split('|')
                if ($parts.Count -ge 4) {
                    $basePath = $parts[2].Trim()
                    $readyPath = $parts[3].Trim()
                    if (Test-Path $basePath -and (Test-Path $readyPath)) {
                        Start-Process -FilePath $tmPath -ArgumentList "/base:`"$basePath`" /mine:`"$readyPath`""
                    }
                }
            }
        }
    })
}

# ── Settings button handlers ──
$btnSaveSettings.Add_Click({
    Save-Settings -Panel $script:settingsPanel -ConfigPath $script:configPath -ProjectRoot $script:projectRoot
    # Обновить script:loadingAnimationIndex и script:compareAllMax из config после сохранения
    try {
        $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.gui.loading_animation -ge 1 -and $cfg.gui.loading_animation -le 10) {
            $script:loadingAnimationIndex = $cfg.gui.loading_animation
        }
        if ($cfg.gui.compare_all_max -ge 1 -and $cfg.gui.compare_all_max -le 10) {
            $script:compareAllMax = $cfg.gui.compare_all_max
        }
    } catch {}
    $script:metroAccent = Get-MetroAccent
})
$btnResetSettings.Add_Click({
    Build-SettingsUI -Panel $script:settingsPanel -ConfigPath $script:configPath -ProjectRoot $script:projectRoot
    Attach-SettingsHandlers -Panel $script:settingsPanel -ConfigPath $script:configPath -ProjectRoot $script:projectRoot
    Validate-AllPaths -Panel $script:settingsPanel -ProjectRoot $script:projectRoot
})
$btnValidatePaths.Add_Click({
    Validate-AllPaths -Panel $script:settingsPanel -ProjectRoot $script:projectRoot
})
$btnExportSettings.Add_Click({
    Export-Settings -ConfigPath $script:configPath -ProjectRoot $script:projectRoot
})
$btnImportSettings.Add_Click({
    Import-Settings -Panel $script:settingsPanel -ConfigPath $script:configPath -ProjectRoot $script:projectRoot
})
$btnSettingsHistory.Add_Click({
    $histFile = Join-Path $script:projectRoot "config\settings_history.json"
    if (-not (Test-Path $histFile)) { [System.Windows.MessageBox]::Show("Журнал изменений пуст.", "Информация", "OK", "Information"); return }
    $histData = Get-Content $histFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $win = New-Object Windows.Window
    $win.Title = "Журнал изменений настроек"
    $win.Width = 800; $win.Height = 500
    $win.WindowStartupLocation = "CenterScreen"
    $win.AllowsTransparency = $true
    $win.WindowStyle = [Windows.WindowStyle]::None
    $win.Background = [Windows.Media.Brushes]::Transparent
    $win.ResizeMode = "CanResizeWithGrip"
    # APPL2 outerBorder
    $ob = New-Object Windows.Controls.Border; $ob.CornerRadius = 60
    $ob.BorderBrush = "#1A3A60"; $ob.BorderThickness = 1; $ob.Background = "#33FFFFFF"
    $bs = New-Object Windows.Media.Effects.DropShadowEffect
    $bs.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $bs.Direction = 270; $bs.ShadowDepth = 4; $bs.BlurRadius = 10; $bs.Opacity = 0.5; $ob.Effect = $bs
    $cg = New-Object Windows.Controls.Grid
    $cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    # Title bar (APPL2)
    $atb = New-Object Windows.Controls.Border
    $atb.Background = "#05FFFFFF"; $atb.CornerRadius = 10
    $atb.Margin = "25,1,25,0"; $atb.Padding = "20,2,20,0"
    $atg = New-Object Windows.Controls.Grid
    $atg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
    $atg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $atg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $atg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleLayer = New-Object Windows.Controls.Grid; $titleLayer.VerticalAlignment = "Center"
    $titleA = New-Object Windows.Controls.TextBlock
    $titleA.Text = "Журнал изменений настроек"; $titleA.FontSize = 16; $titleA.FontWeight = "Bold"
    $titleA.Foreground = [Windows.Media.Brushes]::White; $titleA.Margin = "1,1,0,0"
    [void]$titleLayer.Children.Add($titleA)
    $titleB = New-Object Windows.Controls.TextBlock
    $titleB.Text = "Журнал изменений настроек"; $titleB.FontSize = 16; $titleB.FontWeight = "Bold"
    $titleB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    [void]$titleLayer.Children.Add($titleB)
    [System.Windows.Controls.Grid]::SetColumn($titleLayer, 0); [void]$atg.Children.Add($titleLayer)
    # Вспомогательная функция создания кнопок title bar (APPL2: двухслойный 3D-символ)
    $tbFunc = {
        param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose)
        $b = New-Object Windows.Controls.Button
        $btnGrid = New-Object Windows.Controls.Grid
        $btnA = New-Object Windows.Controls.TextBlock
        $btnA.Text = $Text; $btnA.FontSize = 16; $btnA.FontWeight = "Bold"
        $btnA.Foreground = [Windows.Media.Brushes]::White
        $btnA.Margin = New-Object Windows.Thickness(1,1,0,0)
        $btnA.HorizontalAlignment = "Center"; $btnA.VerticalAlignment = "Center"
        [void]$btnGrid.Children.Add($btnA)
        $btnB = New-Object Windows.Controls.TextBlock
        $btnB.Text = $Text; $btnB.FontSize = 16; $btnB.FontWeight = "Bold"
        $btnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        $btnB.HorizontalAlignment = "Center"; $btnB.VerticalAlignment = "Center"
        [void]$btnGrid.Children.Add($btnB)
        $b.Content = $btnGrid; $b.Width = 40; $b.Height = 34
        $b.Cursor = "Hand"; $b.HorizontalContentAlignment = "Center"
        $b.VerticalContentAlignment = "Center"; $b.Padding = "0"
        $b.BorderThickness = "3"
        $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        $tg = New-Object Windows.Media.LinearGradientBrush
        $tg.StartPoint = "0,0"; $tg.EndPoint = "0,1"
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
        $b.Background = $tg
        try {
            $tx = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
            $rr = New-Object System.Xml.XmlNodeReader ([xml]$tx).DocumentElement
            $b.Template = [Windows.Markup.XamlReader]::Load($rr)
        } catch { }
        $b.Add_Click($Click)
        [System.Windows.Controls.Grid]::SetColumn($b, $Col)
        return $b
    }
    $minBtn = & $tbFunc "━" 1 { $win.WindowState = [Windows.WindowState]::Minimized }
    $maxBtn = & $tbFunc "▣" 2 {
        if ($win.WindowState -eq "Maximized") { $win.WindowState = "Normal"; $maxBtn.Content = "▣" }
        else { $win.WindowState = "Maximized"; $maxBtn.Content = "❐" }
    }
    $closeBtn = & $tbFunc "✕" 3 { $win.Close() } -IsClose
    [void]$atg.Children.Add($minBtn); [void]$atg.Children.Add($maxBtn); [void]$atg.Children.Add($closeBtn)
    $atb.Child = $atg
    $atb.Add_MouseLeftButtonDown({ if ($_.ClickCount -eq 1) { try { $win.DragMove() } catch {} } })
    [System.Windows.Controls.Grid]::SetRow($atb, 0); [void]$cg.Children.Add($atb)
    # Content
    $cw = New-Object Windows.Controls.Border
    $cw.Background = "#1A3A60"; $cw.CornerRadius = 46; $cw.Margin = "4,0,4,4"
    $mb0 = New-Object Windows.Controls.Border
    $mb0.CornerRadius = 42; $mb0.Background = [Windows.Media.Brushes]::White; $mb0.Margin = 4
    $dg = New-Object Windows.Controls.DataGrid
    $dg.IsReadOnly = $true; $dg.AutoGenerateColumns = $false
    $dg.HeadersVisibility = "Column"; $dg.Margin = "12"
    $dg.Background = [Windows.Media.Brushes]::White
    $dg.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#4A5568")
    $dg.FontSize = 12; $dg.RowHeight = 24
    $dg.AlternatingRowBackground = [Windows.Media.BrushConverter]::new().ConvertFromString("#F7FAFC")
    $dg.VerticalScrollBarVisibility = "Auto"; $dg.HorizontalScrollBarVisibility = "Auto"
    $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header = "Параметр"; $c1.Binding = [Windows.Data.Binding]::new("parameter"); $c1.Width = New-Object Windows.Controls.DataGridLength(3, "Star")
    $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header = "Было"; $c2.Binding = [Windows.Data.Binding]::new("old_value"); $c2.Width = New-Object Windows.Controls.DataGridLength(3, "Star")
    $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header = "Стало"; $c3.Binding = [Windows.Data.Binding]::new("new_value"); $c3.Width = New-Object Windows.Controls.DataGridLength(3, "Star")
    $c4 = New-Object Windows.Controls.DataGridTextColumn; $c4.Header = "Время"; $c4.Binding = [Windows.Data.Binding]::new("timestamp"); $c4.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
    [void]$dg.Columns.Add($c1); [void]$dg.Columns.Add($c2); [void]$dg.Columns.Add($c3); [void]$dg.Columns.Add($c4)
    $dg.ItemsSource = $histData
    $mb0.Child = $dg; $cw.Child = $mb0
    [System.Windows.Controls.Grid]::SetRow($cw, 1); [void]$cg.Children.Add($cw)
    $ob.Child = $cg; $win.Content = $ob
    $null = $win.ShowDialog()
})

# ── Init ──
try {
    BuildParams
    "Showing window..." | Out-File $logFile -Append
    # Окно стартует свёрнутым — разворачивается при клике на иконку в панели задач
    # Скрываем консоль безопасным способом (без user32.dll — антивирус не детектит)
    try { . (Join-Path $script:scriptsDir "Hide-ConsoleWindow.ps1"); Hide-ConsoleWindow } catch { }
    # Построение логотипа нативными WPF-элементами
    if ($logoBorder) {
        $logoGrad = New-Object Windows.Media.LinearGradientBrush
        $logoGrad.StartPoint = "0,0"; $logoGrad.EndPoint = "1,1"
        [void]$logoGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x6B,0x2D,0x8B), 0.0)))
        [void]$logoGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x31,0x82,0xCE), 1.0)))
        $logoBorder.Background = $logoGrad
        $logoCanvas = New-Object Windows.Controls.Canvas
        $logoBorder.Child = $logoCanvas
        $logoTri = New-Object Windows.Shapes.Polygon
        $logoTri.Points = "8,10 16,26 0,26"; $logoTri.Fill = [Windows.Media.Brushes]::Green
        $logoTri.Stroke = [Windows.Media.Brushes]::White; $logoTri.StrokeThickness = 0.5
        $logoTri.Margin = "4,0,0,0"; $logoTri.HorizontalAlignment = "Left"; $logoTri.VerticalAlignment = "Center"
        [void]$logoCanvas.Children.Add($logoTri)
        $logoText = New-Object Windows.Controls.TextBlock
        $logoText.Text = "Ренессанс."; $logoText.FontSize = 14; $logoText.FontWeight = "Bold"
        $logoText.Foreground = [Windows.Media.Brushes]::White; $logoText.Margin = "22,8,0,0"
        [void]$logoCanvas.Children.Add($logoText)
        $logSubText = New-Object Windows.Controls.TextBlock
        $logSubText.Text = "СТРАХОВАНИЕ"; $logSubText.FontSize = 9
        $logSubText.Foreground = [Windows.Media.Brushes]::White
        $logSubText.Opacity = 0.9; $logSubText.Margin = "22,26,0,0"
        [void]$logoCanvas.Children.Add($logSubText)
    }
    # APPL-глянцевые кнопки
    $script:metroAccent = if ($cfg.gui.accent_color) { $cfg.gui.accent_color } else { "#3182CE" }
    $btnNames = @{
        'BtnSaveSettings'    = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnResetSettings'   = @{Top="#606060"; Bottom="#808080"}
        'BtnValidatePaths'   = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnExportSettings'  = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnImportSettings'  = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnSettingsHistory' = @{Top="#606060"; Bottom="#808080"}
        'BtnStop'            = @{Top="#E53E3E"; Bottom="#C53030"}
        'BtnRun'             = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnExportLog'       = @{Top="#2A5080"; Bottom="#87CEEB"}
        'BtnTogglePwd'       = @{Top="#2A5080"; Bottom="#87CEEB"}
    }
    foreach ($entry in $btnNames.GetEnumerator()) {
        $btn = $window.FindName($entry.Key)
        if ($btn -and $btn -is [System.Windows.Controls.Button]) {
            Apply-GlossyButtonStyle -Button $btn -ColorTop $entry.Value.Top -ColorBottom $entry.Value.Bottom
        }
    }
    # APPL2: построение кастомного title bar
    $appTitleBorder = $window.FindName("AppTitleBar")
    if ($appTitleBorder) {
        $appTitleBorder.Visibility = "Visible"
        $atGrid = New-Object Windows.Controls.Grid
        $atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
        $atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
        $atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
        $atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
        # Двухслойный заголовок: А (белый смещён) + Б (#1A3A60 поверх)
        $titleLayer = New-Object Windows.Controls.Grid
        $titleLayer.VerticalAlignment = "Center"
        $titleTextA = New-Object Windows.Controls.TextBlock
        $titleTextA.Text = "ПРОД-GUI"; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
        $titleTextA.Foreground = [Windows.Media.Brushes]::White
        $titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
        [void]$titleLayer.Children.Add($titleTextA)
        $titleTextB = New-Object Windows.Controls.TextBlock
        $titleTextB.Text = "ПРОД-GUI"; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
        $titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        [void]$titleLayer.Children.Add($titleTextB)
        [System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
        [void]$atGrid.Children.Add($titleLayer)
        # Функция создания кнопок title bar
        function Add-AppTitleButton {
            param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$W = 40, [int]$H = 34, [int]$FS = 16)
            $b = New-Object Windows.Controls.Button
            $btnGrid = New-Object Windows.Controls.Grid
            $btnA = New-Object Windows.Controls.TextBlock
            $btnA.Text = $Text; $btnA.FontSize = $FS; $btnA.FontWeight = "Bold"
            $btnA.Foreground = [Windows.Media.Brushes]::White
            $btnA.Margin = New-Object Windows.Thickness(1,1,0,0)
            $btnA.HorizontalAlignment = "Center"; $btnA.VerticalAlignment = "Center"
            [void]$btnGrid.Children.Add($btnA)
            $btnB = New-Object Windows.Controls.TextBlock
            $btnB.Text = $Text; $btnB.FontSize = $FS; $btnB.FontWeight = "Bold"
            $btnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
            $btnB.HorizontalAlignment = "Center"; $btnB.VerticalAlignment = "Center"
            [void]$btnGrid.Children.Add($btnB)
            $b.Content = $btnGrid; $b.Width = $W; $b.Height = $H
            $b.FontWeight = "Bold"; $b.FontSize = $FS
            $b.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
            $b.Cursor = "Hand"
            $b.HorizontalContentAlignment = "Center"
            $b.VerticalContentAlignment = "Center"
            $b.Padding = New-Object Windows.Thickness(0)
            $b.BorderThickness = New-Object Windows.Thickness(3)
            $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
            $tg = New-Object Windows.Media.LinearGradientBrush
            $tg.StartPoint = "0,0"; $tg.EndPoint = "0,1"
            [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
            [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
            [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
            $b.Background = $tg
            try {
                $tx = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
                $rr = New-Object System.Xml.XmlNodeReader ([xml]$tx).DocumentElement
                $b.Template = [Windows.Markup.XamlReader]::Load($rr)
            } catch { }
            [System.Windows.Controls.Grid]::SetColumn($b, $Col)
            $b.Add_Click($Click)
            $b.Add_MouseEnter({
                $hoverB = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"}))
                $this.Background = $hoverB
            })
            $b.Add_MouseLeave({
                $tg2 = New-Object Windows.Media.LinearGradientBrush
                $tg2.StartPoint = "0,0"; $tg2.EndPoint = "0,1"
                [void]$tg2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
                [void]$tg2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
                [void]$tg2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
                $this.Background = $tg2
            })
            return $b
        }
        $minBtn = Add-AppTitleButton -Text "━" -Col 1 -Click { $window.WindowState = [Windows.WindowState]::Minimized }
        $maxBtn = Add-AppTitleButton -Text "▣" -Col 2 -Click {
            if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal"; $atGrid.Children[2].Content = "▣" }
            else { $window.WindowState = "Maximized"; $atGrid.Children[2].Content = "❐" }
        } -FS 18
        $closeBtn = Add-AppTitleButton -Text "✕" -Col 3 -Click { $window.Close() } -IsClose
        [void]$atGrid.Children.Add($minBtn)
        [void]$atGrid.Children.Add($maxBtn)
        [void]$atGrid.Children.Add($closeBtn)
        $appTitleBorder.Child = $atGrid
        # DragMove
        $appTitleBorder.Add_MouseLeftButtonDown({
            if ($_.ClickCount -eq 1 -and $window.WindowState -ne "Maximized") {
                try { $window.DragMove() } catch {}
            }
            elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
        })
    }
    # APPL: скруглённые углы для полей ввода
    $inputGrad = New-Object Windows.Media.LinearGradientBrush
    $inputGrad.StartPoint = "0,0"; $inputGrad.EndPoint = "0,1"
    [void]$inputGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xFA,0xFA,0xFA), 0.0)))
    [void]$inputGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xF0,0xF0,0xF0), 1.0)))
    $inputShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $inputShadow.Color = [Windows.Media.Color]::FromRgb(0xA0,0xA0,0xA0)
    $inputShadow.Direction = 270; $inputShadow.ShadowDepth = 1; $inputShadow.BlurRadius = 2; $inputShadow.Opacity = 0.3
    foreach ($ctrl in @($pwdBox, $pwdText)) {
        if ($ctrl) {
            $ctrl.Background = $inputGrad
            $ctrl.Effect = $inputShadow
            Set-InputRoundedStyle -Control $ctrl -Radius 12
        }
    }
    # Овальная рамка для CmbOperation (через Border, не через ControlTemplate)
    if ($cmbOp -and $cmbOp.Parent) {
        try {
            # Проверить, не обёрнут ли уже в Border
            $parent = $cmbOp.Parent
            if ($parent -is [System.Windows.Controls.Border] -and $parent.Child -eq $cmbOp) {
                return  # Уже обёрнут
            }
            $cmbBorder = New-Object System.Windows.Controls.Border
            $cmbBorder.CornerRadius = [System.Windows.CornerRadius]::new(12)
            $cmbBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
            $cmbBorder.BorderThickness = "1"
            $cmbBorder.Background = $inputGrad
            $cmbBorder.Effect = $inputShadow
            $cmbBorder.Margin = "0,0,0,0"
            $cmbParent = $cmbOp.Parent
            $idx = $cmbParent.Children.IndexOf($cmbOp)
            if ($idx -ge 0) {
                $cmbOp.BorderThickness = "0"
                $cmbOp.Margin = "0"
                $cmbBorder.Child = $cmbOp
                $cmbParent.Children.RemoveAt($idx)
                $cmbParent.Children.InsertAt($idx, $cmbBorder)
            }
        } catch { }  # Молча игнорировать ошибки обёртки
    }
    # 3D для блока параметров (горизонтальный градиент)
    if ($paramsBorder) {
        $pGrad = New-Object Windows.Media.LinearGradientBrush
        $pGrad.StartPoint = "0,0"; $pGrad.EndPoint = "1,0"
        [void]$pGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xF5,0xF7,0xFA), 0.0)))
        [void]$pGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xE8,0xEC,0xF4), 0.5)))
        [void]$pGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xDE,0xE4,0xEE), 1.0)))
        $paramsBorder.Background = $pGrad
        $pShadow = New-Object Windows.Media.Effects.DropShadowEffect
        $pShadow.Color = [Windows.Media.Color]::FromRgb(0x80,0x80,0x80)
        $pShadow.Direction = 270; $pShadow.ShadowDepth = 3; $pShadow.BlurRadius = 6; $pShadow.Opacity = 0.3
        $paramsBorder.Effect = $pShadow
    }
    # 3D для кнопки Run — в словаре btnNames (общий стиль)
    # Восстановить положение и размер окна
    $layoutFile = Join-Path $script:projectRoot "config\window_layout.json"
    if (Test-Path $layoutFile) {
        try {
            $layout = Get-Content $layoutFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($layout.Width -ge 400 -and $layout.Height -ge 400) {
                $window.WindowStartupLocation = "Manual"
                if ($layout.Left -ge -100 -or $layout.Top -ge -100) {
                    if ($layout.Left -ge 0) { $window.Left = $layout.Left }
                    if ($layout.Top -ge 0) { $window.Top = $layout.Top }
                }
                $window.Width = $layout.Width
                $window.Height = $layout.Height
            }
        } catch { "Window layout load error: $_" | Out-File $logFile -Append }
    }
    # Регистрация обработчика закрытия ДО ShowDialog
    $window.Add_Closing({
        # Остановить все таймеры
        if ($script:currentAnimationTimer) {
            try { $script:currentAnimationTimer.Stop() } catch {}
            $script:currentAnimationTimer = $null
        }
        if ($script:uiTimer) {
            try { $script:uiTimer.Stop() } catch {}
            $script:uiTimer = $null
        }
        # Сохранить положение и размер окна
        try {
            $layoutDir = Join-Path $script:projectRoot "config"
            if (-not (Test-Path $layoutDir)) { New-Item -ItemType Directory -Path $layoutDir -Force -ErrorAction Stop | Out-Null }
            $layoutFile = Join-Path $layoutDir "window_layout.json"
            $layout = @{Width=$window.Width; Height=$window.Height; Left=$window.Left; Top=$window.Top} | ConvertTo-Json
            Set-Content -Path $layoutFile -Value $layout -Encoding UTF8 -ErrorAction Stop
        } catch { try { "Window layout save error: $_" | Out-File $logFile -Append } catch {} }
        # Консоль была скрыта через перезапуск — восстановление не требуется
    })
    
    # AutoRun блок
    if ($script:autoRun -and $script:autoRunOpName) {
        $script:autoRunSelecting = $true
        $window.Add_Loaded({
            try {
                "AutoRun: selecting operation '$script:autoRunOpName'" | Out-File $logFile -Append
                $found = $false
                
                # Нормализуем строку для сравнения (убираем кракозябры)
                $searchName = $script:autoRunOpName
                # Проверяем числовой индекс
                $idx = $null
                if ($searchName -match '^\d+$') {
                    $idx = [int]$searchName - 1
                }
                
                # Если строка содержит кракозябры, ищем по ключевым словам
                if ($null -ne $idx -and $idx -ge 0 -and $idx -lt $cmbOp.Items.Count) {
                    $cmbOp.SelectedIndex = $idx
                    "AutoRun: selected by index $idx" | Out-File $logFile -Append
                    $found = $true
                } elseif ($searchName -match 'Сравнение' -or $searchName -match 'Compare') {
                    $searchName = "Сравнение PB"
                } elseif ($searchName -match 'Выгрузка' -or $searchName -match 'Export') {
                    $searchName = "Выгрузка PB"
                } elseif ($searchName -match 'PB' -and $searchName -match 'Current' -and $searchName -match 'Main') {
                    $searchName = "Сравнение PB"
                } elseif ($searchName -match 'VSS.*History' -or $searchName -match 'История') {
                    $searchName = "История"
                }
                
                for ($i = 0; $i -lt $cmbOp.Items.Count; $i++) {
                    $item = $cmbOp.Items[$i]
                    $itemText = $item.ToString()
                    if ($itemText -match [regex]::Escape($searchName)) {
                        $cmbOp.SelectedIndex = $i
                        "AutoRun: selected index $i (matched '$searchName')" | Out-File $logFile -Append
                        $found = $true
                        break
                    }
                }
                if (-not $found) {
                    "AutoRun: operation not found! Search='$searchName', Items=$($cmbOp.Items.Count)" | Out-File $logFile -Append
                    for ($i = 0; $i -lt $cmbOp.Items.Count; $i++) {
                        "AutoRun:   [$i] = '$($cmbOp.Items[$i])'" | Out-File $logFile -Append
                    }
                    return
                }
                Start-Sleep -Milliseconds 500
                if ($script:autoRunTaskName) {
                    foreach ($child in $paramsPanel.Children) {
                        if ($child -is [System.Windows.Controls.StackPanel]) {
                            foreach ($inner in $child.Children) {
                                if ($inner -is [System.Windows.Controls.TextBox] -and $inner.Name -eq "txt_TaskName") {
                                    $inner.Text = $script:autoRunTaskName
                                    "AutoRun: set txt_TaskName = $script:autoRunTaskName" | Out-File $logFile -Append
                                }
                            }
                        }
                    }
                }
                if ($script:autoRunOutputFile) {
                    foreach ($child in $paramsPanel.Children) {
                        if ($child -is [System.Windows.Controls.StackPanel]) {
                            foreach ($inner in $child.Children) {
                                if ($inner -is [System.Windows.Controls.TextBox] -and $inner.Name -eq "txt_OutputFile") {
                                    $inner.Text = $script:autoRunOutputFile
                                    "AutoRun: set txt_OutputFile = $script:autoRunOutputFile" | Out-File $logFile -Append
                                }
                            }
                        }
                    }
                }
                $script:autoRunSelecting = $false
                Start-Sleep -Milliseconds 300
                try { BuildParams } catch { "AutoRun BuildParams error: $_" | Out-File $logFile -Append }
                Start-Sleep -Milliseconds 100
                $btnRun.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                "AutoRun: Run clicked" | Out-File $logFile -Append
            } catch {
                "AutoRun error: $_" | Out-File $logFile -Append
            }
        })
    }
    
    if ($script:autoRun) {
        $closeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $closeTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $closeTimer.Add_Tick({
            if ($script:autoRunCompleted -and $closeTimer -and $window) {
                try {
                    $closeTimer.Stop()
                    $window.Close()
                } catch {}
            }
        })
        $closeTimer.Start()
    }
    if ($window) {
        try { $window.ShowDialog() | Out-Null } catch {}
    }
    "Window closed" | Out-File $logFile -Append
} catch {
    $errMsg = "Fatal: $_`n`n$($_.ScriptStackTrace)"
    if ($_.Exception.InnerException) {
        $errMsg += "`n`nInner: $($_.Exception.InnerException)`n$($_.Exception.InnerException.StackTrace)"
    }
    [System.IO.File]::AppendAllText($logFile, $errMsg + "`r`n")
    [System.Windows.MessageBox]::Show($errMsg, "Fatal Error", "OK", "Error")
}


