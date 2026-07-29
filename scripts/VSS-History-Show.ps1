param(
    [string]$VssDb,
    [string]$VssUser,
    [string]$VssPass,
    [string]$VssPath,
    [string]$SearchText,
    [string]$TaskName,
    [switch]$ShowHistory,
    [switch]$SearchMode,
    [switch]$Automated,
    [switch]$AutomatedTest
)

. "C:\AIS\AI\Prod\scripts\Set-MetroTheme.ps1"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

# Скрытие консоли не требуется — скрипт запускается через Start-Process -WindowStyle Hidden

$scriptDir = Split-Path $PSScriptRoot -Parent
$vssHistoryScript = Join-Path $scriptDir "scripts\VSS-History.ps1"
if (-not (Test-Path $vssHistoryScript)) { [System.Windows.MessageBox]::Show("VSS-History.ps1 не найден: $vssHistoryScript", "Ошибка", "OK", "Error"); exit }
. $vssHistoryScript

# Если указан только TaskName (без VssPath) — в Automated режиме берём первый объект
if ($TaskName -and -not $VssPath -and $Automated) {
    $cfg = Get-Content (Join-Path $scriptDir "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseRoot = $cfg.paths.release_root
    $taskPath = Join-Path $releaseRoot $TaskName
    if (-not (Test-Path $taskPath)) {
        $found = Get-ChildItem $releaseRoot -Directory | Where-Object { $_.Name -like "$TaskName*" } | Select-Object -First 1
        if ($found) { $taskPath = $found.FullName } else { Write-Host "###VSS_ERROR###Папка задачи не найдена: $TaskName"; exit 1 }
    }
    $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
    if ($allDirs.Count -eq 0) { Write-Host "###VSS_ERROR###Нет папок Ready_*/Test_*/Git_* в задаче $TaskName"; exit 1 }
    $firstObj = $null
    foreach ($d in $allDirs) {
        $f = Get-ChildItem $d.FullName -Recurse -File -Filter "*.sr*" | Select-Object -First 1
        if ($f) { $firstObj = $f; break }
    }
    if (-not $firstObj) { Write-Host "###VSS_ERROR###Нет PB-объектов в задаче $TaskName"; exit 1 }
    $objName = [System.IO.Path]::GetFileNameWithoutExtension($firstObj.Name)
    foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
        $f = Get-ChildItem $dir -Recurse -File -Filter "$objName.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { $libName = $f.Directory.Name; break }
    }
    if (-not $libName) { Write-Host "###VSS_ERROR###Библиотека не найдена для объекта '$objName' из задачи $TaskName"; exit 1 }
    $VssPath = "`$/SRC125/gold/$libName/$objName.sr*"
    Write-Host "--- Авто-выбор объекта из задачи: $objName ($libName) ---"
}

# Если указан только VssPath (без TaskName) — пытаемся разрешить короткое имя
if ($VssPath -and -not $TaskName) {
    if ($VssPath -notmatch '^\$\/') {
        $cfg = Get-Content (Join-Path $scriptDir "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
            $f = Get-ChildItem $dir -Recurse -File -Filter "$([System.IO.Path]::GetFileNameWithoutExtension($VssPath)).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { $libName = $f.Directory.Name; break }
        }
        if (-not $libName) {
            if ($Automated) { Write-Host "###VSS_ERROR###Библиотека не найдена для объекта '$VssPath'"; exit 1 }
            [System.Windows.MessageBox]::Show("Не удалось определить библиотеку для объекта '$VssPath'. Проверьте имя или укажите полный путь VSS.", "Ошибка", "OK", "Error")
            exit
        }
        $objName = [System.IO.Path]::GetFileNameWithoutExtension($VssPath)
        $ext = if ($VssPath -match '\.sr\w*$') { [System.IO.Path]::GetExtension($VssPath) } else { ".sr*" }
        $VssPath = "`$/SRC125/gold/$libName/$objName$ext"
    }
}

