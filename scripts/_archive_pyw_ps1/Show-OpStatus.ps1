param()

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"

$registryFile = "C:\AIS\AI\Prod\config\status_registry.json"
$fixshowLayoutFile = "C:\AIS\AI\Prod\config\fixshow_layout.json"

$registry = $null
if (Test-Path $registryFile) {
    $jsonText = Get-Content $registryFile -Raw -Encoding UTF8
    $registry = $jsonText | ConvertFrom-Json
}
if (-not $registry -or -not $registry.objects) {
    [System.Windows.MessageBox]::Show("Не удалось загрузить $registryFile", "Ошибка", "OK", "Error")
    exit 1
}

# Авто-регистрация новых ДО
$knownDOs = @{}
Get-ChildItem "C:\AIS\AI\Prod\scripts" -Filter "*.ps1" | Where-Object { $_.Name -like "Show-*" -or $_.Name -eq "VSS-History-Show.ps1" } | ForEach-Object { $knownDOs[$_.BaseName] = $_.Name }
Get-ChildItem "C:\AIS\AI\Prod\bin" -Filter "*.ps1" | Where-Object { $_.Name -like "Show-*" -or $_.Name -eq "Prod-GUI.ps1" } | ForEach-Object { $knownDOs[$_.BaseName] = $_.Name }
$changed = $false
foreach ($key in $knownDOs.Keys) {
    if (-not ($registry.objects.PSObject.Properties.Name -contains $key)) {
        $friendlyName = $key -replace '^Show-', '' -replace '\.ps1$', ''
        $friendlyName = $friendlyName -replace 'Prod-GUI', 'МОРДА (главное окно)'
        $friendlyName = $friendlyName -replace 'VSS-History-Show', 'ДО VSS: История'
        $newObj = [PSCustomObject]@{ id = $key; type = "ДО"; name = $friendlyName; status = "EDIT" }
        $registry.objects | Add-Member -MemberType NoteProperty -Name $key -Value $newObj -Force
        $changed = $true
    }
}
if ($changed) {
    $json = $registry | ConvertTo-Json -Depth 10
    Set-Content -Path $registryFile -Value $json -Encoding UTF8
}

$opData = New-Object System.Collections.ArrayList
$originalStatuses = @{}
foreach ($key in $registry.objects.PSObject.Properties.Name) {
    $obj = $registry.objects.$key
    $originalStatuses[$key] = $obj.status
    [void]$opData.Add([PSCustomObject]@{
        ID = $obj.id
        Type = $obj.type
        Name = $obj.name
        Status = $obj.status
    })
}

$window = New-Object Windows.Window
$window.Title = "FIXSHOW - Статусы объектов ($($opData.Count))"
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.AllowsTransparency = $true
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.Background = [Windows.Media.Brushes]::Transparent
$window.ResizeMode = "CanResizeWithGrip"
$window.Width = 900
$window.Height = 500

if (Test-Path $fixshowLayoutFile) {
    try {
        $layout = Get-Content $fixshowLayoutFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($layout.Width -ge 400 -and $layout.Height -ge 300) {
            $window.WindowStartupLocation = "Manual"
            if ($layout.Left -ge -100 -or $layout.Top -ge -100) {
                if ($layout.Left -ge 0) { $window.Left = $layout.Left }
                if ($layout.Top -ge 0) { $window.Top = $layout.Top }
            }
            $window.Width = $layout.Width
            $window.Height = $layout.Height
        }
    } catch { }
}

$outerBorder = New-Object Windows.Controls.Border
$outerBorder.CornerRadius = 60
$outerBorder.BorderBrush = "#1A3A60"
$outerBorder.BorderThickness = 1
$outerBorder.Background = "#33FFFFFF"
$borderShadow = New-Object Windows.Media.Effects.DropShadowEffect
$borderShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
$borderShadow.Direction = 270; $borderShadow.ShadowDepth = 4; $borderShadow.BlurRadius = 10; $borderShadow.Opacity = 0.5
$outerBorder.Effect = $borderShadow

$contentGrid = New-Object Windows.Controls.Grid
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

