<#
.SYNOPSIS
    ДО «СБОРКА» — диалоговое окно автоматической сборки golden.exe + *.pbd
.DESCRIPTION
    СТАНДАРТ1. Параметры: имя задачи, папка выгрузки, вариант 1 (подготовить PBS,
    без сборки) / вариант 2 (сразу собрать exe+pbd). Запускает Sborka-Golden.ps1
    в фоне, выводит лог, показывает прогресс. Скрытие консоли — STELLS.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Web.Extensions -ErrorAction SilentlyContinue

$scriptPath = Split-Path $PSCommandPath -Parent
$sborkaScript = Join-Path $scriptPath 'Sborka-Golden.ps1'
$configPath = Join-Path $scriptPath '..\config\config.json'
$config = Get-Content -Path $configPath -Encoding UTF8 -Raw | ConvertFrom-Json
$tempDir = $config.paths.temp_dir
$goldRoot = $config.paths.pb_current_source
$srjFile = Join-Path $goldRoot 'golden_start\golden.srj'

# ── Текущая версия из golden.srj ──
function Read-SrjProductVersion {
    if (-not (Test-Path $srjFile)) { return '' }
    $lines = Get-Content -Path $srjFile -Encoding Default
    foreach ($ln in $lines) { if ($ln -like 'PVS:*') { return $ln.Substring(4) } }
    return ''
}

# ── Корни задач (как в TaskPlan: prodRoot + releaseRoot) ──
$prodRoot = 'C:\AIS\AI\Prod\tasks'
$releaseRoot = 'C:\AIS\1 Release'

function Get-ReleaseRoot {
    param([string]$TaskName)
    if ($TaskName -match '^(SYBASE|SUPRT)-') { return $releaseRoot } else { return $prodRoot }
}

# ── Загрузка имён задач из task_index.json (как в TaskPlan) ──
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
                if ($data -is [hashtable] -and $data.ContainsKey('tasks')) {
                    $taskList = $data['tasks']
                    foreach ($t in $taskList) {
                        $tasks += @{ name = if ($t.ContainsKey('name')) { $t['name'] } else { '' }; root = $r }
                    }
                } elseif ($data -is [System.Collections.ArrayList]) {
                    foreach ($t in $data) {
                        $tasks += @{ name = if ($t.ContainsKey('name')) { $t['name'] } else { '' }; root = $r }
                    }
                }
            } catch {}
        }
    }
    return $tasks | Where-Object { $_.name }
}

# ── Загрузка имён задач из папок (как в TaskPlan, если индекса нет) ──
function Load-TaskFolders {
    $folders = @()
    foreach ($r in @($prodRoot, $releaseRoot)) {
        if (Test-Path $r) {
            Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $folders += @{ name = $_.Name; root = $r }
            }
        }
    }
    return $folders | Sort-Object { $_.name } -Descending
}

# ── Наполнение комбо-бокса именами задач ──
function Update-TaskCombo {
    $tasks = Load-TaskIndex
    if (-not $tasks -or $tasks.Count -eq 0) { $tasks = Load-TaskFolders }
    $labels = $tasks | ForEach-Object { "[$($_.root.Split('\')[-1])] $($_.name)" } | Select-Object -Unique
    $script:comboTask.ItemsSource = $labels
    try { $script:comboTask.Items.Refresh() } catch {}
}

# ── Построение окна ──
$window = New-Object Windows.Window
$window.Title = "СБОРКА — сборка golden.exe + *.pbd"
$window.Width = 920; $window.Height = 640
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.AllowsTransparency = $true
$window.WindowStyle = "None"
$window.Background = "Transparent"
$window.ResizeMode = "CanResizeWithGrip"
$window.ShowInTaskbar = $true

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
$tb.Add_MouseLeftButtonDown({ param($s, $e) try { $window.DragMove() } catch {} })

