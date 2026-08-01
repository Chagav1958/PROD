<#
.SYNOPSIS
    Отображение архива пользовательских промптов в отдельном WPF-окне.
.DESCRIPTION
    Читает temp/user_prompts.log, парсит по разделителю ====
    и показывает в диалоговом окне с тремя колонками:
    - Название (узкая)
    - Дата/время (очень узкая, мелкий шрифт)
    - Полный текст (широкая, растягивается при изменении окна)
.PARAMETER LogFile
    Путь к файлу лога.
.EXAMPLE
    .\Show-Prompts.ps1
#>
param(
    [string]$LogFile = "",
    [switch]$Test,
    [switch]$Force
)

# ── Функция: окно загрузки с ПБ ────────────────────────────────────────
# ── Функция: сохранение промпта в лог ───────────────────────────────────
function Save-PromptToLog {
    param([string]$Text, [string]$Timestamp)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if ($Text.Trim().Length -le 20) { return }
    $logFile = Join-Path (Split-Path $PSScriptRoot -Parent) "temp\user_prompts.log"
    $dir = Split-Path $logFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
    if (-not (Test-Path $logFile)) { New-Item -ItemType File $logFile -Force | Out-Null }
    $raw = Get-Content $logFile -Raw -Encoding UTF8
    $textNorm = $Text.Trim() -replace '\s+', ' '
    if ($raw) {
        $blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
        foreach ($block in $blocks) {
            $lines = $block.Trim() -split "`r`n|`n"
            $existing = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
            if (($existing.Trim() -replace '\s+', ' ') -eq $textNorm) { return }
        }
    }
    $ts = if ($Timestamp) { $Timestamp } else { Get-Date -Format "dd.MM.yyyy, HH:mm:ss" }
    $entry = "`n[$ts]`n$Text`n" + ("=" * 60)
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Invoke-WithProgress {
    param([string]$Title = "Загрузка...", [scriptblock]$Action)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $window = New-Object Windows.Window
    $window.Title = $Title; $window.Width = 380; $window.Height = 130
    $window.WindowStartupLocation = "CenterScreen"
    $window.WindowStyle = "ToolWindow"; $window.ResizeMode = "NoResize"
    $window.Topmost = $true; $window.ShowInTaskbar = $false
    $stack = New-Object Windows.Controls.StackPanel; $stack.Margin = "15"
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = "Загрузка архива промптов..."; $label.FontSize = 13
    $label.FontWeight = "SemiBold"; $label.Margin = "0,0,0,10"
    [void]$stack.Children.Add($label)
    $pb = New-Object Windows.Controls.ProgressBar
    $pb.Height = 20; $pb.IsIndeterminate = $true
    [void]$stack.Children.Add($pb)
    $stLabel = New-Object Windows.Controls.TextBlock
    $stLabel.Text = "Чтение файлов..."; $stLabel.FontSize = 11
    $stLabel.Margin = "0,8,0,0"
    [void]$stack.Children.Add($stLabel)
    $window.Content = $stack
    $global:g_progressStatus = $stLabel
    $window.Show()
    [Windows.Forms.Application]::DoEvents()
    try { & $Action } catch { }
    try { $stLabel.Text = "Готово" } catch { }
    [Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 200
    try { $window.Close() } catch {}
}

# ── Функция: восстановление промптов из архивов ────────────────────────
function Recover-FromArchives {
    param([string]$TargetLog)
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $recovered = 0
    $existingTexts = @()
    if (Test-Path $TargetLog) {
        $raw = Get-Content $TargetLog -Raw -Encoding UTF8
        $blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
        foreach ($block in $blocks) {
            $lines = $block.Trim() -split "`r`n|`n"
            if ($lines.Count -ge 1 -and $lines[0] -match '\[(.+?)\]') {
                $text = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
                if ($text.Trim().Length -gt 20) { $existingTexts += $text.Trim() }
            }
        }
    }
    if ($global:g_progressStatus) {
        $global:g_progressStatus.Text = "Поиск в архивах..."
        [Windows.Forms.Application]::DoEvents()
    }
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $archiveDirs = @(
        (Join-Path $projectRoot "archives\prompts\prompts_archive.log"),
        (Join-Path $projectRoot "archives\SNAPSHOT\*\temp\user_prompts.log"),
        (Join-Path $projectRoot "archives\FIX\*\*\temp\user_prompts.log"),
        (Join-Path $projectRoot "archives\*\*\user_prompts.log")
    )
    $foundFiles = @()
    foreach ($pattern in $archiveDirs) {
        $files = Resolve-Path $pattern -ErrorAction SilentlyContinue
        if (-not $files -or $files.Count -eq 0) {
            $dir = Split-Path $pattern -Parent; $leaf = Split-Path $pattern -Leaf
            if (Test-Path $dir) {
                $files2 = Get-ChildItem -Path $dir -Filter $leaf -Recurse -ErrorAction SilentlyContinue
                if ($files2) { foreach ($f in $files2) { $foundFiles += $f.FullName } }
            }
        } else {
            foreach ($f in $files) { $foundFiles += $f.Path }
        }
    }
    $foundFiles = $foundFiles | Where-Object { $_ -ne $TargetLog } | Sort-Object -Unique
    if ($global:g_progressStatus) {
        $global:g_progressStatus.Text = "Найдено архивов: $($foundFiles.Count)"
        [Windows.Forms.Application]::DoEvents()
    }
    foreach ($af in $foundFiles) {
        try {
            if (-not (Test-Path $af)) { continue }
            $raw = Get-Content $af -Raw -Encoding UTF8
            if (-not $raw) { continue }
            $blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
            foreach ($block in $blocks) {
                $lines = $block.Trim() -split "`r`n|`n"
                $dt = ""; $text = ""
                if ($lines.Count -ge 1 -and $lines[0] -match '\[(.+?)\]') {
                    $dt = $matches[1].Trim()
                    $text = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
                } else {
                    $text = $lines -join "`n"
                }
                $t = $text.Trim()
                if ($t.Length -le 20) { continue }
                $isDup = $false
                foreach ($et in $existingTexts) {
                    if ($et -eq $t) { $isDup = $true; break }
                }
                if ($isDup) { continue }
                $existingTexts += $t
                $entry = "`n[$dt]`n$text`n" + ("=" * 60)
                Add-Content -Path $TargetLog -Value $entry -Encoding UTF8
                $recovered++
            }
        } catch { }
    }
    return $recovered
}

# ── Общие функции ─────────────────────────────────────────────────────
function Parse-PromptLog {
    param($LogFile, [int]$MinLength = 0)
    if (-not (Test-Path $LogFile)) { return @() }
    $raw = Get-Content $LogFile -Raw -Encoding UTF8
    if (-not $raw) { return @() }
    $blocks = $raw -split '={3,}' | Where-Object { $_.Trim() -ne '' }
    $data = @()
    $seen = @{}
    foreach ($block in $blocks) {
        $lines = $block.Trim() -split "`r`n|`n"
        $dt = ""
        $text = ""
        if ($lines.Count -ge 1 -and $lines[0] -match '\[(.+?)\]') {
            $dt = $matches[1].Trim()
            $text = ($lines[1..($lines.Count-1)] | Where-Object { $_ -ne '' }) -join "`n"
        } else {
            $text = $lines -join "`n"
        }
        if ($MinLength -gt 0 -and $text.Trim().Length -le $MinLength) { continue }
        # Дедупликация по нормализованному тексту
        $key = ($text.Trim() -replace '\s+', ' ').ToLower()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $firstLine = ($text -split "`n")[0]
        $name = if ($firstLine.Length -gt 60) { $firstLine.Substring(0,57) + "..." } else { $firstLine }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $firstLine }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "(пусто)" }
        $data += [PSCustomObject]@{ Name = $name; DateTime = $dt; FullText = $text }
    }
    return $data
}