$appTitleBorder = New-Object Windows.Controls.Border
$appTitleBorder.Background = "#05FFFFFF"
$appTitleBorder.CornerRadius = 10
$appTitleBorder.Margin = "25,1,25,0"
$appTitleBorder.Padding = "20,2,20,0"
$atGrid = New-Object Windows.Controls.Grid
$atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$atGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = "FIXSHOW - Статусы объектов ($($opData.Count))"
$titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = "FIXSHOW - Статусы объектов ($($opData.Count))"
$titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$atGrid.Children.Add($titleLayer)

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

$minBtn = Add-TitleButton -Text "━" -Col 1 -Click { $window.WindowState = [Windows.WindowState]::Minimized }
$maxBtn = Add-TitleButton -Text "▣" -Col 2 -Click {
    if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal"; $maxBtn.Content = "▣" }
    else { $window.WindowState = "Maximized"; $maxBtn.Content = "❐" }
} -FontSize 18
$closeBtn = Add-TitleButton -Text "✕" -Col 3 -Click { $window.Close() } -IsClose
[void]$atGrid.Children.Add($minBtn)
[void]$atGrid.Children.Add($maxBtn)
[void]$atGrid.Children.Add($closeBtn)
$appTitleBorder.Child = $atGrid
$appTitleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $window.WindowState -ne "Maximized") { try { $window.DragMove() } catch {} }
})
[System.Windows.Controls.Grid]::SetRow($appTitleBorder, 0); [void]$contentGrid.Children.Add($appTitleBorder)

$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = "#1A3A60"
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = "4,0,4,4"
$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Margin = 4

$stack = New-Object Windows.Controls.Grid
$stack.Margin = New-Object Windows.Thickness(20)
$stack.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$stack.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

$dg = New-Object Windows.Controls.DataGrid
$dg.AutoGenerateColumns = $false
$dg.IsReadOnly = $true
$dg.HeadersVisibility = "All"
$dg.RowHeaderWidth = 0
$dg.FontSize = 12
$dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
$dg.SelectionMode = "Single"
$dg.SelectionUnit = "FullRow"
$dg.VerticalScrollBarVisibility = "Auto"
$dg.HorizontalScrollBarVisibility = "Auto"

$cID = New-Object Windows.Controls.DataGridTextColumn
$cID.Header = "ID"; $cID.Binding = [Windows.Data.Binding]::new("ID"); $cID.Width = 100
[void]$dg.Columns.Add($cID)

$cType = New-Object Windows.Controls.DataGridTextColumn
$cType.Header = "Тип"; $cType.Binding = [Windows.Data.Binding]::new("Type"); $cType.Width = 50
[void]$dg.Columns.Add($cType)

$cName = New-Object Windows.Controls.DataGridTextColumn
$cName.Header = "Имя"; $cName.Binding = [Windows.Data.Binding]::new("Name"); $cName.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
[void]$dg.Columns.Add($cName)

$cStatus = New-Object Windows.Controls.DataGridTextColumn
$cStatus.Header = "Статус"; $cStatus.Binding = [Windows.Data.Binding]::new("Status"); $cStatus.Width = 80
[void]$dg.Columns.Add($cStatus)

$dg.ItemsSource = $opData
[System.Windows.Controls.Grid]::SetRow($dg, 0)
[void]$stack.Children.Add($dg)

$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Center"
$btnPanel.Margin = "0,12,0,0"
$btnPanel.Height = 44
$btnPanel.VerticalAlignment = "Bottom"

$btnFix = New-Object Windows.Controls.Button
$btnFix.Content = "FIX"
$btnFix.Width = 80; $btnFix.Height = 36; $btnFix.FontSize = 12; $btnFix.Margin = "0,0,6,0"
Apply-GlossyButtonStyle -Button $btnFix -ColorTop "#C53030" -ColorBottom "#E53E3E"
$btnFix.Add_Click({
    $sel = $dg.SelectedItem
    if ($sel) {
        $sel.Status = "FIXED"
        $registry.objects.$($sel.ID).status = "FIXED"
        $dg.Items.Refresh()
    }
})
[void]$btnPanel.Children.Add($btnFix)

