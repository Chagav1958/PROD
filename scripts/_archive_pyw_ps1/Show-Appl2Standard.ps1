<#
.SYNOPSIS
    Эталон APPL2-стиля (ОКНО_СТАНДАРТ_1).
.DESCRIPTION
    Шаблон для всех APPL2-окон проекта.
    При создании нового APPL2-окна копировать этот файл как основу.
    
    Ключевые элементы стиля:
    - outerBorder: #33FFFFFF, CornerRadius=60, BorderBrush #1A3A60, DropShadowEffect
    - titleBorder: #05FFFFFF, CornerRadius=10, Margin=(25,1,25,0), Padding=(20,2,20,0)
    - Двухслойный 3D-текст заголовка (белый смещён + #1A3A60 поверх)
    - Кнопки title bar (━ ▣ ✕): Add-TitleButton, Button + ControlTemplate
      CornerRadius=6, Border #1A3A60, толщина 3, градиент alpha 13, hover
    - contentWrapper: #1A3A60, CornerRadius=46, Margin=(4,0,4,4)
    - mainBorder: белый, CornerRadius=42, Margin=4
    - ResizeMode: CanResizeWithGrip (или NoResize для фикс. окон)
    - DataGrid: скроллинг Auto, AlternatingRowBackground=LightGray, заголовки на русском
    - Поиск контекста (КОНТЕКСТ): ПС (поисковая строка) + счётчик + кнопки ▼/▲ над DataGrid.
      Поиск по всем полям, регистронезависимый. Enter = ▼. Синее выделение (#3182CE).
      Функции Invoke-SearchDown/Invoke-SearchUp — эталон для всех APPL2-окон.
    - Прогресс-бары: Apply-GlossyProgressStyle (фаза #1A3A60→#2B6CB0,
      шаг #0F2440→#1A5276, CornerRadius=5)
    - Клавиши: Enter = кнопка OK (IsDefault), Esc = кнопка Отмена (RoutedEvent ClickEvent)
#>

param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

# Загрузить тему (Apply-GlossyButtonStyle, Apply-GlossyProgressStyle)
$scriptPath = Split-Path $PSCommandPath -Parent
. (Join-Path $scriptPath "Set-MetroTheme.ps1")

# ── Окно ──
$win = New-Object Windows.Window
$win.Title = "APPL2 Стандарт"
$win.Width = 520; $win.Height = 580
$win.WindowStartupLocation = "CenterScreen"
$win.Topmost = $true
$win.AllowsTransparency = $true
$win.WindowStyle = [Windows.WindowStyle]::None
$win.Background = [Windows.Media.Brushes]::Transparent
$win.ResizeMode = "CanResizeWithGrip"

# ── outerBorder (внешний слой) ──
$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60
$outerBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$outerBorder.BorderThickness = 1
$outerBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")

# Тень
$borderShadow = New-Object Windows.Media.Effects.DropShadowEffect
$borderShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
$borderShadow.Direction = 270; $borderShadow.ShadowDepth = 4; $borderShadow.BlurRadius = 10; $borderShadow.Opacity = 0.5
$outerBorder.Effect = $borderShadow

# ── contentGrid (title bar + content) ──
$contentGrid = New-Object Windows.Controls.Grid
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

# ── titleBorder ──
$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[System.Windows.Controls.Grid]::SetRow($titleBorder, 0)

# Перетаскивание окна за title bar
$titleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $win.WindowState -ne "Maximized") {
        try { $win.DragMove() } catch {}
    }
    elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
})

# ── titleGrid (текст + 3 кнопки) ──
$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

# Двухслойный 3D-текст заголовка
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = "APPL2 Стандарт"; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = "APPL2 Стандарт"; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