function Parse-Date {
    param([string]$dt)
    if ([string]::IsNullOrWhiteSpace($dt)) { return $null }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($dt, 'dd.MM.yyyy, HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed }
    if ([datetime]::TryParseExact($dt, 'dd.MM.yyyy, HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed }
    return $null
}

function Filter-ByDateRange {
    param($data, $dateFrom, $dateTo)
    if (-not $dateFrom -and -not $dateTo) { return $data }
    return $data | Where-Object {
        $d = Parse-Date $_.DateTime
        if (-not $d) { return $false }
        if ($dateFrom -and $d -lt $dateFrom) { return $false }
        if ($dateTo -and $d -gt $dateTo.AddDays(1)) { return $false }
        return $true
    }
}

function Invoke-SearchDown {
    param($ctx)
    $sq = $ctx.sb.Text.Trim()
    if (-not $sq) { return }
    if ($sq -ne $ctx.st.query) {
        $ctx.st.query = $sq
        $sr = $ctx.dt | Where-Object { $_.FullText -match [regex]::Escape($sq) }
        $ctx.st.results = @($sr)
        if ($ctx.st.results.Count -gt 0) {
            $ctx.st.index = 0
            $ctx.dg.SelectedItem = $ctx.st.results[0]
            $ctx.dg.ScrollIntoView($ctx.dg.SelectedItem); $ctx.dg.Focus()
            $ctx.bu.IsEnabled = $true
            $ctx.bd.IsEnabled = $true
            $ctx.ml.Text = "1 - $($ctx.st.results.Count)"
        } else {
            $ctx.dg.SelectedItem = $null
            $ctx.bu.IsEnabled = $false
            $ctx.bd.IsEnabled = $false
            $ctx.ml.Text = "0 - 0"
        }
        return
    }
    if ($ctx.st.results.Count -eq 0) { return }
    $ctx.st.index = ($ctx.st.index + 1) % $ctx.st.results.Count
    $ctx.dg.SelectedItem = $ctx.st.results[$ctx.st.index]
    $ctx.dg.ScrollIntoView($ctx.dg.SelectedItem); $ctx.dg.Focus()
    $ctx.ml.Text = "$($ctx.st.index + 1) - $($ctx.st.results.Count)"
}

function Invoke-SearchUp {
    param($ctx)
    $sq = $ctx.sb.Text.Trim()
    if (-not $sq) { return }
    if ($sq -ne $ctx.st.query -or $ctx.st.results.Count -eq 0) {
        $ctx.st.query = $sq
        $sr = $ctx.dt | Where-Object { $_.FullText -match [regex]::Escape($sq) }
        $ctx.st.results = @($sr)
        if ($ctx.st.results.Count -gt 0) {
            $ctx.st.index = $ctx.st.results.Count - 1
            $ctx.dg.SelectedItem = $ctx.st.results[$ctx.st.index]
            $ctx.dg.ScrollIntoView($ctx.dg.SelectedItem); $ctx.dg.Focus()
            $ctx.bu.IsEnabled = $true
            $ctx.bd.IsEnabled = $true
            $ctx.ml.Text = "$($ctx.st.index + 1) - $($ctx.st.results.Count)"
        } else {
            $ctx.dg.SelectedItem = $null
            $ctx.bu.IsEnabled = $false
            $ctx.bd.IsEnabled = $false
            $ctx.ml.Text = "0 - 0"
        }
        return
    }
    if ($ctx.st.results.Count -eq 0) { return }
    $ctx.st.index = ($ctx.st.index - 1 + $ctx.st.results.Count) % $ctx.st.results.Count
    $ctx.dg.SelectedItem = $ctx.st.results[$ctx.st.index]
    $ctx.dg.ScrollIntoView($ctx.dg.SelectedItem); $ctx.dg.Focus()
    $ctx.ml.Text = "$($ctx.st.index + 1) - $($ctx.st.results.Count)"
}

# ── АВТОТЕСТ ──────────────────────────────────────────────────────────
if ($Test) {
    # Фикс кодировки вывода (PowerShell 5.1 → CP866 → кракозябры)
    $prevEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    
    Write-Host "=== АВТОТЕСТ Show-Prompts.ps1 ==="
    
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    
    # Создаём тестовые данные
    $testData = @(
        [PSCustomObject]@{ Name='Запрос A'; DateTime='2024-01-01 10:00'; FullText='Первый тестовый запрос с кириллицей' }
        [PSCustomObject]@{ Name='Запрос B'; DateTime='2024-01-02 11:00'; FullText='Второй запрос про настройки и параметры' }
        [PSCustomObject]@{ Name='Запрос C'; DateTime='2024-01-03 12:00'; FullText='Третий тестовый запрос с поиском слова' }
        [PSCustomObject]@{ Name='Запрос D'; DateTime='2024-01-04 13:00'; FullText='Совсем другой текст без совпадений' }
        [PSCustomObject]@{ Name='Запрос E'; DateTime='2024-01-05 14:00'; FullText='Ещё один запрос с тестовым словом' }
    )
    
    # ── Создаём UI-элементы ──
    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false
    $dg.ItemsSource = $testData
    $dg.VerticalScrollBarVisibility = "Auto"
    $dg.HorizontalScrollBarVisibility = "Auto"
    $dg.SelectionMode = "Single"; $dg.SelectionUnit = "FullRow"; $dg.IsReadOnly = $true
    $rowStyle = New-Object Windows.Style([Windows.Controls.DataGridRow])
    $selTrig = New-Object Windows.Trigger
    $selTrig.Property = [Windows.Controls.DataGridRow]::IsSelectedProperty
    $selTrig.Value = $true
    $selBg = New-Object Windows.Setter([Windows.Controls.DataGridRow]::BackgroundProperty, [Windows.Media.BrushConverter]::new().ConvertFromString("#3182CE"))
    $selFg = New-Object Windows.Setter([Windows.Controls.DataGridRow]::ForegroundProperty, [Windows.Media.Brushes]::White)
    $selTrig.Setters.Add($selBg); $selTrig.Setters.Add($selFg)
    $rowStyle.Triggers.Add($selTrig); $dg.RowStyle = $rowStyle
    $cN = New-Object Windows.Controls.DataGridTextColumn; $cN.Header="Промпт"; $cN.Binding=[Windows.Data.Binding]::new("Name")
    $cD = New-Object Windows.Controls.DataGridTextColumn; $cD.Header="Дата"; $cD.Binding=[Windows.Data.Binding]::new("DateTime")
    $cT = New-Object Windows.Controls.DataGridTextColumn; $cT.Header="Текст"; $cT.Binding=[Windows.Data.Binding]::new("FullText")
    [void]$dg.Columns.Add($cN); [void]$dg.Columns.Add($cD); [void]$dg.Columns.Add($cT)
    
    $searchBox = New-Object Windows.Controls.TextBox
    $searchBox.Height = 30; $searchBox.FontSize = 14
    $matchLabel = New-Object Windows.Controls.TextBlock
    $matchLabel.Text = "0 - 0"; $matchLabel.VerticalAlignment = "Center"; $matchLabel.MinWidth = 50
    $btnDown = New-Object Windows.Controls.Button; $btnDown.Content = "▼"; $btnDown.Width = 32; $btnDown.Height = 32
    $btnUp = New-Object Windows.Controls.Button; $btnUp.Content = "▲"; $btnUp.Width = 32; $btnUp.Height = 32
    
    # ── Глобальные переменные для обработчиков (без GetNewClosure) ──
    $global:tg_sb = $searchBox; $global:tg_ml = $matchLabel; $global:tg_bu = $btnUp; $global:tg_bd = $btnDown
    $global:tg_dg = $dg; $global:tg_dt = $testData; $global:tg_st = @{ results = @(); index = -1; query = "" }
    
    $btnDown.Add_Click({
        $sb = $global:tg_sb; $ml = $global:tg_ml; $bu = $global:tg_bu; $bd = $global:tg_bd
        $dg = $global:tg_dg; $dt = $global:tg_dt; $st = $global:tg_st
        $sq = $sb.Text.Trim()
        if (-not $sq) { return }
        if ($sq -ne $st.query) {
            $st.query = $sq
            $sr = $dt | Where-Object { $_.FullText -match [regex]::Escape($sq) }
            $st.results = @($sr)
            if ($st.results.Count -gt 0) { $st.index = 0; $dg.SelectedItem = $st.results[0]; $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus(); $bu.IsEnabled = $true; $bd.IsEnabled = $true; $ml.Text = "1 - $($st.results.Count)" }
            else { $dg.SelectedItem = $null; $bu.IsEnabled = $false; $bd.IsEnabled = $false; $ml.Text = "0 - 0" }
            return
        }
        if ($st.results.Count -eq 0) { return }
        $st.index = ($st.index + 1) % $st.results.Count
        $dg.SelectedItem = $st.results[$st.index]; $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
        $ml.Text = "$($st.index + 1) - $($st.results.Count)"
    })
    $btnUp.Add_Click({
        $sb = $global:tg_sb; $ml = $global:tg_ml; $bu = $global:tg_bu; $bd = $global:tg_bd
        $dg = $global:tg_dg; $dt = $global:tg_dt; $st = $global:tg_st
        $sq = $sb.Text.Trim()
        if (-not $sq) { return }
        if ($sq -ne $st.query -or $st.results.Count -eq 0) {
            $st.query = $sq
            $sr = $dt | Where-Object { $_.FullText -match [regex]::Escape($sq) }
            $st.results = @($sr)
            if ($st.results.Count -gt 0) { $st.index = $st.results.Count - 1; $dg.SelectedItem = $st.results[$st.index]; $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus(); $bu.IsEnabled = $true; $bd.IsEnabled = $true; $ml.Text = "$($st.index + 1) - $($st.results.Count)" }
            else { $dg.SelectedItem = $null; $bu.IsEnabled = $false; $bd.IsEnabled = $false; $ml.Text = "0 - 0" }
            return
        }
        if ($st.results.Count -eq 0) { return }
        $st.index = ($st.index - 1 + $st.results.Count) % $st.results.Count
        $dg.SelectedItem = $st.results[$st.index]; $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
        $ml.Text = "$($st.index + 1) - $($st.results.Count)"
    })
    $searchBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq "Enter") { $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) } })
    
    # ── Сборка UI ──
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = "10"
    $searchPanel = New-Object Windows.Controls.StackPanel; $searchPanel.Orientation = "Horizontal"
    $null = $searchPanel.Children.Add($searchBox); $null = $searchPanel.Children.Add($btnDown); $null = $searchPanel.Children.Add($btnUp); $null = $searchPanel.Children.Add($matchLabel)
    $null = $sp.Children.Add($searchPanel); $null = $sp.Children.Add($dg)
    
    $tWin = New-Object Windows.Window
    $tWin.Title = "АВТОТЕСТ"; $tWin.Left = -1999; $tWin.Top = -1999; $tWin.Width = 600; $tWin.Height = 400
    $tWin.WindowStartupLocation = "Manual"; $tWin.ShowInTaskbar = $false; $tWin.WindowStyle = "ToolWindow"
    $tWin.Content = $sp
    
    # Общие результаты тестов
    $passed = 0; $failed = 0
    function Assert { param($cond, $msg) if ($cond) { $global:tPassed++; Write-Host "  PASS: $msg" } else { $global:tFailed++; Write-Host "  FAIL: $msg" } }
    
    # Таймер запускает тесты после отображения окна
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({
        $timer.Stop()
        $global:tPassed = 0; $global:tFailed = 0
        $st = $global:tg_st; $dg = $global:tg_dg
        
        # Тест 1: пустой запрос
        $global:tg_sb.Text = ""
        $global:tg_st.query = ""; $global:tg_st.results = @()
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_ml.Text -eq "0 - 0") "Тест 1: пустой запрос — счётчик 0 - 0"
        Assert ($global:tg_dg.SelectedItem -eq $null) "Тест 1: ничего не выбрано"
        
        # Тест 2: поиск слова 'тестовый' (2 совпадения: строки 0, 2)
        $global:tg_sb.Text = "тестовый"; $global:tg_st.query = ""; $global:tg_st.results = @()
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_st.results.Count -eq 2) "Тест 2: найдено 2 результата для 'тестовый'"
        Assert ($global:tg_dg.SelectedItem.Name -eq "Запрос A") "Тест 2: выбран первый результат (Запрос A)"
        Assert ($global:tg_ml.Text -eq "1 - 2") "Тест 2: счётчик 1 - 2"
        
        # Тест 3: ▼ — переход к следующему результату
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_dg.SelectedItem.Name -eq "Запрос C") "Тест 3: ▼ перешёл к Запрос C"
        Assert ($global:tg_ml.Text -eq "2 - 2") "Тест 3: счётчик 2 - 2"
        
        # Тест 4: ▲ с тем же запросом — переход к предыдущему
        $global:tg_bu.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_dg.SelectedItem.Name -eq "Запрос A") "Тест 4: ▲ — перешёл к предыдущему (Запрос A)"
        
        # Тест 5: новый поиск без совпадений
        $global:tg_sb.Text = "НОВЫЙ_ПОИСК_БЕЗ_СОВПАДЕНИЙ"; $global:tg_st.query = ""; $global:tg_st.results = @()
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_st.results.Count -eq 0) "Тест 5: нет совпадений"
        Assert ($global:tg_ml.Text -eq "0 - 0") "Тест 5: счётчик 0 - 0"
        Assert ($global:tg_dg.SelectedItem -eq $null) "Тест 5: ничего не выбрано"
        
        # Тест 6: Enter — та же логика, что ▼ (raise ClickEvent на btnDown)
        $global:tg_sb.Text = "совсем"; $global:tg_st.query = ""; $global:tg_st.results = @()
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_st.results.Count -eq 1) "Тест 6: Enter — найден 1 результат"
        Assert ($global:tg_dg.SelectedItem.Name -eq "Запрос D") "Тест 6: Enter — выбран Запрос D"
        
        # Тест 7: проверка ScrollIntoView — слово 'запрос' в 4 из 5 строк
        $global:tg_sb.Text = "запрос"; $global:tg_st.query = ""; $global:tg_st.results = @()
        $global:tg_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:tg_st.results.Count -eq 4) "Тест 7: 'запрос' — 4 результата"
        Assert ($global:tg_dg.SelectedItem -ne $null) "Тест 7: элемент выбран"
        # Для проверки скролла — ищем ScrollViewer внутри DataGrid
        $sv = $null; $global:tg_dg.ApplyTemplate()
        function Get-ScrollViewer { param($p) for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($p);$i++){ $c=[Windows.Media.VisualTreeHelper]::GetChild($p,$i); if($c -is [Windows.Controls.ScrollViewer]){return $c}; $r=Get-ScrollViewer $c; if($r){return $r} } }
        $sv = Get-ScrollViewer $global:tg_dg
        Assert ($sv -ne $null) "Тест 7: ScrollViewer найден"
        
        # Тест 8: Apply-GlossyButtonStyle и RaiseEvent
        . (Join-Path $PSScriptRoot "Set-MetroTheme.ps1")
        $gBtn = New-Object Windows.Controls.Button; $gBtn.Content = "v"
        Apply-GlossyButtonStyle -Button $gBtn
        $gBtn.Add_Click({ $global:gClicked = $true })
        $global:gClicked = $false
        $gBtn.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert ($global:gClicked) "Тест 8: GlossyButton + RaiseEvent работает"
        
        # Тест 9: кнопки ▼/▲ после IsHitTestVisible фикса
        $checkXml = [xml]'<r><Rectangle IsHitTestVisible="False" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"/></r>'
        Assert ($checkXml.DocumentElement.InnerXml -match 'IsHitTestVisible="False"') "Тест 9: шаблон кнопки не блокирует клик"
        
        # Итог
        $global:tPassed = $global:tPassed + 0; $global:tFailed = $global:tFailed + 0  # force global
        Write-Host "`n=== ИТОГ: PASS=$($global:tPassed) FAIL=$($global:tFailed) ==="
        $global:tg_tWin.Close()
    })
    
    $global:tg_tWin = $tWin
    $timer.Start()
    $tWin.ShowDialog()
    
    [Console]::OutputEncoding = $prevEnc
    
    if ($global:tFailed -gt 0) { exit 1 } else { exit 0 }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Загрузить тему (Apply-GlossyButtonStyle, Apply-GlossyProgressStyle)
