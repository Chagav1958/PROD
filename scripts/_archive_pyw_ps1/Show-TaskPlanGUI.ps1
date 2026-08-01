<#
.SYNOPSIS
    ДО TaskPlan — управление планом задачи (3 вкладки: Список задач, Управление, Тесты)
.DESCRIPTION
    СТАНДАРТ1 (APPL2). Использует TaskPlan-Tracker.ps1 для работы с планами.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Web.Extensions -ErrorAction SilentlyContinue

. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"

$scriptPath = Split-Path $PSCommandPath -Parent
$trackerPath = Join-Path $scriptPath 'TaskPlan-Tracker.ps1'
$managerPath  = Join-Path $scriptPath 'TaskPlan-Manager.ps1'
$testsPath    = Join-Path $scriptPath 'TaskPlan-Tests.ps1'
$prodRoot   = 'C:\AIS\AI\Prod\tasks'
$releaseRoot = 'C:\AIS\1 Release'

# ── Загрузка индекса задач из task_index.json ──
function Load-TaskIndex {
    $roots = @($prodRoot, $releaseRoot)
    $tasks = @()
    foreach ($r in $roots) {
        $idxFile = Join-Path $r 'task_index.json'
        if (Test-Path $idxFile) {
            try {
                $raw = Get-Content -LiteralPath $idxFile -Raw -Encoding UTF8
                $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                $jss.MaxJsonLength = 10 * 1024 * 1024
                $data = $jss.DeserializeObject($raw)
                # Обработка формата: {"tasks":[...],"current":"...","timestamp":"..."}
                if ($data -is [hashtable] -and $data.ContainsKey('tasks')) {
                    $taskList = $data['tasks']
                    foreach ($t in $taskList) {
                        $tasks += @{
                            id = if ($t.ContainsKey('id')) { $t['id'] } else { '' }
                            name = if ($t.ContainsKey('name')) { $t['name'] } else { '' }
                            root = $r
                            status = if ($t.ContainsKey('status')) { $t['status'] } else { '' }
                            timestamp = if ($t.ContainsKey('updated')) { $t['updated'] } else { '' }
                            sortTime = if ($t.ContainsKey('updated')) { $t['updated'] } else { '' }
                        }
                    }
                } elseif ($data -is [System.Collections.ArrayList]) { $data = @($data) }
                elseif ($data -is [array] -or $data -is [System.Collections.IList]) {
                    foreach ($t in $data) {
                        $tasks += @{
                            id = $t['id']; name = $t['name']; root = $r;
                            status = if ($t['status']) { $t['status'] } else { '' }
                            timestamp = if ($t['updated']) { $t['updated'] } else { '' }
                            sortTime = if ($t['updated']) { $t['updated'] } else { '' }
                        }
                    }
                }
            } catch {}
        }
    }
    # Сортируем: свежие сверху
    $tasks = $tasks | Sort-Object { $_.name } -Descending
    return $tasks
}

function Get-ReleaseRoot {
    param([string]$TaskName)
    if ($TaskName -match '^(SYBASE|SUPRT)-') { return $releaseRoot } else { return $prodRoot }
}

# ── Чтение папок задач (если task_index.json нет) ──
function Load-TaskFolders {
    $folders = @()
    foreach ($r in @($prodRoot, $releaseRoot)) {
        if (Test-Path $r) {
            Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $ts = $_.LastWriteTime.ToString('dd.MM.yyyy HH:mm:ss')
                $stateFile = Join-Path $_.FullName 'Describe\plan_state.json'
                if (Test-Path $stateFile) {
                    try {
                        $raw = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8
                        $jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer
                        if ($raw -match '"timestamp":\s*"(.+?)"') { $ts = $matches[1] }
                    } catch {}
                }
                $folders += @{ name = $_.Name; root = $r; timestamp = $ts; sortTime = $ts }
            }
        }
    }
    return $folders | Sort-Object { $_.sortTime } -Descending
}

# ── Чтение плана задачи ──
function Read-TaskPlan {
    param([string]$Name, [string]$Root)
    # Ищем папку: сначала префикс (правило TASK)
    $found = Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$Name*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($found) {
        $taskPath = $found.FullName
    } else {
        $taskPath = Join-Path $Root $Name
        if (-not (Test-Path $taskPath)) { return $null }
    }
    $descDir = Join-Path $taskPath 'Describe'
    $planFile = Join-Path $descDir 'ПЛАН_РЕАЛИЗАЦИИ.txt'
    if (-not (Test-Path $planFile)) { return $null }
    $lines = Get-Content -LiteralPath $planFile -Encoding UTF8
    $goal = ''; $stages = @(); $inStages = $false
    foreach ($ln in $lines) {
        if ($ln -match '^ЦЕЛЬ:\s*(.+)$') { $goal = $matches[1]; $inStages = $false }
        elseif ($ln -match '^ЭТАПЫ:') { $inStages = $true }
        elseif ($inStages -and $ln -match '^\[([ x~!])\]\s*(\d+)\.\s*(.+?)(?:\s*\((.+)\))?$') {
            $stages += [PSCustomObject]@{
                num = [int]$matches[2]
                text = $matches[3].Trim()
                status = switch ($matches[1]) { ' ' { 'не начато' } 'x' { 'готово' } '~' { 'в работе' } '!' { 'отложено' } }
                engStatus = switch ($matches[1]) { ' ' { 'todo' } 'x' { 'done' } '~' { 'wip' } '!' { 'defer' } }
                by = if ($matches[4]) { $matches[4].Trim() } else { '' }
            }
        }
    }
    return @{ goal = $goal; stages = $stages }
}

