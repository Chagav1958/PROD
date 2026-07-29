param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

# Загрузить тему
$scriptPath = Split-Path $PSCommandPath -Parent
$projRoot = Split-Path $scriptPath -Parent
. (Join-Path $scriptPath "Set-MetroTheme.ps1")

$win = New-Object Windows.Window
$win.Title = "MSG Тест дизайна"
$win.Width = 520; $win.Height = 580
$win.WindowStartupLocation = "CenterScreen"
$win.Topmost = $true
$win.AllowsTransparency = $true
$win.WindowStyle = [Windows.WindowStyle]::None
$win.Background = [Windows.Media.Brushes]::Transparent
$win.ResizeMode = "NoResize"
$win.WindowStartupLocation = "CenterScreen"

# Border с сильно скруглёнными углами
$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60
$outerBorder.BorderBrush = "#1A3A60"
$outerBorder.BorderThickness = 1
$outerBorder.Margin = 0

$outerBorder.Background = "#33FFFFFF"  # Белый, прозрачность 80%

# Тень на бордюре
$borderShadow = New-Object Windows.Media.Effects.DropShadowEffect
$borderShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
$borderShadow.Direction = 270; $borderShadow.ShadowDepth = 4; $borderShadow.BlurRadius = 10; $borderShadow.Opacity = 0.5
$outerBorder.Effect = $borderShadow

# Контейнер-сетка: title bar сверху, контент снизу
$contentGrid = New-Object Windows.Controls.Grid
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

# Title bar (прозрачный, чёрный жирный текст, перетаскивание)
$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = "#05FFFFFF"  # Прозрачность 98%
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[System.Windows.Controls.Grid]::SetRow($titleBorder, 0)

$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

# Двухслойный текст: А (белый смещён вниз-вправо) + Б (тёмно-синий поверх)
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = "MSG Тест дизайна"; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = "MSG Тест дизайна"; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

function Add-TitleButton {
    param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$Width = 40, [int]$Height = 34, [int]$FontSize = 16)
    $b = New-Object Windows.Controls.Button
    # Двухслойный символ: А (белый смещён) + Б (тёмно-синий поверх)
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
    # 95% прозрачности (alpha ~13)
    $transGrad = New-Object Windows.Media.LinearGradientBrush
    $transGrad.StartPoint = "0,0"; $transGrad.EndPoint = "0,1"
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
    [void]$transGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
    $b.Background = $transGrad
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
    $hoverBrush = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"}))
    $b.Add_MouseEnter({
        $hoverB = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"}))
        $this.Background = $hoverB
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
$titleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $win.WindowState -ne "Maximized") {
        try { $win.DragMove() } catch {}
    }
    elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
})

# Цветная подложка 4px вокруг контента (имитация бордюра)
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = "#1A3A60"
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)

# Главный контейнер с контентом
$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "20,16,20,16"
$mainBorder.Margin = New-Object Windows.Thickness(4)

$stack = New-Object Windows.Controls.StackPanel
$stack.Orientation = "Vertical"

# ---- 1. Белое овальное поле с текстом ----
$infoBorder = New-Object Windows.Controls.Border
$infoBorder.CornerRadius = 12
$infoBorder.Background = "#F5F7FA"
$infoBorder.BorderBrush = "#E2E8F0"
$infoBorder.BorderThickness = 1
$infoBorder.Padding = "14,10,14,10"
$infoBorder.Margin = New-Object Windows.Thickness(0,0,0,14)

$infoText = New-Object Windows.Controls.TextBlock
$infoText.Text = "Это тестовое окно для проверки оформления MSG-диалогов в стиле APPL. Овальные поля, градиентные кнопки, серая градация фона."
$infoText.FontSize = 12
$infoText.Foreground = "#4A5568"
$infoText.TextWrapping = "Wrap"
$infoBorder.Child = $infoText
[void]$stack.Children.Add($infoBorder)

# ---- 2. Группа полей ----
$fieldsGroup = New-Object Windows.Controls.StackPanel
$fieldsGroup.Orientation = "Vertical"
$fieldsGroup.Margin = New-Object Windows.Thickness(0,0,0,14)