$btnEdit = New-Object Windows.Controls.Button
$btnEdit.Content = "EDIT"
$btnEdit.Width = 80; $btnEdit.Height = 36; $btnEdit.FontSize = 12; $btnEdit.Margin = "0,0,6,0"
Apply-GlossyButtonStyle -Button $btnEdit -ColorTop "#2F855A" -ColorBottom "#38A169"
$btnEdit.Add_Click({
    $sel = $dg.SelectedItem
    if ($sel) {
        $sel.Status = "EDIT"
        $registry.objects.$($sel.ID).status = "EDIT"
        $dg.Items.Refresh()
    }
})
[void]$btnPanel.Children.Add($btnEdit)

$btnSave = New-Object Windows.Controls.Button
$btnSave.Content = "Сохранить"
$btnSave.Width = 110; $btnSave.Height = 36; $btnSave.FontSize = 12; $btnSave.Margin = "0,0,6,0"
$btnSave.IsDefault = $true
Apply-GlossyButtonStyle -Button $btnSave -ColorTop "#2A5080" -ColorBottom "#87CEEB"
$btnSave.Add_Click({
    $fixedObjects = @()
    foreach ($item in $opData) {
        $oldStatus = $originalStatuses[$item.ID]
        if ($item.Status -eq "FIXED" -and $oldStatus -ne "FIXED") {
            $fixedObjects += $item
        }
    }
    $newHistory = @()
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"
    foreach ($item in $fixedObjects) {
        $oldStatus = $originalStatuses[$item.ID]
        $newHistory += @{
            timestamp = $now
            object = $item.ID
            oldStatus = $oldStatus
            newStatus = "FIXED"
            reason = "Готово, изменения запрещены"
        }
    }
    if ($newHistory.Count -gt 0) {
        $existingHistory = @()
        foreach ($h in $registry.history) { $existingHistory += $h }
        $existingHistory += $newHistory
        $registry.history = $existingHistory
        foreach ($item in $fixedObjects) {
            $originalStatuses[$item.ID] = "FIXED"
        }
    }
    $json = $registry | ConvertTo-Json -Depth 10
    Set-Content -Path $registryFile -Value $json -Encoding UTF8

    foreach ($item in $fixedObjects) {
        $objName = $item.Name -replace '[<>:"/\\|?*]', '_' -replace '\s+', '_'
        $today = Get-Date -Format "yyyy_MM_dd"
        $archivesBase = "C:\AIS\AI\Prod\archives\FIX"
        $operationDir = "$archivesBase\\$objName"
        $dateDir = "$operationDir\\$today"
        $serial = 1
        while (Test-Path "$dateDir\\$serial") { $serial++ }
        $backupDir = "$dateDir\\$serial"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        New-Item -ItemType Directory -Path "$backupDir\\bin" -Force | Out-Null
        New-Item -ItemType Directory -Path "$backupDir\\config" -Force | Out-Null
        New-Item -ItemType Directory -Path "$backupDir\\scripts" -Force | Out-Null
        New-Item -ItemType Directory -Path "$backupDir\\reports" -Force | Out-Null
        Copy-Item "C:\\AIS\\AI\\Prod\\bin\\*" -Destination "$backupDir\\bin\\" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item "C:\\AIS\\AI\\Prod\\config\\*" -Destination "$backupDir\\config\\" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item "C:\\AIS\\AI\\Prod\\scripts\\*" -Destination "$backupDir\\scripts\\" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item "C:\\AIS\\AI\\Prod\\reports\\*" -Destination "$backupDir\\reports\\" -Recurse -Force -ErrorAction SilentlyContinue
    }

    $msg = "Статусы сохранены"
    if ($fixedObjects.Count -gt 0) { $msg += " и заархивировано объектов: $($fixedObjects.Count)" }
    [System.Windows.MessageBox]::Show($msg, "Сохранение", "OK", "Information")
})
[void]$btnPanel.Children.Add($btnSave)