# Сканируем папки задачи, если указан TaskName
if ($TaskName) {
    $cfg = Get-Content (Join-Path $scriptDir "config\config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseRoot = $cfg.paths.release_root
    $taskPath = Join-Path $releaseRoot $TaskName
    if (-not (Test-Path $taskPath)) {
        $found = Get-ChildItem $releaseRoot -Directory | Where-Object { $_.Name -like "$TaskName*" } | Select-Object -First 1
        if ($found) { $taskPath = $found.FullName } else { [System.Windows.MessageBox]::Show("Папка задачи не найдена: $TaskName", "Ошибка", "OK", "Error"); exit }
    }
    $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
    if ($allDirs.Count -eq 0) { [System.Windows.MessageBox]::Show("Нет папок Ready_*/Test_*/Git_* в задаче $TaskName", "Ошибка", "OK", "Error"); exit }
    $pbMap = @{}; 
    foreach ($d in $allDirs) {
        $sourceTag = if ($d.Name -like 'Ready_*') { ' [Ready]' } elseif ($d.Name -like 'Test_*') { ' [Test]' } else { ' [Git]' }
        Get-ChildItem $d.FullName -Recurse -File -Filter "*.sr*" | ForEach-Object { 
            $bn = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $pbMap.ContainsKey($bn)) { 
                $lib = $_.Directory.Name; if ($lib -eq 'PB') { $lib = "" }
                $pbMap[$bn] = [PSCustomObject]@{ Name = $bn; Lib = $lib; Path = $_.FullName; Source = $sourceTag }
            }
        }
    }
    $pbMap.Values | ForEach-Object { 
        $resolvedLib = ""
        foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
            $f = Get-ChildItem $dir -Recurse -File -Filter "$($_.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { $resolvedLib = $f.Directory.Name; break }
        }
        if ($resolvedLib) { $_.Lib = $resolvedLib }
    }
    $pbFiles = @($pbMap.Values | Sort-Object Name)
    if ($pbFiles.Count -eq 0) { [System.Windows.MessageBox]::Show("Нет PB-объектов в задаче $TaskName", "Ошибка", "OK", "Error"); exit }
    if ($pbFiles.Count -eq 1) {
        $script:chosenObj = $pbFiles[0]
    } else {
    # ── Диалог выбора объекта (СТАНДАРТ1 / APPL2) ──
    $selWin = New-Object Windows.Window
    $selWin.Title = "Выберите объект задачи $TaskName ($($pbFiles.Count) объектов)"
    $selWin.Width = 500; $selWin.Height = 400
    $selWin.WindowStartupLocation = "CenterScreen"
    $selWin.Topmost = $true
    $selWin.AllowsTransparency = $true
    $selWin.WindowStyle = [Windows.WindowStyle]::None
    $selWin.Background = [Windows.Media.Brushes]::Transparent
    $selWin.ResizeMode = "CanResizeWithGrip"

    $selOuterBorder = New-Object Windows.Controls.Border
    $selOuterBorder.CornerRadius = 60
    $selOuterBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $selOuterBorder.BorderThickness = 1
    $selOuterBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#33FFFFFF")
    $selBorderShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $selBorderShadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $selBorderShadow.Direction = 270; $selBorderShadow.ShadowDepth = 4; $selBorderShadow.BlurRadius = 10; $selBorderShadow.Opacity = 0.5
    $selOuterBorder.Effect = $selBorderShadow

    $selContentGrid = New-Object Windows.Controls.Grid
    $selContentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $selContentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

    $selTitleBorder = New-Object Windows.Controls.Border
    $selTitleBorder.CornerRadius = 10
    $selTitleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
    $selTitleBorder.Padding = "20,2,20,0"
    $selTitleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
    [System.Windows.Controls.Grid]::SetRow($selTitleBorder, 0)

    $selTitleBorder.Add_MouseLeftButtonDown({
        if ($_.ClickCount -eq 1 -and $selWin.WindowState -ne "Maximized") { try { $selWin.DragMove() } catch {} }
        elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
    })

    $selTitleGrid = New-Object Windows.Controls.Grid
    $selTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
    $selTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $selTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $selTitleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

    $selTitleLayer = New-Object Windows.Controls.Grid
    $selTitleLayer.VerticalAlignment = "Center"
    $selTitleTextA = New-Object Windows.Controls.TextBlock
    $selTitleTextA.Text = "Выберите объект задачи $TaskName"; $selTitleTextA.FontSize = 14; $selTitleTextA.FontWeight = "Bold"
    $selTitleTextA.Foreground = [Windows.Media.Brushes]::White
    $selTitleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
    [void]$selTitleLayer.Children.Add($selTitleTextA)
    $selTitleTextB = New-Object Windows.Controls.TextBlock
    $selTitleTextB.Text = "Выберите объект задачи $TaskName"; $selTitleTextB.FontSize = 14; $selTitleTextB.FontWeight = "Bold"
    $selTitleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    [void]$selTitleLayer.Children.Add($selTitleTextB)
    [System.Windows.Controls.Grid]::SetColumn($selTitleLayer, 0)
    [void]$selTitleGrid.Children.Add($selTitleLayer)

    # Кнопки title bar (inline)
    $selMinBtn = New-Object Windows.Controls.Button
    $selMinBtn.Width = 40; $selMinBtn.Height = 34; $selMinBtn.FontWeight = "Bold"; $selMinBtn.FontSize = 16
    $selMinBtn.Cursor = "Hand"; $selMinBtn.Padding = New-Object Windows.Thickness(0)
    $selMinBtn.BorderThickness = New-Object Windows.Thickness(3)
    $selMinBtn.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $selMinBtn.HorizontalContentAlignment = "Center"; $selMinBtn.VerticalContentAlignment = "Center"
    $selMinGrad = New-Object Windows.Media.LinearGradientBrush
    $selMinGrad.StartPoint = "0,0"; $selMinGrad.EndPoint = "0,1"
    [void]$selMinGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
    [void]$selMinGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
    [void]$selMinGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))
    $selMinBtn.Background = $selMinGrad
    $minBtnContent = New-Object Windows.Controls.Grid
    $minBtnA = New-Object Windows.Controls.TextBlock; $minBtnA.Text = "━"; $minBtnA.FontSize = 16; $minBtnA.FontWeight = "Bold"
    $minBtnA.Foreground = [Windows.Media.Brushes]::White
    $minBtnA.Margin = New-Object Windows.Thickness(1,1,0,0); $minBtnA.HorizontalAlignment = "Center"; $minBtnA.VerticalAlignment = "Center"
    [void]$minBtnContent.Children.Add($minBtnA)
    $minBtnB = New-Object Windows.Controls.TextBlock; $minBtnB.Text = "━"; $minBtnB.FontSize = 16; $minBtnB.FontWeight = "Bold"
    $minBtnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $minBtnB.HorizontalAlignment = "Center"; $minBtnB.VerticalAlignment = "Center"
    [void]$minBtnContent.Children.Add($minBtnB)
    $selMinBtn.Content = $minBtnContent
    $selMinBtn.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#401A3A60") })
    $selMinBtn.Add_MouseLeave({ $this.Background = $selMinGrad })
    try {
        $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
        $selMinBtn.Template = [Windows.Markup.XamlReader]::Load($reader)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($selMinBtn, 1)
    $selMinBtn.Add_Click({ $selWin.WindowState = [Windows.WindowState]::Minimized })

    $selMaxBtn = New-Object Windows.Controls.Button
    $selMaxBtn.Width = 40; $selMaxBtn.Height = 34; $selMaxBtn.FontWeight = "Bold"; $selMaxBtn.FontSize = 18
    $selMaxBtn.Cursor = "Hand"; $selMaxBtn.Padding = New-Object Windows.Thickness(0)
    $selMaxBtn.BorderThickness = New-Object Windows.Thickness(3)
    $selMaxBtn.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $selMaxBtn.HorizontalContentAlignment = "Center"; $selMaxBtn.VerticalContentAlignment = "Center"
    $selMaxBtn.Background = $selMinGrad
    $maxBtnContent = New-Object Windows.Controls.Grid
    $maxBtnA = New-Object Windows.Controls.TextBlock; $maxBtnA.Text = "▣"; $maxBtnA.FontSize = 18; $maxBtnA.FontWeight = "Bold"
    $maxBtnA.Foreground = [Windows.Media.Brushes]::White
    $maxBtnA.Margin = New-Object Windows.Thickness(1,1,0,0); $maxBtnA.HorizontalAlignment = "Center"; $maxBtnA.VerticalAlignment = "Center"
    [void]$maxBtnContent.Children.Add($maxBtnA)
    $maxBtnB = New-Object Windows.Controls.TextBlock; $maxBtnB.Text = "▣"; $maxBtnB.FontSize = 18; $maxBtnB.FontWeight = "Bold"
    $maxBtnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $maxBtnB.HorizontalAlignment = "Center"; $maxBtnB.VerticalAlignment = "Center"
    [void]$maxBtnContent.Children.Add($maxBtnB)
    $selMaxBtn.Content = $maxBtnContent
    $selMaxBtn.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#401A3A60") })
    $selMaxBtn.Add_MouseLeave({ $this.Background = $selMinGrad })
    try {
        $xaml2 = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
        $reader2 = New-Object System.Xml.XmlNodeReader ([xml]$xaml2).DocumentElement
        $selMaxBtn.Template = [Windows.Markup.XamlReader]::Load($reader2)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($selMaxBtn, 2)
    $selMaxBtn.Add_Click({
        if ($selWin.WindowState -eq "Maximized") { $selWin.WindowState = "Normal"; $selMaxBtn.Content = "▣" }
        else { $selWin.WindowState = "Maximized"; $selMaxBtn.Content = "❐" }
    })

    $selCloseBtn = New-Object Windows.Controls.Button
    $selCloseBtn.Width = 40; $selCloseBtn.Height = 34; $selCloseBtn.FontWeight = "Bold"; $selCloseBtn.FontSize = 16
    $selCloseBtn.Cursor = "Hand"; $selCloseBtn.Padding = New-Object Windows.Thickness(0)
    $selCloseBtn.BorderThickness = New-Object Windows.Thickness(3)
    $selCloseBtn.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $selCloseBtn.HorizontalContentAlignment = "Center"; $selCloseBtn.VerticalContentAlignment = "Center"
    $selCloseBtn.Background = $selMinGrad
    $closeBtnContent = New-Object Windows.Controls.Grid
    $closeBtnA = New-Object Windows.Controls.TextBlock; $closeBtnA.Text = "✕"; $closeBtnA.FontSize = 16; $closeBtnA.FontWeight = "Bold"
    $closeBtnA.Foreground = [Windows.Media.Brushes]::White
    $closeBtnA.Margin = New-Object Windows.Thickness(1,1,0,0); $closeBtnA.HorizontalAlignment = "Center"; $closeBtnA.VerticalAlignment = "Center"
    [void]$closeBtnContent.Children.Add($closeBtnA)
    $closeBtnB = New-Object Windows.Controls.TextBlock; $closeBtnB.Text = "✕"; $closeBtnB.FontSize = 16; $closeBtnB.FontWeight = "Bold"
    $closeBtnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $closeBtnB.HorizontalAlignment = "Center"; $closeBtnB.VerticalAlignment = "Center"
    [void]$closeBtnContent.Children.Add($closeBtnB)
    $selCloseBtn.Content = $closeBtnContent
    $selCloseBtn.Add_MouseEnter({ $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#40E81123") })
    $selCloseBtn.Add_MouseLeave({ $this.Background = $selMinGrad })
    try {
        $xaml3 = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@
        $reader3 = New-Object System.Xml.XmlNodeReader ([xml]$xaml3).DocumentElement
        $selCloseBtn.Template = [Windows.Markup.XamlReader]::Load($reader3)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($selCloseBtn, 3)
    $selCloseBtn.Add_Click({ $selWin.Close() })

    [void]$selTitleGrid.Children.Add($selMinBtn)
    [void]$selTitleGrid.Children.Add($selMaxBtn)
    [void]$selTitleGrid.Children.Add($selCloseBtn)
    $selTitleBorder.Child = $selTitleGrid
    [void]$selContentGrid.Children.Add($selTitleBorder)

    $selContentWrapper = New-Object Windows.Controls.Border
    $selContentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $selContentWrapper.CornerRadius = 46
    $selContentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
    [System.Windows.Controls.Grid]::SetRow($selContentWrapper, 1)

    $selMainBorder = New-Object Windows.Controls.Border
    $selMainBorder.CornerRadius = 42
    $selMainBorder.Background = [Windows.Media.Brushes]::White
    $selMainBorder.Padding = "16,12,16,16"
    $selMainBorder.Margin = New-Object Windows.Thickness(4)

    $selGridInner = New-Object Windows.Controls.Grid
    $selRow1 = New-Object Windows.Controls.RowDefinition; $selRow1.Height = '*'; [void]$selGridInner.RowDefinitions.Add($selRow1)
    $selRow2 = New-Object Windows.Controls.RowDefinition; $selRow2.Height = 'Auto'; [void]$selGridInner.RowDefinitions.Add($selRow2)

    $selDg = New-Object Windows.Controls.DataGrid
    $selDg.AutoGenerateColumns = $false; $selDg.IsReadOnly = $true; $selDg.HeadersVisibility = "All"
    $selDg.RowHeaderWidth = 0; $selDg.FontSize = 12; $selDg.SelectionMode = "Extended"; $selDg.SelectionUnit = "FullRow"
    $selDg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
    $selDg.VerticalScrollBarVisibility = "Auto"; $selDg.HorizontalScrollBarVisibility = "Auto"
    $selDg.Margin = "0,0,0,8"
    $selSc1 = New-Object Windows.Controls.DataGridTextColumn; $selSc1.Header = "Объект"; $selSc1.Binding = [Windows.Data.Binding]::new("Name"); $selSc1.Width = 200; [void]$selDg.Columns.Add($selSc1)
    $selSc2 = New-Object Windows.Controls.DataGridTextColumn; $selSc2.Header = "Библиотека"; $selSc2.Binding = [Windows.Data.Binding]::new("Lib"); $selSc2.Width = 150; [void]$selDg.Columns.Add($selSc2)
    $selDg.ItemsSource = $pbFiles
    [void]$selGridInner.Children.Add($selDg)

    $selBtnPanel = New-Object Windows.Controls.StackPanel
    $selBtnPanel.Orientation = "Horizontal"
    $selBtnPanel.HorizontalAlignment = "Right"
    $selBtnPanel.Margin = "0,4,0,0"
    [System.Windows.Controls.Grid]::SetRow($selBtnPanel, 1)

    $selOk = New-Object Windows.Controls.Button
    $selOk.Content = "Выбрать"; $selOk.Width = 100; $selOk.Height = 32; $selOk.Margin = "0,0,8,0"
    Apply-GlossyButtonStyle -Button $selOk
    $script:chosenObj = $null
    $script:chosenObjs = @()
    $selOk.Add_Click({ $selItems = @($selDg.SelectedItems); if ($selItems.Count -gt 0) { $script:chosenObjs = @($selItems); if ($selItems.Count -eq 1) { $script:chosenObj = $selItems[0] }; $selWin.Close() } else { [System.Windows.MessageBox]::Show("Выберите один или несколько объектов (Ctrl+Click — мульти-выбор)", "Выбор", "OK", "Warning") } })
    [void]$selBtnPanel.Children.Add($selOk)

    $selCancel = New-Object Windows.Controls.Button
    $selCancel.Content = "Отмена"; $selCancel.Width = 100; $selCancel.Height = 32
    Apply-GlossyButtonStyle -Button $selCancel -ColorTop "#606060" -ColorBottom "#808080"
    $selCancel.Add_Click({ $selWin.Close() })
    [void]$selBtnPanel.Children.Add($selCancel)

    [void]$selGridInner.Children.Add($selBtnPanel)
    $selMainBorder.Child = $selGridInner
    $selContentWrapper.Child = $selMainBorder
    [void]$selContentGrid.Children.Add($selContentWrapper)
    $selOuterBorder.Child = $selContentGrid
    $selWin.Content = $selOuterBorder

    $selWin.Add_KeyDown({ if ($_.Key -eq "Escape") { $selWin.Close() } })

    [void]$selWin.ShowDialog()
    } # конец else (диалог выбора при Count > 1)
    if (-not $script:chosenObj) { exit }
    $libName = if ($script:chosenObj.Lib) { $script:chosenObj.Lib } else { "" }
    if (-not $libName) {
        foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
            $f = Get-ChildItem $dir -Recurse -File -Filter "$($script:chosenObj.Name).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { $libName = $f.Directory.Name; break }
        }
    }
    if (-not $libName) { [System.Windows.MessageBox]::Show("Не удалось определить библиотеку для объекта '$($script:chosenObj.Name)'", "Ошибка", "OK", "Error"); exit }
    $VssPath = "`$/SRC125/gold/$libName/$($script:chosenObj.Name).sr*"
}

# Получаем историю
$history = Get-VssHistory -VssPath $VssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
if ($history.Count -eq 0) {
    [System.Windows.MessageBox]::Show("История для объекта не найдена: $VssPath", "VSS История", "OK", "Information")
    exit
}

# Сортируем по убыванию версий (свежие сверху)
$sorted = $history | Sort-Object { $_.Version } -Descending
$sorted | ForEach-Object { $_ | Add-Member -NotePropertyName "Found" -NotePropertyValue $false -Force; $_ | Add-Member -NotePropertyName "Line" -NotePropertyValue 0 -Force }

if ($SearchMode -and $SearchText) {
    $searchResults = Search-InVssHistory -VssPath $VssPath -SearchText $SearchText -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
    if ($searchResults.Count -eq 0) {
        if ($Automated) { Write-Host "###VSS_SEARCH###Text not found|0"; exit 0 }
        [System.Windows.MessageBox]::Show("Текст '$SearchText' не найден в истории объекта.", "Поиск в истории", "OK", "Information")
        exit
    }
    $first = $searchResults | Sort-Object { $_.Version } | Select-Object -First 1
    if ($Automated) {
        Write-Host "###VSS_SEARCH###Found in version $($first.Version)|$($searchResults.Count)"
        exit 0
    }
    [System.Windows.MessageBox]::Show("Текст '$SearchText' найден в версии $($first.Version) ($($first.User), $($first.Date)). Всего совпадений: $($searchResults.Count)", "Результат поиска", "OK", "Information")
    exit
}

# Автоматизированный режим: вывод истории без GUI
if ($Automated -and $ShowHistory) {
    $sorted | ForEach-Object {
        Write-Host "###VSS_HISTORY###$($_.Version)|$($_.User)|$($_.Date)|$($_.Time)|$($_.Action)|$($_.Comment)"
    }
    Write-Host "###VSS_HISTORY_END###Total versions: $($sorted.Count)"
    exit 0
}

# ── Главное окно VSS История (СТАНДАРТ1 / APPL2) ──
$window = New-Object Windows.Window
$window.Title = "VSS История: $(Split-Path $VssPath -Leaf)"
$window.Width = 800
$window.Height = 580
$window.MinWidth = 600
$window.MinHeight = 400
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.AllowsTransparency = $true
$window.WindowStyle = [Windows.WindowStyle]::None
$window.Background = [Windows.Media.Brushes]::Transparent
$window.ResizeMode = "CanResizeWithGrip"

# ── outerBorder ──
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

# ── titleBorder ──
$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[System.Windows.Controls.Grid]::SetRow($titleBorder, 0)

$titleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $window.WindowState -ne "Maximized") { try { $window.DragMove() } catch {} }
    elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
})

