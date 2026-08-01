<#
.SYNOPSIS
    ДО для просмотра и редактирования файлов-правил проекта AIS.
.DESCRIPTION
    СТАНДАРТ1 (APPL2). Основные вкладки по темам, подвкладки по файлам.
    Редактор с кнопками Редактировать/Сохранить/Отмена.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"

$projectRoot = Split-Path $PSScriptRoot -Parent

# Определение вкладок
$tabDefs = @(
    @{
        Name = "Общие"
        Files = @(
            @{ Name = "AGENTS.md"; Path = "AGENTS.md" }
            @{ Name = "index.mdc"; Path = ".opencode\index.mdc" }
            @{ Name = "project-context.mdc"; Path = ".opencode\project-context.mdc" }
            @{ Name = "general-rules.md"; Path = "rules\general-rules.md" }
            @{ Name = "repository-layout.mdc"; Path = ".opencode\repository-layout.mdc" }
        )
    }
    @{
        Name = "PowerBuilder"
        Files = @(
            @{ Name = "pb-object-rules.mdc"; Path = ".opencode\pb-object-rules.mdc" }
            @{ Name = "entity-reference.mdc"; Path = ".opencode\entity-reference.mdc" }
            @{ Name = "pb_export_rules.md"; Path = "docs\service_rules\pb_export_rules.md" }
        )
    }
    @{
        Name = "SQL"
        Files = @(
            @{ Name = "sql-rules.mdc"; Path = ".opencode\sql-rules.mdc" }
            @{ Name = "sql-rules.md"; Path = "rules\sql-rules.md" }
            @{ Name = "sql_export_rules.md"; Path = "docs\service_rules\sql_export_rules.md" }
        )
    }
    @{
        Name = "Jira"
        Files = @(
            @{ Name = "jira-table-rules.mdc"; Path = ".opencode\jira-table-rules.mdc" }
            @{ Name = "jira-rules.md"; Path = "rules\jira-rules.md" }
            @{ Name = "jira_rfc_rules.md"; Path = "docs\service_rules\jira_rfc_rules.md" }
        )
    }
    @{
        Name = "VSS"
        Files = @(
            @{ Name = "vss-rules.mdc"; Path = ".opencode\vss-rules.mdc" }
            @{ Name = "vss-rules.md"; Path = "rules\vss-rules.md" }
            @{ Name = "vss_rules.md"; Path = "docs\service_rules\vss_rules.md" }
        )
    }
    @{
        Name = "GUI"
        Files = @(
            @{ Name = "gui-rules.md"; Path = "rules\gui-rules.md" }
            @{ Name = "gui_rules.md"; Path = "docs\service_rules\gui_rules.md" }
        )
    }
    @{
        Name = "Тестирование"
        Files = @(
            @{ Name = "testing-rules.md"; Path = "rules\testing-rules.md" }
            @{ Name = "test_rules.md"; Path = "docs\service_rules\test_rules.md" }
        )
    }
    @{
        Name = "Сокращения"
        Files = @(
            @{ Name = "abbreviations.md"; Path = "rules\abbreviations.md" }
            @{ Name = "glossary.mdc"; Path = ".opencode\glossary.mdc" }
        )
    }
    @{
        Name = "Команды"
        Files = @(
            @{ Name = "abbr.md"; Path = ".opencode\command\abbr.md" }
            @{ Name = "cycle.md"; Path = ".opencode\command\cycle.md" }
            @{ Name = "design.md"; Path = ".opencode\command\design.md" }
            @{ Name = "fixshow.md"; Path = ".opencode\command\fixshow.md" }
            @{ Name = "llm.md"; Path = ".opencode\command\llm.md" }
            @{ Name = "otest.md"; Path = ".opencode\command\otest.md" }
            @{ Name = "prompts.md"; Path = ".opencode\command\prompts.md" }
            @{ Name = "remember.md"; Path = ".opencode\command\remember.md" }
            @{ Name = "rudiment.md"; Path = ".opencode\command\rudiment.md" }
            @{ Name = "save.md"; Path = ".opencode\command\save.md" }
            @{ Name = "voice.md"; Path = ".opencode\command\voice.md" }
        )
    }
    @{
        Name = "Сервисы"
        Files = @(
            @{ Name = "compare_rules.md"; Path = "docs\service_rules\compare_rules.md" }
            @{ Name = "init_rules.md"; Path = "docs\service_rules\init_rules.md" }
        )
    }
    @{
        Name = "Прочее"
        Files = @(
            @{ Name = "tool-usage.md"; Path = "rules\tool-usage.md" }
            @{ Name = "remember-rule.md"; Path = "rules\remember-rule.md" }
            @{ Name = "remember.md"; Path = ".opencode\command\remember.md" }
        )
    }
)

