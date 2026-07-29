param()

. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"
Import-MetroDlls

$script:projectRoot = "C:\AIS\AI\Prod"
$script:archiveRoot = "$script:projectRoot\archives\SNAPSHOT"
$script:timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$script:backupDir = "$script:archiveRoot\$script:timestamp"
New-Item -ItemType Directory -Path $script:backupDir -Force | Out-Null

Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

# ── Диалог подтверждения ──
$window = New-Object MahApps.Metro.Controls.MetroWindow
$window.Title = "СОХР - создание архива"
$window.Width = 420
$window.Height = 280
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.ResizeMode = "NoResize"

$border = New-Object Windows.Controls.Border
$border.CornerRadius = 12
$border.BorderBrush = "#808080"
$border.BorderThickness = 1

$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.Margin = New-Object Windows.Thickness(12,12,12,0)

$r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$mainGrid.RowDefinitions.Add($r1)
$r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "20"; [void]$mainGrid.RowDefinitions.Add($r2)
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
$header.Text = "Создание архива текущего состояния"
$header.FontSize = 14; $header.FontWeight = "Bold"; $header.Margin = "0,0,0,8"
[void]$msgGrid.Children.Add($header)

$info = New-Object Windows.Controls.TextBlock
$info.Text = "Архив будет создан в:`n$script:backupDir`n`nКопируются: bin, scripts, config, docs, rules, .opencode, AGENTS.md"
$info.FontSize = 12; $info.TextWrapping = "Wrap"
[System.Windows.Controls.Grid]::SetRow($info, 1)
[void]$msgGrid.Children.Add($info)

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
$btnPanel.Margin = "0,0,0,0"
$btnBorder.Child = $btnPanel