# ── Функция Add-TitleButton (эталон для всех APPL2 окон) ──
function Add-TitleButton {
    param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$Width = 40, [int]$Height = 34, [int]$FontSize = 16)
    $b = New-Object Windows.Controls.Button
    # Двухслойный символ
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
    # Градиент alpha 13
    $transGrad = New-Object Windows.Media.LinearGradientBrush
    $transGrad.StartPoint = "0,0"; $transGrad.EndPoint = "0,1"
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
    $b.Background = $transGrad
    # ControlTemplate для скруглённых углов
    try {
        $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
        $b.Template = [Windows.Markup.XamlReader]::Load($reader)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($b, $Col)
    $b.Add_Click($Click)
    # Hover эффекты
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

# ── Функции поиска контекста (эталон для всех APPL2-окон) ──
function Invoke-SearchDown {
    param($ctx)
    $query = $ctx.sb.Text.Trim()
    if ([string]::IsNullOrEmpty($query)) { return }
    if ($ctx.st.query -ne $query) { $ctx.st.query = $query; $ctx.st.results = @(); $ctx.st.idx = -1 }
    if ($ctx.st.results.Count -eq 0) {
        $allItems = @($ctx.dg.Items)
        for ($i = 0; $i -lt $allItems.Count; $i++) {
            $line = "$($allItems[$i])"
            if ($line.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $ctx.st.results += $i }
        }
        $ctx.st.idx = -1
    }
    if ($ctx.st.results.Count -eq 0) {
        $ctx.ml.Text = "0 - 0"
        $ctx.bu.IsEnabled = $false; $ctx.bd.IsEnabled = $false
        return
    }
    $ctx.bu.IsEnabled = $true; $ctx.bd.IsEnabled = $true
    $ctx.st.idx = ($ctx.st.idx + 1) % $ctx.st.results.Count
    $rowIdx = $ctx.st.results[$ctx.st.idx]
    $ctx.dg.SelectedIndex = $rowIdx; $ctx.dg.ScrollIntoView($ctx.dg.Items[$rowIdx])
    $ctx.ml.Text = "$($ctx.st.idx + 1) - $($ctx.st.results.Count)"
    $ctx.dg.Focus()
}

function Invoke-SearchUp {
    param($ctx)
    $query = $ctx.sb.Text.Trim()
    if ([string]::IsNullOrEmpty($query)) { return }
    if ($ctx.st.query -ne $query) { $ctx.st.query = $query; $ctx.st.results = @(); $ctx.st.idx = -1 }
    if ($ctx.st.results.Count -eq 0) {
        $allItems = @($ctx.dg.Items)
        for ($i = 0; $i -lt $allItems.Count; $i++) {
            $line = "$($allItems[$i])"
            if ($line.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $ctx.st.results += $i }
        }
        $ctx.st.idx = $ctx.st.results.Count
    }
    if ($ctx.st.results.Count -eq 0) {
        $ctx.ml.Text = "0 - 0"
        $ctx.bu.IsEnabled = $false; $ctx.bd.IsEnabled = $false
        return
    }
    $ctx.bu.IsEnabled = $true; $ctx.bd.IsEnabled = $true
    $ctx.st.idx = ($ctx.st.idx - 1 + $ctx.st.results.Count) % $ctx.st.results.Count
    $rowIdx = $ctx.st.results[$ctx.st.idx]
    $ctx.dg.SelectedIndex = $rowIdx; $ctx.dg.ScrollIntoView($ctx.dg.Items[$rowIdx])
    $ctx.ml.Text = "$($ctx.st.idx + 1) - $($ctx.st.results.Count)"
    $ctx.dg.Focus()
}

# ── Кнопки title bar ──
$minBtn = Add-TitleButton -Text "━" -Col 1 -Click { $win.WindowState = [Windows.WindowState]::Minimized }
$maxBtn = Add-TitleButton -Text "▣" -Col 2 -Click {
    if ($win.WindowState -eq "Maximized") { $win.WindowState = "Normal"; $maxBtn.Content = "▣" }
    else { $win.WindowState = "Maximized"; $maxBtn.Content = "❐" }
} -FontSize 18
$closeBtn = Add-TitleButton -Text "✕" -Col 3 -Click { $win.Close() } -IsClose
[void]$titleGrid.Children.Add($minBtn)
[void]$titleGrid.Children.Add($maxBtn)
[void]$titleGrid.Children.Add($closeBtn)

$titleBorder.Child = $titleGrid
[void]$contentGrid.Children.Add($titleBorder)

# ── contentWrapper (тёмно-синяя подложка) ──
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)

# ── mainBorder (белый контейнер контента) ──
$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "20,16,20,22"
$mainBorder.Margin = New-Object Windows.Thickness(4)