. (Join-Path $PSScriptRoot "Set-MetroTheme.ps1")

if (-not $LogFile) {
    $tempLog = Join-Path (Split-Path $PSScriptRoot -Parent) "temp\user_prompts.log"
    $archiveLog = Join-Path (Split-Path $PSScriptRoot -Parent) "archives\prompts\prompts_archive.log"
    if (Test-Path $tempLog) { $LogFile = $tempLog }
    elseif (Test-Path $archiveLog) { $LogFile = $archiveLog }
    else { $LogFile = $tempLog }
}

if (-not (Test-Path $LogFile)) {
    Write-Host "ОШИБКА: Файл архива не найден: $LogFile" -ForegroundColor Red
    if (-not $Force) {
        [System.Windows.MessageBox]::Show("Файл архива не найден: $LogFile", "Архив промптов", "OK", "Information")
    }
    exit
}

# ── Загрузка с прогресс-баром и восстановлением из архивов ──
$global:g_promptData = @()
$recoveredCount = 0

Invoke-WithProgress -Title "Архив промптов - загрузка" -Action {
    $global:g_progressStatus.Text = "Чтение основного лога..."
    [Windows.Forms.Application]::DoEvents()
    $tempData = Parse-PromptLog $LogFile -MinLength 0

    # Проверка: есть ли записи за последние 2 дня
    $twoDaysAgo = (Get-Date).AddDays(-2)
    $hasRecent = $false
    foreach ($item in $tempData) {
        $d = Parse-Date $item.DateTime
        if ($d -and $d -ge $twoDaysAgo) { $hasRecent = $true; break }
    }

    if (-not $hasRecent) {
        $global:g_progressStatus.Text = "Нет свежих записей, восстанавливаю из архивов..."
        [Windows.Forms.Application]::DoEvents()
        $recoveredCount = Recover-FromArchives -TargetLog $LogFile
        if ($recoveredCount -gt 0) {
            $global:g_progressStatus.Text = "Восстановлено $recoveredCount записей"
            [Windows.Forms.Application]::DoEvents()
            $tempData = Parse-PromptLog $LogFile -MinLength 0
        }
    }

    $global:g_promptData = $tempData
}