# Загрузка содержимого всех файлов
$loadedFiles = @{}
function Load-FileContent {
    param([string]$relPath)
    $fullPath = Join-Path $projectRoot $relPath
    if ($loadedFiles.ContainsKey($relPath)) { return }
    try {
        $content = [System.IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
        $fi = Get-Item -LiteralPath $fullPath
        $loadedFiles[$relPath] = @{
            Content = $content
            Path = $fullPath
            Size = $fi.Length
            LastWrite = $fi.LastWriteTime
        }
    } catch {
        $loadedFiles[$relPath] = @{
            Content = "ОШИБКА: не удалось прочитать файл $relPath`n$_"
            Path = $fullPath
            Size = 0
            LastWrite = Get-Date
        }
    }
}

foreach ($tab in $tabDefs) {
    foreach ($f in $tab.Files) {
        Load-FileContent -relPath $f.Path
    }
}

# Заголовок тайтл-бара (APPL2)
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

# Создание редактора файла
function New-FileEditor {
    param([string]$relPath)
    $data = $loadedFiles[$relPath]
    if (-not $data) { return $null }

    $container = New-Object Windows.Controls.Grid
    $container.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $container.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $container.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    # Инфо-панель
    $infoPanel = New-Object Windows.Controls.StackPanel
    $infoPanel.Orientation = "Horizontal"
    $infoPanel.Margin = [Windows.Thickness]::new(0,0,0,4)

    $fiName = Split-Path -Leaf $data.Path
    $sizeKB = [math]::Round($data.Size / 1024, 1)
    $lastW = $data.LastWrite.ToString("dd.MM.yyyy HH:mm")

    $infoText = New-Object Windows.Controls.TextBlock
    $infoText.Text = "$fiName  |  $sizeKB KB  |  $lastW"
    $infoText.FontSize = 11
    $infoText.Foreground = "#4A5568"
    $infoText.ToolTip = $data.Path
    [void]$infoPanel.Children.Add($infoText)

    [Windows.Controls.Grid]::SetRow($infoPanel, 0)
    [void]$container.Children.Add($infoPanel)

    # TextBox (без внешнего ScrollViewer — TextBox сам управляет скроллингом)
    $tb = New-Object Windows.Controls.TextBox
    $tb.Text = $data.Content
    $tb.IsReadOnly = $true
    $tb.FontFamily = "Consolas"
    $tb.FontSize = 10
    $tb.Background = "#F5F7FA"
    $tb.Foreground = "#1A3A60"
    $tb.BorderThickness = [Windows.Thickness]::new(1)
    $tb.BorderBrush = "#CBD5E0"
    $tb.AcceptsReturn = $true
    $tb.AcceptsTab = $true
    $tb.TextWrapping = "NoWrap"
    $tb.VerticalScrollBarVisibility = "Auto"
    $tb.HorizontalScrollBarVisibility = "Auto"
    $tb.Padding = [Windows.Thickness]::new(6)
    $tb.Tag = $data.Content
    $tb.IsInactiveSelectionHighlightEnabled = $true
    $tb.SelectionBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#5699FF")
    $tb.SelectionOpacity = 0.9

    [Windows.Controls.Grid]::SetRow($tb, 1)
    [void]$container.Children.Add($tb)

    # Панель кнопок
    $btnPanel = New-Object Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"
    $btnPanel.Margin = [Windows.Thickness]::new(0,4,0,0)

    $btnEdit = New-Object Windows.Controls.Button
    $btnEdit.Content = "Редактировать"
    $btnEdit.Width = 140; $btnEdit.Height = 30
    $btnEdit.Margin = [Windows.Thickness]::new(0,0,4,0)
    Apply-GlossyButtonStyle -Button $btnEdit

    $btnSave = New-Object Windows.Controls.Button
    $btnSave.Content = "Сохранить"
    $btnSave.Width = 120; $btnSave.Height = 30
    $btnSave.Margin = [Windows.Thickness]::new(0,0,4,0)
    $btnSave.Visibility = "Collapsed"
    Apply-GlossyButtonStyle -Button $btnSave -ColorTop "#2E7D32" -ColorBottom "#66BB6A"

    $btnCancel = New-Object Windows.Controls.Button
    $btnCancel.Content = "Отмена"
    $btnCancel.Width = 110; $btnCancel.Height = 30
    $btnCancel.Visibility = "Collapsed"
    Apply-GlossyButtonStyle -Button $btnCancel -ColorTop "#606060" -ColorBottom "#808080"

    $data.TbRef = $tb
    $data.EditBtn = $btnEdit
    $data.SaveBtn = $btnSave
    $data.CancelBtn = $btnCancel
    $data.InfoText = $infoText
    $data.FiName = $fiName

    $btnEdit.Tag = $data
    $btnSave.Tag = $data
    $btnCancel.Tag = $data

    $btnEdit.Add_Click({
        $d = $this.Tag
        if (-not $d) { return }
        $tbBx = $d.TbRef
        $btnE = $d.EditBtn
        $btnS = $d.SaveBtn
        $btnC = $d.CancelBtn
        if (-not $tbBx) { return }
        $btnE.Visibility = "Collapsed"
        $btnS.Visibility = "Visible"
        $btnC.Visibility = "Visible"
        $tbBx.IsReadOnly = $false
        $tbBx.Background = "White"
        $tbBx.Focus()
    })

    $btnSave.Add_Click({
        $d = $this.Tag
        if (-not $d) { return }
        $tbBx = $d.TbRef; $btnE = $d.EditBtn; $btnS = $d.SaveBtn; $btnC = $d.CancelBtn; $infT = $d.InfoText; $fNm = $d.FiName
        if (-not $tbBx) { return }
        try {
            [System.IO.File]::WriteAllText($d.Path, $tbBx.Text, [Text.Encoding]::UTF8)
            $tbBx.Tag = $tbBx.Text
            $d.Content = $tbBx.Text
            $fi2 = Get-Item -LiteralPath $d.Path
            $sizeKB2 = [math]::Round($fi2.Length / 1024, 1)
            $lastW2 = $fi2.LastWriteTime.ToString("dd.MM.yyyy HH:mm")
            $infT.Text = "$fNm  |  $sizeKB2 KB  |  $lastW2"
            $btnE.Visibility = "Visible"
            $btnS.Visibility = "Collapsed"
            $btnC.Visibility = "Collapsed"
            $tbBx.IsReadOnly = $true
            $tbBx.Background = "#F5F7FA"
            [System.Windows.MessageBox]::Show("Файл сохранён: $fNm", "Сохранено", "OK", "Information")
        } catch {
            [System.Windows.MessageBox]::Show("Ошибка сохранения: $_", "Ошибка", "OK", "Error")
        }
    })

    $btnCancel.Add_Click({
        $d = $this.Tag
        if (-not $d) { return }
        $tbBx = $d.TbRef; $btnE = $d.EditBtn; $btnS = $d.SaveBtn; $btnC = $d.CancelBtn
        if (-not $tbBx) { return }
        $tbBx.Text = $tbBx.Tag
        $btnE.Visibility = "Visible"
        $btnS.Visibility = "Collapsed"
        $btnC.Visibility = "Collapsed"
        $tbBx.IsReadOnly = $true
        $tbBx.Background = "#F5F7FA"
    })

    [void]$btnPanel.Children.Add($btnEdit)
    [void]$btnPanel.Children.Add($btnSave)
    [void]$btnPanel.Children.Add($btnCancel)

    [Windows.Controls.Grid]::SetRow($btnPanel, 2)
    [void]$container.Children.Add($btnPanel)

    return $container
}

# ── Построение окна ──
$window = New-Object Windows.Window
$window.Title = "Правила проекта AIS"; $window.Width = 1220; $window.Height = 780
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

# Двухслойный 3D-текст заголовка
$tl = New-Object Windows.Controls.Grid; $tl.VerticalAlignment = "Center"
$t1 = New-Object Windows.Controls.TextBlock
$t1.Text = "Правила проекта AIS"; $t1.FontSize = 16; $t1.FontWeight = "Bold"
$t1.Foreground = "White"; $t1.Margin = [Windows.Thickness]::new(1,1,0,0)
[void]$tl.Children.Add($t1)
$t2 = New-Object Windows.Controls.TextBlock
$t2.Text = "Правила проекта AIS"; $t2.FontSize = 16; $t2.FontWeight = "Bold"
$t2.Foreground = "#1A3A60"
[void]$tl.Children.Add($t2)
[Windows.Controls.Grid]::SetColumn($tl, 0); [void]$tg.Children.Add($tl)

# Кнопки title bar
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

# Main border
$mb = New-Object Windows.Controls.Border
$mb.CornerRadius = 42; $mb.Background = "White"; $mb.Padding = "20,16,20,22"; $mb.Margin = [Windows.Thickness]::new(4)

# Main grid внутри mainBorder
$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# Поисковый сервис (как в ПРОМПТ)
$script:searchState = @{ results = @(); index = -1; query = "" }
$script:searchItems = @()  # плоский список файлов с ссылками на вкладки

$searchPanel = New-Object Windows.Controls.Grid
$searchPanel.Margin = [Windows.Thickness]::new(0,4,0,0)
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
[Windows.Controls.Grid]::SetRow($searchPanel, 2)

$lblSearch = New-Object Windows.Controls.TextBlock
$lblSearch.Text = "Поиск:"
$lblSearch.FontSize = 11; $lblSearch.Foreground = "#4A5568"
$lblSearch.VerticalAlignment = "Center"
$lblSearch.Margin = [Windows.Thickness]::new(0,0,4,0)
[Windows.Controls.Grid]::SetColumn($lblSearch, 0)
[void]$searchPanel.Children.Add($lblSearch)

$hdrText = New-Object Windows.Controls.TextBlock
$hdrText.Text = "Файлы-правил проекта AIS ($($loadedFiles.Count) файлов)"
$hdrText.FontSize = 11; $hdrText.Foreground = "#4A5568"
$hdrText.Margin = [Windows.Thickness]::new(0,0,0,2)
[Windows.Controls.Grid]::SetRow($hdrText, 0)
[void]$mainGrid.Children.Add($hdrText)

$searchBox = New-Object Windows.Controls.TextBox
$searchBox.FontSize = 12; $searchBox.Height = 28
$searchBox.Margin = [Windows.Thickness]::new(8,0,4,0)
$searchBox.VerticalContentAlignment = "Center"
$searchBox.Padding = "6,0"
$searchBox.Background = "White"
$searchBox.BorderBrush = "#CBD5E0"
$searchBox.BorderThickness = "1"
[Windows.Controls.Grid]::SetColumn($searchBox, 1)
[void]$searchPanel.Children.Add($searchBox)

$btnDown = New-Object Windows.Controls.Button
$btnDown.Content = "▼"; $btnDown.Width = 30; $btnDown.Height = 28
$btnDown.Margin = [Windows.Thickness]::new(0,0,2,0); $btnDown.FontSize = 12
Apply-GlossyButtonStyle -Button $btnDown
[Windows.Controls.Grid]::SetColumn($btnDown, 2)
[void]$searchPanel.Children.Add($btnDown)

$btnUp = New-Object Windows.Controls.Button
$btnUp.Content = "▲"; $btnUp.Width = 30; $btnUp.Height = 28
$btnUp.Margin = [Windows.Thickness]::new(0,0,4,0); $btnUp.FontSize = 12
Apply-GlossyButtonStyle -Button $btnUp
[Windows.Controls.Grid]::SetColumn($btnUp, 3)
[void]$searchPanel.Children.Add($btnUp)

$matchLabel = New-Object Windows.Controls.TextBlock
$matchLabel.Text = "0 - 0"
$matchLabel.FontSize = 11; $matchLabel.FontWeight = "SemiBold"
$matchLabel.Foreground = "#4A5568"
$matchLabel.VerticalAlignment = "Center"; $matchLabel.MinWidth = 40
$matchLabel.Margin = [Windows.Thickness]::new(0,0,8,0)
[Windows.Controls.Grid]::SetColumn($matchLabel, 4)  # добавляем колонку 4
$null = $searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
[void]$searchPanel.Children.Add($matchLabel)

[void]$mainGrid.Children.Add($searchPanel)

# Поиск TextBox в визуальном дереве и выделение контекста
function Select-SearchResult {
    param([string]$Query)
    if ([string]::IsNullOrEmpty($Query)) { return }
    # Ищем активный TabItem — если есть вложенный TabControl, берём его выбранную вкладку
    $activeTab = $mainTabControl.SelectedItem
    if (-not $activeTab) { return }
    $content = $activeTab.Content
    # Если есть вложенный TabControl, берём его выбранную вкладку
    $innerTabControl = $content
    if ($innerTabControl -is [System.Windows.Controls.TabControl]) {
        $activeInner = $innerTabControl.SelectedItem
        if ($activeInner) { $content = $activeInner.Content }
    }
    # Поиск TextBox и выделение через таймер (после переключения вкладок)
    $script:highlightQuery = $Query
    if ($script:hlTimer) { $script:hlTimer.Stop(); $script:hlTimer = $null }
    $script:hlTimer = New-Object Windows.Threading.DispatcherTimer
    $script:hlTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:hlTimer.Add_Tick({
        $qLoc = $script:highlightQuery
        if ([string]::IsNullOrEmpty($qLoc)) { $script:hlTimer.Stop(); $script:hlTimer = $null; return }
        # BFS-поиск TextBox внутри активной вкладки
        $tbLoc = $null
        $activeC = $mainTabControl.SelectedItem.Content
        if ($activeC -is [System.Windows.Controls.TabControl]) { $activeC = $activeC.SelectedItem.Content }
        if ($activeC) {
            $stk = New-Object Collections.Generic.Stack[System.Windows.DependencyObject]
            $stk.Push($activeC)
            while ($stk.Count -gt 0 -and -not $tbLoc) {
                $p = $stk.Pop()
                $cnt = [Windows.Media.VisualTreeHelper]::GetChildrenCount($p)
                for ($i = 0; $i -lt $cnt -and -not $tbLoc; $i++) {
                    $c = [Windows.Media.VisualTreeHelper]::GetChild($p, $i)
                    if ($c -is [System.Windows.Controls.TextBox] -and $c.IsInactiveSelectionHighlightEnabled) { $tbLoc = $c }
                    if (-not $tbLoc) { $stk.Push($c) }
                }
            }
        }
        # Если не нашли через active content — ищем по всему окну
        if (-not $tbLoc) {
            $stk2 = New-Object Collections.Generic.Stack[System.Windows.DependencyObject]
            $stk2.Push([System.Windows.Application]::Current.MainWindow)
            while ($stk2.Count -gt 0 -and -not $tbLoc) {
                $p = $stk2.Pop()
                $cnt = [Windows.Media.VisualTreeHelper]::GetChildrenCount($p)
                for ($i = 0; $i -lt $cnt -and -not $tbLoc; $i++) {
                    $c = [Windows.Media.VisualTreeHelper]::GetChild($p, $i)
                    if ($c -is [System.Windows.Controls.TextBox] -and $c.IsInactiveSelectionHighlightEnabled) { $tbLoc = $c }
                    if (-not $tbLoc) { $stk2.Push($c) }
                }
            }
        }
        if ($tbLoc) {
            $idx = $tbLoc.Text.IndexOf($qLoc, [StringComparison]::OrdinalIgnoreCase)
            if ($idx -ge 0) {
                $tbLoc.Select($idx, $qLoc.Length)
                $tbLoc.ScrollToHome()
                # Скроллинг к строке с контекстом: считаем переносы строк до позиции
                $lineCount = 0
                for ($c = 0; $c -lt $idx -and $c -lt $tbLoc.Text.Length; $c++) {
                    if ($tbLoc.Text[$c] -eq "`n") { $lineCount++ }
                }
                # Листаем вниз на 2 строки меньше, чтобы контекст был вверху
                $scrollLines = [Math]::Max(0, $lineCount - 2)
                for ($s = 0; $s -lt $scrollLines -and $s -lt 2000; $s++) { $tbLoc.LineDown() }
                [System.Windows.Input.Keyboard]::Focus($tbLoc)
                $searchBox.Dispatcher.BeginInvoke([Action]{ $searchBox.Focus() }, [Windows.Threading.DispatcherPriority]::Background)
            }
        }
        $script:hlTimer.Stop()
        $script:hlTimer = $null
    })
    $script:hlTimer.Start()
}

$script:highlightTb = $null; $script:highlightQuery = ""; $script:hlTimer = $null; $script:hlRetryCount = 0

# Функция навигации поиска
function Navigate-Search {
    param([int]$Direction)  # 1 = ▼, -1 = ▲
    $st = $script:searchState
    if ($st.results.Count -eq 0) { return }
    $st.index = ($st.index + $Direction + $st.results.Count) % $st.results.Count
    $r = $st.results[$st.index]
    $matchLabel.Text = "$($st.index + 1) - $($st.results.Count)"

    $mainTabControl.SelectedItem = $r.MainTab
    if ($r.InnerTab) { $r.InnerTabControl.SelectedItem = $r.InnerTab }

    Select-SearchResult -Query $st.query
}

# Обработчики поиска
$btnDown.Add_Click({
    $sq = $searchBox.Text.Trim()
    $oldQuery = $script:searchState.query
    $script:searchState.query = $sq
    if (-not $sq) { $matchLabel.Text = "0 - 0"; return }

    # Если новый запрос — ищем заново
    if ($sq -ne $oldQuery -or $script:searchState.results.Count -eq 0) {
        $allResults = @()
        foreach ($si in $script:searchItems) {
            if ($si.Content -match [regex]::Escape($sq)) {
                $allResults += $si
            }
        }
        # Сортируем: сначала результаты текущей вкладки
        $currentMainTab = $mainTabControl.SelectedItem
        $currentResults = @($allResults | Where-Object { $_.MainTab -eq $currentMainTab })
        $otherResults = @($allResults | Where-Object { $_.MainTab -ne $currentMainTab })
        $allResults = $currentResults + $otherResults
        $script:searchState.results = $allResults
        $script:searchState.index = -1
        $matchLabel.Text = "Найдено: $($allResults.Count)"
                        if ($allResults.Count -gt 0) {
                            $script:searchState.index = 0
                            $r = $allResults[0]
                            $mainTabControl.SelectedItem = $r.MainTab
                            if ($r.InnerTab) { $r.InnerTabControl.SelectedItem = $r.InnerTab }
                            Select-SearchResult -Query $sq
                            $btnUp.IsEnabled = $true; $btnDown.IsEnabled = $true
                            $matchLabel.Text = "1 - $($allResults.Count)"
                        } else {
                            $btnUp.IsEnabled = $false; $btnDown.IsEnabled = $false
                        }
                        return
                    }
                    Navigate-Search -Direction 1
                })

$btnUp.Add_Click({
    $sq = $searchBox.Text.Trim()
    $oldQuery = $script:searchState.query
    $script:searchState.query = $sq
    if (-not $sq) { return }
    if ($sq -ne $oldQuery -or $script:searchState.results.Count -eq 0) {
        $allResults = @()
        foreach ($si in $script:searchItems) {
            if ($si.Content -match [regex]::Escape($sq)) {
                $allResults += $si
            }
        }
        # Сортируем: сначала результаты текущей вкладки
        $currentMainTab = $mainTabControl.SelectedItem
        $currentResults = @($allResults | Where-Object { $_.MainTab -eq $currentMainTab })
        $otherResults = @($allResults | Where-Object { $_.MainTab -ne $currentMainTab })
        $allResults = $currentResults + $otherResults
        $script:searchState.results = $allResults
        $matchLabel.Text = "Найдено: $($allResults.Count)"
                        if ($allResults.Count -gt 0) {
                            $script:searchState.index = $allResults.Count - 1
                            $r = $allResults[$script:searchState.index]
                            $mainTabControl.SelectedItem = $r.MainTab
                            if ($r.InnerTab) { $r.InnerTabControl.SelectedItem = $r.InnerTab }
                            Select-SearchResult -Query $sq
                            $btnUp.IsEnabled = $true; $btnDown.IsEnabled = $true
                            $matchLabel.Text = "$($allResults.Count) - $($allResults.Count)"
                        } else {
                            $btnUp.IsEnabled = $false; $btnDown.IsEnabled = $false
                        }
                        return
                    }
                    Navigate-Search -Direction -1
                })

$searchBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq "Enter") { if ($e.KeyboardDevice.Modifiers -eq "Shift") { $btnUp.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) } else { $btnDown.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) } } })