$btnYes = New-Object Windows.Controls.Button
$btnYes.Content = "Создать архив"
$btnYes.Width = 140; $btnYes.Height = 36; $btnYes.Margin = "0,8,8,0"
$btnYes.IsDefault = $true
Apply-GlossyButtonStyle -Button $btnYes
$btnYes.Add_Click({
    $window.Close()
    # Показать «песочные часы»
    $loading = New-Object MahApps.Metro.Controls.MetroWindow
    $loading.Title = "СОХР"
    $loading.Width = 300; $loading.Height = 260
    $loading.WindowStartupLocation = "CenterScreen"
    $loading.Topmost = $true
    $loading.ResizeMode = "NoResize"
    Apply-GrayWindowStyle -Window $loading
    $lBorder = New-Object Windows.Controls.Border
    $lBorder.CornerRadius = 12
    $lBorder.Background = [Windows.Media.Brushes]::White
    $lBorder.Padding = "20,16"
    $lStack = New-Object Windows.Controls.StackPanel
    $lStack.HorizontalAlignment = "Center"
    $lStack.VerticalAlignment = "Center"
    # Объёмное 3D кольцо с орбитальной анимацией
    $lCanvas = New-Object Windows.Controls.Canvas
    $lCanvas.Width = 140; $lCanvas.Height = 140
    $lCanvas.Margin = "0,0,0,32"
    $lCanvas.HorizontalAlignment = "Center"
    # Градиент кольца (голубой → синий → фиолетовый)
    $ringGrad = New-Object Windows.Media.LinearGradientBrush
    $ringGrad.StartPoint = "0,0"; $ringGrad.EndPoint = "1,1"
    [void]$ringGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x00,0xD2,0xFF), 0.0)))
    [void]$ringGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x31,0x82,0xCE), 0.5)))
    [void]$ringGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x6B,0x2D,0x8B), 1.0)))
    # Орбитальная траектория (тонкое кольцо)
    $orbitPath = New-Object Windows.Shapes.Ellipse
    $orbitPath.Width = 128; $orbitPath.Height = 128
    $orbitPath.Stroke = [Windows.Media.Brushes]::LightGray
    $orbitPath.StrokeThickness = 1
    $orbitPath.Fill = [Windows.Media.Brushes]::Transparent
    $orbitPath.Opacity = 0.3
    [System.Windows.Controls.Canvas]::SetLeft($orbitPath, 6)
    [System.Windows.Controls.Canvas]::SetTop($orbitPath, 6)
    [void]$lCanvas.Children.Add($orbitPath)
    # Контейнер для вращающегося кольца
    $ringContainer = New-Object Windows.Controls.Canvas
    $ringContainer.Width = 140; $ringContainer.Height = 140
    # Основное кольцо (увеличено в 4 раза)
    $ring = New-Object Windows.Shapes.Ellipse
    $ring.Width = 80; $ring.Height = 80
    $ring.Stroke = $ringGrad
    $ring.StrokeThickness = 5
    $ring.Fill = [Windows.Media.Brushes]::Transparent
    # Тень для объёма
    $ringShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $ringShadow.Color = [Windows.Media.Color]::FromRgb(0x20,0x50,0x90)
    $ringShadow.Direction = 270; $ringShadow.ShadowDepth = 6; $ringShadow.BlurRadius = 12; $ringShadow.Opacity = 0.7
    $ring.Effect = $ringShadow
    # Позиция кольца на орбите (радиус орбиты увеличен в 1.5 раза = 24px)
    [System.Windows.Controls.Canvas]::SetLeft($ring, 30)
    [System.Windows.Controls.Canvas]::SetTop($ring, 6)
    [void]$ringContainer.Children.Add($ring)
    # Блик на кольце
    $ringHighlight = New-Object Windows.Shapes.Ellipse
    $ringHighlight.Width = 24; $ringHighlight.Height = 16
    $ringHighlight.Fill = [Windows.Media.Brushes]::White
    $ringHighlight.Opacity = 0.7
    [System.Windows.Controls.Canvas]::SetLeft($ringHighlight, 48)
    [System.Windows.Controls.Canvas]::SetTop($ringHighlight, 12)
    [void]$ringContainer.Children.Add($ringHighlight)
    # Анимация орбитального вращения
    $orbitAnim = New-Object Windows.Media.Animation.DoubleAnimation
    $orbitAnim.From = 0; $orbitAnim.To = 360
    $orbitAnim.Duration = [Windows.Duration]::new([TimeSpan]::FromSeconds(3))
    $orbitAnim.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $rt = New-Object Windows.Media.RotateTransform
    $rt.CenterX = 70; $rt.CenterY = 70
    $ringContainer.RenderTransform = $rt
    $rt.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $orbitAnim)
    [System.Windows.Controls.Canvas]::SetLeft($ringContainer, 0)
    [System.Windows.Controls.Canvas]::SetTop($ringContainer, 0)
    [void]$lCanvas.Children.Add($ringContainer)
    [void]$lStack.Children.Add($lCanvas)
    $lText = New-Object Windows.Controls.TextBlock
    $lText.Text = "Создание архива..."
    $lText.FontSize = 13
    $lText.HorizontalAlignment = "Center"
    [void]$lStack.Children.Add($lText)
    $lBorder.Child = $lStack
    $loading.Content = $lBorder
    $loading.Show()
    # Удалить BOM из конфигов перед архивацией
    . "$PSScriptRoot\Remove-BomFromConfigs.ps1" -Silent
    # Выполнить копирование
    @("bin\*.ps1", "bin\*.bat", "*.json", "*.jsonc", "scripts\*.ps1", "config\*.json", "config\*.txt",
      "docs\*.html", "docs\*.pdf", "docs\*.md", "docs\screenshots\*.*",
      "rules\*.md", ".opencode\*.mdc", ".opencode\plugin\*.js", ".opencode\plugins\*.js", ".opencode\command\*.md") | ForEach-Object {
        $src = Join-Path $script:projectRoot $_
        $dstDir = Join-Path $script:backupDir ([System.IO.Path]::GetDirectoryName($_))
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        Copy-Item $src -Destination $dstDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item "$script:projectRoot\AGENTS.md" -Destination "$script:backupDir\" -Force -ErrorAction SilentlyContinue
    $loading.Close()
})
[void]$btnPanel.Children.Add($btnYes)

$btnCancel = New-Object Windows.Controls.Button
$btnCancel.Content = "Отмена"
$btnCancel.Width = 90; $btnCancel.Height = 36; $btnCancel.Margin = "0,8,0,0"
Apply-GlossyButtonStyle -Button $btnCancel -ColorTop "#505050" -ColorBottom "#707070"
$btnCancel.Add_Click({ $window.Close() })
[void]$btnPanel.Children.Add($btnCancel)

[void]$mainGrid.Children.Add($btnBorder)
$border.Child = $mainGrid
$window.Content = $border
Set-MetroTheme -Window $window -AccentColor "Blue"
Apply-GrayWindowStyle -Window $window
[void]$window.ShowDialog()
