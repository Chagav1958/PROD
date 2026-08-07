<#
.SYNOPSIS
    МОРДА — Главное окно GUI для подготовки релизов AIS (СТАНДАРТ2)
.DESCRIPTION
    WPF-интерфейс по СТАНДАРТ2 (Show-Appl2Standard). Все 19 операций,
    панель параметров, запуск через temp-скрипт, ДО результата.
    tech_journal + --autotest.
.NOTES
    Версия: 2.0 (СТАНДАРТ2)
#>

# --- ИМПОРТ ХЕЛПЕРОВ СТАНДАРТ2 ---
. "C:\AIS\AI\Prod\scripts\Standard2-Helpers.ps1"
. "C:\AIS\AI\Prod\scripts\Settings-Module.ps1"
. "C:\AIS\AI\Prod\scripts\Background-Runner.ps1"

# --- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ---
$script:ScriptArgs = @($args)
$script:ProjectRoot = if ($PSScriptRoot -match '[\\/]bin$') { Split-Path $PSScriptRoot -Parent } else { 'C:\AIS\AI\Prod' }
$script:ConfigPath = Join-Path $script:ProjectRoot "config\config.json"
$script:LogFile = Join-Path $env:TEMP "morda_st2_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:TechJournal = @()
$script:AutoTestCommands = @()
$script:AutoTestFile = ""
$script:AutoTestIndex = 0
$script:IsAutoTest = $false
$script:MainButtons = @{}
$script:ParamsFields = @()
$script:SelectedOpIndex = -1
$script:currentProcess = $null

# Прогресс-бары (глобальные переменные для обновления из операций)
$script:PhaseProgress = @{ Value = 0; Text = "" }
$script:StepProgress = @{ Value = 0; Text = "" }

# VSS defaults (из config.json)
$script:vssDefaults = @{ user = "User"; db_path = ""; project = "$/"; ss_exe = "C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe" }
$script:localRoot = "C:\SRC125\gold"
$script:pbtName = "gold"

# --- ЗАГРУЗКА КОНФИГУРАЦИИ ---
function Load-Config {
    try {
        if (Test-Path $script:ConfigPath) {
            $script:Config = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($script:Config.vss) {
                $script:vssDefaults.user    = if ($script:Config.vss.user) { $script:Config.vss.user } else { "User" }
                $script:vssDefaults.db_path = if ($script:Config.vss.db_path) { $script:Config.vss.db_path } else { "" }
                $script:vssDefaults.project = if ($script:Config.vss.project) { $script:Config.vss.project } else { "$/" }
                $script:vssDefaults.ss_exe  = if ($script:Config.vss.ss_exe) { $script:Config.vss.ss_exe } else { "C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe" }
            }
            if ($script:Config.paths.pb_main_source) { $script:localRoot = $script:Config.paths.pb_main_source }
            if ($script:Config.paths.pbt_name) { $script:pbtName = $script:Config.paths.pbt_name }
            Write-TechJournal "INFO" "Config loaded: $script:ConfigPath"
        }
    } catch {
        Write-TechJournal "ERROR" "Config load failed: $_"
    }
}

# --- TECH JOURNAL ---
function Init-TechJournal {
    $script:TechJournalPath = Join-Path $env:TEMP "tech_journal_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$PID.log"
    Write-TechJournal "INFO" "MORDA started (ST2)"
    Write-TechJournal "INFO" "EXE path: $PSCommandPath"
    Write-TechJournal "INFO" "Args: $($script:ScriptArgs -join ' ')"
}

function Write-TechJournal {
    param([string]$Level, [string]$Message)
    try {
        $line = "[{0:HH:mm:ss.fff}] [{1}] {2}" -f (Get-Date), $Level, $Message
        $script:TechJournal += $line
        Add-Content -Path $script:TechJournalPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        if ($script:TechJournalPath) {
            Add-Content -Path "$script:TechJournalPath.fallback" -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
}

# --- AUTO TEST ---
function Parse-AutoTestArgs {
    $argsArray = $script:ScriptArgs
    for ($i = 0; $i -lt $argsArray.Length; $i++) {
        if ($argsArray[$i] -eq "--autotest" -and $i + 1 -lt $argsArray.Length) {
            $script:AutoTestFile = $argsArray[$i + 1]
            $script:IsAutoTest = $true
            if (Test-Path $script:AutoTestFile) {
                $script:AutoTestCommands = Get-Content $script:AutoTestFile -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch '^\s*#' }
                Write-TechJournal "INFO" "AutoTest loaded: $($script:AutoTestCommands.Count) commands from $script:AutoTestFile"
            }
        }
    }
}

function Start-AutoTest {
    Write-TechJournal "INFO" "AutoTest started"
    Run-NextAutoTestCommand
}

function Invoke-ButtonClick {
    param([string]$Name)
    try {
        if ($script:MainButtons -and $script:MainButtons.ContainsKey($Name)) {
            $btn = $script:MainButtons[$Name]
            $peer = New-Object System.Windows.Automation.Peers.ButtonAutomationPeer($btn)
            $peer.Invoke()
            Write-TechJournal "CLICK" $Name
        } else {
            Write-TechJournal "ERROR" "Button not found: $Name"
        }
    } catch { Write-TechJournal "ERROR" "ButtonClick $Name failed: $_" }
}

function Set-SearchInput {
    param([string]$Value)
    try {
        if ($script:MainWindow) {
            $box = $script:MainWindow.FindName("txtSearch")
            if ($box) { $box.Text = $Value }
        }
    } catch { }
}

function Save-AutoShot {
    param([string]$Name)
    try {
        if (-not $script:MainWindow) { Write-TechJournal "ERROR" "Shot ${Name}: no window"; return }
        $win = $script:MainWindow
        $win.UpdateLayout()
        $w = [Math]::Max(1, [int]$win.ActualWidth)
        $h = [Math]::Max(1, [int]$win.ActualHeight)
        $rbt = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $rbt.Render($win.Content)
        $shotDir = Join-Path $env:TEMP "autotest_shots"
        if (-not (Test-Path $shotDir)) { New-Item -ItemType Directory -Path $shotDir | Out-Null }
        $path = Join-Path $shotDir "$Name.png"
        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rbt))
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
        try { $enc.Save($fs) } finally { $fs.Close() }

        $stride = $w * 4
        $bytes = New-Object byte[] ($stride * $h)
        $rbt.CopyPixels($bytes, $stride, 0)
        $total = $w * $h
        $content = 0
        for ($i = 0; $i -lt $bytes.Length; $i += 4) {
            $b = $bytes[$i]; $g = $bytes[$i + 1]; $r = $bytes[$i + 2]; $a = $bytes[$i + 3]
            if ($a -gt 128) {
                $isWhite = ($r -gt 240 -and $g -gt 240 -and $b -gt 240)
                $isBg = ([Math]::Abs($r - 232) -lt 10 -and [Math]::Abs($g - 236) -lt 10 -and [Math]::Abs($b - 240) -lt 10)
                if (-not $isWhite -and -not $isBg) { $content++ }
            }
        }
        $pct = [Math]::Round(100.0 * $content / $total, 2)
        $mark = if ($pct -ge 1.0) { "OK" } else { "EMPTY" }
        if ($mark -eq "EMPTY") { Write-TechJournal "ERROR" "Shot ${Name}: окно пустое (content=$content/$total, $pct%)" }
        Write-TechJournal "SHOT" "$Name $mark $content/$total $pct%"
    } catch {
        Write-TechJournal "ERROR" "Shot $Name failed: $_"
    }
}

function Check-AutoElement {
    param([string]$Name)
    try {
        $el = $null
        if ($script:MainButtons -and $script:MainButtons.ContainsKey($Name)) { $el = $script:MainButtons[$Name] }
        elseif ($script:OpCombo -and $Name -eq "cmbOp") { $el = $script:OpCombo }
        elseif ($script:OpDescText -and $Name -eq "txtDesc") { $el = $script:OpDescText }
        elseif ($script:ParamsFields) {
            foreach ($pf in $script:ParamsFields) {
                if ($pf.Control -and ($pf.Control.Name -eq $Name -or $pf.Name -eq $Name)) { $el = $pf.Control; break }
            }
        }
        elseif ($script:MainWindow) { $el = $script:MainWindow.FindName($Name) }
        if (-not $el) { Write-TechJournal "ERROR" "Check ${Name}: элемент не найден"; return }
        $visible = $el.IsVisible -and $el.ActualWidth -gt 0 -and $el.ActualHeight -gt 0
        $mark = if ($visible) { "OK" } else { "FAIL" }
        if (-not $visible) { Write-TechJournal "ERROR" "Check ${Name}: невидим (W=$($el.ActualWidth) H=$($el.ActualHeight) IsVisible=$($el.IsVisible))" }
        Write-TechJournal "CHECK" "$Name $mark"
    } catch { Write-TechJournal "ERROR" "Check $Name failed: $_" }
}

function Check-AutoFields {
    try {
        $count = if ($script:ParamsFields) { $script:ParamsFields.Count } else { 0 }
        $op = $operations[$script:SelectedOpIndex]
        $expected = 0
        if ($op) {
            $expected = $op.Fields.Count + $op.Checkboxes.Count
            if ($op.NeedsPassword) { $expected++ }
        }
        $mark = if ($count -eq $expected) { "OK" } else { "FAIL" }
        if ($mark -eq "FAIL") { Write-TechJournal "ERROR" "Fields mismatch: got $count expected $expected (op $($op.Name))" }
        Write-TechJournal "FIELDS" "$($op.Name) $count/$expected $mark"
    } catch { Write-TechJournal "ERROR" "Fields check failed: $_" }
}

function Check-AutoOps {
    param([int]$Expected)
    try {
        $count = if ($operations) { $operations.Count } else { 0 }
        $mark = if ($count -eq $Expected) { "OK" } else { "FAIL" }
        if ($mark -eq "FAIL") { Write-TechJournal "ERROR" "Ops mismatch: got $count expected $Expected" }
        Write-TechJournal "OPS" "$count/$Expected $mark"
    } catch { Write-TechJournal "ERROR" "Ops check failed: $_" }
}

function Get-ElementRect {
    param($Element)
    try {
        $win = $script:MainWindow
        if (-not $win -or -not $Element) { return $null }
        $origin = $Element.TransformToAncestor($win).Transform([Windows.Point]::new(0, 0))
        return [System.Windows.Rect]::new($origin.X, $origin.Y, $Element.ActualWidth, $Element.ActualHeight)
    } catch { return $null }
}

function Test-RectOverlap {
    param([System.Windows.Rect]$A, [System.Windows.Rect]$B)
    if (-not $A -or -not $B) { return $false }
    return ($A.IntersectsWith($B))
}

