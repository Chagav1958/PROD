<# 
.SYNOPSIS
    Монитор GUI OpenCode — автопродолжение ТОЛЬКО если последнее сообщение "Streaming response failed"
.DESCRIPTION
    Находит поле ввода (TextBox/ContentEditable), проверяет что "Streaming response failed" 
    является ПОСЛЕДНИМ сообщением в чате, и только тогда вводит "ОО"+Enter.
    Запуск: powershell -NoLogo -File OpenCode-GUI-Watchdog-v2.ps1 [-IntervalSec 3] [-Verbose]
#>

param(
    [int]$IntervalSec = 3,
    [switch]$Verbose
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms

$ErrorActionPreference = 'Continue'

Write-Host "[GUI-Watchdog v2] Запуск мониторинга OpenCode (интервал: ${IntervalSec}с)" -ForegroundColor Cyan

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

# Найти поле ввода (TextBox, TextArea, ContentEditable)
function Find-InputField($window) {
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $all = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    
    # 1. Сначала ищем по плейсхолдеру (самое точное для OpenCode)
    foreach ($el in $all) {
        try {
            $name = $el.Current.Name
            if ($name -and $name -like 'Ask anything*') {
                $patterns = $el.GetSupportedPatterns()
                foreach ($p in $patterns) {
                    if ($p.ProgrammaticName -like '*ValuePattern*' -or $p.ProgrammaticName -like '*TextPattern*') {
                        if ($Verbose) { Write-Host "[Watchdog] Найдено поле ввода по плейсхолдеру: '$name'" }
                        return $el
                    }
                }
            }
        } catch { }
    }
    
    # 2. Fallback: Edit/Document/Text с ValuePattern/TextPattern
    foreach ($el in $all) {
        try {
            $ctrlType = $el.Current.ControlType
            $patterns = $el.GetSupportedPatterns()
            $isInput = $false
            
            if ($ctrlType -eq [System.Windows.Automation.ControlType]::Edit -or
                $ctrlType -eq [System.Windows.Automation.ControlType]::Document -or
                $ctrlType -eq [System.Windows.Automation.ControlType]::Text) {
                $isInput = $true
            }
            foreach ($p in $patterns) {
                if ($p.ProgrammaticName -like '*ValuePattern*' -or $p.ProgrammaticName -like '*TextPattern*') {
                    $isInput = $true
                    break
                }
            }
            if ($isInput) {
                try {
                    $valPattern = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
                    if ($valPattern -and $valPattern.Current.IsReadOnly) { continue }
                } catch { }
                if ($Verbose) { Write-Host "[Watchdog] Найдено поле ввода (fallback): Type=$ctrlType, Name='$($el.Current.Name)'" }
                return $el
            }
        } catch { }
    }
    return $null
}

# Получить все сообщения чата в порядке появления (последнее = последнее)
function Get-ChatMessages($window) {
    $messages = @()
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $all = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    foreach ($el in $all) {
        try {
            # Ищем элементы с текстом сообщений (Name, ValuePattern, TextPattern)
            $text = $null
            $valPattern = $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            if ($valPattern) { $text = $valPattern.Current.Value }
            if (-not $text) {
                $txtPattern = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
                if ($txtPattern) { $text = $txtPattern.DocumentRange.GetText(-1) }
            }
            if (-not $text) { $text = $el.Current.Name }
            
            if ($text -and $text.Trim().Length -gt 5) {
                # Примерный heuristic: сообщения чата часто в ListItem, Group, Custom, TextBlock
                $ctrlType = $el.Current.ControlType
                if ($ctrlType -in @(
                    [System.Windows.Automation.ControlType]::Text,
                    [System.Windows.Automation.ControlType]::TextBlock,
                    [System.Windows.Automation.ControlType]::Custom,
                    [System.Windows.Automation.ControlType]::Group,
                    [System.Windows.Automation.ControlType]::ListItem
                )) {
                    $messages += @{
                        Element = $el
                        Text    = $text.Trim()
                        Bounds  = $el.Current.BoundingRectangle
                    }
                }
            }
        } catch { }
    }
    # Сортируем по Y (вертикальное положение) — последние внизу
    $messages = $messages | Sort-Object { $_.Bounds.Bottom }
    return $messages
}

function Send-OO-ToInput($inputEl) {
    try {
        # Пробуем ValuePattern
        $valPattern = $inputEl.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ($valPattern -and -not $valPattern.Current.IsReadOnly) {
            $valPattern.SetValue("ОО")
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
            return $true
        }
        # Пробуем TextPattern (ContentEditable)
        $txtPattern = $inputEl.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
        if ($txtPattern) {
            $range = $txtPattern.DocumentRange
            $range.Select()
            Start-Sleep -Milliseconds 50
            [System.Windows.Forms.SendKeys]::SendWait("ОО{ENTER}")
            return $true
        }
        # Fallback: фокус + SendKeys
        $inputEl.SetFocus()
        Start-Sleep -Milliseconds 50
        [System.Windows.Forms.SendKeys]::SendWait("ОО{ENTER}")
        return $true
    } catch {
        Write-Host "[Watchdog] Ошибка ввода: $_" -ForegroundColor Red
        return $false
    }
}

$lastTriggerTime = 0
$lastProcessedHash = ""

while ($true) {
    try {
        $win = Find-OpenCodeWindow
        if ($win) {
            if ($Verbose) { Write-Host "[Watchdog] Окно найдено: PID=$($win.Current.ProcessId)" }
            
            # Находим поле ввода
            $inputField = Find-InputField $win
            if (-not $inputField) {
                if ($Verbose) { Write-Host "[Watchdog] Поле ввода не найдено" }
                Start-Sleep -Seconds $IntervalSec
                continue
            }
            
            # Получаем сообщения чата
            $messages = Get-ChatMessages $win
            if ($messages.Count -eq 0) {
                Start-Sleep -Seconds $IntervalSec
                continue
            }
            
            # Берём ПОСЛЕДНЕЕ сообщение
            $lastMsg = $messages[-1]
            $lastText = $lastMsg.Text
            
            # Хэш для дедупа (текст + позиция)
            $currentHash = [System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lastText + $lastMsg.Bounds.Bottom)).ToString()
            
            # Проверяем: последнее сообщение содержит ошибку И это новое сообщение
            if ($lastText -match 'Streaming response failed' -and $currentHash -ne $lastProcessedHash) {
                $now = [DateTime]::Now.Ticks / 10000000
                if ($now - $lastTriggerTime -gt 15) {  # не чаще раза в 15 сек
                    Write-Host "[Watchdog] Последнее сообщение: 'Streaming response failed' — ввожу 'ОО'" -ForegroundColor Yellow
                    $ok = Send-OO-ToInput $inputField
                    if ($ok) {
                        Write-Host "[Watchdog] 'ОО'+Enter отправлено в поле ввода" -ForegroundColor Green
                        $lastTriggerTime = $now
                        $lastProcessedHash = $currentHash
                    } else {
                        Write-Host "[Watchdog] Не удалось ввести" -ForegroundColor Red
                    }
                }
            }
        } else {
            if ($Verbose) { Write-Host "[Watchdog] Окно OpenCode не найдено" }
        }
    } catch {
        Write-Host "[Watchdog] Ошибка цикла: $_" -ForegroundColor Red
    }
    Start-Sleep -Seconds $IntervalSec
}