# ── Список LLM из opencode.jsonc ──
function Get-OpenCodeModelList {
    $projectRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    $cfgPaths = @(
        [System.IO.Path]::Combine($projectRoot, 'opencode.jsonc')
        [System.IO.Path]::Combine($env:USERPROFILE, '.config\opencode\opencode.jsonc')
    )
    $models = @()
    foreach ($cfgPath in $cfgPaths) {
        if (-not (Test-Path -LiteralPath $cfgPath)) { continue }
        try {
            $raw = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
            foreach ($p in $data.provider.PSObject.Properties) {
                if (-not $p.Value.models) { continue }
                foreach ($m in $p.Value.models.PSObject.Properties) {
                    if ($m.Value.enabled -eq $false) { continue }
                    $costInput = 0.0
                    if ($m.Value.cost -and $m.Value.cost.input) { $costInput = [double]$m.Value.cost.input }
                    $models += @{ name = "$($m.Value.name)  [$($m.Name)]"; rawId = $m.Name; cost = $costInput }
                }
            }
        } catch { continue }
    }

    # Встроенные модели OpenCode (built-in), отсутствующие в opencode.jsonc
    $builtinModels = @(
        @{ name = 'Big Pickle  [big-pickle]';                     rawId = 'big-pickle';                cost = 0.0 }
        @{ name = 'Claude Opus 4.1  [claude-opus-4-1]';           rawId = 'claude-opus-4-1';          cost = 0.0 }
        @{ name = 'Claude Opus 4.5  [claude-opus-4-5]';           rawId = 'claude-opus-4-5';          cost = 0.0 }
        @{ name = 'Claude Opus 4.8  [claude-opus-4-8]';           rawId = 'claude-opus-4-8';          cost = 0.0 }
        @{ name = 'Claude Sonnet 4.5  [claude-sonnet-4-5]';       rawId = 'claude-sonnet-4-5';        cost = 0.0 }
        @{ name = 'Claude Sonnet 5  [claude-sonnet-5]';           rawId = 'claude-sonnet-5';          cost = 0.0 }
        @{ name = 'DeepSeek V4 Flash  [deepseek-v4-flash]';       rawId = 'deepseek-v4-flash';        cost = 0.0 }
        @{ name = 'DeepSeek V4 Flash Free  [deepseek-v4-flash-free]'; rawId = 'deepseek-v4-flash-free'; cost = 0.0 }
        @{ name = 'DeepSeek V4 Pro  [deepseek-v4-pro]';           rawId = 'deepseek-v4-pro';          cost = 0.0 }
        @{ name = 'GLM-4.7  [glm-4.7]';                           rawId = 'glm-4.7';                  cost = 0.0 }
        @{ name = 'GLM-5  [glm-5]';                               rawId = 'glm-5';                    cost = 0.0 }
        @{ name = 'GLM-5.1  [glm-5.1]';                           rawId = 'glm-5.1';                  cost = 0.0 }
        @{ name = 'GLM-5.2  [glm-5.2]';                           rawId = 'glm-5.2';                  cost = 0.0 }
        @{ name = 'GPT-4o Mini  [gpt-4o-mini]';                   rawId = 'gpt-4o-mini';              cost = 0.0 }
        @{ name = 'GPT-5  [gpt-5]';                               rawId = 'gpt-5';                    cost = 0.0 }
        @{ name = 'GPT-5.4 Pro  [gpt-5.4-pro]';                   rawId = 'gpt-5.4-pro';              cost = 0.0 }
        @{ name = 'GPT-5.5 Pro  [gpt-5.5-pro]';                   rawId = 'gpt-5.5-pro';              cost = 0.0 }
        @{ name = 'Gemini 3.1 Pro  [gemini-3.1-pro]';             rawId = 'gemini-3.1-pro';           cost = 0.0 }
        @{ name = 'Grok Code Fast  [grok-code]';                  rawId = 'grok-code';                cost = 0.0 }
        @{ name = 'Hy3 Free  [hy3-free]';                         rawId = 'hy3-free';                 cost = 0.0 }
        @{ name = 'Kimi K2  [kimi-k2]';                           rawId = 'kimi-k2';                  cost = 0.0 }
        @{ name = 'Kimi K2.5  [kimi-k2.5]';                       rawId = 'kimi-k2.5';                cost = 0.0 }
        @{ name = 'Kimi K2.5 Free  [kimi-k2.5-free]';             rawId = 'kimi-k2.5-free';           cost = 0.0 }
        @{ name = 'Kimi K2.6  [kimi-k2.6]';                       rawId = 'kimi-k2.6';                cost = 0.0 }
        @{ name = 'Kimi K2.7 Code  [kimi-k2.7-code]';             rawId = 'kimi-k2.7-code';           cost = 0.0 }
        @{ name = 'MiniMax-M3  [minimax-m3]';                     rawId = 'minimax-m3';               cost = 0.0 }
        @{ name = 'MiniMax-M2.5  [minimax-m2.5]';                 rawId = 'minimax-m2.5';             cost = 0.0 }
        @{ name = 'MiMo V2.5 Free  [mimo-v2.5-free]';             rawId = 'mimo-v2.5-free';           cost = 0.0 }
        @{ name = 'MiMo V2.5 Pro  [mimo-v2.5-pro]';               rawId = 'mimo-v2.5-pro';            cost = 0.0 }
        @{ name = 'MiMo V2 Omni Free  [mimo-v2-omni-free]';       rawId = 'mimo-v2-omni-free';        cost = 0.0 }
        @{ name = 'Nemotron 3 Ultra Free  [nemotron-3-ultra-free]'; rawId = 'nemotron-3-ultra-free';  cost = 0.0 }
        @{ name = 'North Mini  [north-mini]';                     rawId = 'north-mini';               cost = 0.0 }
        @{ name = 'Qwen3 Coder 480B  [qwen3-coder]';              rawId = 'qwen3-coder';              cost = 0.0 }
        @{ name = 'Qwen3.5 Plus  [qwen3.5-plus]';                 rawId = 'qwen3.5-plus';             cost = 0.0 }
        @{ name = 'Qwen3.7 Plus  [qwen3.7-plus]';                 rawId = 'qwen3.7-plus';             cost = 0.0 }
        @{ name = 'Qwen3.7 Max  [qwen3.7-max]';                   rawId = 'qwen3.7-max';              cost = 0.0 }
    )

    # Добавляем встроенные, если их ещё нет
    $knownIds = @{}
    foreach ($m in $models) { $knownIds[$m.rawId] = $true }
    foreach ($bi in $builtinModels) {
        if (-not $knownIds.ContainsKey($bi.rawId)) {
            $models += $bi
        }
    }

    $free = $models | Where-Object { $_.cost -eq 0 } | Sort-Object name
    $paid = $models | Where-Object { $_.cost -gt 0 } | Sort-Object @{Expression={[double]$_.cost}}, name
    $result = @()
    foreach ($m in $free) { $result += $m.name }
    foreach ($m in $paid) { $result += $m.name }
    $result += '(своё)'
    return $result
}