$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

# Двухслойный 3D-текст заголовка
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = "VSS История: $(Split-Path $VssPath -Leaf)"; $titleTextA.FontSize = 14; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = "VSS История: $(Split-Path $VssPath -Leaf)"; $titleTextB.FontSize = 14; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

# Градиент для кнопок title bar
$titleBtnGrad = New-Object Windows.Media.LinearGradientBrush
$titleBtnGrad.StartPoint = "0,0"; $titleBtnGrad.EndPoint = "0,1"
[void]$titleBtnGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70), 0.0)))
[void]$titleBtnGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60), 0.5)))
[void]$titleBtnGrad.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50), 1.0)))

# Шаблон для кнопок title bar
$btnTemplateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="6" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
</ControlTemplate>
"@

function New-TitleButton {
    param([string]$Text, [int]$Col, [scriptblock]$Click, [switch]$IsClose, [int]$Width = 40, [int]$Height = 34, [int]$FontSize = 16)
    $b = New-Object Windows.Controls.Button
    $btnContent = New-Object Windows.Controls.Grid
    $btnA = New-Object Windows.Controls.TextBlock; $btnA.Text = $Text; $btnA.FontSize = $FontSize; $btnA.FontWeight = "Bold"
    $btnA.Foreground = [Windows.Media.Brushes]::White
    $btnA.Margin = New-Object Windows.Thickness(1,1,0,0); $btnA.HorizontalAlignment = "Center"; $btnA.VerticalAlignment = "Center"
    [void]$btnContent.Children.Add($btnA)
    $btnB = New-Object Windows.Controls.TextBlock; $btnB.Text = $Text; $btnB.FontSize = $FontSize; $btnB.FontWeight = "Bold"
    $btnB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $btnB.HorizontalAlignment = "Center"; $btnB.VerticalAlignment = "Center"
    [void]$btnContent.Children.Add($btnB)
    $b.Content = $btnContent; $b.Width = $Width; $b.Height = $Height
    $b.FontWeight = "Bold"; $b.FontSize = $FontSize
    $b.Cursor = "Hand"; $b.Padding = New-Object Windows.Thickness(0)
    $b.BorderThickness = New-Object Windows.Thickness(3)
    $b.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $b.HorizontalContentAlignment = "Center"; $b.VerticalContentAlignment = "Center"
    $b.Background = $titleBtnGrad
    $b.Add_MouseEnter({
        $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose) {"#40E81123"} else {"#401A3A60"}))
    })
    $b.Add_MouseLeave({ $this.Background = $titleBtnGrad })
    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$btnTemplateXaml).DocumentElement
        $b.Template = [Windows.Markup.XamlReader]::Load($reader)
    } catch { }
    [System.Windows.Controls.Grid]::SetColumn($b, $Col)
    $b.Add_Click($Click)
    return $b
}

