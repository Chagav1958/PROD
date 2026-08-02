<# 
.SYNOPSIS
    Монитор GUI OpenCode — автопродолжение при "Streaming response failed"
.DESCRIPTION
    Использует UI Automation для поиска окна OpenCode, сканирует дерево элементов
    на наличие текста "Streaming response failed" и при находке посылает "ОО" + Enter.
    Запуск: powershell -NoLogo -File OpenCode-GUI-Watchdog.ps1 [-IntervalSec 5] [-Verbose]
#>

param(
    [int]$IntervalSec = 3,
    [switch]$Verbose
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = 'Continue'

Write-Host "[GUI-Watchdog] Запуск мониторинга OpenCode (интервал: ${IntervalSec}с)" -ForegroundColor Cyan

function Find-OpenCodeWindow {
    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )
    foreach ($w in $windows) {
        try {
            $procId = $w.Current.ProcessId
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -like "*OpenCode*") {
                return $w
            }
        } catch { }
    }
    return $null
}

function Search-ErrorText($element) {
    # Проверяем сам элемент
    try {
        $text = $element.Current.Name
        if ($text -and $text -match 'Streaming response failed') {
            return $element
        }
        $patterns = $element.GetSupportedPatterns()
        foreach ($p in $patterns) {
            if ($p.ProgrammaticName -eq 'ValuePatternIdentifiers.Pattern') {
                $valPattern = $element.GetCurrentPattern($p)
                if ($valPattern) {
                    $val = $valPattern.Current.Value
                    if ($val -and $val -match 'Streaming response failed') {
                        return $element
                    }
                }
            }
            if ($p.ProgrammaticName -eq 'TextPatternIdentifiers.Pattern') {
                $txtPattern = $element.GetCurrentPattern($p)
                if ($txtPattern) {
                    $txt = $txtPattern.DocumentRange.GetText(-1)
                    if ($txt -match 'Streaming response failed') {
                        return $element
                    }
                }
            }
        }
    } catch { }

    # Рекурсивно детей
    $children = $element.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($child in $children) {
        $found = Search-ErrorText $child
        if ($found) { return $found }
    }
    return $null
}

function Send-OO($window) {
    try {
        # Пробуем через ValuePattern на фокусном элементе
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($focused) {
            $valPattern = $focused.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            if ($valPattern) {
                $valPattern.SetValue("ОО")
                # Enter
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Write-Host "[GUI-Watchdog] Послано 'ОО'+Enter через ValuePattern" -ForegroundColor Green
                return $true
            }
        }
        # Fallback: SendKeys на окно
        $hwnd = $window.Current.NativeWindowHandle
        [System.Windows.Forms.SendKeys]::SendWait("ОО{ENTER}")
        Write-Host "[GUI-Watchdog] Послано 'ОО'+Enter через SendKeys (hwnd=$hwnd)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[GUI-Watchdog] Ошибка отправки: $_" -ForegroundColor Red
        return $false
    }
}

$lastAlert = 0
while ($true) {
    try {
        $win = Find-OpenCodeWindow
        if ($win) {
            if ($Verbose) { Write-Host "[GUI-Watchdog] Окно найдено: PID=$($win.Current.ProcessId)" }
            $found = Search-ErrorText $win
            if ($found) {
                $now = [DateTime]::Now.Ticks / 10000000
                if ($now - $lastAlert -gt 10) {  # не чаще раза в 10 сек
                    Write-Host "[GUI-Watchdog] Обнаружен 'Streaming response failed'!" -ForegroundColor Yellow
                    Send-OO $win
                    $lastAlert = $now
                }
            }
        } else {
            if ($Verbose) { Write-Host "[GUI-Watchdog] Окно OpenCode не найдено, жду..." }
        }
    } catch {
        Write-Host "[GUI-Watchdog] Ошибка цикла: $_" -ForegroundColor Red
    }
    Start-Sleep -Seconds $IntervalSec
}