$btnHistory = New-Object Windows.Controls.Button
$btnHistory.Content = "История"
$btnHistory.Width = 90; $btnHistory.Height = 36; $btnHistory.FontSize = 12
Apply-GlossyButtonStyle -Button $btnHistory -ColorTop "#C08020" -ColorBottom "#E5A00D"
$btnHistory.Add_Click({
    $selItems = @($dg.SelectedItems)
    $filteredObjects = if ($selItems.Count -gt 0) { $selItems | ForEach-Object { $_.ID } } else { $null }
    $histData = New-Object System.Collections.ArrayList
    foreach ($h in $registry.history) {
        if (-not $filteredObjects -or ($filteredObjects -contains $h.object)) {
            [void]$histData.Add([PSCustomObject]@{
                Timestamp = $h.timestamp
                Object = $h.object
                OldStatus = $h.oldStatus
                NewStatus = $h.newStatus
                Reason = $h.reason
            })
        }
    }
    if ($histData.Count -eq 0) {
        if ($filteredObjects) { [System.Windows.MessageBox]::Show("Нет истории изменений для выбранных объектов", "История", "OK", "Information") }
        else { [System.Windows.MessageBox]::Show("История изменений пуста", "История", "OK", "Information") }
        return
    }
    $hWindow = New-Object Windows.Window
    $hWindow.Title = "История изменений статусов"
    $hWindow.Width = 700; $hWindow.Height = 400
    $hWindow.WindowStartupLocation = "CenterOwner"
    $hWindow.Owner = $window
    $hWindow.AllowsTransparency = $true
    $hWindow.WindowStyle = [System.Windows.WindowStyle]::None
    $hWindow.Background = [Windows.Media.Brushes]::Transparent
    $hWindow.ResizeMode = "CanResizeWithGrip"
    $hWindow.Topmost = $true

    $hOuter = New-Object Windows.Controls.Border
    $hOuter.CornerRadius = 40
    $hOuter.BorderBrush = "#1A3A60"
    $hOuter.BorderThickness = 1
    $hOuter.Background = "#33FFFFFF"
    $hShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $hShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $hShadow.Direction = 270; $hShadow.ShadowDepth = 4; $hShadow.BlurRadius = 10; $hShadow.Opacity = 0.5
    $hOuter.Effect = $hShadow

    $hContentGrid = New-Object Windows.Controls.Grid
    $hContentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $hContentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

    $hTitleBorder = New-Object Windows.Controls.Border
    $hTitleBorder.Background = "#05FFFFFF"
    $hTitleBorder.CornerRadius = 8
    $hTitleBorder.Margin = "15,1,15,0"
    $hTitleBorder.Padding = "12,2,12,0"
    $hTitleGrid = New-Object Windows.Controls.Grid
    $hTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
    $hTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $hTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $hTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

    $hTitleLayer = New-Object Windows.Controls.Grid
    $hTitleLayer.VerticalAlignment = "Center"
    $hTitleA = New-Object Windows.Controls.TextBlock
    $hTitleA.Text = "История изменений ($($histData.Count))"
    $hTitleA.FontSize = 14; $hTitleA.FontWeight = "Bold"
    $hTitleA.Foreground = [Windows.Media.Brushes]::White
    $hTitleA.Margin = New-Object Windows.Thickness(1,1,0,0)
    [void]$hTitleLayer.Children.Add($hTitleA)
    $hTitleB = New-Object Windows.Controls.TextBlock
    $hTitleB.Text = "История изменений ($($histData.Count))"
    $hTitleB.FontSize = 14; $hTitleB.FontWeight = "Bold"
    $hTitleB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    [void]$hTitleLayer.Children.Add($hTitleB)
    [System.Windows.Controls.Grid]::SetColumn($hTitleLayer, 0)
    [void]$hTitleGrid.Children.Add($hTitleLayer)

    function Add-HistoryTitleButton {
        param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$Width = 34, [int]$Height = 30, [int]$FontSize = 14)
        $b = New-Object Windows.Controls.Button
        $bg = New-Object Windows.Controls.Grid
        $ba = New-Object Windows.Controls.TextBlock
        $ba.Text = $Text; $ba.FontSize = $FontSize; $ba.FontWeight = "Bold"
        $ba.Foreground = [Windows.Media.Brushes]::White
        $ba.Margin = New-Object Windows.Thickness(1,1,0,0)
        $ba.HorizontalAlignment = "Center"; $ba.VerticalAlignment = "Center"
        [void]$bg.Children.Add($ba)
        $bb = New-Object Windows.Controls.TextBlock
        $bb.Text = $Text; $bb.FontSize = $FontSize; $bb.FontWeight = "Bold"
        $bb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        $bb.HorizontalAlignment = "Center"; $bb.VerticalAlignment = "Center"
        [void]$bg.Children.Add($bb)
        $b.Content = $bg; $b.Width = $Width; $b.Height = $Height
        $b.FontWeight = "Bold"; $b.FontSize = $FontSize
        $b.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        $b.Cursor = "Hand"
        $b.HorizontalContentAlignment = "Center"
        $b.VerticalContentAlignment = "Center"
        $b.Padding = New-Object Windows.Thickness(0)
        $b.BorderThickness = New-Object Windows.Thickness(2)
        $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
        $tg = New-Object Windows.Media.LinearGradientBrush
        $tg.StartPoint = "0,0"; $tg.EndPoint = "0,1"
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
        [void]$tg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
        $b.Background = $tg
        try {
            $xaml2 = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="5" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
            $reader2 = New-Object System.Xml.XmlNodeReader ([xml]$xaml2).DocumentElement
            $b.Template = [Windows.Markup.XamlReader]::Load($reader2)
        } catch { }
        [System.Windows.Controls.Grid]::SetColumn($b, $Col)
        $b.Add_Click($Click)
        $b.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"})) })
        $b.Add_MouseLeave({
            $tgb = New-Object Windows.Media.LinearGradientBrush
            $tgb.StartPoint = "0,0"; $tgb.EndPoint = "0,1"
            [void]$tgb.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
            [void]$tgb.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
            [void]$tgb.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
            $this.Background = $tgb
        })
        return $b
    }

    $hCloseBtn = Add-HistoryTitleButton -Text "✕" -Col 3 -Click { $hWindow.Close() } -IsClose
    [void]$hTitleGrid.Children.Add($hCloseBtn)

    $hTitleBorder.Child = $hTitleGrid
    $hTitleBorder.Add_MouseLeftButtonDown({
        if ($_.ClickCount -eq 1 -and $hWindow.WindowState -ne "Maximized") { try { $hWindow.DragMove() } catch {} }
    })
    [System.Windows.Controls.Grid]::SetRow($hTitleBorder, 0)
    [void]$hContentGrid.Children.Add($hTitleBorder)

    $hContentWrap = New-Object Windows.Controls.Border
    $hContentWrap.Background = "#1A3A60"
    $hContentWrap.CornerRadius = 36
    $hContentWrap.Margin = "3,0,3,3"
    $hMainBorder = New-Object Windows.Controls.Border
    $hMainBorder.CornerRadius = 32
    $hMainBorder.Background = [Windows.Media.Brushes]::White
    $hMainBorder.Margin = 3

    $hInnerGrid = New-Object Windows.Controls.Grid
    $hInnerGrid.Margin = New-Object Windows.Thickness(12)
    $hInnerGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $hInnerGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    $hDg = New-Object Windows.Controls.DataGrid
    $hDg.AutoGenerateColumns = $false
    $hDg.IsReadOnly = $true
    $hDg.HeadersVisibility = "All"
    $hDg.RowHeaderWidth = 0
    $hDg.FontSize = 11
    $hDg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $hDg.VerticalScrollBarVisibility = "Auto"
    $hDg.HorizontalScrollBarVisibility = "Auto"

    $hc1 = New-Object Windows.Controls.DataGridTextColumn
    $hc1.Header = "Дата"; $hc1.Binding = [Windows.Data.Binding]::new("Timestamp"); $hc1.Width = 130
    [void]$hDg.Columns.Add($hc1)

    $hc2 = New-Object Windows.Controls.DataGridTextColumn
    $hc2.Header = "Объект"; $hc2.Binding = [Windows.Data.Binding]::new("Object"); $hc2.Width = 100
    [void]$hDg.Columns.Add($hc2)

    $hc3 = New-Object Windows.Controls.DataGridTextColumn
    $hc3.Header = "Было"; $hc3.Binding = [Windows.Data.Binding]::new("OldStatus"); $hc3.Width = 60
    [void]$hDg.Columns.Add($hc3)

    $hc4 = New-Object Windows.Controls.DataGridTextColumn
    $hc4.Header = "Стало"; $hc4.Binding = [Windows.Data.Binding]::new("NewStatus"); $hc4.Width = 60
    [void]$hDg.Columns.Add($hc4)

    $hc5 = New-Object Windows.Controls.DataGridTextColumn
    $hc5.Header = "Причина"; $hc5.Binding = [Windows.Data.Binding]::new("Reason"); $hc5.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
    [void]$hDg.Columns.Add($hc5)

    $hDg.ItemsSource = $histData
    [System.Windows.Controls.Grid]::SetRow($hDg, 0)
    [void]$hInnerGrid.Children.Add($hDg)

    $hBtnClose = New-Object Windows.Controls.Button
    $hBtnClose.Content = "Закрыть"
    $hBtnClose.Width = 100; $hBtnClose.Height = 32; $hBtnClose.FontSize = 11
    $hBtnClose.HorizontalAlignment = "Right"
    $hBtnClose.Margin = "0,8,0,0"
    Apply-GlossyButtonStyle -Button $hBtnClose
    $hBtnClose.Add_Click({ $hWindow.Close() })
    [System.Windows.Controls.Grid]::SetRow($hBtnClose, 1)
    [void]$hInnerGrid.Children.Add($hBtnClose)

    $hMainBorder.Child = $hInnerGrid
    $hContentWrap.Child = $hMainBorder
    [System.Windows.Controls.Grid]::SetRow($hContentWrap, 1)
    [void]$hContentGrid.Children.Add($hContentWrap)
    $hOuter.Child = $hContentGrid

    $hWindowGrid = New-Object Windows.Controls.Grid
    [void]$hWindowGrid.Children.Add($hOuter)
    $hWindow.Content = $hWindowGrid

    $hWindow.Add_KeyDown({ if ($_.Key -eq "Escape") { $hWindow.Close() } })

    [void]$hWindow.ShowDialog()
})
[void]$btnPanel.Children.Add($btnHistory)