$minBtn = New-TitleButton -Text "━" -Col 1 -Click { $window.WindowState = [Windows.WindowState]::Minimized }
$maxBtn = New-TitleButton -Text "▣" -Col 2 -Click {
    if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal"; $maxBtn.Content = "▣" }
    else { $window.WindowState = "Maximized"; $maxBtn.Content = "❐" }
} -FontSize 18
$closeBtn = New-TitleButton -Text "✕" -Col 3 -Click { $window.Close() } -IsClose
[void]$titleGrid.Children.Add($minBtn)
[void]$titleGrid.Children.Add($maxBtn)
[void]$titleGrid.Children.Add($closeBtn)

$titleBorder.Child = $titleGrid
[void]$contentGrid.Children.Add($titleBorder)

# ── contentWrapper ──
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)

# ── mainBorder (белый контейнер контента) ──
$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "16,12,16,14"
$mainBorder.Margin = New-Object Windows.Thickness(4)

# ── Содержимое окна ──
$grid = New-Object Windows.Controls.Grid
$grid.Margin = New-Object Windows.Thickness(4)
$r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = 'Auto'; [void]$grid.RowDefinitions.Add($r1)
$r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = 'Auto'; [void]$grid.RowDefinitions.Add($r2)
$r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = 'Auto'; [void]$grid.RowDefinitions.Add($r3)
$r4 = New-Object Windows.Controls.RowDefinition; $r4.Height = '*';   [void]$grid.RowDefinitions.Add($r4)
$r5 = New-Object Windows.Controls.RowDefinition; $r5.Height = 'Auto'; [void]$grid.RowDefinitions.Add($r5)