$tg = New-Object Windows.Controls.Grid
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$tg.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$tl = New-Object Windows.Controls.Grid; $tl.VerticalAlignment = "Center"
$t1 = New-Object Windows.Controls.TextBlock
$t1.Text = "СБОРКА — сборка golden.exe + *.pbd"; $t1.FontSize = 14; $t1.FontWeight = "Bold"
$t1.Foreground = "White"; $t1.Margin = [Windows.Thickness]::new(1,1,0,0)
[void]$tl.Children.Add($t1)
$t2 = New-Object Windows.Controls.TextBlock
$t2.Text = "СБОРКА — сборка golden.exe + *.pbd"; $t2.FontSize = 14; $t2.FontWeight = "Bold"
$t2.Foreground = "#1A3A60"
[void]$tl.Children.Add($t2)
[Windows.Controls.Grid]::SetColumn($tl, 0); [void]$tg.Children.Add($tl)

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
    $b.Add_MouseEnter({ param($s,$e) $this.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($IsClose){"#40E81123"}else{"#401A3A60"})) })
    $b.Add_MouseLeave({ param($s,$e)
        $b2 = New-Object Windows.Media.LinearGradientBrush; $b2.StartPoint="0,0"; $b2.EndPoint="0,1"
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x2A,0x4A,0x70),0.0)))
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x1A,0x3A,0x60),0.5)))
        [void]$b2.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(13,0x12,0x2A,0x50),1.0)))
        $this.Background = $b2
    })
    return $b
}

$minB = Add-TitleButton -Text "━" -Col 1
$cloB = Add-TitleButton -Text "✕" -Col 2 -IsClose
$minB.Add_Click({ $window.WindowState = "Minimized" })
$cloB.Add_Click({ $window.Close() })
[void]$tg.Children.Add($minB); [void]$tg.Children.Add($cloB)
$tb.Child = $tg; [void]$cg.Children.Add($tb)

# Content wrapper
$cw = New-Object Windows.Controls.Border
$cw.Background = "#1A3A60"; $cw.CornerRadius = 46; $cw.Margin = [Windows.Thickness]::new(4,0,4,4)
[Windows.Controls.Grid]::SetRow($cw, 1)

$mb = New-Object Windows.Controls.Border
$mb.CornerRadius = 42; $mb.Background = "White"; $mb.Padding = "16,10,16,14"; $mb.Margin = [Windows.Thickness]::new(4)

$mainGrid = New-Object Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$mainGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))

$headerText = New-Object Windows.Controls.TextBlock
$headerText.Text = "Сервис «СБОРКА» — сборка golden.exe + pbd (PB 12.5, OrcaScript)"
$headerText.FontSize = 14; $headerText.FontWeight = "Bold"
$headerText.Foreground = "#1A3A60"
$headerText.Margin = [Windows.Thickness]::new(0,2,0,4)
[Windows.Controls.Grid]::SetRow($headerText, 0)
[void]$mainGrid.Children.Add($headerText)

# ── Панель параметров ──
$params = New-Object Windows.Controls.StackPanel
$params.Margin = [Windows.Thickness]::new(0,2,0,6)
[Windows.Controls.Grid]::SetRow($params, 1)

function Add-LabeledRow {
    param([string]$Label, [System.Windows.FrameworkElement]$Control, [double]$LabelWidth = 150)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = "Horizontal"; $sp.Margin = [Windows.Thickness]::new(0,0,0,6)
    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label; $lbl.FontSize = 12; $lbl.Foreground = "#1A3A60"
    $lbl.VerticalAlignment = "Center"; $lbl.Width = $LabelWidth
    $lbl.Margin = [Windows.Thickness]::new(0,0,6,0)
    [void]$sp.Children.Add($lbl)
    [void]$sp.Children.Add($Control)
    return $sp
}

# Строка: имя задачи (выпадающий список с редактированием)
$script:comboTask = New-Object Windows.Controls.ComboBox
$script:comboTask.Width = 460; $script:comboTask.Height = 24; $script:comboTask.FontSize = 12
$script:comboTask.IsEditable = $true
$script:comboTask.ToolTip = "Имя задачи (SYBASE-*, SUPRT-*, TASK-*) — список из task_index.json / папок задач; можно ввести новое"
[void]$params.Children.Add((Add-LabeledRow -Label "Имя задачи:" -Control $script:comboTask))