$llmList = Get-OpenCodeModelList
$statusList = @('не начато', 'в работе', 'готово', 'отложено')
$statusToEng = @{ 'не начато' = 'todo'; 'в работе' = 'wip'; 'готово' = 'done'; 'отложено' = 'defer' }

# ── Построение окна ──
$window = New-Object Windows.Window
$window.Title = "TaskPlan — управление планом задачи"
$window.Width = 1100; $window.Height = 720
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.AllowsTransparency = $true
$window.WindowStyle = "None"
$window.Background = "Transparent"
$window.ResizeMode = "CanResizeWithGrip"
$window.ShowInTaskbar = $false

$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60; $outerBorder.BorderBrush = "#1A3A60"
$outerBorder.BorderThickness = 1; $outerBorder.Background = "#33FFFFFF"
$shadow = New-Object Windows.Media.Effects.DropShadowEffect
$shadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
$shadow.Direction = 270; $shadow.ShadowDepth = 4; $shadow.BlurRadius = 10; $shadow.Opacity = 0.5
$outerBorder.Effect = $shadow

$cg = New-Object Windows.Controls.Grid
$cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$cg.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

# Title border
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

# 3D текст заголовка
$tl = New-Object Windows.Controls.Grid; $tl.VerticalAlignment = "Center"
$t1 = New-Object Windows.Controls.TextBlock
$t1.Text = "TaskPlan — управление планом задачи"; $t1.FontSize = 14; $t1.FontWeight = "Bold"
$t1.Foreground = "White"; $t1.Margin = [Windows.Thickness]::new(1,1,0,0)
[void]$tl.Children.Add($t1)
$t2 = New-Object Windows.Controls.TextBlock
$t2.Text = "TaskPlan — управление планом задачи"; $t2.FontSize = 14; $t2.FontWeight = "Bold"
$t2.Foreground = "#1A3A60"
[void]$tl.Children.Add($t2)
[Windows.Controls.Grid]::SetColumn($tl, 0); [void]$tg.Children.Add($tl)

# Кнопки title bar
function Add-TitleButton {
    param($Text, [int]$Col, [switch]$IsClose)
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
    return $b
}