function Check-AutoOverlap {
    try {
        $win = $script:MainWindow
        if (-not $win) { Write-TechJournal "ERROR" "Overlap: no window"; return }

        $targets = @()
        $pbPanel = $win.FindName("pbPanel")
        if ($script:PhaseBar) { $targets += @{ Name="PhaseBar"; Element=$script:PhaseBar } }
        if ($script:StepBar)  { $targets += @{ Name="StepBar"; Element=$script:StepBar } }
        if ($script:ParamsPanel) { $targets += @{ Name="ParamsPanel"; Element=$script:ParamsPanel } }

        $overlapFound = $false
        foreach ($btnName in @('btnRun','btnHistory','btnExit')) {
            if (-not $script:MainButtons.ContainsKey($btnName)) { continue }
            $btnRect = Get-ElementRect $script:MainButtons[$btnName]
            if (-not $btnRect) { Write-TechJournal "ERROR" "Overlap: $btnName нет координат"; continue }
            foreach ($t in $targets) {
                $tRect = Get-ElementRect $t.Element
                if (-not $tRect) { continue }
                if (Test-RectOverlap $btnRect $tRect) {
                    Write-TechJournal "ERROR" "Overlap: $btnName наезжает на $($t.Name)"
                    $overlapFound = $true
                }
            }
        }
        $mark = if ($overlapFound) { "FAIL" } else { "OK" }
        Write-TechJournal "OVERLAP" "$mark"
    } catch { Write-TechJournal "ERROR" "Overlap check failed: $_" }
}