# Строка: папка выгрузки + обзор
$outPanel = New-Object Windows.Controls.StackPanel
$outPanel.Orientation = "Horizontal"
$txtOutDir = New-Object Windows.Controls.TextBox
$txtOutDir.Width = 380; $txtOutDir.Height = 24; $txtOutDir.FontSize = 12
$txtOutDir.ToolTip = "Куда класть результат Exe_yyyy_mm_dd__hh_mm (если пусто — автоопределение по имени задачи)"
$btnBrowse = New-Object Windows.Controls.Button
$btnBrowse.Content = "Обзор…"; $btnBrowse.Width = 70; $btnBrowse.Height = 24
$btnBrowse.Margin = [Windows.Thickness]::new(6,0,0,0); $btnBrowse.FontSize = 11
[void]$outPanel.Children.Add($txtOutDir); [void]$outPanel.Children.Add($btnBrowse)
[void]$params.Children.Add((Add-LabeledRow -Label "Папка выгрузки:" -Control $outPanel))

# Строка: вариант 1/2
$varPanel = New-Object Windows.Controls.StackPanel
$varPanel.Orientation = "Horizontal"
$rbDry = New-Object Windows.Controls.RadioButton
$rbDry.Content = "Вариант 1 — подготовить PBS (dry-run, без сборки)"
$rbDry.FontSize = 12; $rbDry.Foreground = "#1A3A60"; $rbDry.IsChecked = $false
$rbDry.VerticalAlignment = "Center"; $rbDry.Margin = [Windows.Thickness]::new(0,0,20,0)
$rbRun = New-Object Windows.Controls.RadioButton
$rbRun.Content = "Вариант 2 — сразу собрать exe + pbd (RunBuild)"
$rbRun.FontSize = 12; $rbRun.Foreground = "#1A3A60"; $rbRun.IsChecked = $true
$rbRun.VerticalAlignment = "Center"
[void]$varPanel.Children.Add($rbDry); [void]$varPanel.Children.Add($rbRun)
[void]$params.Children.Add((Add-LabeledRow -Label "Режим:" -Control $varPanel))

# Строка: текущая версия + ручное переопределение
$verPanel = New-Object Windows.Controls.StackPanel
$verPanel.Orientation = "Horizontal"
$lblVer = New-Object Windows.Controls.TextBlock
$lblVer.Text = ("Текущая: {0}" -f (Read-SrjProductVersion))
$lblVer.FontSize = 11; $lblVer.Foreground = "#4A5568"; $lblVer.VerticalAlignment = "Center"
$btnRefreshVer = New-Object Windows.Controls.Button
$btnRefreshVer.Content = "⟳"; $btnRefreshVer.Width = 26; $btnRefreshVer.Height = 22
$btnRefreshVer.Margin = [Windows.Thickness]::new(8,0,0,0); $btnRefreshVer.FontSize = 11
$txtVersion = New-Object Windows.Controls.TextBox
$txtVersion.Width = 110; $txtVersion.Height = 24; $txtVersion.FontSize = 12
$txtVersion.ToolTip = "Ручной номер версии (напр. 12.5.266.5) — если пусто, версия повышается автоматически"
$txtVersion.Margin = [Windows.Thickness]::new(12,0,0,0)
[void]$verPanel.Children.Add($lblVer); [void]$verPanel.Children.Add($btnRefreshVer); [void]$verPanel.Children.Add($txtVersion)
[void]$params.Children.Add((Add-LabeledRow -Label "Версия:" -Control $verPanel -LabelWidth 156))