$minB = Add-TitleButton -Text "━" -Col 1
$maxB = Add-TitleButton -Text "▣" -Col 2
$cloB = Add-TitleButton -Text "✕" -Col 3 -IsClose
$minB.Add_Click({ $window.WindowState = "Minimized" })
$maxB.Add_Click({ if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal" } else { $window.WindowState = "Maximized" } })
$cloB.Add_Click({ $window.Close() })
[void]$tg.Children.Add($minB); [void]$tg.Children.Add($maxB); [void]$tg.Children.Add($cloB)
$tb.Child = $tg; [void]$cg.Children.Add($tb)

# Content wrapper
$cw = New-Object Windows.Controls.Border
$cw.Background = "#1A3A60"; $cw.CornerRadius = 46; $cw.Margin = [Windows.Thickness]::new(4,0,4,4)
[Windows.Controls.Grid]::SetRow($cw, 1)

$mb = New-Object Windows.Controls.Border
$mb.CornerRadius = 42; $mb.Background = "White"; $mb.Padding = "16,10,16,14"; $mb.Margin = [Windows.Thickness]::new(4)

$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

$headerText = New-Object Windows.Controls.TextBlock
$headerText.Text = "TaskPlan — Сервис управления задачами"
$headerText.FontSize = 14; $headerText.FontWeight = "Bold"
$headerText.Foreground = "#1A3A60"
$headerText.Margin = [Windows.Thickness]::new(0,2,0,4)
[Windows.Controls.Grid]::SetRow($headerText, 0)
[void]$mainGrid.Children.Add($headerText)

# ── TabControl ──
$tabControl = New-Object Windows.Controls.TabControl
$tabControl.FontSize = 12
$tabControl.Margin = [Windows.Thickness]::new(0,0,0,0)
[Windows.Controls.Grid]::SetRow($tabControl, 1)

# ============ ВКЛАДКА 0: СПИСОК ЗАДАЧ ============
$tabList = New-Object Windows.Controls.TabItem
$tabList.Header = "Список задач"
$tabList.FontSize = 12; $tabList.FontWeight = "Bold"

$listGrid = New-Object Windows.Controls.Grid
$listGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$listGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$listGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$listGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# Комбобокс выбора задачи
$selectPanel = New-Object Windows.Controls.StackPanel
$selectPanel.Orientation = "Horizontal"
$selectPanel.Margin = [Windows.Thickness]::new(0,2,0,4)

$lblTask = New-Object Windows.Controls.TextBlock
$lblTask.Text = "Задача:"
$lblTask.FontSize = 12; $lblTask.Foreground = "#1A3A60"
$lblTask.VerticalAlignment = "Center"; $lblTask.Margin = [Windows.Thickness]::new(0,0,6,0)
[void]$selectPanel.Children.Add($lblTask)

$comboTask = New-Object Windows.Controls.ComboBox
$comboTask.Width = 300; $comboTask.Height = 26
$comboTask.FontSize = 11
$comboTask.IsEditable = $true
$comboTask.ToolTip = "Выберите или введите имя задачи"
[void]$selectPanel.Children.Add($comboTask)

$btnRefresh = New-Object Windows.Controls.Button
$btnRefresh.Content = "⟳"; $btnRefresh.Width = 30; $btnRefresh.Height = 26
$btnRefresh.Margin = [Windows.Thickness]::new(4,0,0,0)
Apply-GlossyButtonStyle -Button $btnRefresh
[void]$selectPanel.Children.Add($btnRefresh)

[Windows.Controls.Grid]::SetRow($selectPanel, 0)
[void]$listGrid.Children.Add($selectPanel)

# Таблица этапов (ListView)
$listView = New-Object Windows.Controls.ListView
$listView.FontSize = 11
$gv = New-Object Windows.Controls.GridView
$c1 = New-Object Windows.Controls.GridViewColumn; $c1.Header="№"; $c1.Width=35; $c1.DisplayMemberBinding=[Windows.Data.Binding]::new("num"); [void]$gv.Columns.Add($c1)
$c2 = New-Object Windows.Controls.GridViewColumn; $c2.Header="Статус"; $c2.Width=80; $c2.DisplayMemberBinding=[Windows.Data.Binding]::new("status"); [void]$gv.Columns.Add($c2)
$c3 = New-Object Windows.Controls.GridViewColumn; $c3.Header="Этап"; $c3.Width=400; $c3.DisplayMemberBinding=[Windows.Data.Binding]::new("text"); [void]$gv.Columns.Add($c3)
$c4 = New-Object Windows.Controls.GridViewColumn; $c4.Header="Исполнитель"; $c4.Width=120; $c4.DisplayMemberBinding=[Windows.Data.Binding]::new("by"); [void]$gv.Columns.Add($c4)
$listView.View = $gv
$listView.AlternationCount = 2
$listView.Background = "#F5F7FA"
$listView.BorderBrush = "#CBD5E0"
$listView.BorderThickness = 1
$listView.SelectionMode = "Single"

[Windows.Controls.Grid]::SetRow($listView, 1)
[void]$listGrid.Children.Add($listView)

# Прогресс-бар
$progressPanel = New-Object Windows.Controls.Grid
$progressPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$progressPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$progressPanel.Margin = [Windows.Thickness]::new(0,4,0,2)
[Windows.Controls.Grid]::SetRow($progressPanel, 2)

$progressBar = New-Object Windows.Controls.ProgressBar
$progressBar.Height = 20
$progressBar.Margin = [Windows.Thickness]::new(0,0,8,0)
$progressBar.Foreground = "#2E7D32"
$progressBar.Background = "#E2E8F0"
$progressBar.BorderBrush = "#CBD5E0"
$progressBar.BorderThickness = 1
$progressBar.Minimum = 0; $progressBar.Maximum = 100
[Windows.Controls.Grid]::SetColumn($progressBar, 0)
[void]$progressPanel.Children.Add($progressBar)

$statLabel = New-Object Windows.Controls.TextBlock
$statLabel.Text = "0/0 (0%)"
$statLabel.FontSize = 11; $statLabel.FontWeight = "SemiBold"
$statLabel.Foreground = "#1A3A60"
$statLabel.VerticalAlignment = "Center"; $statLabel.MinWidth = 80
[Windows.Controls.Grid]::SetColumn($statLabel, 1)
[void]$progressPanel.Children.Add($statLabel)

[void]$listGrid.Children.Add($progressPanel)

# Цель задачи
$goalText = New-Object Windows.Controls.TextBlock
$goalText.Text = ""
$goalText.FontSize = 11; $goalText.Foreground = "#4A5568"
$goalText.Margin = [Windows.Thickness]::new(0,0,0,2)
$goalText.TextWrapping = "Wrap"
[Windows.Controls.Grid]::SetRow($goalText, 3)
[void]$listGrid.Children.Add($goalText)

$tabList.Content = $listGrid; [void]$tabControl.Items.Add($tabList)

# ============ ВКЛАДКА 1: УПРАВЛЕНИЕ ============
$tabMgmt = New-Object Windows.Controls.TabItem
$tabMgmt.Header = "Управление"
$tabMgmt.FontSize = 12; $tabMgmt.FontWeight = "Bold"

$mgmtScroll = New-Object Windows.Controls.ScrollViewer
$mgmtScroll.VerticalScrollBarVisibility = "Auto"

$mgmtPanel = New-Object Windows.Controls.StackPanel
$mgmtPanel.Margin = [Windows.Thickness]::new(0,2,0,0)

# Функция создания подписи
function Add-Label {
    param([string]$Text)
    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Text
    $lbl.FontSize = 11; $lbl.FontWeight = "SemiBold"
    $lbl.Foreground = "#1A3A60"; $lbl.Margin = [Windows.Thickness]::new(0,4,0,2)
    return $lbl
}

# Имя задачи
[void]$mgmtPanel.Children.Add((Add-Label "Имя задачи"))
$gridTaskName = New-Object Windows.Controls.Grid
$gridTaskName.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$gridTaskName.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$comboTaskName = New-Object Windows.Controls.ComboBox
$comboTaskName.Height = 26; $comboTaskName.FontSize = 11
$comboTaskName.IsEditable = $true
$comboTaskName.ToolTip = "Выберите или введите имя задачи"
[Windows.Controls.Grid]::SetColumn($comboTaskName, 0)
[void]$gridTaskName.Children.Add($comboTaskName)

$labelRoot = New-Object Windows.Controls.TextBlock
$labelRoot.Text = "Корень: $prodRoot"
$labelRoot.FontSize = 10; $labelRoot.Foreground = "#718096"
$labelRoot.VerticalAlignment = "Center"; $labelRoot.Margin = [Windows.Thickness]::new(6,0,0,0)
[Windows.Controls.Grid]::SetColumn($labelRoot, 1)
[void]$gridTaskName.Children.Add($labelRoot)

[void]$mgmtPanel.Children.Add($gridTaskName)

# Цель
[void]$mgmtPanel.Children.Add((Add-Label "Цель (Goal)"))
$txtGoal = New-Object Windows.Controls.TextBox
$txtGoal.Height = 60; $txtGoal.FontSize = 11
$txtGoal.AcceptsReturn = $true; $txtGoal.TextWrapping = "Wrap"
$txtGoal.Background = "White"; $txtGoal.BorderBrush = "#CBD5E0"
$txtGoal.BorderThickness = 1; $txtGoal.Padding = "4,2"
[void]$mgmtPanel.Children.Add($txtGoal)

# Этапы
[void]$mgmtPanel.Children.Add((Add-Label "Этапы (каждый с новой строки, формат: Текст или Текст|Исполнитель)"))
$txtStages = New-Object Windows.Controls.TextBox
$txtStages.Height = 100; $txtStages.FontSize = 11
$txtStages.AcceptsReturn = $true; $txtStages.TextWrapping = "Wrap"
$txtStages.Background = "White"; $txtStages.BorderBrush = "#CBD5E0"
$txtStages.BorderThickness = 1; $txtStages.Padding = "4,2"
[void]$mgmtPanel.Children.Add($txtStages)

# LLM / исполнитель
[void]$mgmtPanel.Children.Add((Add-Label "LLM / исполнитель"))
$comboLLM = New-Object Windows.Controls.ComboBox
$comboLLM.Height = 26; $comboLLM.FontSize = 11
$comboLLM.IsEditable = $true
$comboLLM.ItemsSource = $llmList
$comboLLM.SelectedIndex = 0
$comboLLM.ToolTip = "Выберите LLM или введите своё значение"
[void]$mgmtPanel.Children.Add($comboLLM)

# Статус этапа + Номер этапа
$statusNumPanel = New-Object Windows.Controls.Grid
$statusNumPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$statusNumPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="180"}))
$statusNumPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$statusNumPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="80"}))
$statusNumPanel.Margin = [Windows.Thickness]::new(0,4,0,0)