function Add-TestField {
    param([string]$Label, [bool]$IsPassword = $false)
    $fieldStack = New-Object Windows.Controls.StackPanel
    $fieldStack.Orientation = "Vertical"
    $fieldStack.Margin = New-Object Windows.Thickness(0,0,0,8)

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label
    $lbl.FontSize = 12
    $lbl.Foreground = "#4A5568"
    $lbl.FontWeight = "SemiBold"
    $lbl.Margin = New-Object Windows.Thickness(0,0,0,2)
    [void]$fieldStack.Children.Add($lbl)

    if ($IsPassword) {
        $input = New-Object Windows.Controls.PasswordBox
        $input.PasswordChar = "*"
        $input.Height = 32
        $input.FontSize = 12
        $input.Padding = New-Object Windows.Thickness(8,2,8,2)
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = 12
        $b.BorderBrush = "#CBD5E0"
        $b.BorderThickness = 1
        $b.Background = [Windows.Media.Brushes]::White
        $b.Child = $input
        [void]$fieldStack.Children.Add($b)
    } else {
        $input = New-Object Windows.Controls.TextBox
        $input.Height = 32
        $input.FontSize = 12
        $input.Padding = New-Object Windows.Thickness(8,2,8,2)
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = 12
        $b.BorderBrush = "#CBD5E0"
        $b.BorderThickness = 1
        $b.Background = [Windows.Media.Brushes]::White
        $b.Child = $input
        [void]$fieldStack.Children.Add($b)
    }
    [void]$fieldsGroup.Children.Add($fieldStack)
}

Add-TestField -Label "Текстовое поле (TextBox)"
Add-TestField -Label "Поле пароля (PasswordBox)" -IsPassword $true

# ComboBox
$comboStack = New-Object Windows.Controls.StackPanel
$comboStack.Orientation = "Vertical"
$comboStack.Margin = New-Object Windows.Thickness(0,0,0,4)
$lblCombo = New-Object Windows.Controls.TextBlock
$lblCombo.Text = "Выпадающий список (ComboBox)"
$lblCombo.FontSize = 12
$lblCombo.Foreground = "#4A5568"
$lblCombo.FontWeight = "SemiBold"
$lblCombo.Margin = New-Object Windows.Thickness(0,0,0,2)
[void]$comboStack.Children.Add($lblCombo)

$cmb = New-Object Windows.Controls.ComboBox
$cmb.Height = 32
$cmb.FontSize = 12
$cmb.IsEditable = $true
[void]$cmb.Items.Add("Пункт 1 — обычный")
[void]$cmb.Items.Add("Пункт 2 — важный")
[void]$cmb.Items.Add("Пункт 3 — срочный")
$cmb.SelectedIndex = 0
$cmbBorder = New-Object Windows.Controls.Border
$cmbBorder.CornerRadius = 12
$cmbBorder.BorderBrush = "#CBD5E0"
$cmbBorder.BorderThickness = 1
$cmbBorder.Background = [Windows.Media.Brushes]::White
$cmbBorder.Child = $cmb
[void]$comboStack.Children.Add($cmbBorder)
[void]$fieldsGroup.Children.Add($comboStack)

[void]$stack.Children.Add($fieldsGroup)

# ---- 2.5. Прогресс-бары (ПБ) ----
$pbWrap = New-Object Windows.Controls.StackPanel
$pbWrap.Orientation = "Vertical"
$pbWrap.Margin = New-Object Windows.Thickness(0,0,0,14)

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

[void]$stack.Children.Add($pbWrap)

# ---- 3. Кнопки ----
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Center"
$btnPanel.Margin = New-Object Windows.Thickness(0,4,0,0)

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

[void]$stack.Children.Add($btnPanel)

$mainBorder.Child = $stack
$contentWrapper.Child = $mainBorder
[void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid
$win.Content = $outerBorder

# Закрытие по ESC
$win.Add_KeyDown({
    if ($_.Key -eq "Escape") { $win.Close() }
})

[void]$win.ShowDialog()



