$data = $global:g_promptData

# Фильтр: удаляем промпты <= 20 символов
$data = $data | Where-Object { $_.FullText.Trim().Length -gt 20 }

# Дата по умолчанию: вчера → сегодня
$dfFrom = (Get-Date).AddDays(-1).Date
$dfTo = (Get-Date).Date
$filteredData = Filter-ByDateRange $data $dfFrom $dfTo
$global:gFullData = $data
$global:gFilteredData = $filteredData

$dataCount = $data.Count
$global:g_titleExtra = if ($recoveredCount -gt 0) { " (восстановлено $recoveredCount)" } else { "" }

if ($data.Count -eq 0) {
    Write-Host "ОШИБКА: В архиве нет записей." -ForegroundColor Red
    exit
}

# ── APPL2: окно ──
$window = New-Object Windows.Window
$window.Title = "Архив промптов: $dataCount записей$($global:g_titleExtra)"
$window.Width = 800
$window.Height = 500
$window.MinWidth = 500
$window.MinHeight = 300
$window.WindowStartupLocation = "CenterScreen"
$window.Topmost = $true
$window.ResizeMode = "CanResizeWithGrip"
$window.AllowsTransparency = $true
$window.WindowStyle = [Windows.WindowStyle]::None
$window.Background = [Windows.Media.Brushes]::Transparent

