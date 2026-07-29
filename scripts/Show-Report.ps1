<#
.SYNOPSIS
    Show-Report.ps1 — WPF-диалог «ОТЧЁТ» в стиле СТАНДАРТ1 (APPL2/APPL3).
.DESCRIPTION
    Открывает модальное окно отчёта по задаче $TaskName.
    Вкладки: Изменённые объекты, Объекты PowerBuilder IDE, Структура задачи, Полный отчёт.
    Источник данных: C:\AIS\1 Release\<TaskName>\Git_*\PB и Test_*\PB.
    Кнопка «Создать архив» копирует Test_* в archives\REPORT\<TaskName>_<timestamp>\.
#>

param([string]$TaskName = "")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

$scriptPath = Split-Path $PSCommandPath -Parent
. (Join-Path $scriptPath "Set-MetroTheme.ps1")

$projectRoot = Split-Path $scriptPath -Parent
$layoutPath = Join-Path $projectRoot "config\report_layout.json"

# ── Проверка TaskName ──
if ([string]::IsNullOrWhiteSpace($TaskName)) {
    [System.Windows.MessageBox]::Show("Имя задачи не указано. Запустите скрипт с параметром -TaskName.", "ОТЧЁТ", "OK", "Warning")
    exit
}

$releaseRoot = "C:\AIS\1 Release"
$taskPath = Join-Path $releaseRoot $TaskName
if (-not (Test-Path -LiteralPath $taskPath -PathType Container)) {
    # Поиск: префикс (главный), точные вариации (SYBASE-19296 → SYBASE-19298_19296)
    $candidates = Get-ChildItem -LiteralPath $releaseRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "$TaskName*" -or $_.Name -eq $TaskName -or $_.Name -like "*_$($TaskName -replace '^SYBASE-','')"
    } | Sort-Object Name -Descending
    if ($candidates.Count -gt 1) {
        $msg = "Найдено $($candidates.Count) папок:`n"
        foreach ($c in $candidates) { $msg += "  $($c.Name)`n" }
        $msg += "`nВыбрана первая: $($candidates[0].Name)"
        [System.Windows.MessageBox]::Show($msg, "ОТЧЁТ — несколько задач", "OK", "Information")
    }
    if ($candidates) {
        $taskPath = $candidates[0].FullName
        $TaskName = $candidates[0].Name
    } else {
        [System.Windows.MessageBox]::Show("Папка задачи не найдена для: $TaskName`nПоиск в: $releaseRoot", "ОТЧЁТ", "OK", "Warning")
        exit
    }
}

# ── Окно прогресса ──
$progWin = New-Object Windows.Window
$progWin.Title = "Формирование отчёта"
$progWin.Width = 400; $progWin.Height = 120
$progWin.WindowStartupLocation = "CenterScreen"
$progWin.Topmost = $true
$progWin.WindowStyle = [Windows.WindowStyle]::None
$progWin.AllowsTransparency = $true
$progWin.Background = [Windows.Media.Brushes]::Transparent
$progWin.ResizeMode = "NoResize"
$progBorder = New-Object Windows.Controls.Border
$progBorder.CornerRadius = 20
$progBorder.Background = [Windows.Media.Brushes]::White
$progBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$progBorder.BorderThickness = 1
$progStack = New-Object Windows.Controls.StackPanel
$progStack.Margin = "20,15,20,15"
$progLabel = New-Object Windows.Controls.TextBlock
$progLabel.Text = "Поиск папки задачи..."
$progLabel.FontSize = 12; $progLabel.Foreground = "#4A5568"; $progLabel.Margin = "0,0,0,8"
[void]$progStack.Children.Add($progLabel)
$progBar = New-Object Windows.Controls.ProgressBar
$progBar.Minimum = 0; $progBar.Maximum = 100; $progBar.Height = 20
$progBar.Value = 0
Apply-GlossyProgressStyle -ProgressBar $progBar -BarColorTop "#1A3A60" -BarColorBottom "#2B6CB0"
[void]$progStack.Children.Add($progBar)
$progBorder.Child = $progStack
$progWin.Content = $progBorder
$progWin.Show()
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

# ── Сбор данных ──
function Get-PbType {
    param([string]$Name)
    $n = $Name.ToLower()
    switch -Wildcard ($n) {
        "w_*" { return "Window" }
        "u_*" { return "UserObject" }
        "d_*" { return "DataWindow" }
        "dw_*" { return "DataWindow" }
        "m_*" { return "Menu" }
        "n_*" { return "Standard Class" }
        "tr_*" { return "Trigger" }
        "p_*" { return "Procedure" }
        "f_*" { return "Function" }
        default {
            if ($Name -match '\.sql$') { return "SQL" }
            return "Object"
        }
    }
}

