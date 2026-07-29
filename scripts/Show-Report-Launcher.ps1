param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

. (Join-Path (Split-Path $PSCommandPath -Parent) "Set-MetroTheme.ps1")
$scriptPath = Split-Path $PSCommandPath -Parent
$projectRoot = Split-Path (Split-Path $PSCommandPath -Parent) -Parent

$releaseRoot = "C:\AIS\1 Release"
$taskHistory = @()
if (Test-Path -LiteralPath $releaseRoot) {
    $taskHistory = Get-ChildItem -LiteralPath $releaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^SYBASE-|^SUPRT-' } |
        Sort-Object CreationTime -Descending | Select-Object -ExpandProperty Name
}

$win = New-Object Windows.Window
$win.Title = "ОТЧЁТ — ввод задачи"
$win.Width = 520; $win.Height = 260
$win.WindowStartupLocation = "CenterScreen"
$win.Topmost = $true
$win.AllowsTransparency = $true
$win.WindowStyle = [Windows.WindowStyle]::None
$win.Background = [Windows.Media.Brushes]::Transparent
$win.ResizeMode = "NoResize"

$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60
$outerBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")
$outerBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$outerBorder.BorderThickness = 1
$shadow = New-Object Windows.Media.Effects.DropShadowEffect
$shadow.Color = "#404040"; $shadow.Direction = 270; $shadow.ShadowDepth = 4; $shadow.BlurRadius = 10; $shadow.Opacity = 0.5
$outerBorder.Effect = $shadow

$grid = New-Object Windows.Controls.Grid
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

# titleBorder
$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[Windows.Controls.Grid]::SetRow($titleBorder, 0)
$titleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $win.WindowState -ne "Maximized") {
        try { $win.DragMove() } catch {}
    } elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
})

$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$titleText = "ОТЧЁТ"
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleA = New-Object Windows.Controls.TextBlock
$titleA.Text = $titleText; $titleA.FontSize = 16; $titleA.FontWeight = "Bold"
$titleA.Foreground = [Windows.Media.Brushes]::White
$titleA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleA)
$titleB = New-Object Windows.Controls.TextBlock
$titleB.Text = $titleText; $titleB.FontSize = 16; $titleB.FontWeight = "Bold"
$titleB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleB)
[Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

function Add-Btn {
    param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$W=40, [int]$H=34, [int]$FS=16)
    $b = New-Object Windows.Controls.Button
    $cg = New-Object Windows.Controls.Grid
    $ca = New-Object Windows.Controls.TextBlock
    $ca.Text = $Text; $ca.FontSize = $FS; $ca.FontWeight = "Bold"
    $ca.Foreground = [Windows.Media.Brushes]::White
    $ca.Margin = New-Object Windows.Thickness(1,1,0,0)
    $ca.HorizontalAlignment = "Center"; $ca.VerticalAlignment = "Center"
    [void]$cg.Children.Add($ca)
    $cb = New-Object Windows.Controls.TextBlock
    $cb.Text = $Text; $cb.FontSize = $FS; $cb.FontWeight = "Bold"
    $cb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $cb.HorizontalAlignment = "Center"; $cb.VerticalAlignment = "Center"
    [void]$cg.Children.Add($cb)
    $b.Content = $cg; $b.Width = $W; $b.Height = $H
    $b.FontWeight = "Bold"; $b.FontSize = $FS
    $b.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $b.Cursor = "Hand"
    $b.HorizontalContentAlignment = "Center"
    $b.VerticalContentAlignment = "Center"
    $b.Padding = New-Object Windows.Thickness(0)
    $b.BorderThickness = New-Object Windows.Thickness(3)
    $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $grad = New-Object Windows.Media.LinearGradientBrush
    $grad.StartPoint = "0,0"; $grad.EndPoint = "0,1"
    [void]$grad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
    [void]$grad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
    [void]$grad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
    $b.Background = $grad
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
    [Windows.Controls.Grid]::SetColumn($b, $Col)
    $b.Add_Click($Click)
    $b.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"})) })
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

$closeBtn = Add-Btn -Text "✕" -Col 3 -Click { $win.Close() } -IsClose
[void]$titleGrid.Children.Add($closeBtn)
$titleBorder.Child = $titleGrid
[void]$grid.Children.Add($titleBorder)

# contentWrapper
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[Windows.Controls.Grid]::SetRow($contentWrapper, 1)

$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "20,20,20,22"
$mainBorder.Margin = New-Object Windows.Thickness(4)

$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# Заголовок
$header = New-Object Windows.Controls.TextBlock
$header.Text = "Введите имя задачи Jira"
$header.FontSize = 14; $header.FontWeight = "SemiBold"
$header.Foreground = "#4A5568"; $header.Margin = "0,0,0,4"
[Windows.Controls.Grid]::SetRow($header, 0)
[void]$mainGrid.Children.Add($header)

# ComboBox
$combo = New-Object Windows.Controls.ComboBox
$combo.IsEditable = $true
$combo.FontSize = 14
$combo.Height = 32
$combo.Margin = "0,0,0,12"
$combo.ItemsSource = $taskHistory
if ($taskHistory.Count -gt 0) { $combo.Text = $taskHistory[0] }
[Windows.Controls.Grid]::SetRow($combo, 1)
[void]$mainGrid.Children.Add($combo)

# Кнопки
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Right"
$btnPanel.Margin = "0,0,0,0"

$btnOpen = New-Object Windows.Controls.Button
$btnOpen.Content = "Открыть отчёт"
$btnOpen.Width = 150; $btnOpen.Height = 36
$btnOpen.Margin = "0,0,10,0"
Apply-GlossyButtonStyle -Button $btnOpen

$btnCancel = New-Object Windows.Controls.Button
$btnCancel.Content = "Отмена"
$btnCancel.Width = 100; $btnCancel.Height = 36
Apply-GlossyButtonStyle -Button $btnCancel -ColorTop "#606060" -ColorBottom "#808080"

$btnOpen.Add_Click({
    $taskName = $combo.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($taskName)) {
        [System.Windows.MessageBox]::Show("Введите имя задачи", "ОТЧЁТ", "OK", "Warning")
        return
    }
    $win.Close()
    $reportScript = Join-Path $scriptPath "Show-Report.ps1"
    Start-Process powershell -ArgumentList "-NoLogo -File `"$reportScript`" -TaskName `"$taskName`""
})

$btnCancel.Add_Click({ $win.Close() })
$win.Add_KeyDown({ param($s,$e) if ($e.Key -eq "Escape") { $win.Close() } })

[void]$btnPanel.Children.Add($btnOpen)
[void]$btnPanel.Children.Add($btnCancel)
[Windows.Controls.Grid]::SetRow($btnPanel, 2)
[void]$mainGrid.Children.Add($btnPanel)

$mainBorder.Child = $mainGrid
$contentWrapper.Child = $mainBorder
[void]$grid.Children.Add($contentWrapper)
$outerBorder.Child = $grid
$win.Content = $outerBorder

[void]$win.ShowDialog()