$lblStatus = New-Object Windows.Controls.TextBlock
$lblStatus.Text = "Статус этапа:"
$lblStatus.FontSize = 11; $lblStatus.FontWeight = "SemiBold"
$lblStatus.Foreground = "#1A3A60"
$lblStatus.VerticalAlignment = "Center"
$lblStatus.Margin = [Windows.Thickness]::new(0,0,4,0)
[Windows.Controls.Grid]::SetColumn($lblStatus, 0)
[void]$statusNumPanel.Children.Add($lblStatus)

$comboStatus = New-Object Windows.Controls.ComboBox
$comboStatus.Height = 26; $comboStatus.FontSize = 11
$comboStatus.ItemsSource = $statusList
$comboStatus.SelectedIndex = 0
[Windows.Controls.Grid]::SetColumn($comboStatus, 1)
[void]$statusNumPanel.Children.Add($comboStatus)

$lblNum = New-Object Windows.Controls.TextBlock
$lblNum.Text = "Номер этапа:"
$lblNum.FontSize = 11; $lblNum.FontWeight = "SemiBold"
$lblNum.Foreground = "#1A3A60"
$lblNum.VerticalAlignment = "Center"
$lblNum.Margin = [Windows.Thickness]::new(8,0,4,0)
[Windows.Controls.Grid]::SetColumn($lblNum, 2)
[void]$statusNumPanel.Children.Add($lblNum)

$spinnerNum = New-Object Windows.Controls.TextBox
$spinnerNum.Text = "1"; $spinnerNum.Width = 70; $spinnerNum.Height = 26
$spinnerNum.FontSize = 11; $spinnerNum.VerticalContentAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($spinnerNum, 3)
[void]$statusNumPanel.Children.Add($spinnerNum)

[void]$mgmtPanel.Children.Add($statusNumPanel)

# Кнопки
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.Margin = [Windows.Thickness]::new(0,8,0,0)
$btnPanel.HorizontalAlignment = "Center"

function New-ActionButton {
    param([string]$Text, [string]$ColorTop="#1A3A60", [string]$ColorBottom="#2A4A70")
    $btn = New-Object Windows.Controls.Button
    if ($Text.Length -gt 3) { $btn.Content = " $Text " } else { $btn.Content = $Text }
    $btn.Height = 30; $btn.FontSize = 11
    $btn.Margin = [Windows.Thickness]::new(3,0,3,0)
    Apply-GlossyButtonStyle -Button $btn -ColorTop $ColorTop -ColorBottom $ColorBottom
    return $btn
}

$btnNewPlan  = New-ActionButton -Text "Новый план"
$btnSetStatus = New-ActionButton -Text "Уст. статус"
$btnAddStages = New-ActionButton -Text "Доб. этапы"
$btnNextStage = New-ActionButton -Text "След. этап"
$btnBrief     = New-ActionButton -Text "Подг. бриф"
$btnSyncJson  = New-ActionButton -Text "Синхр. JSON"

[void]$btnPanel.Children.Add($btnNewPlan)
[void]$btnPanel.Children.Add($btnSetStatus)
[void]$btnPanel.Children.Add($btnAddStages)
[void]$btnPanel.Children.Add($btnNextStage)
[void]$btnPanel.Children.Add($btnBrief)
[void]$btnPanel.Children.Add($btnSyncJson)
[void]$mgmtPanel.Children.Add($btnPanel)