# ── Row 0: Заголовок ──
$header = New-Object Windows.Controls.TextBlock
$header.Text = "Объект: $VssPath  —  Всего версий: $($history.Count)"
$header.FontSize = 12; $header.FontWeight = "SemiBold"; $header.Foreground = "#1A3A60"
$header.Margin = "0,0,0,6"; $header.TextWrapping = "Wrap"
[void]$grid.Children.Add($header)

# ── Row 1: Панель поиска (КОНТЕКСТ) ──
$searchPanel = New-Object Windows.Controls.Grid
$searchPanel.Margin = "0,0,0,4"
[System.Windows.Controls.Grid]::SetRow($searchPanel, 1)
$spCol1 = New-Object Windows.Controls.ColumnDefinition; $spCol1.Width = [System.Windows.GridLength]::Auto; [void]$searchPanel.ColumnDefinitions.Add($spCol1)
$spCol2 = New-Object Windows.Controls.ColumnDefinition; $spCol2.Width = [System.Windows.GridLength]::new(1, "Star"); [void]$searchPanel.ColumnDefinitions.Add($spCol2)
$spCol3 = New-Object Windows.Controls.ColumnDefinition; $spCol3.Width = [System.Windows.GridLength]::Auto; [void]$searchPanel.ColumnDefinitions.Add($spCol3)
$spCol4 = New-Object Windows.Controls.ColumnDefinition; $spCol4.Width = [System.Windows.GridLength]::Auto; [void]$searchPanel.ColumnDefinitions.Add($spCol4)

$matchLabel = New-Object Windows.Controls.TextBlock
$matchLabel.Text = "0 - 0"; $matchLabel.FontSize = 11; $matchLabel.Foreground = "#4A5568"
$matchLabel.VerticalAlignment = "Center"; $matchLabel.Margin = "0,0,6,0"
[System.Windows.Controls.Grid]::SetColumn($matchLabel, 0); [void]$searchPanel.Children.Add($matchLabel)

$searchInput = New-Object Windows.Controls.TextBox
$searchInput.FontSize = 11; $searchInput.MinHeight = 24; $searchInput.MaxHeight = 60
$searchInput.Margin = "0,0,6,0"
$searchInput.ToolTip = "Введите текст для поиска по истории VSS (Enter — поиск, ▼/▲ — навигация)"
[System.Windows.Controls.Grid]::SetColumn($searchInput, 1); [void]$searchPanel.Children.Add($searchInput)