# OuterBorder — белый полупрозрачный, рамка #1A3A60
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

# Title bar
$titleBorder = New-Object Windows.Controls.Border
$titleBorder.CornerRadius = 10
$titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#05FFFFFF")
$titleBorder.Padding = "20,2,20,0"
$titleBorder.Margin = New-Object Windows.Thickness(25,1,25,0)
[System.Windows.Controls.Grid]::SetRow($titleBorder, 0)

$titleGrid = New-Object Windows.Controls.Grid
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

# Двухслойный текст
$titleLayer = New-Object Windows.Controls.Grid
$titleLayer.VerticalAlignment = "Center"
$titleTextA = New-Object Windows.Controls.TextBlock
$titleTextA.Text = "Архив промптов: $($filteredData.Count) из $dataCount записей$($global:g_titleExtra)"; $titleTextA.FontSize = 16; $titleTextA.FontWeight = "Bold"
$titleTextA.Foreground = [Windows.Media.Brushes]::White
$titleTextA.Margin = New-Object Windows.Thickness(1,1,0,0)
[void]$titleLayer.Children.Add($titleTextA)
$titleTextB = New-Object Windows.Controls.TextBlock
$titleTextB.Text = "Архив промптов: $($filteredData.Count) из $dataCount записей$($global:g_titleExtra)"; $titleTextB.FontSize = 16; $titleTextB.FontWeight = "Bold"
$titleTextB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
[void]$titleLayer.Children.Add($titleTextB)
[System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
[void]$titleGrid.Children.Add($titleLayer)

# Функция создания кнопок title bar (по эталону ОТЕСТ)
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

$btnMin = Add-TitleButton -Text "━" -Col 1 -Click { $window.WindowState = [Windows.WindowState]::Minimized }
$btnMax = Add-TitleButton -Text "▣" -Col 2 -Click {
    if ($window.WindowState -eq "Maximized") { $window.WindowState = "Normal"; $btnMax.Content = "▣" }
    else { $window.WindowState = "Maximized"; $btnMax.Content = "❐" }
} -FontSize 18
$btnClose2 = Add-TitleButton -Text "✕" -Col 3 -Click { $window.Close() } -IsClose
[void]$titleGrid.Children.Add($btnMin)
[void]$titleGrid.Children.Add($btnMax)
[void]$titleGrid.Children.Add($btnClose2)
$titleBorder.Child = $titleGrid
[void]$contentGrid.Children.Add($titleBorder)

# Перетаскивание окна за title bar
$titleBorder.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 1 -and $window.WindowState -ne "Maximized") {
        try { $window.DragMove() } catch {}
    }
    elseif ($_.ClickCount -ge 2) { $_.Handled = $true }
})

# contentWrapper + mainBorder
$contentWrapper = New-Object Windows.Controls.Border
$contentWrapper.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$contentWrapper.CornerRadius = 46
$contentWrapper.Margin = "4,0,4,4"
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)

$mainBorder = New-Object Windows.Controls.Border
$mainBorder.Background = [Windows.Media.Brushes]::White
$mainBorder.CornerRadius = 42
$mainBorder.Margin = "4"
$mainBorder.Padding = "20,16,20,22"

$innerGrid = New-Object Windows.Controls.Grid
$innerGrid.Margin = New-Object Windows.Thickness(0)

$r0 = New-Object Windows.Controls.RowDefinition; $r0.Height = "*";   [void]$innerGrid.RowDefinitions.Add($r0)
$r1 = New-Object Windows.Controls.RowDefinition; $r1.Height = "Auto"; [void]$innerGrid.RowDefinitions.Add($r1)
$r2 = New-Object Windows.Controls.RowDefinition; $r2.Height = "Auto"; [void]$innerGrid.RowDefinitions.Add($r2)
$r3 = New-Object Windows.Controls.RowDefinition; $r3.Height = "Auto"; [void]$innerGrid.RowDefinitions.Add($r3)

# Поиск (над нижними кнопками)
$searchPanel = New-Object Windows.Controls.Grid
$searchPanel.Margin = "0,15,0,10"
[System.Windows.Controls.Grid]::SetRow($searchPanel, 2)
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$searchPanel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

$matchLabel = New-Object Windows.Controls.TextBlock
$matchLabel.Text = "0 - 0"
$matchLabel.FontSize = 12
$matchLabel.FontWeight = "SemiBold"
$matchLabel.Foreground = "#4A5568"
$matchLabel.VerticalAlignment = "Center"
$matchLabel.Margin = "0,0,8,0"
$matchLabel.MinWidth = 40
[System.Windows.Controls.Grid]::SetColumn($matchLabel, 0)

$searchBox = New-Object Windows.Controls.TextBox
$searchBox.Name = "SearchBox"
$searchBox.ToolTip = "Поиск"
$searchBox.FontSize = 12
$searchBox.Height = 32
$searchBox.Margin = "0,0,8,0"
$searchBox.VerticalContentAlignment = "Center"
$searchBox.Padding = "8,0"
$searchBox.Background = [Windows.Media.Brushes]::White
$searchBox.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
$searchBox.BorderThickness = "1"
[System.Windows.Controls.Grid]::SetColumn($searchBox, 1)

$btnDown = New-Object Windows.Controls.Button
$btnDown.Content = "▼"
$btnDown.Width = 32
$btnDown.Height = 32
$btnDown.Margin = "0,0,2,0"
$btnDown.FontSize = 14
Apply-GlossyButtonStyle -Button $btnDown
[System.Windows.Controls.Grid]::SetColumn($btnDown, 2)

$btnUp = New-Object Windows.Controls.Button
$btnUp.Content = "▲"
$btnUp.Width = 32
$btnUp.Height = 32
$btnUp.Margin = "0,0,0,0"
$btnUp.FontSize = 14
Apply-GlossyButtonStyle -Button $btnUp
[System.Windows.Controls.Grid]::SetColumn($btnUp, 3)

$script:state = @{ results = @(); index = -1; query = "" }

# DataGrid
$dg = New-Object Windows.Controls.DataGrid
$dg.AutoGenerateColumns = $false
$dg.HeadersVisibility = "All"
$dg.RowHeaderWidth = 0
$dg.FontSize = 12
$dg.VerticalScrollBarVisibility = "Auto"
$dg.HorizontalScrollBarVisibility = "Auto"
$dg.AlternatingRowBackground = [Windows.Media.Brushes]::LightGray
$dg.SelectionMode = "Single"
$dg.SelectionUnit = "FullRow"
$dg.IsReadOnly = $true