# Строка: кнопки запуска
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnRun = New-Object Windows.Controls.Button
$btnRun.Content = "▶ СБОРКА"; $btnRun.Width = 120; $btnRun.Height = 30; $btnRun.FontSize = 12; $btnRun.FontWeight = "Bold"
$btnOpen = New-Object Windows.Controls.Button
$btnOpen.Content = "Открыть результат"; $btnOpen.Width = 140; $btnOpen.Height = 30; $btnOpen.FontSize = 11
$btnOpen.Margin = [Windows.Thickness]::new(8,0,0,0)
$btnCloseG = New-Object Windows.Controls.Button
$btnCloseG.Content = "Закрыть"; $btnCloseG.Width = 90; $btnCloseG.Height = 30; $btnCloseG.FontSize = 11
$btnCloseG.Margin = [Windows.Thickness]::new(8,0,0,0)
[void]$btnPanel.Children.Add($btnRun); [void]$btnPanel.Children.Add($btnOpen); [void]$btnPanel.Children.Add($btnCloseG)
[void]$params.Children.Add((Add-LabeledRow -Label "" -Control $btnPanel -LabelWidth 156))

[void]$mainGrid.Children.Add($params)

# ── Прогресс и лог ──
$bottomGrid = New-Object Windows.Controls.Grid
$bottomGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$bottomGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
[Windows.Controls.Grid]::SetRow($bottomGrid, 2)

$progressBar = New-Object Windows.Controls.ProgressBar
$progressBar.Height = 18; $progressBar.IsIndeterminate = $true
$progressBar.Visibility = "Collapsed"; $progressBar.Margin = [Windows.Thickness]::new(0,0,0,4)
$progressBar.Foreground = "#2E7D32"; $progressBar.Background = "#E2E8F0"
[Windows.Controls.Grid]::SetRow($progressBar, 0)
[void]$bottomGrid.Children.Add($progressBar)

$logBox = New-Object Windows.Controls.TextBox
$logBox.IsReadOnly = $true
$logBox.FontFamily = "Consolas"; $logBox.FontSize = 11
$logBox.Background = "#0F1A3A60"; $logBox.Foreground = "#E8EEF5"
$logBox.BorderBrush = "#CBD5E0"; $logBox.BorderThickness = 1
$logBox.VerticalScrollBarVisibility = "Auto"
$logBox.HorizontalScrollBarVisibility = "Auto"
$logBox.AcceptsReturn = $true; $logBox.TextWrapping = "NoWrap"
[Windows.Controls.Grid]::SetRow($logBox, 1)
[void]$bottomGrid.Children.Add($logBox)

[void]$mainGrid.Children.Add($bottomGrid)

$mb.Child = $mainGrid
$cw.Child = $mb
[void]$cg.Children.Add($cw)
$outerBorder.Child = $cg
$window.Content = $outerBorder

$script:lastOutFull = ""

function Append-Log {
    param([string]$Text)
    try {
        $logBox.Dispatcher.Invoke([Action]{
            $logBox.AppendText($Text + "`r`n")
            $logBox.ScrollToEnd()
        }, "Normal")
    } catch {}
}

function Set-Busy {
    param([bool]$Busy)
    try {
        $logBox.Dispatcher.Invoke([Action]{
            $btnRun.IsEnabled = -not $Busy
            $btnBrowse.IsEnabled = -not $Busy
            $script:comboTask.IsEnabled = -not $Busy
            if ($Busy) { $progressBar.Visibility = "Visible" } else { $progressBar.Visibility = "Collapsed" }
            try { $window.Cursor = $(if ($Busy) { "Wait" } else { "Arrow" }) } catch {}
        }, "Normal")
    } catch {}
}

# ── Обработчики ──
$btnBrowse.Add_Click({
    try {
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Выберите папку для результата сборки"
        $startPath = $txtOutDir.Text.Trim()
        if ($startPath -and (Test-Path $startPath)) { $fbd.SelectedPath = $startPath }
        else { $fbd.SelectedPath = $tempDir }
        $owner = [System.Windows.Interop.IWin32Window][System.Windows.Interop.WindowInteropHelper]::new($window)
        if ($fbd.ShowDialog($owner) -eq "OK") { $txtOutDir.Text = $fbd.SelectedPath }
    } catch {}
})

$btnRefreshVer.Add_Click({
    $lblVer.Text = ("Текущая: {0}" -f (Read-SrjProductVersion))
})

$btnCloseG.Add_Click({ $window.Close() })
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })

$btnOpen.Add_Click({
    if ($script:lastOutFull -and (Test-Path $script:lastOutFull)) {
        Start-Process explorer.exe -ArgumentList $script:lastOutFull | Out-Null
    } else {
        $base = if ($txtOutDir.Text.Trim()) { $txtOutDir.Text.Trim() } else { $tempDir }
        $latest = Get-ChildItem -LiteralPath $base -Directory -Filter "Exe_*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { Start-Process explorer.exe -ArgumentList $latest.FullName | Out-Null }
        else { Append-Log "Результат ещё не собран (не найдено Exe_* в $base)" }
    }
})

$btnRun.Add_Click({
    $taskName = ($script:comboTask.Text -replace '^\[[^\]]*\]\s*', '').Trim()
    $outDir = $txtOutDir.Text.Trim()
    $variant = if ($rbRun.IsChecked) { "RunBuild" } else { "DryRun" }
    $modeName = if ($variant -eq "RunBuild") { "Вариант 2 (сразу собрать)" } else { "Вариант 1 (dry-run)" }

    if (-not (Test-Path $sborkaScript)) { Append-Log "ОШИБКА: Sborka-Golden.ps1 не найден: $sborkaScript"; return }

    $manualVer = $txtVersion.Text.Trim()
    $argLine = "-NoLogo -File `"$sborkaScript`" -TaskName `"$taskName`""
    if ($outDir) { $argLine += " -OutDir `"$outDir`"" }
    if ($manualVer) { $argLine += " -Version `"$manualVer`"" }
    if ($variant -eq "RunBuild") { $argLine += " -RunBuild" } else { $argLine += " -DryRun" }

    Set-Busy $true
    Append-Log "=== СБОРКА: $modeName ==="
    Append-Log "Задача: $taskName"
    if ($manualVer) { Append-Log ("Ручная версия: {0}" -f $manualVer) }
    if ($outDir) { Append-Log "Папка выгрузки: $outDir" }
    Append-Log "Команда: powershell $argLine"

    $psExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = $null
    try { $proc = [Diagnostics.Process]::Start($psi) } catch { Append-Log "ОШИБКА запуска: $_"; Set-Busy $false; return }

    $null = $proc.OutputDataReceived.Add({ param($s, $e) if ($e.Data) { Append-Log $e.Data } })
    $null = $proc.ErrorDataReceived.Add({ param($s, $e) if ($e.Data) { Append-Log "[STDERR] $($e.Data)" } })
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    $waiter = New-Object System.Threading.Thread([System.Threading.ThreadStart]{
        $proc.WaitForExit()
        $code = $proc.ExitCode
        Start-Sleep -Milliseconds 300
        $logBox.Dispatcher.Invoke([Action]{
            Set-Busy $false
            if ($code -eq 0) {
                Append-Log ""
                Append-Log "=== ГОТОВО (код 0) ==="
                $base = if ($txtOutDir.Text.Trim()) { $txtOutDir.Text.Trim() } else { $tempDir }
                $latest = Get-ChildItem -LiteralPath $base -Directory -Filter "Exe_*" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latest) { $script:lastOutFull = $latest.FullName; Append-Log ("Результат: {0}" -f $latest.FullName) }
            } else {
                Append-Log ""
                Append-Log ("=== ОШИБКА: код {0} ===" -f $code)
            }
        }, "Normal")
    })
    $waiter.IsBackground = $true
    $waiter.Start()
})

# ── Скрытие консоли (STELLS, без P/Invoke в основном скрипте) ──
try {
    . (Join-Path $scriptPath 'Stells-HideConsole.ps1')
    Invoke-StellsHide
} catch {}

# ── Инициализация и запуск ──
Update-TaskCombo
Append-Log "ДО «СБОРКА» запущено."
Append-Log "ДО «СБОРКА» запущено."
Append-Log "Рабочий корень: $goldRoot"
Append-Log "Скрипт сборки: $sborkaScript"
Append-Log "Для сборки выберите вариант и нажмите «СБОРКА»."
[void]$window.ShowDialog()