$btnDown = New-Object Windows.Controls.Button
$btnDown.Content = "▼"; $btnDown.Width = 30; $btnDown.Height = 28
$btnDown.Padding = New-Object Windows.Thickness(0); $btnDown.FontSize = 12; $btnDown.FontWeight = "Bold"
$btnDown.ToolTip = "Найти далее (Enter)"
Apply-GlossyButtonStyle -Button $btnDown
[System.Windows.Controls.Grid]::SetColumn($btnDown, 2); [void]$searchPanel.Children.Add($btnDown)

$btnUp = New-Object Windows.Controls.Button
$btnUp.Content = "▲"; $btnUp.Width = 30; $btnUp.Height = 28
$btnUp.Padding = New-Object Windows.Thickness(0); $btnUp.FontSize = 12; $btnUp.FontWeight = "Bold"
$btnUp.ToolTip = "Найти ранее (Shift+Enter)"
Apply-GlossyButtonStyle -Button $btnUp
[System.Windows.Controls.Grid]::SetColumn($btnUp, 3); [void]$searchPanel.Children.Add($btnUp)

[void]$grid.Children.Add($searchPanel)

# ── Row 2: Прогресс-бары поиска ──
$searchPbPanel = New-Object Windows.Controls.StackPanel
$searchPbPanel.Margin = "0,0,4,4"
[System.Windows.Controls.Grid]::SetRow($searchPbPanel, 2)

$spLabel = New-Object Windows.Controls.TextBlock
$spLabel.Text = "Поиск..."
$spLabel.FontSize = 11; $spLabel.Foreground = "#4A5568"; $spLabel.Margin = "0,0,0,2"
[void]$searchPbPanel.Children.Add($spLabel)

$spPhase = New-Object Windows.Controls.ProgressBar
$spPhase.Minimum = 0; $spPhase.Maximum = 100; $spPhase.Margin = "0,0,0,4"
Apply-GlossyProgressStyle -ProgressBar $spPhase -BarColorTop "#1A3A60" -BarColorBottom "#2B6CB0"
[void]$searchPbPanel.Children.Add($spPhase)

$spStep = New-Object Windows.Controls.ProgressBar
$spStep.Minimum = 0; $spStep.Maximum = 100; $spStep.Margin = "0,0,0,0"
Apply-GlossyProgressStyle -ProgressBar $spStep -BarColorTop "#0F2440" -BarColorBottom "#1A5276"
[void]$searchPbPanel.Children.Add($spStep)

[void]$grid.Children.Add($searchPbPanel)

# ── Row 3: DataGrid ──
$dg = New-Object Windows.Controls.DataGrid
$dg.AutoGenerateColumns = $false; $dg.IsReadOnly = $true; $dg.HeadersVisibility = "All"
$dg.RowHeaderWidth = 0; $dg.FontSize = 12; $dg.SelectionMode = "Extended"; $dg.SelectionUnit = "FullRow"
$dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
$dg.VerticalScrollBarVisibility = "Auto"; $dg.HorizontalScrollBarVisibility = "Auto"
$dg.Margin = "0,0,0,6"

$cVer = New-Object Windows.Controls.DataGridTextColumn; $cVer.Header = "Версия"; $cVer.Binding = [Windows.Data.Binding]::new("Version"); $cVer.Width = 70; [void]$dg.Columns.Add($cVer)
$cUsr = New-Object Windows.Controls.DataGridTextColumn; $cUsr.Header = "Пользователь"; $cUsr.Binding = [Windows.Data.Binding]::new("User"); $cUsr.Width = 120; [void]$dg.Columns.Add($cUsr)
$cDt  = New-Object Windows.Controls.DataGridTextColumn; $cDt.Header = "Дата"; $cDt.Binding = [Windows.Data.Binding]::new("Date"); $cDt.Width = 100; [void]$dg.Columns.Add($cDt)
$cTm  = New-Object Windows.Controls.DataGridTextColumn; $cTm.Header = "Время"; $cTm.Binding = [Windows.Data.Binding]::new("Time"); $cTm.Width = 80; [void]$dg.Columns.Add($cTm)
$cAct = New-Object Windows.Controls.DataGridTextColumn; $cAct.Header = "Действие"; $cAct.Binding = [Windows.Data.Binding]::new("Action"); $cAct.Width = 120; [void]$dg.Columns.Add($cAct)
$cCmt = New-Object Windows.Controls.DataGridTextColumn; $cCmt.Header = "Комментарий"; $cCmt.Binding = [Windows.Data.Binding]::new("Comment"); $cCmt.Width = New-Object Windows.Controls.DataGridLength(1, "Star"); $cCmt.MinWidth = 100; [void]$dg.Columns.Add($cCmt)
$cFound = New-Object Windows.Controls.DataGridCheckBoxColumn; $cFound.Header = "Найдено"; $cFound.Binding = [Windows.Data.Binding]::new("Found"); $cFound.Width = 70; $cFound.IsReadOnly = $true; [void]$dg.Columns.Add($cFound)

$dg.ItemsSource = $sorted
[System.Windows.Controls.Grid]::SetRow($dg, 3)
[void]$grid.Children.Add($dg)

# ── Row 4: Нижняя панель кнопок ──
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Right"
$btnPanel.Margin = "0,4,0,0"
[System.Windows.Controls.Grid]::SetRow($btnPanel, 4)

$tmPath = if (Test-Path "C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe") { "C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe" } else { "" }