# Лог операций
$mgmtLog = New-Object Windows.Controls.TextBox
$mgmtLog.Height = 80; $mgmtLog.FontSize = 10
$mgmtLog.FontFamily = "Consolas"; $mgmtLog.IsReadOnly = $true
$mgmtLog.Background = "#1A202C"; $mgmtLog.Foreground = "#A0AEC0"
$mgmtLog.BorderThickness = 1; $mgmtLog.BorderBrush = "#CBD5E0"
$mgmtLog.Padding = "4,2"; $mgmtLog.TextWrapping = "Wrap"
$mgmtLog.VerticalScrollBarVisibility = "Auto"
$mgmtLog.Margin = [Windows.Thickness]::new(0,6,0,0)
[void]$mgmtPanel.Children.Add($mgmtLog)

function Add-MgmtLog {
    param([string]$Msg)
    $time = Get-Date -Format "HH:mm:ss"
    $line = "[$time] $Msg"
    $mgmtLog.Text = $mgmtLog.Text + "$line`r`n"
    $mgmtLog.ScrollToEnd()
    $logFile = Join-Path $scriptPath '..\temp\taskplan_gui_log.log'
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

$mgmtScroll.Content = $mgmtPanel
$tabMgmt.Content = $mgmtScroll; [void]$tabControl.Items.Add($tabMgmt)

# ============ ВКЛАДКА 2: ТЕСТЫ ============
$tabTests = New-Object Windows.Controls.TabItem
$tabTests.Header = "Тесты"
$tabTests.FontSize = 12; $tabTests.FontWeight = "Bold"

$testGrid = New-Object Windows.Controls.Grid
$testGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$testGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$testGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

$testHeader = New-Object Windows.Controls.TextBlock
$testHeader.Text = "Автотесты TaskPlan (15 тестов: трекер + GUI)"
$testHeader.FontSize = 11; $testHeader.Foreground = "#4A5568"
$testHeader.Margin = [Windows.Thickness]::new(0,2,0,4)
[Windows.Controls.Grid]::SetRow($testHeader, 0)
[void]$testGrid.Children.Add($testHeader)

$testLog = New-Object Windows.Controls.TextBox
$testLog.FontSize = 10; $testLog.FontFamily = "Consolas"
$testLog.IsReadOnly = $true
$testLog.Background = "#1A202C"; $testLog.Foreground = "#A0AEC0"
$testLog.BorderThickness = 1; $testLog.BorderBrush = "#CBD5E0"
$testLog.Padding = "4,2"; $testLog.TextWrapping = "Wrap"
$testLog.VerticalScrollBarVisibility = "Auto"
$testLog.HorizontalScrollBarVisibility = "Auto"
[Windows.Controls.Grid]::SetRow($testLog, 1)
[void]$testGrid.Children.Add($testLog)

$testBtnPanel = New-Object Windows.Controls.StackPanel
$testBtnPanel.Orientation = "Horizontal"
$testBtnPanel.HorizontalAlignment = "Right"
$testBtnPanel.Margin = [Windows.Thickness]::new(0,4,0,0)
[Windows.Controls.Grid]::SetRow($testBtnPanel, 2)

$btnRunTests = New-Object Windows.Controls.Button
$btnRunTests.Content = "Запустить тесты"
$btnRunTests.Width = 140; $btnRunTests.Height = 30
$btnRunTests.Margin = [Windows.Thickness]::new(0,0,6,0)
Apply-GlossyButtonStyle -Button $btnRunTests -ColorTop "#2E7D32" -ColorBottom "#66BB6A"

$btnClose = New-Object Windows.Controls.Button
$btnClose.Content = "Закрыть"
$btnClose.Width = 100; $btnClose.Height = 30
Apply-GlossyButtonStyle -Button $btnClose -ColorTop "#606060" -ColorBottom "#808080"

[void]$testBtnPanel.Children.Add($btnRunTests)
[void]$testBtnPanel.Children.Add($btnClose)
[void]$testGrid.Children.Add($testBtnPanel)

$tabTests.Content = $testGrid; [void]$tabControl.Items.Add($tabTests)

# ============ ВКЛАДКА 3: ИМПОРТ ИЗ TASK ============
$tabImport = New-Object Windows.Controls.TabItem
$tabImport.Header = "Импорт из TASK"
$tabImport.FontSize = 12; $tabImport.FontWeight = "Bold"

$impGrid = New-Object Windows.Controls.Grid
$impGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$impGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$impGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

# Панель выбора задачи
$impSelect = New-Object Windows.Controls.StackPanel
$impSelect.Orientation = "Horizontal"
$impSelect.Margin = [Windows.Thickness]::new(0,2,0,4)

$lblImpTask = New-Object Windows.Controls.TextBlock
$lblImpTask.Text = "Задача TASK:"
$lblImpTask.FontSize = 12; $lblImpTask.Foreground = "#1A3A60"
$lblImpTask.VerticalAlignment = "Center"; $lblImpTask.Margin = [Windows.Thickness]::new(0,0,6,0)
[void]$impSelect.Children.Add($lblImpTask)

$comboImpTask = New-Object Windows.Controls.ComboBox
$comboImpTask.Width = 320; $comboImpTask.Height = 26
$comboImpTask.FontSize = 11
$comboImpTask.IsEditable = $true
$comboImpTask.ToolTip = "Выберите или введите имя TASK-задачи (папка SYBASE-*/SUPRT-*/TASK-*)"
[void]$impSelect.Children.Add($comboImpTask)

$btnImpRefresh = New-Object Windows.Controls.Button
$btnImpRefresh.Content = "⟳"; $btnImpRefresh.Width = 30; $btnImpRefresh.Height = 26
$btnImpRefresh.Margin = [Windows.Thickness]::new(4,0,0,0)
Apply-GlossyButtonStyle -Button $btnImpRefresh
[void]$impSelect.Children.Add($btnImpRefresh)

$btnImport = New-Object Windows.Controls.Button
$btnImport.Content = " Импортировать "
$btnImport.Height = 26; $btnImport.FontSize = 11
$btnImport.Margin = [Windows.Thickness]::new(4,0,0,0)
Apply-GlossyButtonStyle -Button $btnImport -ColorTop "#2E7D32" -ColorBottom "#66BB6A"
[void]$impSelect.Children.Add($btnImport)

[Windows.Controls.Grid]::SetRow($impSelect, 0)
[void]$impGrid.Children.Add($impSelect)

# Описание
$impDesc = New-Object Windows.Controls.TextBlock
$impDesc.Text = "Подхватывает ранее подготовленную TASK-задачу (папку с Git_/Test_/Ready_/Describe). " +
               "Обработанные объекты (есть в Ready/Test) помечаются как выполненные [x]; " +
               "необработанные (только в Git) — как ожидающие [ ]; рекомендации из Describe — как исполняемые этапы."
$impDesc.FontSize = 11; $impDesc.Foreground = "#4A5568"
$impDesc.Margin = [Windows.Thickness]::new(0,2,0,6)
$impDesc.TextWrapping = "Wrap"
[Windows.Controls.Grid]::SetRow($impDesc, 1)
[void]$impGrid.Children.Add($impDesc)

# Лог
$impLog = New-Object Windows.Controls.TextBox
$impLog.FontSize = 10; $impLog.FontFamily = "Consolas"
$impLog.IsReadOnly = $true
$impLog.Background = "#1A202C"; $impLog.Foreground = "#A0AEC0"
$impLog.BorderThickness = 1; $impLog.BorderBrush = "#CBD5E0"
$impLog.Padding = "4,2"; $impLog.TextWrapping = "Wrap"
$impLog.VerticalScrollBarVisibility = "Auto"
$impLog.Margin = [Windows.Thickness]::new(0,4,0,0)
[Windows.Controls.Grid]::SetRow($impLog, 2)
[void]$impGrid.Children.Add($impLog)

$tabImport.Content = $impGrid; [void]$tabControl.Items.Add($tabImport)

# ============ ОБРАБОТЧИКИ ============

# Обновление списка задач (сортировка по дате использования)
function Update-TaskList {
    $sel = $comboTask.SelectedItem
    $tasks = Load-TaskIndex
    if ($tasks.Count -eq 0) { $tasks = Load-TaskFolders }
    # Добавляем дату последнего изменения для сортировки
    $now = Get-Date
    foreach ($t in $tasks) {
        $ts = if ($t.timestamp) { $t.timestamp } else { $t.sortTime }
        if ($ts) {
            try { $t.sortTime = [datetime]::ParseExact($ts, 'dd.MM.yyyy HH:mm:ss', $null) } catch {
                try { $t.sortTime = [datetime]::ParseExact($ts, 'dd.MM.yyyy HH:mm', $null) } catch {
                    $t.sortTime = $now
                }
            }
        } else {
            $t.sortTime = $now
        }
    }
    $tasks = $tasks | Sort-Object { $_.sortTime } -Descending
    $comboTask.ItemsSource = ($tasks | ForEach-Object { "[$($_.root.Split('\')[-1])] $($_.name)" })
    $comboTaskName.ItemsSource = ($tasks | ForEach-Object { "[$($_.root.Split('\')[-1])] $($_.name)" })
    if ($sel) { $comboTask.Text = $sel }
    try { $comboTask.Items.Refresh() } catch {}
}

# Загрузка плана задачи в список
function Load-PlanToView {
    param([string]$TaskName)
    $root = Get-ReleaseRoot -TaskName $TaskName
    $plan = Read-TaskPlan -Name $TaskName -Root $root
    if (-not $plan) {
        $listView.ItemsSource = $null
        $progressBar.Value = 0
        $statLabel.Text = "0/0 (0%)"
        $goalText.Text = "План не найден"
        return
    }
    # Заполняем ВКЛ1 (Список задач)
    $listView.ItemsSource = @($plan.stages)
    $done = @($plan.stages | Where-Object { $_.status -eq 'готово' }).Count
    $total = $plan.stages.Count
    $pct = if ($total -gt 0) { [math]::Round($done / $total * 100) } else { 0 }
    $progressBar.Value = $pct
    $statLabel.Text = "$done/$total ($pct%)"
    $goalText.Text = "ЦЕЛЬ: $($plan.goal)"
    # Заполняем ВКЛ2 (Управление)
    $txtGoal.Text = $plan.goal
    $stagesTextLines = @()
    foreach ($s in $plan.stages) {
        $byPart = if ($s.by) { "|$($s.by)" } else { '' }
        $stagesTextLines += "$($s.text)$byPart"
    }
    $txtStages.Text = $stagesTextLines -join "`r`n"
}

# ComboBox выбора задачи
$comboTask.Add_SelectionChanged({
    $sel = $this.SelectedItem
    if ($sel) {
        $name = $sel -replace '^\[[^\]]*\]\s*', ''
    } else {
        $name = $this.Text -replace '^\[[^\]]*\]\s*', ''
    }
    if ($name) { Load-PlanToView -TaskName $name }
})

# Обновление списка задач для импорта (все папки задач)
function Update-ImportList {
    $folders = @()
    foreach ($r in @($prodRoot, $releaseRoot)) {
        if (Test-Path $r) {
            Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $folders += "[$($r.Split('\')[-1])] $($_.Name)"
            }
        }
    }
    $folders = $folders | Sort-Object -Descending
    $comboImpTask.ItemsSource = $folders
}