[System.Windows.Controls.Grid]::SetRow($btnPanel, 1)
[void]$stack.Children.Add($btnPanel)
$mainBorder.Child = $stack
$contentWrapper.Child = $mainBorder
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1); [void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid

$resizeArea = New-Object Windows.Controls.Border
$resizeArea.VerticalAlignment = "Bottom"; $resizeArea.HorizontalAlignment = "Right"
$resizeArea.Width = 30; $resizeArea.Height = 30
$resizeArea.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$resizeArea.CornerRadius = [System.Windows.CornerRadius]::new(4)
$resizeArea.Cursor = "SizeNWSE"
$resizeArea.Margin = "0,0,20,20"
$resizeArea.ToolTip = "Изменить размер окна"
$resizeArea.Add_MouseLeftButtonDown({
    $script:resizing = $true
    $script:resizeStart = [System.Windows.Point]::new($window.Width, $window.Height)
    $script:mouseStart = ([System.Windows.Forms.Cursor]::Position)
    $resizeArea.CaptureMouse()
})
$resizeArea.Add_MouseMove({
    if ($script:resizing) {
        $mPos = [System.Windows.Forms.Cursor]::Position
        $dx = $mPos.X - $script:mouseStart.X
        $dy = $mPos.Y - $script:mouseStart.Y
        $window.Width = [Math]::Max(400, $script:resizeStart.X + $dx)
        $window.Height = [Math]::Max(300, $script:resizeStart.Y + $dy)
    }
})
$resizeArea.Add_MouseLeftButtonUp({
    $script:resizing = $false
    $resizeArea.ReleaseMouseCapture()
})
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

$windowContentGrid = New-Object Windows.Controls.Grid
[void]$windowContentGrid.Children.Add($outerBorder)
[void]$windowContentGrid.Children.Add($resizeArea)
$window.Content = $windowContentGrid

$window.Add_Closing({
    try {
        $layout = @{Width=$window.Width; Height=$window.Height; Left=$window.Left; Top=$window.Top} | ConvertTo-Json
        $layoutDir = Split-Path $fixshowLayoutFile -Parent
        if (-not (Test-Path $layoutDir)) { New-Item -ItemType Directory -Path $layoutDir -Force | Out-Null }
        Set-Content -Path $fixshowLayoutFile -Value $layout -Encoding UTF8
    } catch { }
})
$window.Add_KeyDown({
    if ($_.Key -eq "Escape") { $window.Close() }
})
[void]$window.ShowDialog()