$btnCompare = New-Object Windows.Controls.Button
$btnCompare.Content = "Сравнить выделенные (TortoiseMerge)"
$btnCompare.Width = 260; $btnCompare.Height = 32; $btnCompare.Margin = "0,0,8,0"
Apply-GlossyButtonStyle -Button $btnCompare
$btnCompare.Add_Click({
    $sel = $dg.SelectedItems
    if ($sel.Count -lt 2) { [System.Windows.MessageBox]::Show("Выберите две версии для сравнения", "Сравнение", "OK", "Warning"); return }
    $savedItems = @($sel)
    $items = @($sel) | Sort-Object { $_.Version }
    $older = $items[0]; $newer = $items[1]
    if (-not $tmPath) { [System.Windows.MessageBox]::Show("TortoiseMerge не найден", "Ошибка", "OK", "Error"); return }
    try { $window.Left = 0; $window.Top = 0; $window.Width = 500 } catch {}
    $searchContext = $searchInput.Text.Trim()
    $hasFoundVersion = ($older.Found -or $newer.Found) -and $searchContext
    $targetLine = 0
    if ($hasFoundVersion) {
        $targetLine = if ($newer.Found) { $newer.Line } elseif ($older.Found) { $older.Line } else { 0 }
    }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vss_diff_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    try {
        $olderDir = Join-Path $tempDir "old"; New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
        $newerDir = Join-Path $tempDir "new"; New-Item -ItemType Directory -Path $newerDir -Force | Out-Null
        $f1 = Get-VssVersionFile -VssPath $VssPath -Version $older.Version -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -OutputDir $olderDir
        $f2 = Get-VssVersionFile -VssPath $VssPath -Version $newer.Version -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -OutputDir $newerDir
        if ($f1 -and $f2) {
            $base1 = [System.IO.Path]::GetFileNameWithoutExtension($f1)
            $ext1 = [System.IO.Path]::GetExtension($f1)
            $base2 = [System.IO.Path]::GetFileNameWithoutExtension($f2)
            $ext2 = [System.IO.Path]::GetExtension($f2)
            $verFile1 = Join-Path $olderDir ("${base1}_ver$($older.Version)$ext1")
            $verFile2 = Join-Path $newerDir ("${base2}_ver$($newer.Version)$ext2")
            Rename-Item $f1 $verFile1 -Force -ErrorAction SilentlyContinue
            Rename-Item $f2 $verFile2 -Force -ErrorAction SilentlyContinue
            $tmArgs = "/base:`"$verFile1`" /mine:`"$verFile2`""
            if ($targetLine -gt 0) { $tmArgs += " /line:$targetLine" }
            Start-Process -FilePath $tmPath -ArgumentList $tmArgs -WindowStyle Normal
        } else {
            [System.Windows.MessageBox]::Show("Не удалось получить файлы версий", "Ошибка", "OK", "Error")
        }
        try {
            $dg.SelectedItems.Clear()
            foreach ($item in $savedItems) {
                if ($item) { [void]$dg.SelectedItems.Add($item) }
            }
        } catch { }
    } finally {
        Start-Sleep -Seconds 2
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
})
[void]$btnPanel.Children.Add($btnCompare)

$btnClose = New-Object Windows.Controls.Button
$btnClose.Content = "Закрыть"
$btnClose.Width = 100; $btnClose.Height = 32
Apply-GlossyButtonStyle -Button $btnClose -ColorTop "#606060" -ColorBottom "#808080"
$btnClose.Add_Click({ $window.Close() })
[void]$btnPanel.Children.Add($btnClose)

[void]$grid.Children.Add($btnPanel)
$mainBorder.Child = $grid
$contentWrapper.Child = $mainBorder
[void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid
$window.Content = $outerBorder

# ── КОНТЕКСТ: поиск по DataGrid ──
$global:dgSearchState = @{ query = ""; results = @(); idx = -1 }

function Get-ItemText {
    param($item)
    if (-not $item) { return "" }
    $props = @("Version","User","Date","Time","Action","Comment")
    $parts = @()
    foreach ($p in $props) {
        $val = $item.$p
        if ($val) { $parts += "$val" }
    }
    return ($parts -join " ")
}

                     # ── VSS-поиск с обновлением колонки Найдено ──
                     function Invoke-VssSearch {
                         param([string]$SearchText)
                         if ([string]::IsNullOrEmpty($SearchText)) { return }
                         try { $window.Cursor = [Windows.Input.Cursors]::Wait } catch {}
                         $dg.IsEnabled = $false
                         $sorted | ForEach-Object { $_.Found = $false; $_.Line = 0 }
                         $dg.Items.Refresh()
                         $spLabel.Text = "VSS-поиск '$SearchText'... (81 версия)"
                         $spPhase.Value = 0; $spStep.Value = 0
                         $onVersionDone = {
                             param($verIdx, $foundInVersion, $foundLine)
                             if ($verIdx -ge 0 -and $verIdx -lt $sorted.Count) {
                                 $sorted[$verIdx].Found = $foundInVersion
                                 $sorted[$verIdx].Line = $foundLine
                             }
                         }
                         $pbObj = [PSCustomObject]@{ PhaseLabel = $spLabel; PhaseBar = $spPhase; StepBar = $spStep; OnVersionDone = $onVersionDone; Dispatcher = $window.Dispatcher }
                         $searchResults = Search-InVssHistory -VssPath $VssPath -SearchText $SearchText -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -ProgressBars $pbObj -History $sorted
                         $spPhase.Value = 100; $spStep.Value = 100
                         $dg.Items.Refresh()
                         $foundRows = @()
                         for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].Found) { $foundRows += $i } }
                         $dgSearchState.results = $foundRows
                         $dgSearchState.query = $SearchText
                         if ($foundRows.Count -gt 0) {
                             $dgSearchState.idx = -1
                             $matchLabel.Text = "0 - $($foundRows.Count)"
                             $btnUp.IsEnabled = $true; $btnDown.IsEnabled = $true
                         } else {
                             $dgSearchState.idx = -1
                             $matchLabel.Text = "0 - 0"
                             $btnUp.IsEnabled = $false; $btnDown.IsEnabled = $false
                         }
                         $dg.Items.Refresh()
                         $spLabel.Text = "Поиск завершён: найдено $($foundRows.Count) из $($sorted.Count)"
                         $dg.IsEnabled = $true
                         try { $window.Cursor = [Windows.Input.Cursors]::Arrow } catch {}
                     }

                     # ── Единая функция поиска ──
                     function Search-DgDown {
                         $sq = $searchInput.Text.Trim()
                         $oldQ = $dgSearchState.query
                         if (-not $sq) { $matchLabel.Text = "0 - 0"; $dgSearchState.results = @(); $dgSearchState.idx = -1; return }
                         if ($sq -ne $oldQ -or $dgSearchState.results.Count -eq 0) {
                             Invoke-VssSearch -SearchText $sq
                         }
                         if ($dgSearchState.results.Count -eq 0) { return }
                         $dgSearchState.idx = ($dgSearchState.idx + 1) % $dgSearchState.results.Count
                         $dg.SelectedIndex = $dgSearchState.results[$dgSearchState.idx]
                         $dg.ScrollIntoView($dg.Items[$dgSearchState.results[$dgSearchState.idx]])
                         $matchLabel.Text = "$($dgSearchState.idx + 1) - $($dgSearchState.results.Count)"
                     }

                     function Search-DgUp {
                         $sq = $searchInput.Text.Trim()
                         $oldQ = $dgSearchState.query
                         if (-not $sq) { return }
                         if ($sq -ne $oldQ -or $dgSearchState.results.Count -eq 0) {
                             Invoke-VssSearch -SearchText $sq
                         }
                         if ($dgSearchState.results.Count -eq 0) { return }
                         $dgSearchState.idx = ($dgSearchState.idx - 1 + $dgSearchState.results.Count) % $dgSearchState.results.Count
                         $dg.SelectedIndex = $dgSearchState.results[$dgSearchState.idx]
                         $dg.ScrollIntoView($dg.Items[$dgSearchState.results[$dgSearchState.idx]])
                         $matchLabel.Text = "$($dgSearchState.idx + 1) - $($dgSearchState.results.Count)"
                     }

                     # ── Кнопки ▼/▲ ──