function Add-ImpLog {
    param([string]$Msg)
    $time = Get-Date -Format "HH:mm:ss"
    $impLog.Text = $impLog.Text + "[$time] $Msg`r`n"
    $impLog.ScrollToEnd()
}

$btnImpRefresh.Add_Click({ Update-ImportList })

$btnImport.Add_Click({
    $sel = $comboImpTask.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $sel) { Add-ImpLog "ОШИБКА: выберите задачу TASK"; return }
    $root = Get-ReleaseRoot -TaskName $sel
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoLogo -File `"$trackerPath`" -Action import -TaskName `"$sel`" -Force"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit(60000)
        Add-ImpLog ($out -replace "`n"," ")
        if ($err) { Add-ImpLog "STDERR: $err" }
        # Обновим список задач и план
        Update-TaskList
        Load-PlanToView -TaskName $sel
    } catch { Add-ImpLog "ОШИБКА: $_" }
})

# Refresh
$btnRefresh.Add_Click({ Update-TaskList })

# НОВЫЙ ПЛАН
$btnNewPlan.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $goal = $txtGoal.Text.Trim()
    if (-not $goal) { Add-MgmtLog "ОШИБКА: укажите цель"; return }
    $stageLines = $txtStages.Text.Trim() -split "`r`n" | Where-Object { $_.Trim() -ne '' }
    if ($stageLines.Count -eq 0) { Add-MgmtLog "ОШИБКА: укажите этапы"; return }
    $root = Get-ReleaseRoot -TaskName $taskName
    try {
        if (Test-Path (Join-Path (Join-Path $root $taskName) 'Describe\ПЛАН_РЕАЛИЗАЦИИ.txt')) {
            $res = [System.Windows.MessageBox]::Show("План уже существует. Перезаписать?", "Подтверждение", "YesNo", "Question")
            if ($res -ne "Yes") { return }
        }
        & $trackerPath -Action 'new' -TaskName $taskName -ReleaseRoot $root -Goal $goal -Stages $stageLines -Force
        Add-MgmtLog "План создан: $taskName ($($stageLines.Count) этапов)"
        Update-TaskList
        Load-PlanToView -TaskName $taskName
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# УСТ. СТАТУС
$btnSetStatus.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $num = 0
    if (-not [int]::TryParse($spinnerNum.Text, [ref]$num) -or $num -le 0) { Add-MgmtLog "ОШИБКА: неверный номер этапа"; return }
    $status = $comboStatus.SelectedItem
    if (-not $status) { Add-MgmtLog "ОШИБКА: выберите статус"; return }
    $engStatus = $statusToEng[$status]
    $llmText = $comboLLM.Text
    # Из строки вида "Name  [model-id]" извлекаем model-id
    if ($llmText -match '\[([^\]]+)\]$') { $llm = $matches[1] } else { $llm = $llmText }
    $root = Get-ReleaseRoot -TaskName $taskName
    try {
        & $trackerPath -Action 'set' -TaskName $taskName -ReleaseRoot $root -StageNum $num -Status $engStatus -DoneBy $llm
        Add-MgmtLog "Статус этапа $num установлен: $status ($llm)"
        Load-PlanToView -TaskName $taskName
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# ДОБ. ЭТАПЫ
$btnAddStages.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $stageLines = $txtStages.Text.Trim() -split "`r`n" | Where-Object { $_.Trim() -ne '' }
    if ($stageLines.Count -eq 0) { Add-MgmtLog "ОШИБКА: укажите этапы"; return }
    $root = Get-ReleaseRoot -TaskName $taskName
    try {
        & $trackerPath -Action 'add' -TaskName $taskName -ReleaseRoot $root -Stages $stageLines
        Add-MgmtLog "Добавлено этапов: $($stageLines.Count)"
        Load-PlanToView -TaskName $taskName
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# СЛЕД. ЭТАП
$btnNextStage.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $root = Get-ReleaseRoot -TaskName $taskName
    try {
        $out = & $trackerPath -Action 'next' -TaskName $taskName -ReleaseRoot $root
        Add-MgmtLog "Следующий этап: $out"
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# ПОДГ. БРИФ
$btnBrief.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $root = Get-ReleaseRoot -TaskName $taskName
    $briefScript = Join-Path $scriptPath 'TaskPlan-PrepareBrief.ps1'
    if (-not (Test-Path $briefScript)) { Add-MgmtLog "ОШИБКА: TaskPlan-PrepareBrief.ps1 не найден"; return }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoLogo -File `"$briefScript`" -TaskName `"$taskName`" -ReleaseRoot `"$root`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit(15000)
        Add-MgmtLog "Бриф: $($out -replace "`n"," ")"
        if ($err) { Add-MgmtLog "STDERR: $err" }
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# СИНХР. JSON
$btnSyncJson.Add_Click({
    $taskName = $comboTaskName.Text -replace '^\[[^\]]*\]\s*', ''
    if (-not $taskName) { Add-MgmtLog "ОШИБКА: укажите имя задачи"; return }
    $root = Get-ReleaseRoot -TaskName $taskName
    try {
        & $trackerPath -Action 'sync' -TaskName $taskName -ReleaseRoot $root
        Add-MgmtLog "JSON синхронизирован"
    } catch { Add-MgmtLog "ОШИБКА: $_" }
})

# ТЕСТЫ
$btnRunTests.Add_Click({
    $testLog.Text = "Запуск тестов...`r`n"
    $btnRunTests.IsEnabled = $false
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell'
        $psi.Arguments = "-NoLogo -File `"$testsPath`" -PassThru"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit(60000)
        $testLog.Text = $out
        if ($err) { $testLog.Text = $testLog.Text + "`r`n--- STDERR ---`r`n$err" }
    } catch { $testLog.Text = "ОШИБКА: $_" }
    finally { $btnRunTests.IsEnabled = $true }
})

$btnClose.Add_Click({ $window.Close() })

# Инициализация
Update-TaskList
Update-ImportList

[void]$mainGrid.Children.Add($tabControl)
$mb.Child = $mainGrid
$cw.Child = $mb
[void]$cg.Children.Add($cw)
$outerBorder.Child = $cg
$window.Content = $outerBorder
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
[void]$window.ShowDialog()
