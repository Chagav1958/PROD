<#
.SYNOPSIS
    ПРОДОБР — Диалог продолжения обработки (СТАНДАРТ2, v3)
.DESCRIPTION
    Показывает задачу, прогресс-бары, кнопки След.этап/Автопереход.
    Автотест отдельно в AutoTest-ProdObr.py.
.NOTES
    Bug-115: Process.add_Exited кросс-потоковый crash → ObrTimer вместо него.
#>
param(
    [string]$TaskName = ""
)

$script:ProjectRoot = if ($PSScriptRoot -match '[\\/]scripts$') { Split-Path $PSScriptRoot -Parent } else { "C:\AIS\AI\Prod" }
. (Join-Path $script:ProjectRoot "scripts\Standard2-Helpers.ps1")

$script:PythonExe      = Join-Path $script:ProjectRoot "scripts\ais_objects_mcp\.venv\Scripts\python.exe"
$script:AnalyzeScript  = Join-Path $script:ProjectRoot "scripts\analyze_batch.py"
$script:TasksRoot      = Join-Path $script:ProjectRoot "tasks"
$script:pyProc         = $null
$script:ObrTimer       = $null
$script:ObrRetries     = 0
$script:CurrentLib     = ""
$script:CurrentKind    = "PB"

# ===== Tech Journal =====
function Write-TJ {
    param([string]$Level, [string]$Msg)
    try {
        $line = "[{0:HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Msg
        if (-not $script:TJPath) {
            $script:TJPath = Join-Path $env:TEMP "prodobr_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        }
        Add-Content -Path $script:TJPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

# ===== Поиск задачи =====
function Find-Task {
    $tasksDir = $script:TasksRoot
    if ($TaskName) {
        $f = Join-Path $tasksDir $TaskName
        if (-not (Test-Path $f)) {
            $alt = Get-ChildItem $tasksDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$TaskName*" } | Select-Object -First 1
            if ($alt) { $f = $alt.FullName }
        }
        if ((Test-Path $f) -and (Test-Path (Join-Path $f "ПЛАН_РЕАЛИЗАЦИИ.txt"))) { return $f }
    }
    foreach ($d in Get-ChildItem $tasksDir -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path (Join-Path $d.FullName "ПЛАН_РЕАЛИЗАЦИИ.txt")) { return $d.FullName }
    }
    return $null
}

# ===== Получить следующую библиотеку (через SQLite) =====
function Get-NextLib {
    try {
        $pyCode = @"
import sys; sys.path.insert(0, r'$($script:ProjectRoot)\scripts\ais_objects_mcp')
from server import get_db
db = get_db()
    for lib in sorted(set(r[0] for r in db.execute("SELECT DISTINCT lib FROM objects WHERE kind='PB' AND src='current' AND lib != ''").fetchall())):
    total = db.execute("SELECT count(*) FROM objects WHERE kind='PB' AND src='current' AND lib=?", (lib,)).fetchone()[0]
    done  = db.execute("SELECT count(DISTINCT o.id) FROM objects o JOIN object_analyses a ON a.object_id=o.id WHERE o.kind='PB' AND o.src='current' AND o.lib=? AND a.tags LIKE '%auto_analysis%'", (lib,)).fetchone()[0]
    if done < total: print(f"PB|{lib}|{total-done}"); db.close(); sys.exit(0)
for cat in ['Procedure','Functions','Triggers','Views','Tables','PK','FK','Grants','Indexes']:
    total = db.execute("SELECT count(*) FROM objects WHERE kind='SQL' AND src='current' AND lib=?", (cat,)).fetchone()[0]
    done  = db.execute("SELECT count(DISTINCT o.id) FROM objects o JOIN object_analyses a ON a.object_id=o.id WHERE o.kind='SQL' AND o.src='current' AND o.lib=? AND a.tags LIKE '%auto_analysis%'", (cat,)).fetchone()[0]
    if done < total: print(f"SQL|{cat}|{total-done}"); db.close(); sys.exit(0)
db.close(); print("DONE")
"@
        $res = & $script:PythonExe -c $pyCode 2>$null
        if ($res -and $res -ne "DONE") {
            $parts = $res -split '\|'
            return @{ Kind = $parts[0]; Library = $parts[1]; Remaining = [int]$parts[2] }
        }
    } catch {}
    return $null
}

# ===== Запуск анализа =====
function Start-Analysis {
    param($Library, $Kind)
    try {
        if ($script:pyProc) { return }
        
        $script:CurrentLib = $Library
        $script:CurrentKind = $Kind
        Write-TJ "INFO" "Start: $Library ($Kind)"
        
        if ($script:PhaseLabel) { $script:PhaseLabel.Text = "Обработка: $Library" }
        if ($script:StepLabel) { $script:StepLabel.Text = "Запуск..." }
        if ($script:LibLabel) { $script:LibLabel.Text = "Тип: $Kind | Библиотека: $Library" }
        if ($script:PhaseBar) { $script:PhaseBar.IsIndeterminate = $true }
        if ($script:RunBtn) { $script:RunBtn.IsEnabled = $false }
        if ($script:NextBtn) { $script:NextBtn.IsEnabled = $false }
        
        $script:ObrRetries = 0
        $argList = @($script:AnalyzeScript, "--kind", $Kind, "--lib", $Library, "--limit", "100", "--offset", "0")
        
        $script:pyProc = New-Object System.Diagnostics.Process
        $script:pyProc.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $script:pyProc.StartInfo.FileName = $script:PythonExe
        $script:pyProc.StartInfo.Arguments = $argList -join ' '
        $script:pyProc.StartInfo.UseShellExecute = $false
        $script:pyProc.StartInfo.RedirectStandardOutput = $true
        $script:pyProc.StartInfo.CreateNoWindow = $true
        $script:pyProc.Start() | Out-Null
        
        if (-not $script:ObrTimer) {
            $script:ObrTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:ObrTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $script:ObrTimer.Add_Tick({
                param($s, $e)
                $script:ObrRetries += 1
                if ($script:pyProc -and $script:pyProc.HasExited) {
                    if ($script:ObrRetries -lt 2) { return }
                    $script:ObrTimer.Stop()
                    $script:pyProc.Dispose()
                    $script:pyProc = $null
                    Write-TJ "INFO" "Done: $($script:CurrentLib)"
                    On-Complete
                }
            })
        }
        $script:ObrTimer.Start()
    } catch {
        Write-TJ "ERROR" "Start: $_"
        if ($script:PhaseLabel) { $script:PhaseLabel.Text = "Ошибка: $_" }
        if ($script:RunBtn) { $script:RunBtn.IsEnabled = $true }
    }
}

function On-Complete {
    if ($script:PhaseBar) { $script:PhaseBar.IsIndeterminate = $false; $script:PhaseBar.Value = 100 }
    if ($script:StepBar)  { $script:StepBar.IsIndeterminate = $false; $script:StepBar.Value = 100 }
    if ($script:PhaseLabel) { $script:PhaseLabel.Text = "Готово: $($script:CurrentLib)" }
    if ($script:StepLabel)  { $script:StepLabel.Text  = "Анализ завершён" }
    if ($script:RunBtn)  { $script:RunBtn.IsEnabled = $true }
    if ($script:NextBtn) { $script:NextBtn.IsEnabled = $true }
    
    if ($script:CbAuto -and $script:CbAuto.IsChecked) {
        Start-Sleep -Seconds 1
        Invoke-NextStep
    }
}

function Invoke-NextStep {
    $libInfo = Get-NextLib
    if ($libInfo) {
        Start-Analysis -Library $libInfo.Library -Kind $libInfo.Kind
    } else {
        if ($script:PhaseLabel) { $script:PhaseLabel.Text = "Все объекты обработаны!" }
        if ($script:StepLabel)  { $script:StepLabel.Text  = "Нет незавершённых библиотек" }
        if ($script:NextBtn) { $script:NextBtn.IsEnabled = $false }
        Write-TJ "INFO" "ALL DONE"
    }
}

# ===== GUI =====
$window = New-Standard2Window -Title "ПРОДОБР" -Width 560 -Height 320
$script:MainWindow = $window

$grid = New-Object Windows.Controls.Grid
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

# Row 0: задача
$lblTask = New-Object Windows.Controls.TextBlock
$lblTask.Text = "Задача: поиск..."; $lblTask.FontSize = 13; $lblTask.FontWeight = "Bold"
$lblTask.Foreground = "#1A3A60"; $lblTask.Margin = "14,10,14,2"
[System.Windows.Controls.Grid]::SetRow($lblTask, 0)
[void]$grid.Children.Add($lblTask)
$script:TaskLabel = $lblTask

# Row 1: прогресс-бары
$pbPanel = New-Standard2ProgressBarPanel
$script:PhaseBar   = $pbPanel.Tag.PhaseBar
$script:PhaseLabel = $pbPanel.Tag.PhaseLabel
$script:StepBar    = $pbPanel.Tag.StepBar
$script:StepLabel  = $pbPanel.Tag.StepLabel
$script:PhaseLabel.Text = "Готов к запуску"
$script:StepLabel.Text  = "Нажмите 'Запустить обработку'"
[System.Windows.Controls.Grid]::SetRow($pbPanel, 1)
[void]$grid.Children.Add($pbPanel)

# Row 2: инфо-панель
$lblLib = New-Object Windows.Controls.TextBlock
$lblLib.Text = "Библиотека: —"; $lblLib.FontSize = 11; $lblLib.Foreground = "#4A5568"
$lblLib.Margin = "14,6,14,2"; $lblLib.TextWrapping = "Wrap"
[System.Windows.Controls.Grid]::SetRow($lblLib, 2)
[void]$grid.Children.Add($lblLib)
$script:LibLabel = $lblLib

# Row 3: кнопки
$btnPanel = New-Object Windows.Controls.StackPanel
$btnPanel.Orientation = "Horizontal"; $btnPanel.Margin = "10,6,10,10"

$btnRun = New-Object Windows.Controls.Button
$btnRun.Content = "Запустить обработку"; $btnRun.Width = 160; $btnRun.Height = 32
$btnRun.Background = "#1A3A60"; $btnRun.Foreground = "White"; $btnRun.FontSize = 12; $btnRun.FontWeight = "Bold"
$btnRun.Add_Click({
    try {
        if (-not $script:pyProc) {
            $libInfo = Get-NextLib
            if ($libInfo) {
                Start-Analysis -Library $libInfo.Library -Kind $libInfo.Kind
            } elseif ($script:PhaseLabel) {
                $script:PhaseLabel.Text = "Все объекты обработаны!"
            }
        }
    } catch {
        if ($script:PhaseLabel) { $script:PhaseLabel.Text = "Ошибка: $_" }
    }
})
$script:RunBtn = $btnRun
[void]$btnPanel.Children.Add($btnRun)

$btnNext = New-Object Windows.Controls.Button
$btnNext.Content = "След. этап"; $btnNext.Width = 100; $btnNext.Height = 32
$btnNext.Background = "#2D7D46"; $btnNext.Foreground = "White"; $btnNext.FontSize = 12; $btnNext.FontWeight = "Bold"
$btnNext.Margin = "8,0,0,0"
$btnNext.IsEnabled = $false
$btnNext.Add_Click({ Invoke-NextStep })
$script:NextBtn = $btnNext
[void]$btnPanel.Children.Add($btnNext)

$cbAuto = New-Object Windows.Controls.CheckBox
$cbAuto.Content = "Автопереход"; $cbAuto.IsChecked = $false; $cbAuto.FontSize = 11
$cbAuto.Foreground = "#2D3748"; $cbAuto.VerticalAlignment = "Center"; $cbAuto.Margin = "12,0,0,0"
$script:CbAuto = $cbAuto
[void]$btnPanel.Children.Add($cbAuto)

# Spacer
$spacer = New-Object Windows.Controls.TextBlock
$spacer.Width = 20
[void]$btnPanel.Children.Add($spacer)

$btnExit = New-Object Windows.Controls.Button
$btnExit.Content = "Закрыть"; $btnExit.Width = 80; $btnExit.Height = 32
$btnExit.Background = "#A0AEC0"; $btnExit.Foreground = "White"; $btnExit.FontSize = 12
$btnExit.HorizontalAlignment = "Right"
$btnExit.Add_Click({ Write-TJ "INFO" "User closed"; $script:MainWindow.Close() })
[void]$btnPanel.Children.Add($btnExit)

[System.Windows.Controls.Grid]::SetRow($btnPanel, 3)
[void]$grid.Children.Add($btnPanel)

$content = New-Standard2Wrapper -Window $window -Content $grid -Title "ПРОДОБР"
$window.Content = $content
$window.Add_Loaded({
    $d = Find-Task
    if ($d) { $script:TaskLabel.Text = "Задача: " + (Split-Path $d -Leaf) }
    else    { $script:TaskLabel.Text = "Задача: не найдена" }
})
$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $script:MainWindow.Close() } })

Write-TJ "INFO" "GUI started"
Add-Type -AssemblyName PresentationFramework
$window.ShowDialog() | Out-Null
Write-TJ "INFO" "GUI closed"