# Содержимое окна — эталонные элементы APPL2
$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# Row 0: поля + DataGrid с поиском + progress-бары (ПБ внизу, над кнопками)
$contentGrid2 = New-Object Windows.Controls.Grid
$contentGrid2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$contentGrid2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$contentGrid2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# ── Row 0: поля ──
$fieldsStack = New-Object Windows.Controls.StackPanel
$fieldsStack.Orientation = "Vertical"
$fieldsStack.Margin = New-Object Windows.Thickness(0,0,0,10)

function Add-TestField {
    param([string]$Label, [bool]$IsPassword = $false)
    $fieldStack = New-Object Windows.Controls.StackPanel
    $fieldStack.Orientation = "Vertical"
    $fieldStack.Margin = New-Object Windows.Thickness(0,0,0,4)
    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label; $lbl.FontSize = 11; $lbl.Foreground = "#4A5568"
    $lbl.FontWeight = "SemiBold"; $lbl.Margin = New-Object Windows.Thickness(0,0,0,1)
    [void]$fieldStack.Children.Add($lbl)
    if ($IsPassword) {
        $input = New-Object Windows.Controls.PasswordBox; $input.PasswordChar = "*"
    } else { $input = New-Object Windows.Controls.TextBox }
    $input.Height = 28; $input.FontSize = 11; $input.Padding = New-Object Windows.Thickness(8,2,8,2)
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = 10; $b.BorderBrush = "#CBD5E0"; $b.BorderThickness = 1
    $b.Background = [Windows.Media.Brushes]::White; $b.Child = $input
    [void]$fieldStack.Children.Add($b)
    return $fieldStack
}

$fieldsPanel = New-Object Windows.Controls.StackPanel; $fieldsPanel.Orientation = "Horizontal"
$fieldsPanel.Margin = New-Object Windows.Thickness(0,0,0,0)
$f1 = Add-TestField -Label "TextBox"; $f1.Margin = New-Object Windows.Thickness(0,0,8,0)
$f2 = Add-TestField -Label "PasswordBox" -IsPassword $true; $f2.Margin = New-Object Windows.Thickness(0,0,8,0)
$f3 = New-Object Windows.Controls.StackPanel; $f3.Orientation = "Vertical"
$lblCombo = New-Object Windows.Controls.TextBlock
$lblCombo.Text = "ComboBox"; $lblCombo.FontSize = 11; $lblCombo.Foreground = "#4A5568"
$lblCombo.FontWeight = "SemiBold"; $lblCombo.Margin = New-Object Windows.Thickness(0,0,0,1)
[void]$f3.Children.Add($lblCombo)
$cmb = New-Object Windows.Controls.ComboBox; $cmb.Height = 28; $cmb.FontSize = 11
[void]$cmb.Items.Add("Пункт 1"); [void]$cmb.Items.Add("Пункт 2"); [void]$cmb.Items.Add("Пункт 3")
$cmb.SelectedIndex = 0
$cmbBorder = New-Object Windows.Controls.Border
$cmbBorder.CornerRadius = 10; $cmbBorder.BorderBrush = "#CBD5E0"; $cmbBorder.BorderThickness = 1
$cmbBorder.Background = [Windows.Media.Brushes]::White; $cmbBorder.Child = $cmb
[void]$f3.Children.Add($cmbBorder)
[void]$fieldsPanel.Children.Add($f1); [void]$fieldsPanel.Children.Add($f2); [void]$fieldsPanel.Children.Add($f3)
[void]$fieldsStack.Children.Add($fieldsPanel)
[System.Windows.Controls.Grid]::SetRow($fieldsStack, 0)
[void]$contentGrid2.Children.Add($fieldsStack)

# ── Row 1: DataGrid с поиском контекста (эталон КОНТЕКСТ) ──
$dgWrapper = New-Object Windows.Controls.Grid
$dgWrapper.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$dgWrapper.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$dgWrapper.Margin = New-Object Windows.Thickness(0,0,0,8)

# Панель поиска (ПС + счётчик + ▼/▲)
$searchPanel = New-Object Windows.Controls.Grid
$searchPanel.Margin = New-Object Windows.Thickness(0,0,0,4)
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$matchLabel = New-Object Windows.Controls.TextBlock
$matchLabel.Text = "0 - 0"; $matchLabel.FontSize = 11; $matchLabel.Foreground = "#4A5568"
$matchLabel.VerticalAlignment = "Center"; $matchLabel.Margin = New-Object Windows.Thickness(0,0,6,0)
[System.Windows.Controls.Grid]::SetColumn($matchLabel, 0); [void]$searchPanel.Children.Add($matchLabel)

