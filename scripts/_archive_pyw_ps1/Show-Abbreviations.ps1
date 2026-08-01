param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

$jsonPath = Join-Path (Split-Path $PSCommandPath -Parent) "..\config\abbreviations_data.json"
$tabs = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

$win = New-Object Windows.Window
$win.Title = "Сокращения AIS Release"
$win.Width = 900; $win.Height = 600
$win.WindowStartupLocation = "CenterScreen"
$win.Topmost = $true
$win.AllowsTransparency = $true
$win.WindowStyle = [Windows.WindowStyle]::None
$win.Background = [Windows.Media.Brushes]::Transparent
$win.ResizeMode = "CanResizeWithGrip"

$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60
$outerBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")
$outerBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$outerBorder.BorderThickness = 1
$effect = New-Object Windows.Media.Effects.DropShadowEffect
$effect.Color = "#404040"; $effect.Direction = 270; $effect.ShadowDepth = 4; $effect.BlurRadius = 10; $effect.Opacity = 0.5
$outerBorder.Effect = $effect

$grid = New-Object Windows.Controls.Grid
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[Windows.Controls.Grid]::SetRow($titleBorder, 0)
$titleBorder.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })

$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$titleText = "Сокращения AIS Release"
$tA = New-Object Windows.Controls.TextBlock; $tA.Text = $titleText; $tA.FontSize = 16; $tA.FontWeight = "Bold"
$tA.Foreground = [Windows.Media.Brushes]::White; $tA.Margin = New-Object Windows.Thickness(1,1,0,0)
$tA.VerticalAlignment = "Center"
[Windows.Controls.Grid]::SetColumn($tA, 0)
[void]$titleGrid.Children.Add($tA)

$closeBtn = New-Object Windows.Controls.Button
$closeBtn.Content = "X"; $closeBtn.Width = 40; $closeBtn.Height = 34
$closeBtn.FontWeight = "Bold"; $closeBtn.FontSize = 16; $closeBtn.Cursor = "Hand"
$closeBtn.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$closeBtn.BorderThickness = New-Object Windows.Thickness(3)
$closeBtn.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$closeBtn.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33000000")
$closeBtn.Add_Click({ $win.Close() })
[Windows.Controls.Grid]::SetColumn($closeBtn, 1)
[void]$titleGrid.Children.Add($closeBtn)

$titleBorder.Child = $titleGrid
[void]$grid.Children.Add($titleBorder)

$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[Windows.Controls.Grid]::SetRow($contentWrapper, 1)

$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "12,8,12,12"
$mainBorder.Margin = New-Object Windows.Thickness(4)

$tabCtrl = New-Object Windows.Controls.TabControl
$tabCtrl.FontSize = 12

foreach ($tab in $tabs) {
    $tabItem = New-Object Windows.Controls.TabItem
    $tabItem.Header = "$($tab.Header) ($($tab.Data.Count))"
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true
    $dg.HeadersVisibility = "All"; $dg.RowHeaderWidth = 0
    $dg.AlternatingRowBackground = [Windows.Media.BrushConverter]::new().ConvertFromString("#F5F7FA")
    $dg.FontSize = 11
    $dg.VerticalScrollBarVisibility = "Auto"
    $dg.HorizontalScrollBarVisibility = "Auto"
    $dg.Background = [Windows.Media.Brushes]::Transparent
    $dg.RowBackground = [Windows.Media.Brushes]::White
    $dg.BorderThickness = New-Object Windows.Thickness(1)
    $dg.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $dg.SelectionMode = "Extended"; $dg.SelectionUnit = "FullRow"
    for ($i = 0; $i -lt $tab.Columns.Count; $i++) {
        $col = New-Object Windows.Controls.DataGridTextColumn
        $col.Header = $tab.Headers[$i]
        $col.Binding = [Windows.Data.Binding]::new($tab.Columns[$i])
        $col.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
        [void]$dg.Columns.Add($col)
    }
    $dg.ItemsSource = $tab.Data
    $tabItem.Content = $dg
    [void]$tabCtrl.Items.Add($tabItem)
}

$mainBorder.Child = $tabCtrl
$contentWrapper.Child = $mainBorder
[void]$grid.Children.Add($contentWrapper)
$outerBorder.Child = $grid
$win.Content = $outerBorder

$win.Add_KeyDown({ param($s,$e) if ($e.Key -eq "Escape") { $win.Close() } })
[void]$win.ShowDialog()