# Основной TabControl
$mainTabControl = New-Object Windows.Controls.TabControl
$mainTabControl.FontSize = 11
[Windows.Controls.Grid]::SetRow($mainTabControl, 1)

foreach ($tDef in $tabDefs) {
    $tab = New-Object Windows.Controls.TabItem
    $tab.Header = "$($tDef.Name) ($($tDef.Files.Count))"
    $tab.FontSize = 12; $tab.FontWeight = "Bold"

    $fileCount = $tDef.Files.Count

    if ($fileCount -eq 1) {
        $f = $tDef.Files[0]
        $editor = New-FileEditor -relPath $f.Path
        if ($editor) { $tab.Content = $editor }
        # Добавляем в поисковый индекс
        $fd = $loadedFiles[$f.Path]
        $script:searchItems += @{ Path=$f.Path; Content=$fd.Content; MainTab=$tab; InnerTab=$null; InnerTabControl=$null; TbRef=$fd.TbRef; FileRef=$fd }
    } else {
        $innerTabControl = New-Object Windows.Controls.TabControl
        $innerTabControl.FontSize = 11
        $innerTabControl.Margin = [Windows.Thickness]::new(0)

        foreach ($f in $tDef.Files) {
            $innerTab = New-Object Windows.Controls.TabItem
            $innerTab.Header = $f.Name
            $innerTab.FontSize = 11; $innerTab.FontWeight = "Normal"

            $editor = New-FileEditor -relPath $f.Path
            if ($editor) { $innerTab.Content = $editor }

            [void]$innerTabControl.Items.Add($innerTab)

            $fd = $loadedFiles[$f.Path]
            $script:searchItems += @{ Path=$f.Path; Content=$fd.Content; MainTab=$tab; InnerTab=$innerTab; InnerTabControl=$innerTabControl; TbRef=$fd.TbRef; FileRef=$fd }
        }

        $tab.Content = $innerTabControl
    }

    [void]$mainTabControl.Items.Add($tab)
}

[void]$mainGrid.Children.Add($mainTabControl)

$mb.Child = $mainGrid
$cw.Child = $mb
[void]$cg.Children.Add($cw)
$outerBorder.Child = $cg
$window.Content = $outerBorder
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
[void]$window.ShowDialog()





