$searchBox = New-Object Windows.Controls.TextBox
$searchBox.FontSize = 11; $searchBox.Height = 24
$searchBox.Margin = New-Object Windows.Thickness(0,0,6,0)
$searchBox.ToolTip = "Введите текст для поиска по таблице"
[System.Windows.Controls.Grid]::SetColumn($searchBox, 1); [void]$searchPanel.Children.Add($searchBox)

$btnDown = New-Object Windows.Controls.Button
$btnDown.Content = "▼"; $btnDown.Width = 26; $btnDown.Height = 24; $btnDown.FontSize = 10
$btnDown.Margin = New-Object Windows.Thickness(0,0,2,0); $btnDown.Padding = New-Object Windows.Thickness(0)
$btnDown.ToolTip = "Найти далее (Enter)"
$btnDown.FontWeight = "Bold"
$btnDownBorder = New-Object Windows.Controls.Border
$btnDownBorder.CornerRadius = 4; $btnDownBorder.BorderBrush = "#CBD5E0"; $btnDownBorder.BorderThickness = 1
$btnDownBorder.Background = "#F5F7FA"; $btnDownBorder.Child = $btnDown
[System.Windows.Controls.Grid]::SetColumn($btnDownBorder, 2); [void]$searchPanel.Children.Add($btnDownBorder)

$btnUp = New-Object Windows.Controls.Button
$btnUp.Content = "▲"; $btnUp.Width = 26; $btnUp.Height = 24; $btnUp.FontSize = 10
$btnUp.Margin = New-Object Windows.Thickness(0); $btnUp.Padding = New-Object Windows.Thickness(0)
$btnUp.ToolTip = "Найти ранее (Shift+Enter)"
$btnUp.FontWeight = "Bold"
$btnUpBorder = New-Object Windows.Controls.Border
$btnUpBorder.CornerRadius = 4; $btnUpBorder.BorderBrush = "#CBD5E0"; $btnUpBorder.BorderThickness = 1
$btnUpBorder.Background = "#F5F7FA"; $btnUpBorder.Child = $btnUp
[System.Windows.Controls.Grid]::SetColumn($btnUpBorder, 3); [void]$searchPanel.Children.Add($btnUpBorder)

[System.Windows.Controls.Grid]::SetRow($searchPanel, 0); [void]$dgWrapper.Children.Add($searchPanel)

# DataGrid с эталонными данными
$dg = New-Object Windows.Controls.DataGrid
$dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true
$dg.HeadersVisibility = "All"; $dg.RowHeaderWidth = 0
$dg.AlternatingRowBackground = [Windows.Media.BrushConverter]::new().ConvertFromString("#F5F7FA")
$dg.FontSize = 11; $dg.VerticalScrollBarVisibility = "Auto"
$dg.HorizontalScrollBarVisibility = "Auto"; $dg.Background = [Windows.Media.Brushes]::Transparent
$dg.RowBackground = [Windows.Media.Brushes]::White
$dg.BorderThickness = New-Object Windows.Thickness(1)
$dg.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
$dg.CanUserResizeRows = $false; $dg.CanUserSortColumns = $true; $dg.GridLinesVisibility = "None"
$dg.SelectionMode = "Single"; $dg.SelectionUnit = "FullRow"

$col1 = New-Object Windows.Controls.DataGridTextColumn
$col1.Header = "Объект"; $col1.Binding = [Windows.Data.Binding]::new("Name")
$col1.Width = 140
$col2 = New-Object Windows.Controls.DataGridTextColumn
$col2.Header = "Тип"; $col2.Binding = [Windows.Data.Binding]::new("Type")
$col2.Width = 100
$col3 = New-Object Windows.Controls.DataGridTextColumn
$col3.Header = "Статус"; $col3.Binding = [Windows.Data.Binding]::new("Status")
$col3.Width = 80
$col4 = New-Object Windows.Controls.DataGridTextColumn
$col4.Header = "Описание"; $col4.Binding = [Windows.Data.Binding]::new("Desc")
$col4.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
[void]$dg.Columns.Add($col1); [void]$dg.Columns.Add($col2)
[void]$dg.Columns.Add($col3); [void]$dg.Columns.Add($col4)