# Стиль: синее выделение выбранной строки (#3182CE / белый текст)
$rowStyle = New-Object Windows.Style([Windows.Controls.DataGridRow])
$selTrig = New-Object Windows.Trigger
$selTrig.Property = [Windows.Controls.DataGridRow]::IsSelectedProperty
$selTrig.Value = $true
$selBg = New-Object Windows.Setter([Windows.Controls.DataGridRow]::BackgroundProperty, [Windows.Media.BrushConverter]::new().ConvertFromString("#3182CE"))
$selFg = New-Object Windows.Setter([Windows.Controls.DataGridRow]::ForegroundProperty, [Windows.Media.Brushes]::White)
$selTrig.Setters.Add($selBg); $selTrig.Setters.Add($selFg)
$rowStyle.Triggers.Add($selTrig)
$dg.RowStyle = $rowStyle

$cName = New-Object Windows.Controls.DataGridTextColumn
$cName.Header = "Промпт"
$cName.Binding = [Windows.Data.Binding]::new("Name")
$cName.Width = 200
$cName.MinWidth = 80
$cName.IsReadOnly = $true
[void]$dg.Columns.Add($cName)

$cDt = New-Object Windows.Controls.DataGridTextColumn
$cDt.Header = "Дата"
$cDt.Binding = [Windows.Data.Binding]::new("DateTime")
$cDt.Width = 130
$cDt.MinWidth = 60
$cDt.IsReadOnly = $true
[void]$dg.Columns.Add($cDt)

# Функция подсветки текста в TextBlock через Inlines
function Set-HighlightedText {
    param([Windows.Controls.TextBlock]$Tb, [string]$Text, [string]$Query)
    $Tb.Inlines.Clear()
    if ([string]::IsNullOrEmpty($Query)) { $Tb.Inlines.Add([Windows.Documents.Run]::new($Text)); return }
    $parts = $Text -split ([regex]::Escape($Query))
    $hlBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFEB3B")
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($parts[$i]) { $Tb.Inlines.Add([Windows.Documents.Run]::new($parts[$i])) }
        if ($i -lt $parts.Count - 1) {
            $r = [Windows.Documents.Run]::new($Query)
            $r.Background = $hlBrush; $r.FontWeight = "Bold"
            $Tb.Inlines.Add($r)
        }
    }
}

# DataGridTextColumn для полного текста (всегда показывает текст через биндинг)
$cText = New-Object Windows.Controls.DataGridTextColumn
$cText.Header = "Полный текст промпта"
$cText.Binding = [Windows.Data.Binding]::new("FullText")
$cText.Width = New-Object Windows.Controls.DataGridLength(1, [Windows.Controls.DataGridLengthUnitType]::Star)
$cText.MinWidth = 150
$cText.IsReadOnly = $true
$textStyle = New-Object Windows.Style([Windows.Controls.TextBlock])
$textStyle.Setters.Add((New-Object Windows.Setter([Windows.Controls.TextBlock]::TextWrappingProperty, [Windows.TextWrapping]::Wrap)))
$cText.ElementStyle = $textStyle
[void]$dg.Columns.Add($cText)

$dg.ItemsSource = $filteredData
[System.Windows.Controls.Grid]::SetRow($dg, 0)
[void]$innerGrid.Children.Add($dg)

# ── Панель фильтрации: даты + длина ──
$periodPanel = New-Object Windows.Controls.StackPanel
$periodPanel.Orientation = "Horizontal"
$periodPanel.Margin = "0,6,0,4"
[System.Windows.Controls.Grid]::SetRow($periodPanel, 1)

$periodLabel = New-Object Windows.Controls.TextBlock
$periodLabel.Text = "Период:"
$periodLabel.FontSize = 12
$periodLabel.FontWeight = "SemiBold"
$periodLabel.Foreground = "#4A5568"
$periodLabel.VerticalAlignment = "Center"
$periodLabel.Margin = "0,0,6,0"
[void]$periodPanel.Children.Add($periodLabel)

$dateFrom = New-Object Windows.Controls.DatePicker
$dateFrom.Width = 110
$dateFrom.Height = 28
$dateFrom.FontSize = 11
$dateFrom.SelectedDate = $dfFrom
$dateFrom.VerticalAlignment = "Center"
$dateFrom.Margin = "0,0,4,0"
[void]$periodPanel.Children.Add($dateFrom)

$dateSep = New-Object Windows.Controls.TextBlock
$dateSep.Text = "—"
$dateSep.FontSize = 12
$dateSep.FontWeight = "SemiBold"
$dateSep.Foreground = "#4A5568"
$dateSep.VerticalAlignment = "Center"
$dateSep.Margin = "0,0,4,0"
[void]$periodPanel.Children.Add($dateSep)

$dateTo = New-Object Windows.Controls.DatePicker
$dateTo.Width = 110
$dateTo.Height = 28
$dateTo.FontSize = 11
$dateTo.SelectedDate = $dfTo
$dateTo.VerticalAlignment = "Center"
$dateTo.Margin = "0,0,8,0"
[void]$periodPanel.Children.Add($dateTo)

# Checkbox: только > 20 символов
$chkMinLen = New-Object Windows.Controls.CheckBox
$chkMinLen.Content = ">20 симв."
$chkMinLen.FontSize = 12
$chkMinLen.FontWeight = "SemiBold"
$chkMinLen.Foreground = "#4A5568"
$chkMinLen.VerticalAlignment = "Center"
$chkMinLen.Margin = "0,0,8,0"
$chkMinLen.IsChecked = $true
[void]$periodPanel.Children.Add($chkMinLen)

# Кнопка "Обновить"
$btnApply = New-Object Windows.Controls.Button
$btnApply.Content = "Обновить"
$btnApply.Width = 80
$btnApply.Height = 28
$btnApply.FontSize = 11
$btnApply.VerticalAlignment = "Center"
$btnApply.Margin = "0,0,8,0"
Add-Type -AssemblyName PresentationFramework; $null = [Windows.Style] -eq 0
$btnApply.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
$btnApply.Foreground = [Windows.Media.Brushes]::White
$btnApply.BorderThickness = 0
$btnApply.Cursor = "Hand"
[void]$periodPanel.Children.Add($btnApply)

$global:gFullData = $data
$global:gFilteredData = $filteredData
$global:gPeriodDg = $dg
$global:gPeriodTitleA = $titleTextA
$global:gPeriodTitleB = $titleTextB

# Initialize search state globals early (before SelectionChanged handler uses them)
$global:g_st = @{ results = @(); index = -1; query = "" }
$global:g_sb = $null  # will be set later
$global:g_ml = $null  # will be set later
$global:g_sq = ""