$gitObjects = @{}    # name -> @{ Path; Library; Type }
$testObjects = @{}   # name -> @{ Path; Library; Type; TestFolder }

# Этап 1: Поиск папок Git_* и Test_*
$progLabel.Text = "Сканирование папок Git_*/Test_*..."
$progBar.Value = 10
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

$allSubDirs = Get-ChildItem -LiteralPath $taskPath -Directory -ErrorAction SilentlyContinue
$gitDirs = @(); $testDirs = @(); $readyDirs = @()
foreach ($d in $allSubDirs) {
    if ($d.Name -like "Git_*") { $gitDirs += $d }
    elseif ($d.Name -like "Test_*") { $testDirs += $d }
    elseif ($d.Name -like "Ready_*") { $readyDirs += $d }
}

# Этап 2: Сканирование Git_*
$progLabel.Text = "Чтение исходных объектов (Git_*)..."
$progBar.Value = 30
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

foreach ($sub in $gitDirs) {
    $pbDir = Join-Path $sub.FullName "PB"
    if (Test-Path -LiteralPath $pbDir) {
        Get-ChildItem -LiteralPath $pbDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $gitObjects.ContainsKey($baseName)) {
                $lib = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                if ($lib -eq "PB") { $lib = $null }
                $gitObjects[$baseName] = @{ Path = $_.FullName; Library = $lib; Type = (Get-PbType $_.Name) }
            }
        }
    }
}

# Определение библиотеки для Git-объектов (если не определена — ищем в Test_*, Ready_*, PB_Current, PB_Main)
$pbCurrentDir = Join-Path $projectRoot "PB_Current"
$pbMainDir = Join-Path $projectRoot "PB_Main"
foreach ($k in $gitObjects.Keys) {
    if ([string]::IsNullOrEmpty($gitObjects[$k].Library)) {
        $foundLib = $null
        # Test_*
        foreach ($sd in $testDirs) {
            $tpb = Join-Path $sd.FullName "PB"
            if (Test-Path -LiteralPath $tpb) {
                $matches = Get-ChildItem -LiteralPath $tpb -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $k }
                foreach ($m in $matches) {
                    $mlib = Split-Path (Split-Path $m.FullName -Parent) -Leaf
                    if ($mlib -ne "PB") { $foundLib = $mlib; break }
                }
            }
            if ($foundLib) { break }
        }
        # Ready_*
        if (-not $foundLib) {
            foreach ($sd in $readyDirs) {
                $rpb = Join-Path $sd.FullName "PB"
                if (Test-Path -LiteralPath $rpb) {
                    $matches = Get-ChildItem -LiteralPath $rpb -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $k }
                    foreach ($m in $matches) {
                        $mlib = Split-Path (Split-Path $m.FullName -Parent) -Leaf
                        if ($mlib -ne "PB") { $foundLib = $mlib; break }
                    }
                }
                if ($foundLib) { break }
            }
        }
        # PB_Current
        if (-not $foundLib -and (Test-Path -LiteralPath $pbCurrentDir)) {
            $matches = Get-ChildItem -LiteralPath $pbCurrentDir -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.sr' -and [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $k }
            foreach ($m in $matches) {
                $mlib = Split-Path (Split-Path $m.FullName -Parent) -Leaf
                $foundLib = $mlib; break
            }
        }
        # PB_Main
        if (-not $foundLib -and (Test-Path -LiteralPath $pbMainDir)) {
            $matches = Get-ChildItem -LiteralPath $pbMainDir -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '^\.sr' -and [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $k }
            foreach ($m in $matches) {
                $mlib = Split-Path (Split-Path $m.FullName -Parent) -Leaf
                $foundLib = $mlib; break
            }
        }
        $gitObjects[$k].Library = if ($foundLib) { $foundLib } else { "—" }
    }
}

# Этап 3: Сканирование Test_*
$progLabel.Text = "Чтение изменённых объектов (Test_*)..."
$progBar.Value = 60
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