$sampleData = @(
    [PSCustomObject]@{ Name = "w_ais_request_select"; Type = "Window"; Status = "READY"; Desc = "Окно выбора заявок — ожидает выгрузки" }
    [PSCustomObject]@{ Name = "w_ais_request_card"; Type = "Window"; Status = "NOT_READY"; Desc = "Карточка заявки — требуется доработка" }
    [PSCustomObject]@{ Name = "u_em_ais_rs"; Type = "UserObject"; Status = "READY"; Desc = "Пользовательский объект для работы с заявками" }
    [PSCustomObject]@{ Name = "d_ais_request_list"; Type = "DataWindow"; Status = "NOT_READY"; Desc = "Список заявок — ожидает выверки" }
    [PSCustomObject]@{ Name = "f_get_client_requests"; Type = "Function"; Status = "READY"; Desc = "Функция получения заявок клиента" }
    [PSCustomObject]@{ Name = "p_create_request"; Type = "Procedure"; Status = "DIFF"; Desc = "Процедура создания заявки — есть отличия" }
    [PSCustomObject]@{ Name = "tr_request_after_insert"; Type = "Trigger"; Status = "READY"; Desc = "Триггер после вставки заявки" }
    [PSCustomObject]@{ Name = "w_ais_request_edit"; Type = "Window"; Status = "NEW_OBJECT"; Desc = "Новое окно редактирования заявки" }
)
$dg.ItemsSource = $sampleData

[System.Windows.Controls.Grid]::SetRow($dg, 1); [void]$dgWrapper.Children.Add($dg)
[System.Windows.Controls.Grid]::SetRow($dgWrapper, 1); [void]$contentGrid2.Children.Add($dgWrapper)

# Поиск контекста (КОНТЕКСТ): объекты, отображение, расположение, функционирование
$ctx = @{}
$ctx.dg = $dg; $ctx.ml = $matchLabel; $ctx.st = @{ query = ""; results = @(); idx = -1 }
$ctx.sb = $searchBox; $ctx.bu = $btnUp; $ctx.bd = $btnDown
$ctx.bu.IsEnabled = $false; $ctx.bd.IsEnabled = $false

$btnDown.Add_Click({ Invoke-SearchDown $ctx }.GetNewClosure())

$btnUp.Add_Click({ Invoke-SearchUp $ctx }.GetNewClosure())

$searchBox.Add_KeyDown({
    if ($_.Key -eq "Return") {
        Invoke-SearchDown $ctx
        $_.Handled = $true
    }
}.GetNewClosure())

# ── Row 2: Прогресс-бары (ПБ) — внизу, над кнопками ----
$pbWrap = New-Object Windows.Controls.StackPanel
$pbWrap.Orientation = "Vertical"
$pbWrap.Margin = New-Object Windows.Thickness(0,0,0,6)

[Windows.Controls.Grid] $pbPhaseGrid = New-Object Windows.Controls.Grid
$pbPhaseGrid.Margin = New-Object Windows.Thickness(0,0,0,4)
$col1 = New-Object Windows.Controls.ColumnDefinition; $col1.Width = 120
$col2 = New-Object Windows.Controls.ColumnDefinition; $col2.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
[void]$pbPhaseGrid.ColumnDefinitions.Add($col1); [void]$pbPhaseGrid.ColumnDefinitions.Add($col2)
$pbPhaseLabel = New-Object Windows.Controls.TextBlock
$pbPhaseLabel.Text = "Фаза: загрузка данных"; $pbPhaseLabel.FontSize = 11; $pbPhaseLabel.Foreground = "#4A5568"
$pbPhaseLabel.VerticalAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($pbPhaseLabel, 0); [void]$pbPhaseGrid.Children.Add($pbPhaseLabel)
$pbPhase = New-Object Windows.Controls.ProgressBar
$pbPhase.Minimum = 0; $pbPhase.Maximum = 100; $pbPhase.Value = 45
Apply-GlossyProgressStyle -ProgressBar $pbPhase -BarColorTop "#1A3A60" -BarColorBottom "#2B6CB0"
$pbPhase.VerticalAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($pbPhase, 1); [void]$pbPhaseGrid.Children.Add($pbPhase)
[void]$pbWrap.Children.Add($pbPhaseGrid)