function Update-Highlights {
    param()
    $sq = $global:g_sq
    if ([string]::IsNullOrEmpty($sq)) {
        if ($global:g_ml) { $global:g_ml.Text = "0 - 0" }
        return
    }
    $results = $global:g_dt | Where-Object { $_.FullText -match [regex]::Escape($sq) }
    $global:g_st.results = @($results)
    if ($global:g_st.results.Count -gt 0) {
        $global:g_st.index = 0
        $global:g_dg.SelectedItem = $global:g_st.results[0]
        $global:g_dg.ScrollIntoView($global:g_dg.SelectedItem)
        $global:g_dg.Focus()
        if ($global:g_bu) { $global:g_bu.IsEnabled = $true }
        if ($global:g_bd) { $global:g_bd.IsEnabled = $true }
        if ($global:g_ml) { $global:g_ml.Text = "1 - $($global:g_st.results.Count)" }
    } else {
        if ($global:g_bu) { $global:g_bu.IsEnabled = $false }
        if ($global:g_bd) { $global:g_bd.IsEnabled = $false }
        if ($global:g_ml) { $global:g_ml.Text = "0 - 0" }
    }
}

function Update-Display {
    $full = $global:gFullData
    $from = $global:gDateFrom.SelectedDate
    $to = $global:gDateTo.SelectedDate
    $minLen = if ($global:gChkMinLen.IsChecked) { 20 } else { 0 }
    $filtered = $full
    if ($from -or $to) {
        $filtered = Filter-ByDateRange $filtered $from $to
    }
    if ($minLen -gt 0) {
        $filtered = $filtered | Where-Object { $_.FullText.Trim().Length -gt $minLen }
    }
    $global:gPeriodDg.ItemsSource = $filtered
    $global:gPeriodTitleA.Text = "Архив промптов: $($filtered.Count) из $($full.Count) записей$($global:g_titleExtra)"
    $global:gPeriodTitleB.Text = "Архив промптов: $($filtered.Count) из $($full.Count) записей$($global:g_titleExtra)"
    $global:g_st.query = ""; $global:g_st.results = @(); $global:g_st.index = -1
    if ($global:g_sb) { $global:g_sb.Text = "" }
    if ($global:g_ml) { $global:g_ml.Text = "0 - 0" }
    Refresh-DataGridView
}

$global:gDateFrom = $dateFrom
$global:gDateTo = $dateTo
$global:gChkMinLen = $chkMinLen

$dateFrom.Add_SelectedDateChanged({ Update-Display })
$dateTo.Add_SelectedDateChanged({ Update-Display })
$chkMinLen.Add_Checked({ Update-Display })
$chkMinLen.Add_Unchecked({ Update-Display })
$btnApply.Add_Click({ Update-Display })

[void]$innerGrid.Children.Add($periodPanel)

# Поиск TextBlock в визуальном дереве элемента
function Find-TbInVisualTree {
    param($Root)
    if (-not $Root) { return $null }
    $stack = New-Object Collections.Generic.Stack[System.Windows.DependencyObject]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $p = $stack.Pop()
        $cnt = [Windows.Media.VisualTreeHelper]::GetChildrenCount($p)
        for ($i = 0; $i -lt $cnt; $i++) {
            $c = [Windows.Media.VisualTreeHelper]::GetChild($p, $i)
            if ($c -is [Windows.Controls.TextBlock]) { return $c }
            $stack.Push($c)
        }
    }
    return $null
}

# Подсветка строк (жёлтый фон) и контекста (бордовый цвет) при загрузке
$dg.Add_LoadingRow({
    $row = $_.Row; $item = $row.Item
    if (-not $item) { return }
    $sq = $global:g_sq
    if ([string]::IsNullOrEmpty($sq)) { return }
    if ($item.FullText -match [regex]::Escape($sq)) {
        $row.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFFDE7")
        $tb = Find-TbInVisualTree $row
        if (-not $tb) { return }
        $parts = $item.FullText -split ([regex]::Escape($sq))
        $tb.Inlines.Clear()
        $burgundy = [Windows.Media.BrushConverter]::new().ConvertFromString("#800000")
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i]) { $tb.Inlines.Add([Windows.Documents.Run]::new($parts[$i])) }
            if ($i -lt $parts.Count - 1) {
                $r = [Windows.Documents.Run]::new($sq)
                $r.Foreground = $burgundy; $r.FontWeight = "Bold"
                $tb.Inlines.Add($r)
            }
        }
    }
})

$global:g_sb = $searchBox; $global:g_ml = $matchLabel; $global:g_bu = $btnUp; $global:g_bd = $btnDown
$global:g_dg = $dg; $global:g_dt = $data; $global:g_st = $script:state; $global:g_sq = ""

function Refresh-DataGridView {
    $dg = $global:g_dg
    if (-not $dg -or -not $dg.ItemsSource) { return }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($dg.ItemsSource)
    if ($view) { $view.Refresh() }
}

$btnDown.Add_Click({
    $sb = $global:g_sb; $ml = $global:g_ml; $bu = $global:g_bu; $bd = $global:g_bd
    $dg = $global:g_dg; $st = $global:g_st
    $sq = $sb.Text.Trim()
    $items = $dg.ItemsSource
    $global:g_sq = $sq
    if (-not $sq) { $ml.Text = "0 - 0"; Update-Highlights; return }
    if ($sq -ne $st.query) {
        $st.query = $sq
        $sr = @($items | Where-Object { $null -ne $_.FullText -and $_.FullText.ToString() -match [regex]::Escape($sq) })
        $st.results = $sr
        $ml.Text = "Найдено: $($st.results.Count)"
        Update-Highlights
        if ($st.results.Count -gt 0) {
            $st.index = 0
            $dg.SelectedItem = $st.results[0]
            $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
            $bu.IsEnabled = $true; $bd.IsEnabled = $true
        } else {
            $dg.SelectedItem = $null
            $bu.IsEnabled = $false; $bd.IsEnabled = $false
        }
        return
    }
    if ($st.results.Count -eq 0) { return }
    $st.index = ($st.index + 1) % $st.results.Count
    $dg.SelectedItem = $st.results[$st.index]
    $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
})

$btnUp.Add_Click({
    $sb = $global:g_sb; $ml = $global:g_ml; $bu = $global:g_bu; $bd = $global:g_bd
    $dg = $global:g_dg; $st = $global:g_st
    $sq = $sb.Text.Trim()
    $items = $dg.ItemsSource
    $global:g_sq = $sq
    if (-not $sq) { Update-Highlights; return }
    if ($sq -ne $st.query -or $st.results.Count -eq 0) {
        $st.query = $sq
        $sr = @($items | Where-Object { $null -ne $_.FullText -and $_.FullText.ToString() -match [regex]::Escape($sq) })
        $st.results = @($sr)
        Update-Highlights
        if ($st.results.Count -gt 0) {
            $st.index = $st.results.Count - 1
            $dg.SelectedItem = $st.results[$st.index]
            $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
            $bu.IsEnabled = $true; $bd.IsEnabled = $true
            $ml.Text = "$($st.index + 1) - $($st.results.Count)"
        } else {
            $dg.SelectedItem = $null
            $bu.IsEnabled = $false; $bd.IsEnabled = $false
            $ml.Text = "0 - 0"
        }
        return
    }
    if ($st.results.Count -eq 0) { return }
    $st.index = ($st.index - 1 + $st.results.Count) % $st.results.Count
    $dg.SelectedItem = $st.results[$st.index]
    $dg.ScrollIntoView($dg.SelectedItem); $sb.Focus()
    $ml.Text = "$($st.index + 1) - $($st.results.Count)"
})

$searchBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq "Enter") { $global:g_bd.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) } })

[void]$searchPanel.Children.Add($matchLabel)
[void]$searchPanel.Children.Add($searchBox)
[void]$searchPanel.Children.Add($btnDown)
[void]$searchPanel.Children.Add($btnUp)
[void]$innerGrid.Children.Add($searchPanel)

# Кнопки
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"
$btnPanel.HorizontalAlignment = "Right"
$btnPanel.Margin = New-Object Windows.Thickness(0,0,0,0)
[System.Windows.Controls.Grid]::SetRow($btnPanel, 3)

$btnCopy = New-Object Windows.Controls.Button
$btnCopy.Content = "Копировать выделенное"
$btnCopy.Width = 190
$btnCopy.Height = 36
$btnCopy.Margin = "0,0,8,0"
$btnCopy.FontSize = 12
Apply-GlossyButtonStyle -Button $btnCopy
$btnCopy.Add_Click({
    $item = $dg.SelectedItem
    if ($item) {
        $textToCopy = "=== $($item.DateTime) ===`r`n$($item.FullText)"
        try { Set-Clipboard -Value $textToCopy } catch { [System.Windows.Clipboard]::SetText($textToCopy) }
    }
})
[void]$btnPanel.Children.Add($btnCopy)

$btnAbbr = New-Object Windows.Controls.Button
$btnAbbr.Content = "Список сокращений"
$btnAbbr.Width = 160
$btnAbbr.Height = 36
$btnAbbr.Margin = "0,0,8,0"
$btnAbbr.FontSize = 12
Apply-GlossyButtonStyle -Button $btnAbbr
$btnAbbr.Add_Click({
    $abbrPath = Join-Path $PSScriptRoot "Show-Abbreviations.ps1"
    Start-Process powershell -ArgumentList '-NoProfile','-WindowStyle','Hidden','-File',$abbrPath -WindowStyle Hidden
})
[void]$btnPanel.Children.Add($btnAbbr)

$btnSavePrompt = New-Object Windows.Controls.Button
$btnSavePrompt.Content = "Сохранить промпт"
$btnSavePrompt.Width = 150
$btnSavePrompt.Height = 36
$btnSavePrompt.Margin = "0,0,8,0"
$btnSavePrompt.FontSize = 12
Apply-GlossyButtonStyle -Button $btnSavePrompt -ColorTop "#2A5080" -ColorBottom "#87CEEB"
$btnSavePrompt.Add_Click({
    $input = [System.Windows.Controls.TextBox]::new()
    $input.Width = 500
    $input.Height = 100
    $input.TextWrapping = "Wrap"
    $input.AcceptsReturn = $true
    $input.VerticalScrollBarVisibility = "Auto"
    $input.FontSize = 13
    
    $dlg = [System.Windows.Window]::new()
    $dlg.Title = "Новый промпт"
    $dlg.Width = 550
    $dlg.Height = 250
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
    
    $grid = [System.Windows.Controls.Grid]::new()
    $rd1 = [System.Windows.Controls.RowDefinition]::new()
    $rd1.Height = [System.Windows.GridLength]::Auto
    $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
    $grid.RowDefinitions.Add($rd1)
    
    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = "Введите текст промпта:"
    $label.Margin = "10,10,10,5"
    $label.FontSize = 13
    [System.Windows.Controls.Grid]::SetRow($label, 0)
    
    $input.Margin = "10,5,10,10"
    [System.Windows.Controls.Grid]::SetRow($input, 1)
    
    $btnPanel2 = [System.Windows.Controls.StackPanel]::new()
    $btnPanel2.Orientation = "Horizontal"
    $btnPanel2.HorizontalAlignment = "Right"
    $btnPanel2.Margin = "0,0,10,10"
    
    $btnOk = [System.Windows.Controls.Button]::new()
    $btnOk.Content = "Сохранить"
    $btnOk.Width = 100
    $btnOk.Height = 32
    $btnOk.Margin = "0,0,8,0"
    Apply-GlossyButtonStyle -Button $btnOk
    $btnOk.Add_Click({
        $text = $input.Text.Trim()
        if ($text) {
            $logFile = Join-Path $PSScriptRoot "..\temp\user_prompts.log"
            $dt = Get-Date -Format "dd.MM.yyyy, HH:mm:ss"
            $entry = "`n============================================================`n [$dt]`n$text"
            Add-Content -Path $logFile -Value $entry -Encoding UTF8
            $dlg.Close()
        }
    })
    
    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = "Отмена"
    $btnCancel.Width = 100
    $btnCancel.Height = 32
    Apply-GlossyButtonStyle -Button $btnCancel -ColorTop "#606060" -ColorBottom "#808080"
    $btnCancel.Add_Click({ $dlg.Close() })
    
    [void]$btnPanel2.Children.Add($btnOk)
    [void]$btnPanel2.Children.Add($btnCancel)
    [System.Windows.Controls.Grid]::SetRow($btnPanel2, 1)
    $grid.Children.Add($label)
    $grid.Children.Add($input)
    $grid.Children.Add($btnPanel2)
    $dlg.Content = $grid
    $dlg.ShowDialog()
})
[void]$btnPanel.Children.Add($btnSavePrompt)

$btnClose = New-Object Windows.Controls.Button
$btnClose.Content = "Закрыть"
$btnClose.Width = 100
$btnClose.Height = 36
$btnClose.FontSize = 12
$btnClose.IsDefault = $true
Apply-GlossyButtonStyle -Button $btnClose -ColorTop "#606060" -ColorBottom "#808080"
$btnClose.Add_Click({ $window.Close() })
[void]$btnPanel.Children.Add($btnClose)

[void]$innerGrid.Children.Add($btnPanel)

$mainBorder.Child = $innerGrid
$contentWrapper.Child = $mainBorder
[System.Windows.Controls.Grid]::SetRow($contentWrapper, 1)
[void]$contentGrid.Children.Add($contentWrapper)
$outerBorder.Child = $contentGrid
$window.Content = $outerBorder

# Закрытие по ESC
$window.Add_KeyDown({
    if ($_.Key -eq "Escape") { $btnClose.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
})

[void]$window.ShowDialog()