foreach ($sub in $testDirs) {
    $pbDir = Join-Path $sub.FullName "PB"
    $sqlDir = Join-Path $sub.FullName "SQL"
    if (Test-Path -LiteralPath $pbDir) {
        Get-ChildItem -LiteralPath $pbDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $lib = Split-Path (Split-Path $_.FullName -Parent) -Leaf
            if ($lib -eq "PB") { $lib = "—" }
            $testObjects[$baseName] = @{ Path = $_.FullName; Library = $lib; Type = (Get-PbType $_.Name); TestFolder = $_.Name }
        }
    }
    if (Test-Path -LiteralPath $sqlDir) {
        Get-ChildItem -LiteralPath $sqlDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $testObjects[$baseName] = @{ Path = $_.FullName; Library = "SQL"; Type = "SQL"; TestFolder = $_.Name }
        }
    }
}

# Этап 3a: Сканирование Ready_* (готовые объекты)
$progLabel.Text = "Чтение готовых объектов (Ready_*)..."
$progBar.Value = 70
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

$readyObjects = @{}
foreach ($sub in $readyDirs) {
    $pbDir = Join-Path $sub.FullName "PB"
    $sqlDir = Join-Path $sub.FullName "SQL"
    if (Test-Path -LiteralPath $pbDir) {
        Get-ChildItem -LiteralPath $pbDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $lib = Split-Path (Split-Path $_.FullName -Parent) -Leaf
            if ($lib -eq "PB") { $lib = "--" }
            $readyObjects[$baseName] = @{ Path = $_.FullName; Library = $lib; Type = (Get-PbType $_.Name); ReadyFolder = $sub.Name }
        }
    }
    if (Test-Path -LiteralPath $sqlDir) {
        Get-ChildItem -LiteralPath $sqlDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $readyObjects[$baseName] = @{ Path = $_.FullName; Library = "SQL"; Type = "SQL"; ReadyFolder = $sub.Name }
        }
    }
}

# Этап 4: Загрузка описаний из папки Describe
$progLabel.Text = "Загрузка описаний (Describe)..."
$progBar.Value = 80
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

$describePath = Join-Path $taskPath "Describe"
$describeData = @{}
if (Test-Path -LiteralPath $describePath -PathType Container) {
    Get-ChildItem -LiteralPath $describePath -File -Filter "*.txt" -ErrorAction SilentlyContinue | ForEach-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $describeData[$baseName] = (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).Trim()
    }
}

# Этап 5: Сравнение и формирование
$progLabel.Text = "Формирование отчёта..."
$progBar.Value = 90
[void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)

# Этап 6: Готово
$progLabel.Text = "Готово"
$progBar.Value = 100
Start-Sleep -Milliseconds 300
$progWin.Close()

$changedRows = New-Object System.Collections.ArrayList
foreach ($k in $testObjects.Keys) {
    $info = $testObjects[$k]
    $desc = if ($describeData.ContainsKey($k)) { $describeData[$k] } else { "изменён" }
    [void]$changedRows.Add([PSCustomObject]@{
        Объект = $k
        Библиотека = $info.Library
        Тип = $info.Type
        "Описание изменений" = $desc
    })
}

$readyRows = New-Object System.Collections.ArrayList
foreach ($k in $readyObjects.Keys) {
    $info = $readyObjects[$k]
    $desc = if ($describeData.ContainsKey($k)) { $describeData[$k] } else { "готово" }
    [void]$readyRows.Add([PSCustomObject]@{
        Объект = $k
        Библиотека = $info.Library
        Тип = $info.Type
        "Описание доработок" = $desc
    })
}

$pbIdeRows = New-Object System.Collections.ArrayList
foreach ($k in $gitObjects.Keys) {
    if (-not $testObjects.ContainsKey($k)) {
        $info = $gitObjects[$k]
        $desc = if ($describeData.ContainsKey($k)) { $describeData[$k] } else { "—" }
        [void]$pbIdeRows.Add([PSCustomObject]@{
            Объект = $k
            Библиотека = $info.Library
            "Что требуется изменить" = $desc
            "Статус" = "ожидает"
        })
    }
}

# ── Дерево структуры задачи ──
$treeSb = New-Object System.Text.StringBuilder
[void]$treeSb.AppendLine("Структура задачи: $TaskName")
[void]$treeSb.AppendLine($taskPath)
[void]$treeSb.AppendLine("")
Get-ChildItem -LiteralPath $taskPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    [void]$treeSb.AppendLine("└─ $($_.Name)")
    $pbDir = Join-Path $_.FullName "PB"
    if (Test-Path -LiteralPath $pbDir) {
        [void]$treeSb.AppendLine("   └─ PB")
        Get-ChildItem -LiteralPath $pbDir -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
            [void]$treeSb.AppendLine("       - $($_.Name)")
        }
        Get-ChildItem -LiteralPath $pbDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
            [void]$treeSb.AppendLine("       └─ $($_.Name)")
            Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
                [void]$treeSb.AppendLine("            - $($_.Name)")
            }
        }
    } else {
        Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
            [void]$treeSb.AppendLine("   - $($_.Name)")
        }
    }
    [void]$treeSb.AppendLine("")
}
$treeText = $treeSb.ToString()