[Windows.Controls.Grid] $pbStepGrid = New-Object Windows.Controls.Grid
$col1 = New-Object Windows.Controls.ColumnDefinition; $col1.Width = 120
$col2 = New-Object Windows.Controls.ColumnDefinition; $col2.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
[void]$pbStepGrid.ColumnDefinitions.Add($col1); [void]$pbStepGrid.ColumnDefinitions.Add($col2)
$pbStepLabel = New-Object Windows.Controls.TextBlock
$pbStepLabel.Text = "Шаг: (3 - 10)"; $pbStepLabel.FontSize = 11; $pbStepLabel.Foreground = "#4A5568"
$pbStepLabel.VerticalAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($pbStepLabel, 0); [void]$pbStepGrid.Children.Add($pbStepLabel)
$pbStep = New-Object Windows.Controls.ProgressBar
$pbStep.Minimum = 0; $pbStep.Maximum = 100; $pbStep.Value = 30
Apply-GlossyProgressStyle -ProgressBar $pbStep -BarColorTop "#0F2440" -BarColorBottom "#1A5276"
$pbStep.VerticalAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($pbStep, 1); [void]$pbStepGrid.Children.Add($pbStep)
[void]$pbWrap.Children.Add($pbStepGrid)

[System.Windows.Controls.Grid]::SetRow($pbWrap, 2)
[void]$contentGrid2.Children.Add($pbWrap)

# ---- 3. Кнопки (Apply-GlossyButtonStyle) ----
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Right"
$btnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)

$btnOk = New-Object Windows.Controls.Button
$btnOk.Content = "OK"
$btnOk.Width = 100; $btnOk.Height = 36
$btnOk.Margin = New-Object Windows.Thickness(0,0,8,0)
$btnOk.IsDefault = $true
Apply-GlossyButtonStyle -Button $btnOk
$btnOk.Add_Click({
    $btnOk.IsEnabled = $false
    $pbPhase.Value = 0; $pbStep.Value = 0
    $pbPhaseLabel.Text = "Фаза 1: инициализация"
    $pbStepLabel.Text = "(0 - 5)"
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $tick = 0; $totalTicks = 30
    $phases = @("Фаза 1: инициализация", "Фаза 2: обработка", "Фаза 3: финализация")
    $timer.Add_Tick({
        $tick++
        $pct = [Math]::Min(100, [int]($tick / $totalTicks * 100))
        $phaseIdx = [Math]::Min(2, [int]($tick / 10))
        $pbPhaseLabel.Text = $phases[$phaseIdx]
        $pbPhase.Value = $pct
        $pbStepLabel.Text = "($tick из $totalTicks)"
        $pbStep.Value = [Math]::Min(100, ($tick % 10) * 10)
        if ($tick -ge $totalTicks) {
            $timer.Stop()
            $pbPhaseLabel.Text = "Готово"
            $pbPhase.Value = 100; $pbStep.Value = 100
            $pbStepLabel.Text = "Завершено"
            $btnOk.IsEnabled = $true
        }
    })
    $timer.Start()
})
[void]$btnPanel.Children.Add($btnOk)

$btnCancel = New-Object Windows.Controls.Button
$btnCancel.Content = "Отмена"
$btnCancel.Width = 100; $btnCancel.Height = 36
$btnCancel.Margin = New-Object Windows.Thickness(8,0,0,0)
Apply-GlossyButtonStyle -Button $btnCancel -ColorTop "#606060" -ColorBottom "#808080"
$btnCancel.Add_Click({ $win.Close() })
[void]$btnPanel.Children.Add($btnCancel)

[System.Windows.Controls.Grid]::SetRow($contentGrid2, 0)
[System.Windows.Controls.Grid]::SetRow($btnPanel, 1)
[void]$mainGrid.Children.Add($contentGrid2)
[void]$mainGrid.Children.Add($btnPanel)

$mainBorder.Child = $mainGrid
$contentWrapper.Child = $mainBorder
[void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid
$win.Content = $outerBorder

# Клавиши: Enter = OK (IsDefault), Esc = Отмена
$win.Add_KeyDown({
    if ($_.Key -eq "Escape") { $btnCancel.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
})

[void]$win.ShowDialog()