$btnDown.Add_Click({
    Search-DgDown
})

$btnUp.Add_Click({
    Search-DgUp
})

# ── Enter → ▼, Shift+Enter → ▲ ──
$searchInput.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq "Enter") {
        $e.Handled = $true
        if ($e.KeyboardDevice.Modifiers -eq "Shift") {
            Search-DgUp
        } else {
            Search-DgDown
        }
    }
})

# ── Закрытие по Escape ──
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })

# ── AutomatedTest: автоматические действия в ДО без человека ──
if ($AutomatedTest) {
    $autoTimer = New-Object System.Windows.Threading.DispatcherTimer
    $autoTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $autoStep = 0
    $autoTimer.Add_Tick({
        $autoStep++
        switch ($autoStep) {
            1 {
                $searchInput.Text = "Чага"
                $spLabel.Text = "Автотест: ввод 'Чага'..."
                $sorted | ForEach-Object { $_.Found = $false }
                $dg.Items.Refresh()
                $spPhase.Value = 0; $spStep.Value = 0
                Write-Protocol "АВТОТЕСТ: Ввод текста 'Чага'"
            }
            2 {
                $spLabel.Text = "Автотест: VSS-поиск 'Чага'..."
                $searchText = "Чага"
                $onVersionDone = {
                    param($verIdx, $foundInVersion, $foundLine)
                    if ($verIdx -ge 0 -and $verIdx -lt $sorted.Count) {
                        $sorted[$verIdx].Found = $foundInVersion
                        $sorted[$verIdx].Line = $foundLine
                        $dg.Items.Refresh()
                    }
                }
                $pbObj = [PSCustomObject]@{ PhaseLabel = $spLabel; PhaseBar = $spPhase; StepBar = $spStep; OnVersionDone = $onVersionDone; Dispatcher = $window.Dispatcher }
                $searchResults = Search-InVssHistory -VssPath $VssPath -SearchText $searchText -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -ProgressBars $pbObj -History $sorted
                $spPhase.Value = 100; $spStep.Value = 100
                $dg.Items.Refresh()
                if ($searchResults.Count -eq 0) {
                    $spLabel.Text = "Автотест: 'Чага' не найден."
                    Write-Host "###VSS_AUTOTEST###SearchNotFound|Text=Чага"
                } else {
                    $firstVer = $searchResults | Sort-Object { $_.Version } | Select-Object -First 1
                    $spLabel.Text = "Автотест: найдено в $($searchResults.Count) версиях. Первое: v$($firstVer.Version)"
                    Write-Host "###VSS_AUTOTEST###SearchDone|Text=Чага|Found=$($searchResults.Count)|FirstVersion=$($firstVer.Version)"
                    $foundRows = @()
                    for ($i = 0; $i -lt $sorted.Count; $i++) { if ($sorted[$i].Found) { $foundRows += $i } }
                    if ($foundRows.Count -gt 0) {
                        $dgSearchState.results = $foundRows; $dgSearchState.query = "Чага"; $dgSearchState.idx = -1
                        $btnUp.IsEnabled = $true; $btnDown.IsEnabled = $true
                        $matchLabel.Text = "1 - $($foundRows.Count)"
                        $dg.SelectedIndex = $foundRows[0]
                        $dg.ScrollIntoView($dg.Items[$foundRows[0]])
                    }
                }
                Write-Protocol "АВТОТЕСТ: VSS-поиск завершён, найдено в $($searchResults.Count) версиях"
            }
            3 {
                $spLabel.Text = "Автотест: ▼ по найденным..."
                Search-DgDown
                Write-Protocol "АВТОТЕСТ: ▼ переход к результату $($dgSearchState.idx + 1) из $($dgSearchState.results.Count)"
            }
            4 {
                $spLabel.Text = "Автотест: ▲ назад..."
                Search-DgUp
                Write-Protocol "АВТОТЕСТ: ▲ возврат к результату $($dgSearchState.idx + 1) из $($dgSearchState.results.Count)"
            }
            5 {
                $vssFound = ($sorted | Where-Object { $_.Found }).Count
                $dgFound = $dgSearchState.results.Count
                $spLabel.Text = "Автотест: VSS=$vssFound, DataGrid=$dgFound"
                Write-Host "###VSS_AUTOTEST###Result|VssFound=$vssFound|DataGridFound=$dgFound"
                Write-Protocol "АВТОТЕСТ: Итог — VSS найдено: $vssFound, DataGrid найдено: $dgFound"
            }
            6 {
                $autoTimer.Stop()
                $window.Close()
                Write-Protocol "АВТОТЕСТ: Окно закрыто"
            }
        }
    })
    $autoTimer.Start()
}

[void]$window.ShowDialog()