function Run-NextAutoTestCommand {
    if ($script:AutoTestIndex -ge $script:AutoTestCommands.Count) {
        Write-TechJournal "INFO" "AutoTest completed, closing"
        Start-Sleep -Milliseconds 500
        if ($script:MainWindow) { $script:MainWindow.Close() }
        return
    }
    $cmd = $script:AutoTestCommands[$script:AutoTestIndex].Trim()
    $script:AutoTestIndex++
    Write-TechJournal "AUTOTEST" "Executing: $cmd"
    try {
        if ($cmd -match '^log\s+(.+)') {
            Write-TechJournal "INFO" $matches[1]
        }
        elseif ($cmd -match '^wait\s+(\d+)') {
            $msVal = [int]::Parse($matches[1])
            Start-Sleep -Milliseconds $msVal
        }
        elseif ($cmd -match '^click\s+(\w+)') {
            Invoke-ButtonClick $matches[1]
        }
        elseif ($cmd -match '^set_search\s+(.+)') {
            Set-SearchInput $matches[1]
        }
        elseif ($cmd -match '^select_op\s+(\d+)') {
            $script:SelectedOpIndex = [int]::Parse($matches[1])
            Select-Operation
        }
        elseif ($cmd -match '^resize\s+(\d+),(\d+)') {
            if ($script:MainWindow) {
                $script:MainWindow.Width = [int]::Parse($matches[1])
                $script:MainWindow.Height = [int]::Parse($matches[2])
                Write-TechJournal "INFO" "SizeChanged: $($matches[1])x$($matches[2])"
            }
        }
        elseif ($cmd -match '^shot\s+(\S+)') {
            Save-AutoShot $matches[1]
        }
        elseif ($cmd -match '^check_visible\s+(\S+)') {
            Check-AutoElement $matches[1]
        }
        elseif ($cmd -eq 'check_fields') {
            Check-AutoFields
        }
        elseif ($cmd -eq 'check_overlap') {
            Check-AutoOverlap
        }
        elseif ($cmd -match '^expect_ops\s+(\d+)') {
            Check-AutoOps ([int]::Parse($matches[1]))
        }
        elseif ($cmd -eq 'close') {
            if ($script:MainWindow) { $script:MainWindow.Close() }
            return
        }
        # --- НОВЫЕ КОМАНДЫ: проверка результата (без участия пользователя) ---
        elseif ($cmd -match '^check_file\s+(.+)') {
            $path = $matches[1]
            if (Test-Path $path) { Write-TechJournal "AUTOTEST" "check_file OK: $path" }
            else { Write-TechJournal "ERROR" "check_file FAIL: $path" }
        }
        elseif ($cmd -match '^check_files\s+(.+)\s+(\d+)') {
            $path = $matches[1]; $min = [int]$matches[2]
            $cnt = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($cnt -ge $min) { Write-TechJournal "AUTOTEST" "check_files OK: $path = $cnt (min=$min)" }
            else { Write-TechJournal "ERROR" "check_files FAIL: $path = $cnt (expected >= $min)" }
        }
        elseif ($cmd -match '^expect_result\s+(.+)') {
            $pat = $matches[1]
            if ($script:LastOpResult -match $pat) { Write-TechJournal "AUTOTEST" "expect_result OK: $pat" }
            else { Write-TechJournal "ERROR" "expect_result FAIL: '$script:LastOpResult' !~ $pat" }
        }
        elseif ($cmd -match '^expect_output\s+(.+)') {
            $pat = $matches[1]
            if ($script:LastOpOutput -match $pat) { Write-TechJournal "AUTOTEST" "expect_output OK: $pat" }
            else { Write-TechJournal "ERROR" "expect_output FAIL: $pat" }
        }
        elseif ($cmd -match '^run_op\s+(\d+)\s+(\d+)') {
            $opIdx = [int]$matches[1]; $timeout = [int]$matches[2]
            Write-TechJournal "AUTOTEST" "run_op: select=$opIdx timeout=$timeout"
            $script:SelectedOpIndex = $opIdx; Select-Operation
            Start-Sleep -Milliseconds 300
            Invoke-ButtonClick "btnRun"
            Start-Sleep -Seconds $timeout
        }
        elseif ($cmd -match '^assert\s+(.+)') {
            $pat = $matches[1]
            if ($script:LastOpResult -match $pat) { Write-TechJournal "AUTOTEST" "assert OK: $pat" }
            else { Write-TechJournal "ERROR" "assert FAIL: '$script:LastOpResult' !~ $pat"; throw "ASSERT FAILED: $pat" }
        }
        elseif ($cmd -eq 'exit_ok') {
            Write-TechJournal "AUTOTEST" "EXIT OK"
            if ($script:MainWindow) { $script:MainWindow.Close() }
            [Environment]::Exit(0)
        }
        elseif ($cmd -eq 'exit_fail') {
            Write-TechJournal "AUTOTEST" "EXIT FAIL"
            if ($script:MainWindow) { $script:MainWindow.Close() }
            [Environment]::Exit(1)
        }
    } catch {
        Write-TechJournal "ERROR" "AutoTest command failed: $cmd - $_"
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $timer.Add_Tick({ $timer.Stop(); Run-NextAutoTestCommand })
    $timer.Start()
}

# --- ОПЕРАЦИИ: функция-обёртки (чтобы избежать проблем синтаксиса однострочников) ---
function Invoke-OpSettings {
    param($params, $password)
    return "Настройки: панель настроек открыта"
}

function Invoke-OpRunTests {
    param($params, $password, $checks)
    $ps = "C:\AIS\AI\Prod\scripts\Run-Tests.ps1"
    
    # Обновляем глобальный прогресс
    $script:PhaseProgress.Value = 10
    $script:PhaseProgress.Text = "Запуск тестов"
    $script:StepProgress.Value = 0
    $script:StepProgress.Text = "0 из 5"
    
    # Симуляция шагов тестирования
    $tests = @("Проверка синтаксиса", "Проверка кодировки", "Проверка операций", "Проверка путей", "Финальная проверка")
    $total = $tests.Count
    
    for ($i = 0; $i -lt $total; $i++) {
        $script:PhaseProgress.Value = [Math]::Round(($i + 1) * 100 / $total)
        $script:PhaseProgress.Text = $tests[$i]
        $script:StepProgress.Value = [Math]::Round(($i + 1) * 100 / $total)
        $script:StepProgress.Text = "$($i + 1) из $total"
        Start-Sleep -Milliseconds 500
    }
    
    if ($checks.QuickMode) { 
        $output = & powershell -ExecutionPolicy Bypass -File $ps -Quick 2>&1 
    } else { 
        $output = & powershell -ExecutionPolicy Bypass -File $ps 2>&1 
    }
    
    $script:PhaseProgress.Value = 100
    $script:PhaseProgress.Text = "Завершено"
    $script:StepProgress.Value = 100
    $script:StepProgress.Text = "$total из $total"
    
    return $output | Out-String
}

function Invoke-OpExportService {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\Export-Service.ps1"
    $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $src = if ($cfg.export_service.source_path) { $cfg.export_service.source_path } else { "C:\AIS\AI\Prod" }
    $dst = if ($params.DestPath) { $params.DestPath } elseif ($cfg.export_service.dest_path) { $cfg.export_service.dest_path } else { "Z:\AI\Prod" }
    & powershell -ExecutionPolicy Bypass -File $ps -SourcePath $src -DestPath $dst -Force 2>&1
}

function Invoke-OpCollectProd {
    param($params, $password)
    $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $releaseRoot = $cfg.paths.release_root
    $TaskName = $params.TaskName
    if (-not $TaskName) { throw "Не указан Task Name" }
    $taskPath = Join-Path $releaseRoot $TaskName
    $prefixMatch = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($prefixMatch) { $taskPath = $prefixMatch.FullName }
    elseif (-not (Test-Path $taskPath)) { throw "Папка задачи не найдена: $taskPath" }
    Write-Host "Задача: $taskPath"
    $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
    if (-not $readyDirs) { throw "Папки Ready_* не найдены" }
    $latestReadyDir = $readyDirs | Select-Object -First 1
    Write-Host "Последняя Ready: $($latestReadyDir.Name)"
    $pbLatest = @{}; $sqlLatest = @{}
    foreach ($rd in $readyDirs) {
        Get-ChildItem $rd.FullName -Recurse -File | ForEach-Object {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if ($_.Extension -match '^\.sr') {
                if (-not $pbLatest.ContainsKey($base)) { $pbLatest[$base] = @{ BaseName=$base; FileName=$_.Name; ReadyDir=$rd.Name; FullPath=$_.FullName } }
            } elseif ($_.Extension -eq '.sql') {
                if (-not $sqlLatest.ContainsKey($base)) { $sqlLatest[$base] = @{ BaseName=$base; FileName=$_.Name; ReadyDir=$rd.Name; FullPath=$_.FullName } }
            }
        }
    }
    Write-Host "Найдено: PB=$($pbLatest.Count), SQL=$($sqlLatest.Count)"
    $prodPath = Join-Path $taskPath "PROD"
    if (-not (Test-Path $prodPath)) { New-Item -ItemType Directory -Path $prodPath -Force | Out-Null }
    Write-Host "Папка PROD: $prodPath"
    $totalObjects = $pbLatest.Count + $sqlLatest.Count
    if ($totalObjects -eq 0) {
        Write-Host "###PROD_NONE###Нет объектов"
    } else {
        foreach ($key in $pbLatest.Keys) { Write-Host ("###PROD_OBJ###" + $key + "|PB|Готов|" + $prodPath + "|-") }
        foreach ($key in $sqlLatest.Keys) { Write-Host ("###PROD_OBJ###" + $key + "|SQL|Готов|" + (Join-Path $prodPath "SQL") + "|-") }
    }
}

function Invoke-OpExportPb {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\Export-PB.ps1"
    $cmdArgs = @("-Source", $params.Source)
    if ($params.TaskName) { $cmdArgs += @("-TaskName", $params.TaskName) }

    $script:PhaseProgress.Value = 10
    $script:PhaseProgress.Text = "Подготовка"
    $script:StepProgress.Value = 0
    $script:StepProgress.Text = "0 из 100"

    # Запускаем процесс асинхронно
    $argStr = ($cmdArgs | ForEach-Object { "`"$_`"" }) -join ' '
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoLogo", "-ExecutionPolicy", "RemoteSigned", "-File", "`"$ps`"", $argStr -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\export_pb_out.txt" -RedirectStandardError "$env:TEMP\export_pb_err.txt"

    # Ждём завершения с обновлением ПБ (индикация активности)
    $step = 0
    $total = 100
    while (-not $process.HasExited) {
        $step++
        $pct = [Math]::Min(10 + [Math]::Floor($step * 80 / 200), 90)
        $script:PhaseProgress.Value = $pct
        $script:PhaseProgress.Text = "Выгрузка PB"
        $script:StepProgress.Value = $pct
        $script:StepProgress.Text = "$step из $total"
        Start-Sleep -Milliseconds 500
    }
    
    # Читаем вывод
    $output = ""
    if (Test-Path "$env:TEMP\export_pb_out.txt") {
        $output = Get-Content "$env:TEMP\export_pb_out.txt" -Raw -Encoding UTF8
        Remove-Item "$env:TEMP\export_pb_out.txt" -Force
    }
    if (Test-Path "$env:TEMP\export_pb_err.txt") {
        $errOutput = Get-Content "$env:TEMP\export_pb_err.txt" -Raw -Encoding UTF8
        if ($errOutput) { $output += "`nERRORS:`n$errOutput" }
        Remove-Item "$env:TEMP\export_pb_err.txt" -Force
    }
    
    Write-Host "###PHASE###Завершено|100"
    Write-Host "###STEP###$total из $total|100"
    $script:PhaseProgress.Value = 100
    $script:PhaseProgress.Text = "Завершено"
    $script:StepProgress.Value = 100
    $script:StepProgress.Text = "$total из $total"

    return $output
}

function Invoke-OpComparePb {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\Compare-PB.ps1"
    $cmdArgs = @("-OutputFile", $params.OutputFile)
    if ($params.TaskName) { $cmdArgs += @("-TaskName", $params.TaskName) }
    & powershell -ExecutionPolicy Bypass -File $ps @cmdArgs 2>&1
}

function Invoke-OpSqlExport {
    param($params, $password)
    $source = $params.Source; $server = $params.Server
    $db = if ($params.Db) { $params.Db } else { "golden" }
    $taskName = $params.TaskName
    $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-TechJournal "INFO" "Invoke-OpSqlExport: source=$source server=$server db=$db taskName=$taskName pwd=***"
    if (-not $taskName) {
        $bat = "C:\AIS\AI\Prod\bin\SQL_exp_param.bat"
        $srv = if ($server -match 'galaxy') { "galaxy" } else { "dev_golden" }
        $objectType = if ($params.ObjectType) { $params.ObjectType.Trim() } else { "" }
        $exportPath = if ($srv -eq "galaxy") { $cfg.paths.bd_main_export } else { $cfg.paths.bd_current_export }
        Write-TechJournal "INFO" "Invoke-OpSqlExport: bat=$bat srv=$srv exportPath=$exportPath objectType=$objectType"
        # Выгрузка через SqlExport.exe с реальным временем
        $sqlExportExe = "C:\AIS\AI\Prod\bin\SqlExport.exe"
        $tmpOut = "$env:TEMP\sql_export_$pid.txt"
        $argsForExe = @($srv, $db, $password, $exportPath)
        if ($objectType) { $argsForExe += $objectType }  # конкретный тип, иначе все
        Write-TechJournal "INFO" "Invoke-OpSqlExport: $sqlExportExe $srv $db *** $exportPath $objectType"
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $sqlExportExe
        $psi.Arguments = "`"$srv`" `"$db`" `"$password`" `"$exportPath`" $objectType"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        
        $proc = [System.Diagnostics.Process]::Start($psi)
        $phaseStats = @{}
        $currentPhase = ""
        $phaseCount = 0
        $knownTypes = @('Procedures','Functions','Triggers','Tables','Views','Indexes','PrimaryKeys','ForeignKeys','Grants')
        $typeNames = @{ Procedures='Процедуры'; Functions='Функции'; Triggers='Триггеры'; Tables='Таблицы'; Views='Представления'; Indexes='Индексы'; PrimaryKeys='Первичные ключи'; ForeignKeys='Внешние ключи'; Grants='Гранты' }
        if ($objectType) { $knownTypes = @($objectType) }
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line) {
                if ($line -match '^###STEP###') {
                    if ($line -match '###STEP###(\d+)\|(\d+)###') {
                        $sn = [int]$matches[1]; $st = [int]$matches[2]
                        $phaseCount = $sn
                        $pct = if ($st -gt 0) { [Math]::Round($sn * 100 / $st) } else { 100 }
                        $script:StepProgress.Value = $pct
                        $script:StepProgress.Text = "$sn из $st"
                    }
                    continue
                }
                Write-Output $line
                if ($line -match '###PHASE###(.+?)\|(\d+)###') {
                    if ($currentPhase -and $phaseCount -gt 0) { $phaseStats[$currentPhase] = $phaseCount }
                    $currentPhase = $matches[1]; $phaseCount = 0
                    $ti = [Array]::IndexOf($knownTypes, $currentPhase)
                    if ($ti -lt 0) { $ti = 0 }
                    $script:PhaseProgress.Value = [Math]::Round(($ti + 1) * 100 / $knownTypes.Count)
                    $ruName = if ($typeNames.ContainsKey($currentPhase)) { $typeNames[$currentPhase] } else { $currentPhase }
                    $script:PhaseProgress.Text = "Тип: $ruName"
                    $script:StepProgress.Value = 0
                    $script:StepProgress.Text = "0 из $($matches[2])"
                }
                elseif ($line -match 'Exporting\s+\w+:\s*(.+)') {
                    $script:StepProgress.Text += " — $($matches[1].Trim())"
                }
            }
        }
        if ($currentPhase -and $phaseCount -gt 0) { $phaseStats[$currentPhase] = $phaseCount }
        $proc.WaitForExit()
        Write-TechJournal "INFO" "Invoke-OpSqlExport: exit=$($proc.ExitCode)"
        $files = Get-ChildItem $exportPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count
        $summary = "Выгружено:`n"
        foreach ($k in $phaseStats.Keys | Sort-Object) { $summary += "  $($k): $($phaseStats[$k])`n" }
        $summary += "`nВсего файлов: $files"
        Write-Output $summary
    }
    $releaseRoot = $cfg.paths.release_root
    $taskPath = Join-Path $releaseRoot $taskName
    $prefixMatch = Get-ChildItem $releaseRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$taskName*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($prefixMatch) { $taskPath = $prefixMatch.FullName }
    elseif (-not (Test-Path $taskPath)) { throw "Папка задачи не найдена" }
    $srv = if ($server -match 'galaxy') { "galaxy" } else { "dev_golden" }
    $singleType = if ($params.ObjectType) { $params.ObjectType.Trim() } else { "" }
    $bat = "C:\AIS\AI\Prod\bin\SQL_exp_single.bat"
    $sqlTypePatterns = @(
        @{ Regex='CREATE\s+PROC(?:EDURE)?\b'; Bat='Procedure' },
        @{ Regex='CREATE\s+FUNCTION\b'; Bat='Function' },
        @{ Regex='CREATE\s+TRIGGER\b'; Bat='Trigger' },
        @{ Regex='CREATE\s+TABLE\b'; Bat='Table' },
        @{ Regex='CREATE\s+VIEW\b'; Bat='View' }
    )
    $taskObjects = @{}
    foreach ($prefix in @('Ready_*','Git_*')) {
        Get-ChildItem $taskPath -Directory -Filter $prefix -ErrorAction SilentlyContinue | ForEach-Object {
            $folderDir = $_.FullName
            Get-ChildItem $folderDir -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue | ForEach-Object {
                $sqlFile = $_
                $firstLines = Get-Content $sqlFile.FullName -TotalCount 20 -ErrorAction SilentlyContinue
                $sqlText = $firstLines -join "`n"
                $targetType = $null; $objName = $null
                foreach ($pattern in $sqlTypePatterns) {
                    $m = [regex]::Match($sqlText, $pattern.Regex)
                    if ($m.Success) {
                        $targetType = $pattern.Bat
                        $rest = $sqlText.Substring($m.Index + $m.Length).Trim()
                        $nameMatch = [regex]::Match($rest, '^(?:\w+\.)?(\w+)')
                        if ($nameMatch.Success) { $objName = $nameMatch.Groups[1].Value }
                        break
                    }
                }
                if (-not $targetType) { return }
                if (-not $objName) { $objName = [System.IO.Path]::GetFileNameWithoutExtension($sqlFile.Name) }
                if ($singleType -and $singleType -ne $targetType) { return }
                if (-not $taskObjects.ContainsKey($objName)) { $taskObjects[$objName] = @{ Type=$targetType; File=$sqlFile.FullName } }
            }
        }
    }
    if ($taskObjects.Count -eq 0) {
        Write-Host "###SQL_TASK_NONE###Нет SQL-объектов для задачи $taskName"
        return
    }
    $basedir = if ($srv -eq "galaxy") { $cfg.paths.bd_main_export } else { $cfg.paths.bd_current_export }
    Write-Host "=== Выборочный экспорт SQL: $taskName ==="
    # Русские названия типов для ПБ
    $typeNames = @{ Procedures='Процедуры'; Functions='Функции'; Triggers='Триггеры'; Tables='Таблицы'; Views='Представления'; Indexes='Индексы'; PrimaryKeys='Первичные ключи'; ForeignKeys='Внешние ключи'; Grants='Гранты' }
    $allTypes = @('Procedures','Functions','Triggers','Tables','Views','Indexes','PrimaryKeys','ForeignKeys','Grants')
    # Группируем объекты по типу для верхнего ПБ
    $byType = @{}
    foreach ($k in $taskObjects.Keys) {
        $t = $taskObjects[$k].Type
        if (-not $byType.ContainsKey($t)) { $byType[$t] = @() }
        $byType[$t] += $k
    }
    $totalTypes = $byType.Count
    $typeIdx = 0
    $exported = 0; $failed = 0; $total = $taskObjects.Count; $objIdx = 0
    foreach ($tp in $allTypes) {
        if (-not $byType.ContainsKey($tp)) { continue }
        $typeIdx++
        $objects = $byType[$tp]
        $typeName = if ($typeNames.ContainsKey($tp)) { $typeNames[$tp] } else { $tp }
        $script:PhaseProgress.Value = [Math]::Round($typeIdx * 100 / $totalTypes)
        $script:PhaseProgress.Text = "Тип: $typeName"
        foreach ($key in $objects | Sort-Object) {
            $objIdx++
            $obj = $taskObjects[$key]
            $script:StepProgress.Value = [Math]::Round($objIdx * 100 / $total)
            $script:StepProgress.Text = "$objIdx из $total — $key"
            $quotedArgs = @($obj.Type, $key, $srv, $db, $password) | ForEach-Object { "`"$_`"" }
            $tmpOut = "$env:TEMP\sql_single_$pid.txt"
            $batArgs = "$($quotedArgs -join ' ')"
            Start-Process cmd -ArgumentList "/c `"$bat`" $batArgs" -NoNewWindow -RedirectStandardOutput $tmpOut -RedirectStandardError "$tmpOut.err" -Wait | Out-Null
            $outFile = Join-Path $basedir ($obj.Type + "\" + $key + ".sql")
            if (Test-Path $outFile) { $exported++; Write-Host "  OK: $key" }
            else { $failed++; Write-Host "  ОШИБКА: $key" }
        }
    }
    Write-Host "Успешно: $exported, Ошибок: $failed, Всего: $total"
}

function Invoke-OpCompareSql {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\Compare-SQL-Task.ps1"
    $quotedArgs = @("-ExecutionPolicy", "Bypass", "-File", $ps, "-TaskName", $params.TaskName, "-Password", $password) | ForEach-Object { "`"$_`"" }
    & powershell $quotedArgs 2>&1
}

function Invoke-OpCompareVerify {
    param($params, $password, $checks)
    $ps = "C:\AIS\AI\Prod\scripts\Compare-Export.ps1"
    $cmdArgs = @("-Password", $password, "-TaskName", $params.TaskName)
    if ($checks.ShowDiff) { $cmdArgs += "-ShowDiff" }
    if ($checks.CreateRFC) { $cmdArgs += "-CreateRFC" }
    & powershell -ExecutionPolicy Bypass -File $ps @cmdArgs 2>&1
}

function Invoke-OpCreateRfc {
    param($params, $password)
    if (-not $password) { Write-Host "ОШИБКА: Не указан пароль/токен Jira"; return }
    $ps = "C:\AIS\AI\Prod\scripts\Create-RFC.ps1"
    $jrUser = try { (Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json).jira.jira_email } catch { "" }
    & powershell -ExecutionPolicy Bypass -File $ps -TaskName $params.TaskName -JiraUser $jrUser -JiraPassword $password -Force 2>&1
}

function Invoke-OpJiraComment {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\Add-ReleaseComment.ps1"
    & powershell -ExecutionPolicy Bypass -File $ps -TaskName "$($params.TaskName)" -ProjectName "$($params.ProjectName)" -JiraPassword $password -Force 2>&1
}

function Invoke-OpVssGetLatest {
    param($params, $password, $checks)
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    if ($params.TaskName) {
        $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
        $taskPath = if ($matchDir) { $matchDir.FullName } else { Join-Path $cfg.paths.release_root $params.TaskName }
        if (-not (Test-Path $taskPath)) { Write-Host "ОШИБКА: Папка задачи не найдена"; return }
        $readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like 'Ready_*' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
        if (-not $readyDirs) { Write-Host "ОШИБКА: Папки Ready_* не найдены"; return }
        $objects = @{}
        foreach ($rd in $readyDirs) {
            Get-ChildItem $rd.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if (-not $objects.ContainsKey($base)) { $objects[$base] = $_.Name }
            }
        }
        $updatedCount = 0
        foreach ($baseName in $objects.Keys | Sort-Object) {
            $ext = [System.IO.Path]::GetExtension($objects[$baseName])
            $vssLib = ""
            foreach ($dir in @($cfg.paths.pb_current_export, $cfg.paths.pb_main_export)) {
                $f = Get-ChildItem $dir -Recurse -File -Filter "${baseName}.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($f) { $vssLib = $f.Directory.Name; break }
            }
            if (-not $vssLib) { Write-Host "  ? $baseName - библиотека не определена"; continue }
            $vssObjPath = "$/SRC125/gold/$vssLib/${baseName}${ext}"
            Get-VssLatest -Project $vssObjPath
            $updatedCount++
        }
        Write-Host "Обновлено: $updatedCount"
    } elseif ($params.PbtFile -and (Test-Path $params.PbtFile)) {
        $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $localRoot2 = if ($cfg.paths.pb_main_source) { $cfg.paths.pb_main_source } else { "C:\SRC125\gold" }
        $vssRoot = $script:vssDefaults.project
        Get-Content $params.PbtFile | ForEach-Object {
            if ($_ -match '^Library:\s+(.+\.pbl)$') {
                $localPath = $matches[1].Trim()
                $vssPath = $localPath -replace [regex]::Escape($localRoot2), $vssRoot
                $vssPath = $vssPath -replace '\\', '/'
                Get-VssLatest -Project $vssPath
            }
        }
    } else {
        Get-VssLatest -Project $params.Project -Recursive:$checks.Recursive
    }
}

function Invoke-OpVssCheckStatus {
    param($params, $password, $checks)
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    if ($params.TaskName) {
        $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
        $taskPath = if ($matchDir) { $matchDir.FullName } else { Join-Path $cfg.paths.release_root $params.TaskName }
        if (-not (Test-Path $taskPath)) { Write-Host "ОШИБКА: Папка задачи не найдена"; return }
        $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
        if (-not $allDirs) { Write-Host "ОШИБКА: Папки не найдены"; return }
        $objects = @{}
        foreach ($d in $allDirs) {
            $source = if ($d.Name -like 'Ready_*') { 'R' } elseif ($d.Name -like 'Test_*') { 'T' } else { 'G' }
            Get-ChildItem $d.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if (-not $objects.ContainsKey($base)) { $objects[$base] = @{ Name=$_.Name; Source=$source } }
            }
        }
        foreach ($baseName in $objects.Keys) {
            $obj = $objects[$baseName]
            $fileName = $obj.Name; $source = $obj.Source
            $sPattern = if ($fileName.Contains('.')) { $fileName } else { "$baseName.*" }
            $vssPath = ''
            foreach ($root in @($cfg.paths.pb_main_export, $cfg.paths.pb_current_export)) {
                if (-not (Test-Path $root)) { continue }
                $gci = Get-ChildItem $root -Recurse -File -Filter $sPattern -ErrorAction SilentlyContinue
                foreach ($m in $gci) {
                    $fb = [System.IO.Path]::GetFileNameWithoutExtension($m.Name)
                    if ($fb -eq $baseName) { $vssPath = "$/SRC125/gold/$($m.Directory.Name)/$($m.Name)"; break }
                }
                if ($vssPath) { break }
            }
            if (-not $vssPath) { Write-Host "###VSS_STATUS### $baseName||NF||$source"; continue }
            $statusOut = Invoke-VssCommand -Command "Status" -Project $vssPath | Out-String
            if ($statusOut -match 'No checked|не найдены|не извлеч') { Write-Host "###VSS_STATUS### $baseName|$vssPath|F||$source" }
            elseif ($statusOut -match '\s(\w+)\s+(Exc|Out)\s') { Write-Host "###VSS_STATUS### $baseName|$vssPath|B|$($matches[1])|$source" }
            else { Write-Host "###VSS_STATUS### $baseName|$vssPath|F||$source" }
        }
    } else {
        Get-VssStatus -Project $params.Project -Recursive:$checks.Recursive
    }
}

function Invoke-OpVssWhoIsUsing {
    param($params, $password, $checks)
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    if ($params.TaskName) {
        $cfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $matchDir = Get-ChildItem $cfg.paths.release_root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($params.TaskName)*" } | Sort-Object Name -Descending | Select-Object -First 1
        $taskPath = if ($matchDir) { $matchDir.FullName } else { Join-Path $cfg.paths.release_root $params.TaskName }
        if (-not (Test-Path $taskPath)) { Write-Host "ОШИБКА: Папка задачи не найдена"; return }
        $allDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -match '^(Ready_|Test_|Git_)' -and $_.Name -ne 'Ready_' } | Sort-Object Name -Descending
        $objects = @{}
        foreach ($d in $allDirs) {
            $source = if ($d.Name -like 'Ready_*') { 'R' } elseif ($d.Name -like 'Test_*') { 'T' } else { 'G' }
            Get-ChildItem $d.FullName -Recurse -File -Filter '*.sr*' | ForEach-Object {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if (-not $objects.ContainsKey($base)) { $objects[$base] = @{ Name=$_.Name; Source=$source } }
            }
        }
        foreach ($baseName in $objects.Keys) {
            $obj = $objects[$baseName]
            $fileName = $obj.Name; $source = $obj.Source
            $sPattern = if ($fileName.Contains('.')) { $fileName } else { "$baseName.*" }
            $vssPath = ''
            foreach ($root in @($cfg.paths.pb_main_export, $cfg.paths.pb_current_export)) {
                if (-not (Test-Path $root)) { continue }
                $gci = Get-ChildItem $root -Recurse -File -Filter $sPattern -ErrorAction SilentlyContinue
                foreach ($m in $gci) {
                    $fb = [System.IO.Path]::GetFileNameWithoutExtension($m.Name)
                    if ($fb -eq $baseName) { $vssPath = "$/SRC125/gold/$($m.Directory.Name)/$($m.Name)"; break }
                }
                if ($vssPath) { break }
            }
            if (-not $vssPath) { Write-Host "--- $baseName [${source}] -> Не найден"; continue }
            $whoOut = Invoke-VssCommand -Command "Status" -Project $vssPath | Out-String
            if ($whoOut -match '\s(\w+)\s+(Exc|Out)\s') { Write-Host "+++ $baseName -> Извлечён: $($matches[1])" }
            else { Write-Host "--- $baseName -> Свободен" }
        }
    } else {
        Get-VssWhoIsUsing -Project $params.Project -Recursive:$checks.Recursive
    }
}

function Invoke-OpVssCheckout {
    param($params, $password, $checks)
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    Set-VssCheckout -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
}

function Invoke-OpVssCheckin {
    param($params, $password, $checks)
    if ([string]::IsNullOrWhiteSpace($params.Comment)) { throw "Комментарий обязателен для Checkin" }
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    Set-VssCheckin -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
}

function Invoke-OpVssUndo {
    param($params, $password, $checks)
    $vssModule = "C:\AIS\AI\Prod\scripts\VSS-Utils.ps1"
    $null = . $vssModule -VssPath $params.VssPath -Username $params.VssUser -Password $params.VssPass -Quiet
    Set-VssUndoCheckout -Project $params.Project -Comment $params.Comment -Recursive:$checks.Recursive
}

function Invoke-OpVssHistory {
    param($params, $password)
    $ps = "C:\AIS\AI\Prod\scripts\VSS-History-Show.ps1"
    $vssArgs = @()
    $vssArgs += "-VssDb", $params.VssPath
    $vssArgs += "-VssUser", $params.VssUser
    $vssArgs += "-VssPass", $params.VssPass
    if ($params.Project) { $vssArgs += "-VssPath", $params.Project }
    if ($params.TaskName) { $vssArgs += "-TaskName", $params.TaskName }
    $argStr = ($vssArgs | ForEach-Object { "`"$_`"" }) -join " "
    $vssTempOutput = Join-Path $env:TEMP "morda_vss_output_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    if (Test-Path $vssTempOutput) { Remove-Item $vssTempOutput -Force }
    $vssBat = $ps -replace '\.ps1$', '.bat'
    if (Test-Path $vssBat) {
        $vssWrapper = Join-Path $env:TEMP "morda_vss_wrapper_$(Get-Date -Format 'yyyyMMdd_HHmmss').cmd"
        $wrapperContent = '@echo off' + "`r`n" + '"' + $vssBat + '" ' + $argStr + ' > "' + $vssTempOutput + '" 2>&1' + "`r`n"
        [System.IO.File]::WriteAllText($vssWrapper, $wrapperContent, [System.Text.Encoding]::Default)
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $vssWrapper -WindowStyle Normal
    } else {
        $vssStartArgs = '-NoProfile', '-STA', '-File', $ps, '-ShowHistory', '-Automated'
        Start-Process powershell -ArgumentList $vssStartArgs -WindowStyle Normal
    }
}

# --- ОПЕРАЦИИ (19) ---
$operations = @(
    @{ Name="Settings"; RusName="Настройки параметров"; Description="Просмотр и редактирование путей, логинов и параметров проекта"; NeedsPassword=$false; Fields=@(); Handler="Invoke-OpSettings" },
    @{ Name="Run Tests"; RusName="Запуск тестов"; Description="Автотестирование проекта: парсер PS, кодировка BOM, операции, пути"; NeedsPassword=$false; Fields=@(); Checkboxes=@(@{ Name="QuickMode"; Label="Быстрый режим" }); Handler="Invoke-OpRunTests" },
    @{ Name="Export Service"; RusName="Export Service (выгрузка проекта)"; Description="Выгрузка проекта: bin, scripts, config, docs, rules"; NeedsPassword=$false; Fields=@(@{ Name="DestPath"; Label="Путь выгрузки"; Default=""; Hint="Путь к папке выгрузки (пусто - из Настроек)" }); Handler="Invoke-OpExportService" },
    @{ Name="Collect PROD Objects"; RusName="Собрать объекты для вывода в ПРОД"; Description="Копирование объектов PB и SQL в папку PROD задачи и сравнение с Ready"; NeedsPassword=$false; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Имя задачи Jira"; Required=$true }, @{ Name="CollectPath"; Label="Путь для сбора объектов"; Default=""; Hint="Путь к папке сбора (пусто - из Настроек)" }); Handler="Invoke-OpCollectProd" },
    @{ Name="Export PB"; RusName="Выгрузка PB: Current или Main"; Description="Выгрузка объектов PowerBuilder из PBL через pbldump"; NeedsPassword=$false; Fields=@(@{ Name="Source"; Label="Источник"; Default="Current"; Hint="Current (C:\Work\gold) или Main (C:\SRC125\gold)"; Items=@("Current","Main") }, @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Пусто - все объекты" }); Handler="Invoke-OpExportPb" },
    @{ Name="Compare PB"; RusName="Сравнение PB: Current и Main"; Description="Сравнение PowerBuilder-объектов Current и Main (MD5)"; NeedsPassword=$false; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Пусто - все объекты" }, @{ Name="OutputFile"; Label="Файл отчёта"; Default="C:\AIS\AI\Prod\compare_pb_report.txt"; Hint="Output file" }); Handler="Invoke-OpComparePb" },
    @{ Name="SQL Export"; RusName="Выгрузка SQL"; Description="Экспорт объектов БД. Задача - только из Ready_/Git_"; NeedsPassword=$true; Fields=@(@{ Name="Source"; Label="Источник"; Default="Current"; Hint="Current / Main"; Items=@("Current","Main") }, @{ Name="Server"; Label="Сервер"; Default="dev_golden"; Hint="galaxy / dev_golden" }, @{ Name="Db"; Label="База данных"; Default="golden"; Hint="Имя БД" }, @{ Name="ObjectType"; Label="Тип объекта"; Default=""; Hint="Пусто - все"; Items=@("","Procedure","Functions","Triggers","Tables","Views","Indexes","PK","FK","Grants") }, @{ Name="TaskName"; Label="Имя задачи (Jira)"; Default=""; Hint="Пусто - все типы" }); Handler="Invoke-OpSqlExport" },
    @{ Name="Compare SQL"; RusName="Сравнение SQL: Current и Main"; Description="Сравнение SQL-объектов задачи между БД Current и Main"; NeedsPassword=$true; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Пусто - все объекты" }); Handler="Invoke-OpCompareSql" },
    @{ Name="Compare & Verify"; RusName="Сравнение и проверка (Compare & Verify)"; Description="Сравнение выгрузок SQL, отчёт готовности и RFC в Jira"; NeedsPassword=$true; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }); Checkboxes=@(@{ Name="ShowDiff"; Label="Показать различия" }, @{ Name="CreateRFC"; Label="Создать RFC в Jira" }); Handler="Invoke-OpCompareVerify" },
    @{ Name="Create RFC"; RusName="Создание RFC в Jira"; Description="Создание задачи RFC в Jira"; NeedsPassword=$true; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }); Handler="Invoke-OpCreateRfc" },
    @{ Name="Jira Release Comment"; RusName="Комментарий в Jira: таблица объектов PB и SQL"; Description="Сканирует Ready_*, собирает объекты, добавляет комментарий в Jira"; NeedsPassword=$true; Fields=@(@{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Required=$true }, @{ Name="ProjectName"; Label="Проект PowerBuilder"; Default="AIS" }); Handler="Invoke-OpJiraComment" },
    @{ Name="VSS: Get Latest"; RusName="VSS: Получить последнюю версию"; Description="Обновление объектов VSS (задача / PBT / один объект)"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Если указать - объекты задачи" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path: $/SRC125/App.pbl" }, @{ Name="PbtFile"; Label="PBT-файл"; Default=""; Hint="PBT - обновит все PBL" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssGetLatest" },
    @{ Name="VSS: Check Status"; RusName="VSS: Проверить статус"; Description="Проверка статуса объектов VSS с таблицей результатов"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB Path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path" }, @{ Name="TaskName"; Label="Имя задачи (Jira)"; Default=""; Hint="Для проверки объектов из Ready_*" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssCheckStatus" },
    @{ Name="VSS: Who Is Using"; RusName="VSS: Кто использует"; Description="Просмотр кто извлёк объект из VSS"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB Path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path" }, @{ Name="TaskName"; Label="Имя задачи (Jira)"; Default=""; Hint="Для объектов из Ready_/Test_/Git_" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssWhoIsUsing" },
    @{ Name="VSS: Checkout"; RusName="VSS: Checkout (Извлечь)"; Description="Извлечение объектов из VSS для редактирования"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB Path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path" }, @{ Name="Comment"; Label="Комментарий"; Default="Checked out via AIS Release GUI"; Hint="Checkout Comment" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssCheckout" },
    @{ Name="VSS: Checkin"; RusName="VSS: Checkin (Сохранить)"; Description="Сохранение изменённых объектов в VSS"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB Path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path" }, @{ Name="Comment"; Label="Комментарий"; Default="Checked in via AIS Release GUI"; Hint="Checkin Comment" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssCheckin" },
    @{ Name="VSS: Undo Check Out"; RusName="VSS: Undo Check Out"; Description="Отмена извлечения объектов в VSS"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="VSS DB Path" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="VSS Username" }, @{ Name="Project"; Label="Объект VSS"; Default=$script:vssDefaults.project; Hint="VSS path" }, @{ Name="Comment"; Label="Комментарий"; Default="Undo via AIS Release GUI"; Hint="Комментарий" }); Checkboxes=@(@{ Name="Recursive"; Label="Рекурсивно" }); Handler="Invoke-OpVssUndo" },
    @{ Name="VSS: Object History"; RusName="VSS: История объекта"; Description="Показать все версии объекта в VSS с сравнением через TortoiseMerge и поиском текста"; NeedsPassword=$false; Fields=@(@{ Name="VssPath"; Label="Путь к БД VSS"; Default=$script:vssDefaults.db_path; Hint="" }, @{ Name="VssUser"; Label="Пользователь VSS"; Default=$script:vssDefaults.user; Hint="" }, @{ Name="TaskName"; Label="Task Name (Jira)"; Default=""; Hint="Необязательно" }, @{ Name="Project"; Label="Объект VSS"; Default=""; Hint="Имя объекта (w_...)" }); Handler="Invoke-OpVssHistory" }
)

# --- ПОСТРОЕНИЕ ГЛАВНОГО ОКНА ---
function Build-MainWindowUI {
    param([System.Windows.Window]$Window)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = "10"
    [void]$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    [void]$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    [void]$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    [void]$grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    # ROW 0: Список операций (ComboBox)
    $opPanel = New-Object Windows.Controls.StackPanel
    $opPanel.Margin = "0,0,0,6"
    $lblOp = New-Object Windows.Controls.TextBlock
    $lblOp.Text = "Операция:"
    $lblOp.FontSize = 10; $lblOp.Foreground = "#4A5568"; $lblOp.Margin = "3,0,0,1"
    [void]$opPanel.Children.Add($lblOp)

    $cmbOp = New-Object Windows.Controls.ComboBox
    $cmbOp.Name = "cmbOp"
    $cmbOp.FontSize = 12
    $cmbOp.Height = 30
    $i = 0
    foreach ($op in $operations) {
        $i++
        [void]$cmbOp.Items.Add("$i. $($op.RusName)")
    }
    $script:OpCombo = $cmbOp
    $cmbOp.Add_SelectionChanged({
        param($s, $e)
        $script:SelectedOpIndex = $s.SelectedIndex
        Select-Operation
    })
    [void]$opPanel.Children.Add($cmbOp)

    $txtDesc = New-Object Windows.Controls.TextBlock
    $txtDesc.Name = "txtDesc"
    $txtDesc.FontSize = 11
    $txtDesc.Foreground = "#4A5568"
    $txtDesc.TextWrapping = "Wrap"
    $txtDesc.Margin = "3,4,3,0"
    $script:OpDescText = $txtDesc
    [void]$opPanel.Children.Add($txtDesc)

    [System.Windows.Controls.Grid]::SetRow($opPanel, 0)
    $grid.Children.Add($opPanel)

    # ROW 1: Панель параметров (ScrollViewer)
    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = "Auto"
    $paramsPanel = New-Object Windows.Controls.StackPanel
    $paramsPanel.Name = "paramsPanel"
    $script:ParamsPanel = $paramsPanel
    $scroll.Content = $paramsPanel
    [System.Windows.Controls.Grid]::SetRow($scroll, 1)
    $grid.Children.Add($scroll)

    # ROW 2: Прогресс-бар (СТАНДАРТ2 §4)
    $pbPanel = New-Standard2ProgressBarPanel
    $script:PhaseLabel = $pbPanel.Tag.PhaseLabel
    $script:PhaseBar = $pbPanel.Tag.PhaseBar
    $script:StepLabel = $pbPanel.Tag.StepLabel
    $script:StepBar = $pbPanel.Tag.StepBar
    [System.Windows.Controls.Grid]::SetRow($pbPanel, 2)
    $grid.Children.Add($pbPanel)

    # ROW 3: Кнопки
    $btnPanel = New-Standard2ButtonPanel -Buttons @(
        @{ Name="btnRun"; Content="Выполнить"; Style="Primary"; Click={ Run-SelectedOperation } }
        @{ Name="btnHistory"; Content="История"; Style="Secondary"; Click={ Show-HistoryWindow } }
        @{ Name="btnExit"; Content="Выход"; Style="Secondary"; Click={ $script:MainWindow.Close() } }
    )
    Write-TechJournal "INFO" "Buttons registered: $($script:MainButtons.Keys -join ', ')"
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 3)
    $grid.Children.Add($btnPanel)

    $content = New-Standard2Wrapper -Window $Window -Content $grid -Title $Window.Title
    $Window.Content = $content
    $Window.Add_KeyDown({ if ($_.Key -eq "Escape") { $script:MainWindow.Close() } })

    # Выбрать первую операцию
    if ($cmbOp.Items.Count -gt 0) { $cmbOp.SelectedIndex = 0 }
}

function Select-Operation {
    $idx = $script:SelectedOpIndex
    if ($idx -lt 0 -or $idx -ge $operations.Count) { return }
    $op = $operations[$idx]
    Write-TechJournal "INFO" "Operation selected: $($op.Name)"

    if ($script:OpDescText) { $script:OpDescText.Text = $op.Description }

    $paramsPanel = $script:ParamsPanel
    if (-not $paramsPanel) { return }
    $paramsPanel.Children.Clear()
    $script:ParamsFields = @()

    # Settings — полноценная панель настроек (как в МОРДА)
    if ($op.Name -eq "Settings") {
        $script:settingsPanel = $paramsPanel
        try {
            Write-TechJournal "INFO" "Settings: calling Build-SettingsUI"
            Build-SettingsUI -Panel $paramsPanel -ConfigPath $script:ConfigPath -ProjectRoot $script:ProjectRoot
            Write-TechJournal "INFO" "Settings: calling Attach-SettingsHandlers"
            Attach-SettingsHandlers -Panel $paramsPanel -ConfigPath $script:ConfigPath -ProjectRoot $script:ProjectRoot
            Write-TechJournal "INFO" "Settings: calling Validate-AllPaths"
            Validate-AllPaths -Panel $paramsPanel -ProjectRoot $script:ProjectRoot
            Write-TechJournal "INFO" "Settings: UI ready"
        } catch {
            Write-TechJournal "ERROR" "Settings UI failed: $_"
            $errText = New-Object Windows.Controls.TextBlock
            $errText.Text = "Ошибка загрузки настроек: $_"
            $errText.Foreground = [Windows.Media.Brushes]::Red
            $errText.TextWrapping = "Wrap"
            [void]$paramsPanel.Children.Add($errText)
        }
        return
    }

    foreach ($f in $op.Fields) {
        $fieldName = $f.Name
        if ($f.Items -and $f.Items.Count -gt 0) {
            $comboPanel = New-Object Windows.Controls.StackPanel
            $comboPanel.Margin = "0,0,0,6"
            $cLbl = New-Object Windows.Controls.TextBlock
            $cLbl.Text = $f.Label; $cLbl.FontSize = 10; $cLbl.Foreground = "#4A5568"; $cLbl.Margin = "3,0,0,1"
            [void]$comboPanel.Children.Add($cLbl)
            $combo = New-Object Windows.Controls.ComboBox
            $combo.Name = "fld_$fieldName"
            $combo.Tag = $fieldName
            $combo.IsEditable = $true
            $combo.FontSize = 11
            foreach ($item in $f.Items) { [void]$combo.Items.Add($item) }
            if ($f.Default) { $combo.Text = $f.Default }
            [void]$comboPanel.Children.Add($combo)
            [void]$paramsPanel.Children.Add($comboPanel)
            $script:ParamsFields += @{ Name=$fieldName; Type="Combo"; Control=$combo; Required=$f.Required }
        } else {
            $textPanel = New-Object Windows.Controls.StackPanel
            $textPanel.Margin = "0,0,0,6"
            $tLbl = New-Object Windows.Controls.TextBlock
            $tLbl.Text = $f.Label; $tLbl.FontSize = 10; $tLbl.Foreground = "#4A5568"; $tLbl.Margin = "3,0,0,1"
            [void]$textPanel.Children.Add($tLbl)
            $tb = New-Object Windows.Controls.TextBox
            $tb.Name = "fld_$fieldName"
            $tb.Tag = $fieldName
            $tb.FontSize = 11
            $tb.MinHeight = 24
            if ($f.Default) { $tb.Text = $f.Default }
            [void]$textPanel.Children.Add($tb)
            [void]$paramsPanel.Children.Add($textPanel)
            $script:ParamsFields += @{ Name=$fieldName; Type="Text"; Control=$tb; Required=$f.Required }
        }
    }

    foreach ($cb in $op.Checkboxes) {
        $cbControl = New-Object Windows.Controls.CheckBox
        $cbControl.Name = "cb_$($cb.Name)"
        $cbControl.Content = $cb.Label
        $cbControl.Tag = $cb.Name
        $cbControl.FontSize = 11
        $cbControl.Margin = "0,4,0,4"
        [void]$paramsPanel.Children.Add($cbControl)
        $script:ParamsFields += @{ Name=$cb.Name; Type="Check"; Control=$cbControl; Required=$false }
    }

    if ($op.NeedsPassword) {
        $pwdPanel = New-Object Windows.Controls.StackPanel
        $pwdPanel.Margin = "0,0,0,6"
        $pLbl = New-Object Windows.Controls.TextBlock
        $pLbl.Text = "Пароль / Токен:"; $pLbl.FontSize = 10; $pLbl.Foreground = "#4A5568"; $pLbl.Margin = "3,0,0,1"
        [void]$pwdPanel.Children.Add($pLbl)
        $pwd = New-Object Windows.Controls.PasswordBox
        $pwd.Name = "pwdField"
        $pwd.Tag = "PASSWORD"
        $pwd.FontSize = 11
        $pwd.MinHeight = 24
        $script:PwdField = $pwd
        [void]$pwdPanel.Children.Add($pwd)
        # Авто-заполнение пароля из .local_secrets.json
        try {
            $secretsPath = Join-Path (Split-Path $script:ConfigPath -Parent) ".local_secrets.json"
            if (Test-Path $secretsPath) {
                $secrets = Get-Content $secretsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($secrets.sybase.password_encrypted) {
                    $mk = Get-MasterKey -ConfigPath $script:ConfigPath
                    if ($mk) {
                        $decPwd = Decrypt-Password -Encrypted $secrets.sybase.password_encrypted -Key $mk
                        if ($decPwd) { $pwd.Password = $decPwd; Write-TechJournal "INFO" "Password auto-filled from .local_secrets.json" }
                    }
                }
            }
        } catch { Write-TechJournal "WARN" "Auto-fill password failed: $_" }
        [void]$paramsPanel.Children.Add($pwdPanel)
        $script:ParamsFields += @{ Name="PASSWORD"; Type="Pwd"; Control=$pwd; Required=$true }
    }
}

function Get-OperationParams {
    $params = @{}
    foreach ($pf in $script:ParamsFields) {
        if ($pf.Type -eq "Text") {
            $params[$pf.Name] = $pf.Control.Text
        } elseif ($pf.Type -eq "Combo") {
            if ($pf.Control.Text) { $params[$pf.Name] = $pf.Control.Text }
            elseif ($pf.Control.SelectedItem) { $params[$pf.Name] = $pf.Control.SelectedItem.ToString() }
            else { $params[$pf.Name] = "" }
        } elseif ($pf.Type -eq "Check") {
            $params[$pf.Name] = [bool]$pf.Control.IsChecked
        } elseif ($pf.Type -eq "Pwd") {
            $params["Password"] = $pf.Control.Password
        }
    }
    if ($script:PwdField) { $params["Password"] = $script:PwdField.Password }
    return $params
}

function Run-SelectedOperation {
    Write-TechJournal "INFO" "Run-SelectedOperation: started"
    $idx = $script:SelectedOpIndex
    if ($idx -lt 0 -or $idx -ge $operations.Count) { 
        Write-TechJournal "ERROR" "Run-SelectedOperation: invalid index $idx"
        return 
    }
    $op = $operations[$idx]
    Write-TechJournal "CLICK" "Run: $($op.Name)"
    Write-TechJournal "INFO" "Run-SelectedOperation: PhaseBar exists = $($script:PhaseBar -ne $null)"

    $params = Get-OperationParams

    # Валидация обязательных полей
    $emptyRequired = @()
    foreach ($pf in $script:ParamsFields) {
        if ($pf.Required) {
            $val = $params[$pf.Name]
            if ([string]::IsNullOrWhiteSpace($val)) { $emptyRequired += $pf.Name }
        }
    }
    if ($op.NeedsPassword -and [string]::IsNullOrWhiteSpace($params["Password"])) {
        $emptyRequired += "Пароль / Токен"
    }
    if ($emptyRequired.Count -gt 0) {
        Write-TechJournal "ERROR" "Required fields empty: $($emptyRequired -join ', ')"
        Show-Standard2Message -Title "Обязательные поля" -Message "Заполните обязательные поля:`n$($emptyRequired -join "`n")"
        return
    }

    # VSS: инжекция пароля из Settings
    if ($op.Name -match '^VSS:' -and -not $params.ContainsKey("VssPass")) {
        $vssPwd = Get-VssPassword
        $params["VssPass"] = $vssPwd
    }

    # Выполнение
    $opName = $op.RusName
    $script:PhaseBar.Value = 10
    $script:PhaseLabel.Text = $opName
    $script:StepBar.IsIndeterminate = $true
    $script:StepLabel.Text = "Запуск..."

    try {
        # Settings — сохранение настроек (не через Handler)
        if ($op.Name -eq "Settings") {
            Write-TechJournal "INFO" "Settings: calling Save-Settings..."
            $script:PhaseBar.Value = 50
            $script:PhaseLabel.Text = "Сохранение..."
            $script:StepBar.IsIndeterminate = $false
            Save-Settings -Panel $script:settingsPanel -ConfigPath $script:ConfigPath -ProjectRoot $script:ProjectRoot
            $script:PhaseBar.Value = 100
            $script:PhaseLabel.Text = "Настройки сохранены"
            $script:StepBar.Value = 100
            $script:StepLabel.Text = "Готово"
            Write-TechJournal "INFO" "Settings saved"
            return
        }

        # Асинхронное выполнение в фоновом Runspace (UI не блокируется)
        $handlerName = $op.Handler

        $script:PhaseBar.Value = 10
        $script:PhaseLabel.Text = "Выполнение: $opName..."
        $script:StepBar.IsIndeterminate = $true
        $script:StepLabel.Text = "Ожидание..."

        $script:AsyncOp = Start-OpAsync -HandlerName $handlerName -Params $params -Password $params["Password"] -Checks $params -RusName $op.RusName
        Write-TechJournal "INFO" "Async started: $handlerName"

        # DispatcherTimer опрашивает завершение фоновой операции
        $script:OpTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:OpTimer.Interval = [TimeSpan]::FromMilliseconds(300)
        $script:OpTimer.Add_Tick({
            $state = $script:AsyncOp
            if (-not $state) { $script:OpTimer.Stop(); return }
            if ($state.Async.IsCompleted) {
                $script:OpTimer.Stop()
                try {
                    $output = $state.PowerShell.EndInvoke($state.Async) | Out-String
                } catch {
                    $output = "ERROR: $($_.Exception.Message)"
                }
                try { $state.PowerShell.Dispose() } catch { }
                try { $state.Runspace.Close() } catch { }
                $script:AsyncOp = $null

                $script:PhaseBar.Value = 100
                $script:PhaseLabel.Text = "Завершено"
                $script:StepBar.IsIndeterminate = $false
                $script:StepBar.Value = 100
                $script:StepLabel.Text = "Готово"

                $result = Get-OperationResult -OpName $state.Handler -Output $output
                $script:LastOpResult = $result
                $script:LastOpOutput = $output
                Write-TechJournal "INFO" "Operation done: $($state.Handler) -> $result"

                # Показываем результат (без модального окна для быстрых операций)
                if ($state.Handler -eq "Invoke-OpSettings") {
                    [System.Windows.MessageBox]::Show($result, "Результат", "OK", "Information")
                } elseif ($output -match '###VSS_STATUS###') {
                    Show-VssStatusWindow -Output $output
                } elseif ($output -match '###VALIDATION_ERROR###') {
                    Show-ValidationErrorWindow -Output $output
                } else {
                    Show-ResultWindow -OpName $state.RusName -Result $result -Output $output
                }
            } else {
                # Прогресс из синхронизированных хешей (общие для UI и Runspace)
                $phaseHadData = $false
                try {
                    $pp = $script:PhaseProgress
                    if ($pp) {
                        $v = [double]$pp.Value
                        if ($v -gt 0) {
                            $script:PhaseBar.Value = $v
                            $phaseHadData = $true
                        }
                        if ($pp.Text -and $pp.Text -ne '') {
                            $script:PhaseLabel.Text = [string]$pp.Text
                            $phaseHadData = $true
                        }
                    }
                } catch { }
                try {
                    $sp = $script:StepProgress
                    if ($sp) {
                        $sv = [double]$sp.Value
                        if ($sv -gt 0) {
                            $script:StepBar.IsIndeterminate = $false
                            $script:StepBar.Value = $sv
                        }
                        if ($sp.Text -and $sp.Text -ne '') {
                            $script:StepBar.IsIndeterminate = $false
                            $script:StepLabel.Text = [string]$sp.Text
                        }
                    }
                } catch { }
                # Пульс верхнего ПБ, если нет реальных данных от хендлера
                if (-not $phaseHadData) {
                    $newPulse = [Math]::Min(90, $script:PhaseBar.Value + 2)
                    if ($newPulse -ge 90) { $newPulse = 10 }
                    $script:PhaseBar.Value = $newPulse
                    if ([string]::IsNullOrEmpty($script:PhaseLabel.Text) -or $script:PhaseLabel.Text -eq "Выполнение: $opName...") {
                        $script:PhaseLabel.Text = "Выполнение: $opName..."
                    }
                }
                $script:OpTimer.Start()
            }
        })
        $script:OpTimer.Start()

    } catch {
        $script:PhaseBar.Value = 0
        $script:PhaseLabel.Text = "Ошибка"
        Write-TechJournal "ERROR" "Operation failed: $($op.Name) - $_"
        Show-ResultWindow -OpName $op.RusName -Result "Ошибка" -Output $_
    }
}

function Get-VssPassword {
    try {
        $mk = Get-MasterKey -ConfigPath $script:ConfigPath
        if ($mk) {
            $cfg = Get-Content $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.vss.password_encrypted) {
                return Decrypt-Password -Encrypted $cfg.vss.password_encrypted -Key $mk
            }
        }
    } catch { }
    return ""
}

function Get-OperationResult {
    param([string]$OpName, [string]$Output)
    if ($Output -match '###VSS_HISTORY_END###') { return "История получена" }
    if ($Output -match '###PROD_NONE###') { return "Нет объектов" }
    if ($Output -match '###PROD_OBJ###') { return "Готово" }
    if ($Output -match '###SQL_TASK_NONE###') { return "Нет SQL-объектов" }
    if ($Output -match 'Успешно: (\d+), Ошибок: (\d+)') { return "Успешно: $($matches[1]), Ошибок: $($matches[2])" }
    if ($Output -match 'Все тесты пройдены|ALL TESTS PASSED|ПРОЙДЕНЫ') { return "Тесты пройдены" }
    if ($Output -match 'ОШИБКА|ERROR|Exception') { return "Ошибка" }
    if ([string]::IsNullOrWhiteSpace($Output)) { return "Завершено" }
    $lastLines = ($Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 3
    return ($lastLines -join " ")
}

# --- АСИНХРОННЫЙ ЗАПУСК ОПЕРАЦИЙ (фоновый Runspace) ---
# Операции выполняются в отдельном Runspace, чтобы НЕ блокировать UI-поток.
# UI-поток (DispatcherTimer) опрашивает завершение и обновляет ПБ.
function Start-OpAsync {
    param([string]$HandlerName, $Params, $Password, $Checks, [string]$RusName)

    # Синхронизированные хеши: единый объект для UI-потока и Runspace
    $syncPhase = [hashtable]::Synchronized(@{Value=0; Text=''})
    $syncStep  = [hashtable]::Synchronized(@{Value=0; Text=''})
    $script:PhaseProgress = $syncPhase
    $script:StepProgress  = $syncStep

    # Собираем определения функций, нужных хендлеру (и его зависимостям)
    $defs = New-Object System.Collections.Generic.List[string]
    foreach ($cmd in Get-Command -CommandType Function) {
        $n = $cmd.Name
        if ($n -like 'Invoke-Op*' -or $n -in @('Write-TechJournal','Get-VssPassword','Get-MasterKey','Decrypt-Password')) {
            $defs.Add("function $n { $($cmd.Definition) }")
        }
    }

    # Проверяем, есть ли у хендлера параметр $checks
    $hasChecks = $false
    try {
        $hi = Get-Command $HandlerName -ErrorAction Stop
        $hasChecks = $hi.Parameters.ContainsKey('checks')
    } catch { }

    $call = "& $HandlerName -params `$script:opParams -password `$script:opPassword"
    if ($hasChecks) { $call += " -checks `$script:opChecks" }

    $esc = { param($v) ($v -replace "'", "''") }
    $fullScript = @"
Write-Output '###ASYNC_START###'
`$script:ConfigPath = '$(& $esc $script:ConfigPath)'
`$script:ProjectRoot = '$(& $esc $script:ProjectRoot)'
`$script:TechJournalPath = '$(& $esc $script:TechJournalPath)'
`$script:TechJournal = @()
`$script:PhaseProgress = `$args[3]
`$script:StepProgress  = `$args[4]
`$script:vssDefaults = @{ user = '$(& $esc $script:vssDefaults.user)'; db_path = '$(& $esc $script:vssDefaults.db_path)'; project = '$(& $esc $script:vssDefaults.project)'; ss_exe = '$(& $esc $script:vssDefaults.ss_exe)' }
`$script:opParams = `$args[0]
`$script:opPassword = `$args[1]
`$script:opChecks = `$args[2]
$($defs -join "`n")
$call
"@

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $null = $ps.AddScript($fullScript)
    $null = $ps.AddArgument($Params)
    $null = $ps.AddArgument($Password)
    $null = $ps.AddArgument($Checks)
    $null = $ps.AddArgument($syncPhase)
    $null = $ps.AddArgument($syncStep)
    $async = $ps.BeginInvoke()

    return @{ PowerShell = $ps; Async = $async; Runspace = $runspace; Handler = $HandlerName; RusName = $RusName }
}

# --- ДО РЕЗУЛЬТАТА (СТАНДАРТ2) ---
function Show-ResultWindow {
    param([string]$OpName, [string]$Result, [string]$Output)
    Write-TechJournal "CLICK" "Show-ResultWindow: $OpName"

    $window = New-Standard2Window -Title "Результат: $OpName" -Width 640 -Height 480
    Build-ResultWindowUI -Window $window -OpName $OpName -Result $Result -Output $Output
    $window.ShowDialog() | Out-Null
}

function Build-ResultWindowUI {
    param([System.Windows.Window]$Window, [string]$OpName, [string]$Result, [string]$Output)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = "10"
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    $resultBorder = New-Object Windows.Controls.Border
    $resultBorder.CornerRadius = 10
    $resultBorder.Background = [Windows.Media.Brushes]::White
    $resultBorder.Padding = "16,12,16,16"
    [System.Windows.Controls.Grid]::SetRow($resultBorder, 0)

    $resultBlock = New-Object Windows.Controls.TextBlock
    $resultBlock.Text = $Result
    $resultBlock.FontWeight = "Bold"
    $resultBlock.FontSize = 13
    $resultBlock.Foreground = "#1A3A60"
    $resultBlock.TextWrapping = "Wrap"
    $resultBorder.Child = $resultBlock
    [void]$grid.Children.Add($resultBorder)

    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = "Auto"
    $scroll.Margin = "0,6,0,0"
    $txt = New-Object Windows.Controls.TextBox
    $txt.Text = $Output
    $txt.FontFamily = "Consolas"
    $txt.FontSize = 11
    $txt.IsReadOnly = $true
    $txt.TextWrapping = "NoWrap"
    $txt.Background = [Windows.Media.Brushes]::White
    $txt.BorderBrush = "#CBD5E0"
    $txt.BorderThickness = 1
    $txt.Padding = "8"
    $txt.VerticalScrollBarVisibility = "Auto"
    $txt.HorizontalScrollBarVisibility = "Auto"
    $scroll.Content = $txt
    [System.Windows.Controls.Grid]::SetRow($scroll, 1)
    [void]$grid.Children.Add($scroll)

    $btnPanel = New-Standard2ButtonPanel -Buttons @(
        @{ Name="btnOk"; Content="OK"; Style="Primary"; IsDefault=$true; Click={ $Window.Close() } }
    )
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 2)
    [void]$grid.Children.Add($btnPanel)

    $content = New-Standard2Wrapper -Window $Window -Content $grid -Title $Window.Title
    $Window.Content = $content
    $Window.Add_KeyDown({ if ($_.Key -eq "Escape") { $Window.Close() } })
}

# --- ДО ВАЛИДАЦИИ (СТАНДАРТ2) ---
function Show-ValidationErrorWindow {
    param([string]$Output)
    Write-TechJournal "CLICK" "Show-ValidationErrorWindow"

    $errors = @()
    foreach ($l in ($Output -split "`r?`n")) {
        if ($l -match '^###VALIDATION_ERROR###\s*(.+)\|(.+)\|(.+)\|(.+)$') {
            $errors += [PSCustomObject]@{ Selected=$false; ObjectName=$matches[1]; Reason=$matches[2]; ReadyPath=$matches[3]; CurrentPath=$matches[4] }
        }
    }
    if ($errors.Count -eq 0) { return }

    $window = New-Standard2Window -Title "Ошибки валидации: $($errors.Count)" -Width 900 -Height 550
    Build-ValidationWindowUI -Window $window -Errors $errors
    $window.ShowDialog() | Out-Null
}

function Build-ValidationWindowUI {
    param([System.Windows.Window]$Window, [array]$Errors)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = "10"
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    $dg = New-Standard2DataGrid
    $dg.IsReadOnly = $false
    $dg.SelectionMode = "Extended"
    $dg.SelectionUnit = "FullRow"
    [System.Windows.Controls.Grid]::SetRow($dg, 0)
    $grid.Children.Add($dg)

    $cSel = New-Object Windows.Controls.DataGridCheckBoxColumn
    $cSel.Header = "Выбрать"; $cSel.Width = 60
    $binding = [Windows.Data.Binding]::new("Selected")
    $binding.Mode = [Windows.Data.BindingMode]::TwoWay
    $binding.UpdateSourceTrigger = [Windows.Data.UpdateSourceTrigger]::PropertyChanged
    $cSel.Binding = $binding
    [void]$dg.Columns.Add($cSel)

    $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header="Объект"; $c1.Binding=[Windows.Data.Binding]::new("ObjectName"); $c1.Width=180; $c1.IsReadOnly=$true; [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header="Причина"; $c2.Binding=[Windows.Data.Binding]::new("Reason"); $c2.Width=180; $c2.IsReadOnly=$true; [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header="Ready"; $c3.Binding=[Windows.Data.Binding]::new("ReadyPath"); $c3.Width=260; $c3.IsReadOnly=$true; [void]$dg.Columns.Add($c3)
    $c4 = New-Object Windows.Controls.DataGridTextColumn; $c4.Header="Current"; $c4.Binding=[Windows.Data.Binding]::new("CurrentPath"); $c4.Width=260; $c4.IsReadOnly=$true; [void]$dg.Columns.Add($c4)

    $dg.ItemsSource = $Errors
    $script:ValidationGrid = $dg

    $btnPanel = New-Standard2ButtonPanel -Buttons @(
        @{ Name="btnClose"; Content="Закрыть"; Style="Secondary"; Click={ $Window.Close() } }
    )
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 1)
    [void]$grid.Children.Add($btnPanel)

    $content = New-Standard2Wrapper -Window $Window -Content $grid -Title $Window.Title
    $Window.Content = $content
    $Window.Add_KeyDown({ if ($_.Key -eq "Escape") { $Window.Close() } })
}

# --- ДО VSS СТАТУС (СТАНДАРТ2) ---
function Show-VssStatusWindow {
    param([string]$Output)
    Write-TechJournal "CLICK" "Show-VssStatusWindow"

    $data = @()
    foreach ($l in ($Output -split "`r?`n")) {
        if ($l -match '^###VSS_STATUS###\s+([^|]+)\|([^|]*)\|([^|]+)\|([^|]*)\|(.*)$') {
            $statusText = switch ($matches[3]) { 'F' { 'Свободен' } 'B' { "Занят: $($matches[4])" } 'NF' { 'Не найден' } 'E' { 'Ошибка' } default { $matches[3] } }
            $srcText = switch ($matches[5]) { 'R' { 'Ready' } 'T' { 'Test' } 'G' { 'Git' } default { '' } }
            $data += [PSCustomObject]@{ ObjectName=$matches[1]; VssPath=$matches[2]; StatusText=$statusText; Source=$srcText }
        }
    }
    if ($data.Count -eq 0) { return }

    $window = New-Standard2Window -Title "VSS Статус: $($data.Count)" -Width 800 -Height 550
    Build-VssStatusWindowUI -Window $window -Data $data
    $window.ShowDialog() | Out-Null
}

function Build-VssStatusWindowUI {
    param([System.Windows.Window]$Window, [array]$Data)

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = "10"
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

    $free = ($Data | Where-Object { $_.StatusText -eq "Свободен" }).Count
    $busy = ($Data | Where-Object { $_.StatusText -like "Занят*" }).Count
    $nf = ($Data | Where-Object { $_.StatusText -eq "Не найден" }).Count

    $summary = New-Object Windows.Controls.TextBlock
    $summary.Text = "Всего: $($Data.Count) | Свободно: $free | Занято: $busy | Не найдено: $nf"
    $summary.FontSize = 13; $summary.FontWeight = "SemiBold"; $summary.Margin = "0,0,0,8"
    [System.Windows.Controls.Grid]::SetRow($summary, 0)
    [void]$grid.Children.Add($summary)

    $dg = New-Standard2DataGrid
    [System.Windows.Controls.Grid]::SetRow($dg, 1)
    $grid.Children.Add($dg)

    $c1 = New-Object Windows.Controls.DataGridTextColumn; $c1.Header="Объект"; $c1.Binding=[Windows.Data.Binding]::new("ObjectName"); $c1.Width=240; $c1.IsReadOnly=$true; [void]$dg.Columns.Add($c1)
    $c2 = New-Object Windows.Controls.DataGridTextColumn; $c2.Header="Статус"; $c2.Binding=[Windows.Data.Binding]::new("StatusText"); $c2.Width=300; $c2.IsReadOnly=$true; [void]$dg.Columns.Add($c2)
    $c3 = New-Object Windows.Controls.DataGridTextColumn; $c3.Header="Источник"; $c3.Binding=[Windows.Data.Binding]::new("Source"); $c3.Width=100; $c3.IsReadOnly=$true; [void]$dg.Columns.Add($c3)

    $dg.ItemsSource = $Data

    $btnPanel = New-Standard2ButtonPanel -Buttons @(
        @{ Name="btnClose"; Content="Закрыть"; Style="Secondary"; Click={ $Window.Close() } }
    )
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 2)
    [void]$grid.Children.Add($btnPanel)

    $content = New-Standard2Wrapper -Window $Window -Content $grid -Title $Window.Title
    $Window.Content = $content
    $Window.Add_KeyDown({ if ($_.Key -eq "Escape") { $Window.Close() } })
}

# --- ДО СООБЩЕНИЕ (СТАНДАРТ2) ---
function Show-Standard2Message {
    param([string]$Title, [string]$Message)
    $window = New-Standard2Window -Title $Title -Width 420 -Height 180
    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = "10"
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $txt = New-Object Windows.Controls.TextBlock
    $txt.Text = $Message
    $txt.FontSize = 12
    $txt.TextWrapping = "Wrap"
    $txt.Foreground = "#2D3748"
    [System.Windows.Controls.Grid]::SetRow($txt, 0)
    [void]$grid.Children.Add($txt)
    $btnPanel = New-Standard2ButtonPanel -Buttons @(
        @{ Name="btnOk"; Content="OK"; Style="Primary"; IsDefault=$true; Click={ $window.Close() } }
    )
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 1)
    [void]$grid.Children.Add($btnPanel)
    $content = New-Standard2Wrapper -Window $window -Content $grid -Title $Title
    $window.Content = $content
    $window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })
    $window.ShowDialog() | Out-Null
}

function Show-HistoryWindow {
    Write-TechJournal "CLICK" "Show-HistoryWindow"
    Show-Standard2Message -Title "История" -Message "История операций — в разработке"
}

# --- ЗАПУСК ---
function Main {
    # Защита от запуска нескольких экземпляров: если окно МОРДА2 уже открыто — завершаемся
    $existing = Get-Process | Where-Object { $_.MainWindowTitle -eq "МОРДА — Подготовка релизов" -and $_.Id -ne $PID }
    if ($existing) {
        if ($script:IsAutoTest) {
            Write-Host "AutoTest: closing existing MORDA2 processes..."
            $existing | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep 1
        } else {
            Write-Host "MORDA2 already running (PID $($existing.Id -join ', '))"
            exit 0
        }
    }

    Parse-AutoTestArgs
    Init-TechJournal
    Load-Config

    $mainWindow = New-Standard2Window -Title "МОРДА — Подготовка релизов" -Width 620 -Height 620
    $script:MainWindow = $mainWindow
    Build-MainWindowUI -Window $mainWindow

    if ($script:IsAutoTest) {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Add_Tick({
            $timer.Stop()
            Start-AutoTest
        })
        $timer.Start()
    }

    # Скруглённые углы (СТАНДАРТ2)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class RoundedWindow {
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateRoundRectRgn(int nL, int nT, int nR, int nB, int nWE, int nHE);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObj);
    public static void Apply(IntPtr hWnd, int w, int h) {
        var rgn = CreateRoundRectRgn(0,0,w+1,h+1,36,36);
        SetWindowRgn(hWnd, rgn, true); DeleteObject(rgn);
    }
}
"@
    $mainWindow.Add_Loaded({
        $src = [System.Windows.Interop.HwndSource]::FromVisual($mainWindow)
        $src.AddHook({
            param($h,$m,$w,$l,[ref]$hd)
            if ($m -eq 0x0084) {  # WM_NCHITTEST
                $x = $l.ToInt64() -band 0xFFFF; $y = ($l.ToInt64() -shr 16) -band 0xFFFF
                $pt = $mainWindow.PointFromScreen([System.Windows.Point]::new($x,$y))
                if ($pt.Y -lt 42 -and $pt.X -ge 8 -and $pt.X -le $mainWindow.ActualWidth-8 -and $pt.Y -ge 8) { $hd.Value = 2; return 0 }
            }
            return 0
        })
        $hWnd = ([System.Windows.Interop.WindowInteropHelper]::new($mainWindow)).Handle
        [RoundedWindow]::Apply($hWnd, $mainWindow.ActualWidth, $mainWindow.ActualHeight)
    })
    $mainWindow.Add_SizeChanged({
        $hWnd = ([System.Windows.Interop.WindowInteropHelper]::new($mainWindow)).Handle
        [RoundedWindow]::Apply($hWnd, $mainWindow.ActualWidth, $mainWindow.ActualHeight)
    })

    $mainWindow.ShowDialog() | Out-Null
    Write-TechJournal "INFO" "Application closed"
}

Main