# ── Полный отчёт ──
$fullSb = New-Object System.Text.StringBuilder
[void]$fullSb.AppendLine("ОТЧЁТ по задаче: $TaskName")
[void]$fullSb.AppendLine("Дата формирования: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("== Изменённые объекты ($($changedRows.Count)) ==")
foreach ($r in $changedRows) {
    [void]$fullSb.AppendLine("  • $($r.Объект) | $($r.Библиотека) | $($r.Тип)")
    [void]$fullSb.AppendLine("    Описание: $($r.'Описание изменений')")
}
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("== Готовые объекты (Ready_) ($($readyRows.Count)) ==")
foreach ($r in $readyRows) {
    [void]$fullSb.AppendLine("  • $($r.Объект) | $($r.Библиотека) | $($r.Тип)")
    [void]$fullSb.AppendLine("    Описание доработок: $($r.'Описание доработок')")
}
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("== Объекты для PowerBuilder IDE ($($pbIdeRows.Count)) ==")
foreach ($r in $pbIdeRows) {
    [void]$fullSb.AppendLine("  • $($r.Объект) | $($r.Библиотека) | $($r.Статус)")
    [void]$fullSb.AppendLine("    Что требуется изменить: $($r.'Что требуется изменить')")
}
[void]$fullSb.AppendLine("")
[void]$fullSb.AppendLine("== Структура задачи ==")
[void]$fullSb.AppendLine($treeText)
$fullText = $fullSb.ToString()

# ── Восстановление размера окна ──
$savedW = 900; $savedH = 600
$savedX = 0; $savedY = 0
$hasSavedPos = $false
if (Test-Path -LiteralPath $layoutPath) {
    try {
        $lay = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($lay.Width)  { $savedW = [int]$lay.Width }
        if ($lay.Height) { $savedH = [int]$lay.Height }
        if ($lay.Left -and $lay.Top) { $savedX = [int]$lay.Left; $savedY = [int]$lay.Top; $hasSavedPos = $true }
    } catch {}
}

# ── Окно ──
$win = New-Object Windows.Window
$win.Title = "ОТЧЁТ по задаче: $TaskName"
if ($hasSavedPos) {
    $win.Left = $savedX; $win.Top = $savedY
    $win.WindowStartupLocation = "Manual"
} else {
    $win.WindowStartupLocation = "CenterScreen"
}
$win.Width = $savedW; $win.Height = $savedH
$win.MinWidth = 600; $win.MinHeight = 400
$win.Topmost = $true
$win.AllowsTransparency = $true
$win.WindowStyle = [Windows.WindowStyle]::None
$win.Background = [Windows.Media.Brushes]::Transparent
$win.ResizeMode = "CanResizeWithGrip"

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

$titleText = "ОТЧЁТ по задаче: $TaskName"
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = $titleText; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = $titleText; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

# ── Add-TitleButton ──
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
    [Windows.Controls.Grid]::SetColumn($b, $Col)
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

# ── contentWrapper ──
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = New-Object Windows.Thickness(4,0,4,4)
[Windows.Controls.Grid]::SetRow($contentWrapper, 1)

$mainBorder = New-Object Windows.Controls.Border
$mainBorder.CornerRadius = 42
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.Padding = "20,16,20,22"
$mainBorder.Margin = New-Object Windows.Thickness(4)

# ── Основной Grid (контент + кнопки) ──
$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# ── Помощник создания DataGrid ──
function New-ReportDataGrid {
    param($data, $columns, [string[]]$wrapFields)
    if (-not $wrapFields) { $wrapFields = @() }
    $d = New-Object Windows.Controls.DataGrid
    $d.AutoGenerateColumns = $false; $d.IsReadOnly = $true
    $d.HeadersVisibility = "All"; $d.RowHeaderWidth = 0
    $d.AlternatingRowBackground = [Windows.Media.BrushConverter]::new().ConvertFromString("#F5F7FA")
    $d.FontSize = 11; $d.VerticalScrollBarVisibility = "Auto"
    $d.HorizontalScrollBarVisibility = "Auto"
    $d.Background = [Windows.Media.Brushes]::Transparent
    $d.RowBackground = [Windows.Media.Brushes]::White
    $d.BorderThickness = New-Object Windows.Thickness(1)
    $d.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $d.CanUserResizeRows = $true; $d.CanUserSortColumns = $true
    $d.GridLinesVisibility = "None"
    $d.SelectionMode = "Extended"
    $d.SelectionUnit = "FullRow"
    foreach ($c in $columns) {
        $isWrap = $wrapFields -contains $c.Field
        if ($isWrap) {
            $col = New-Object Windows.Controls.DataGridTemplateColumn
            $col.Header = $c.Header
            $xaml = @"
<DataTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>
    <TextBlock Text='{Binding $($c.Field)}' TextWrapping='Wrap' Padding='4,2' MaxHeight='300' />
</DataTemplate>
"@
            $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
            $col.CellTemplate = [Windows.Markup.XamlReader]::Load($reader)
        } else {
            $col = New-Object Windows.Controls.DataGridTextColumn
            $col.Binding = [Windows.Data.Binding]::new($c.Field)
        }
        $col.Header = $c.Header
        if ($c.Width -eq "*") {
            $col.Width = New-Object Windows.Controls.DataGridLength(1, "Star")
        } else {
            $col.Width = $c.Width
        }
        [void]$d.Columns.Add($col)
    }
    $d.ItemsSource = $data
    return $d
}

function Get-GridText {
    param($grid)
    if (-not $grid -or -not $grid.ItemsSource) { return "" }
    $sb = New-Object System.Text.StringBuilder
    $first = $true
    foreach ($col in $grid.Columns) {
        if (-not $first) { [void]$sb.Append("`t") }
        [void]$sb.Append($col.Header)
        $first = $false
    }
    [void]$sb.AppendLine("")
    foreach ($row in $grid.ItemsSource) {
        $first = $true
        foreach ($col in $grid.Columns) {
            if (-not $first) { [void]$sb.Append("`t") }
            $field = $col.GetType().Name
            if ($field -eq "DataGridTemplateColumn") {
                # Для template-колонок берём значение напрямую из свойства $row
                $propName = $col.Header -replace '\s+', ''
                try { $val = $row.$propName } catch { $val = "" }
                [void]$sb.Append($val)
            } else {
                try { [void]$sb.Append($col.GetCellContent($row).Text) } catch { }
            }
            $first = $false
        }
        [void]$sb.AppendLine("")
    }
    return $sb.ToString()
}

# ── Помощник кнопок копирования/экспорта ──
function New-ActionButton {
    param([string]$Text, [scriptblock]$Click, [int]$Width = 130)
    $b = New-Object Windows.Controls.Button
    if ($Text.Length -gt 3) { $b.Content = " $Text "; $b.Width = $Width + 20 } else { $b.Content = $Text; $b.Width = $Width }
    $b.Height = 32
    $b.Margin = New-Object Windows.Thickness(0,0,8,0)
    Apply-GlossyButtonStyle -Button $b
    $b.Add_Click($Click)
    return $b
}

# ── TabControl ──
$tabCtrl = New-Object Windows.Controls.TabControl
$tabCtrl.Padding = "12,6,12,6"
$tabCtrl.FontSize = 12

# ── Вкладка 1: Изменённые объекты ──
$tab1 = New-Object Windows.Controls.TabItem
$tab1.Header = "Изменённые объекты"
$tab1Grid = New-Object Windows.Controls.Grid
$tab1Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$tab1Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$dgChanged = New-ReportDataGrid -data $changedRows -columns @(
    @{ Header = "Объект";   Field = "Объект";   Width = 200 },
    @{ Header = "Библиотека"; Field = "Библиотека"; Width = 140 },
    @{ Header = "Тип";     Field = "Тип";     Width = 100 },
    @{ Header = "Описание изменений"; Field = "Описание изменений"; Width = "*" }
) -wrapFields @("Описание изменений")
[Windows.Controls.Grid]::SetRow($dgChanged, 0)
[void]$tab1Grid.Children.Add($dgChanged)

$tab1BtnPanel = New-Object Windows.Controls.StackPanel
$tab1BtnPanel.Orientation = "Horizontal"
$tab1BtnPanel.HorizontalAlignment = "Right"
$tab1BtnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)
$btnCopy1 = New-ActionButton -Text "Копировать" -Click {
    try {
        $text = Get-GridText $dgChanged
        [System.Windows.Clipboard]::SetText($text)
        [System.Windows.MessageBox]::Show("Скопировано в буфер обмена", "ОТЧЁТ", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка копирования: $_", "ОТЧЁТ", "OK", "Warning") }
}
$btnExport1 = New-ActionButton -Text "Экспорт в файл" -Click {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Текстовый файл (*.txt)|*.txt"
    $dlg.FileName = "Отчёт_Изменённые_$TaskName.txt"
    if ($dlg.ShowDialog()) {
        try {
            Set-Content -LiteralPath $dlg.FileName -Value (Get-GridText $dgChanged) -Encoding UTF8
            [System.Windows.MessageBox]::Show("Файл сохранён:`n$($dlg.FileName)", "ОТЧЁТ", "OK", "Information")
        } catch { [System.Windows.MessageBox]::Show("Ошибка сохранения: $_", "ОТЧЁТ", "OK", "Warning") }
    }
} -Width 150
[void]$tab1BtnPanel.Children.Add($btnCopy1)
[void]$tab1BtnPanel.Children.Add($btnExport1)
[Windows.Controls.Grid]::SetRow($tab1BtnPanel, 1)
[void]$tab1Grid.Children.Add($tab1BtnPanel)
$tab1.Content = $tab1Grid

# ── Вкладка 2: Объекты для PowerBuilder IDE ──
$tab2 = New-Object Windows.Controls.TabItem
$tab2.Header = "Объекты для PowerBuilder IDE"
$tab2Grid = New-Object Windows.Controls.Grid
$tab2Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$tab2Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$dgPbIde = New-ReportDataGrid -data $pbIdeRows -columns @(
    @{ Header = "Объект";   Field = "Объект";   Width = 200 },
    @{ Header = "Библиотека"; Field = "Библиотека"; Width = 140 },
    @{ Header = "Что требуется изменить"; Field = "Что требуется изменить"; Width = "*" },
    @{ Header = "Статус"; Field = "Статус"; Width = 100 }
) -wrapFields @("Что требуется изменить")
[Windows.Controls.Grid]::SetRow($dgPbIde, 0)
[void]$tab2Grid.Children.Add($dgPbIde)

$tab2BtnPanel = New-Object Windows.Controls.StackPanel
$tab2BtnPanel.Orientation = "Horizontal"
$tab2BtnPanel.HorizontalAlignment = "Right"
$tab2BtnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)
$btnCopy2 = New-ActionButton -Text "Копировать" -Click {
    try {
        [System.Windows.Clipboard]::SetText((Get-GridText $dgPbIde))
        [System.Windows.MessageBox]::Show("Скопировано в буфер обмена", "ОТЧЁТ", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка копирования: $_", "ОТЧЁТ", "OK", "Warning") }
}
$btnExport2 = New-ActionButton -Text "Экспорт в файл" -Click {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Текстовый файл (*.txt)|*.txt"
    $dlg.FileName = "Отчёт_PBIDE_$TaskName.txt"
    if ($dlg.ShowDialog()) {
        try {
            Set-Content -LiteralPath $dlg.FileName -Value (Get-GridText $dgPbIde) -Encoding UTF8
            [System.Windows.MessageBox]::Show("Файл сохранён:`n$($dlg.FileName)", "ОТЧЁТ", "OK", "Information")
        } catch { [System.Windows.MessageBox]::Show("Ошибка сохранения: $_", "ОТЧЁТ", "OK", "Warning") }
    }
} -Width 150
[void]$tab2BtnPanel.Children.Add($btnCopy2)
[void]$tab2BtnPanel.Children.Add($btnExport2)
[Windows.Controls.Grid]::SetRow($tab2BtnPanel, 1)
[void]$tab2Grid.Children.Add($tab2BtnPanel)
$tab2.Content = $tab2Grid

# ── Вкладка 3: Готовые объекты (Ready_) ──
$tab3 = New-Object Windows.Controls.TabItem
$tab3.Header = "Готовые объекты (Ready_)"
$tab3Grid = New-Object Windows.Controls.Grid
$tab3Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$tab3Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$dgReady = New-ReportDataGrid -data $readyRows -columns @(
    @{ Header = "Объект";   Field = "Объект";   Width = 200 },
    @{ Header = "Библиотека"; Field = "Библиотека"; Width = 140 },
    @{ Header = "Тип";     Field = "Тип";     Width = 100 },
    @{ Header = "Описание доработок"; Field = "Описание доработок"; Width = "*" }
) -wrapFields @("Описание доработок")
[Windows.Controls.Grid]::SetRow($dgReady, 0)
[void]$tab3Grid.Children.Add($dgReady)

$tab3BtnPanel = New-Object Windows.Controls.StackPanel
$tab3BtnPanel.Orientation = "Horizontal"
$tab3BtnPanel.HorizontalAlignment = "Right"
$tab3BtnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)
$btnCopy3 = New-ActionButton -Text "Копировать" -Click {
    try {
        [System.Windows.Clipboard]::SetText((Get-GridText $dgReady))
        [System.Windows.MessageBox]::Show("Скопировано в буфер обмена", "ОТЧЁТ", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка копирования: $_", "ОТЧЁТ", "OK", "Warning") }
}
$btnExport3 = New-ActionButton -Text "Экспорт в файл" -Click {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Текстовый файл (*.txt)|*.txt"
    $dlg.FileName = "Отчёт_Готовые_$TaskName.txt"
    if ($dlg.ShowDialog()) {
        try {
            Set-Content -LiteralPath $dlg.FileName -Value (Get-GridText $dgReady) -Encoding UTF8
            [System.Windows.MessageBox]::Show("Файл сохранён:`n$($dlg.FileName)", "ОТЧЁТ", "OK", "Information")
        } catch { [System.Windows.MessageBox]::Show("Ошибка сохранения: $_", "ОТЧЁТ", "OK", "Warning") }
    }
} -Width 150
[void]$tab3BtnPanel.Children.Add($btnCopy3)
[void]$tab3BtnPanel.Children.Add($btnExport3)
[Windows.Controls.Grid]::SetRow($tab3BtnPanel, 1)
[void]$tab3Grid.Children.Add($tab3BtnPanel)
$tab3.Content = $tab3Grid

# ── Вкладка 4: Структура задачи ──
$tab4 = New-Object Windows.Controls.TabItem
$tab4.Header = "Структура задачи"
$tab4Grid = New-Object Windows.Controls.Grid
$tab4Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$tab4Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$treeBox = New-Object Windows.Controls.TextBox
$treeBox.IsReadOnly = $true
$treeBox.Text = $treeText
$treeBox.FontFamily = "Consolas"
$treeBox.FontSize = 11
$treeBox.VerticalScrollBarVisibility = "Auto"
$treeBox.HorizontalScrollBarVisibility = "Auto"
$treeBox.TextWrapping = "NoWrap"
$treeBox.Background = [Windows.Media.Brushes]::White
$treeBox.BorderThickness = New-Object Windows.Thickness(0)
[Windows.Controls.Grid]::SetRow($treeBox, 0)
[void]$tab4Grid.Children.Add($treeBox)

$tab4BtnPanel = New-Object Windows.Controls.StackPanel
$tab4BtnPanel.Orientation = "Horizontal"
$tab4BtnPanel.HorizontalAlignment = "Right"
$tab4BtnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)
$btnCopy4 = New-ActionButton -Text "Копировать" -Click {
    try {
        [System.Windows.Clipboard]::SetText($treeBox.Text)
        [System.Windows.MessageBox]::Show("Скопировано в буфер обмена", "ОТЧЁТ", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка копирования: $_", "ОТЧЁТ", "OK", "Warning") }
}
[void]$tab4BtnPanel.Children.Add($btnCopy4)
[Windows.Controls.Grid]::SetRow($tab4BtnPanel, 1)
[void]$tab4Grid.Children.Add($tab4BtnPanel)
$tab4.Content = $tab4Grid

# ── Вкладка 5: Полный отчёт (текст) ──
$tab5 = New-Object Windows.Controls.TabItem
$tab5.Header = "Полный отчёт (текст)"
$tab5Grid = New-Object Windows.Controls.Grid
$tab5Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$tab5Grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$fullBox = New-Object Windows.Controls.TextBox
$fullBox.IsReadOnly = $true
$fullBox.Text = $fullText
$fullBox.FontFamily = "Consolas"
$fullBox.FontSize = 11
$fullBox.VerticalScrollBarVisibility = "Auto"
$fullBox.HorizontalScrollBarVisibility = "Auto"
$fullBox.TextWrapping = "NoWrap"
$fullBox.Background = [Windows.Media.Brushes]::White
$fullBox.BorderThickness = New-Object Windows.Thickness(0)
[Windows.Controls.Grid]::SetRow($fullBox, 0)
[void]$tab5Grid.Children.Add($fullBox)

$tab5BtnPanel = New-Object Windows.Controls.StackPanel
$tab5BtnPanel.Orientation = "Horizontal"
$tab5BtnPanel.HorizontalAlignment = "Right"
$tab5BtnPanel.Margin = New-Object Windows.Thickness(0,7,0,0)
$btnCopy5 = New-ActionButton -Text "Копировать" -Click {
    try {
        [System.Windows.Clipboard]::SetText($fullBox.Text)
        [System.Windows.MessageBox]::Show("Скопировано в буфер обмена", "ОТЧЁТ", "OK", "Information")
    } catch { [System.Windows.MessageBox]::Show("Ошибка копирования: $_", "ОТЧЁТ", "OK", "Warning") }
}
$btnExport5 = New-ActionButton -Text "Экспорт в файл" -Click {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Текстовый файл (*.txt)|*.txt"
    $dlg.FileName = "Отчёт_Полный_$TaskName.txt"
    if ($dlg.ShowDialog()) {
        try {
            Set-Content -LiteralPath $dlg.FileName -Value $fullBox.Text -Encoding UTF8
            [System.Windows.MessageBox]::Show("Файл сохранён:`n$($dlg.FileName)", "ОТЧЁТ", "OK", "Information")
        } catch { [System.Windows.MessageBox]::Show("Ошибка сохранения: $_", "ОТЧЁТ", "OK", "Warning") }
    }
} -Width 150
[void]$tab5BtnPanel.Children.Add($btnCopy5)
[void]$tab5BtnPanel.Children.Add($btnExport5)
[Windows.Controls.Grid]::SetRow($tab5BtnPanel, 1)
[void]$tab5Grid.Children.Add($tab5BtnPanel)
$tab5.Content = $tab5Grid

# Добавление вкладок
[void]$tabCtrl.Items.Add($tab1)
[void]$tabCtrl.Items.Add($tab2)
[void]$tabCtrl.Items.Add($tab3)
[void]$tabCtrl.Items.Add($tab4)
[void]$tabCtrl.Items.Add($tab5)
$tabCtrl.SelectedIndex = 0

[Windows.Controls.Grid]::SetRow($tabCtrl, 0)
[void]$mainGrid.Children.Add($tabCtrl)

# ── Нижняя панель кнопок ──
$bottomPanel = New-Object Windows.Controls.StackPanel
$bottomPanel.Orientation = "Horizontal"
$bottomPanel.HorizontalAlignment = "Right"
$bottomPanel.Margin = New-Object Windows.Thickness(0,7,0,0)

$btnArchive = New-Object Windows.Controls.Button
$btnArchive.Content = "Создать архив"
$btnArchive.Width = 160; $btnArchive.Height = 36
$btnArchive.Margin = New-Object Windows.Thickness(0,0,8,0)
Apply-GlossyButtonStyle -Button $btnArchive -ColorTop "#CC7A00" -ColorBottom "#FFB347"
$btnArchive.Add_Click({
    try {
        $stamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
        $archiveRoot = Join-Path $projectRoot "archives\REPORT"
        $dest = Join-Path $archiveRoot "${TaskName}_$stamp"
        if (-not (Test-Path -LiteralPath $archiveRoot)) {
            New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $copied = 0
        Get-ChildItem -LiteralPath $taskPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Test_*" } | ForEach-Object {
            $target = Join-Path $dest $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
            $copied++
        }
        [System.Windows.MessageBox]::Show("Архив создан:`n$dest`nСкопировано папок: $copied", "ОТЧЁТ", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка создания архива: $_", "ОТЧЁТ", "OK", "Warning")
    }
})
[void]$bottomPanel.Children.Add($btnArchive)

$btnClose = New-Object Windows.Controls.Button
$btnClose.Content = "Закрыть"
$btnClose.Width = 100; $btnClose.Height = 36
$btnClose.Margin = New-Object Windows.Thickness(0)
Apply-GlossyButtonStyle -Button $btnClose -ColorTop "#606060" -ColorBottom "#808080"
$btnClose.Add_Click({ $win.Close() })
[void]$bottomPanel.Children.Add($btnClose)

[Windows.Controls.Grid]::SetRow($bottomPanel, 1)
[void]$mainGrid.Children.Add($bottomPanel)

$mainBorder.Child = $mainGrid
$contentWrapper.Child = $mainBorder
[void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid
$win.Content = $outerBorder

# Закрытие по Escape
$win.Add_KeyDown({
    param($sender,$e)
    if ($e.Key -eq "Escape") { $btnClose.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
})

# Сохранение размера/позиции при закрытии
$win.Add_Closed({
    try {
        $lay = [PSCustomObject]@{
            Width  = [int]$win.Width
            Height = [int]$win.Height
            Left   = [int]$win.Left
            Top    = [int]$win.Top
        }
        $json = $lay | ConvertTo-Json -Depth 5
        $cfgDir = Split-Path $layoutPath -Parent
        if (-not (Test-Path -LiteralPath $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }
        Set-Content -LiteralPath $layoutPath -Value $json -Encoding UTF8
    } catch {}
})

[void]$win.ShowDialog()
