# AutoClick-ProdObr.ps1 — UI Automation тест кнопки ПРОДОБР
param(
    [int]$Timeout = 60
)

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# Запускаем GUI
Write-Host "[1] Launching GUI..."
$guiProc = Start-Process powershell -ArgumentList @(
    "-NoLogo", "-ExecutionPolicy", "RemoteSigned",
    "-File", "C:\AIS\AI\Prod\scripts\Show-ProdObr-GUI.ps1"
) -PassThru -WindowStyle Normal

Write-Host "    PID=$($guiProc.Id) — waiting for window..."

# Ждём появления окна
$window = $null
$endTime = (Get-Date).AddSeconds($Timeout)
while ((Get-Date) -lt $endTime -and -not $window) {
    Start-Sleep -Milliseconds 500
    $window = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
        [System.Windows.Automation.TreeScope]::Children,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, "ПРОДОБР"
        ))
    )
}
if (-not $window) { Write-Host "    TIMEOUT: window not found"; $guiProc.Kill(); exit 1 }
Write-Host "    Window found: $($window.Current.Name)"

# Ждём кнопку "Запустить обработку"
Write-Host "[2] Finding button..."
$btn = $null
$endTime = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $endTime -and -not $btn) {
    Start-Sleep -Milliseconds 500
    $buttons = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        ))
    )
    foreach ($b in $buttons) {
        if ($b.Current.Name -eq "Запустить обработку" -and $b.Current.IsEnabled) {
            $btn = $b; break
        }
    }
}
if (-not $btn) { Write-Host "    Button not found"; $guiProc.Kill(); exit 1 }
Write-Host "    Found: $($btn.Current.Name) (enabled=$($btn.Current.IsEnabled))"

# Кликаем
Write-Host "[3] Clicking..."
$clickPattern = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$clickPattern.Invoke()
Write-Host "    Clicked!"

# Ждём завершения (PhaseBar.Value = 100)
Write-Host "[4] Waiting for completion..."
$endTime = (Get-Date).AddSeconds($Timeout)
$done = $false
while ((Get-Date) -lt $endTime -and -not $done) {
    Start-Sleep -Seconds 1
    $bars = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ProgressBar
        ))
    )
    foreach ($bar in $bars) {
        try {
            $rp = $bar.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
            $val = $rp.Current.Value
            if ($val -ge 100) { $done = $true }
        } catch {}
    }
    # Also check if Run button is re-enabled
    $allBtns = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        ))
    )
    foreach ($b in $allBtns) {
        if ($b.Current.Name -eq "Запустить обработку" -and $b.Current.IsEnabled) {
            $done = $true
        }
    }
    Write-Host "    ." -NoNewline
}
Write-Host ""

# Проверяем результат
Write-Host "[5] Checking result..."
Start-Sleep -Seconds 1
$phaseText = ""
$txts = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Text
    ))
)
foreach ($t in $txts) {
    $n = $t.Current.Name
    if ($n -match "Готово") { $phaseText = $n; break }
}
Write-Host "    Phase: $phaseText"

if ($phaseText -match "Готово") {
    Write-Host "    PASSED"
} else {
    Write-Host "    WARN: completion not confirmed"
}

# Закрываем
Write-Host "[6] Closing..."
$exitBtn = $null
$allBtns = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    ))
)
foreach ($b in $allBtns) {
    if ($b.Current.Name -eq "Закрыть") { $exitBtn = $b; break }
}
if ($exitBtn) {
    $exitBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Write-Host "    Closed"
} else {
    $guiProc.Kill()
}

# Читаем техжурнал
Write-Host "[7] Journal:"
$log = Get-ChildItem $env:TEMP -Filter "prodobr_journal_*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($log) {
    $content = Get-Content $log.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    $errors = ($content | Select-String '\[ERROR\]|\[FATAL\]').Count
    Write-Host "    File: $($log.Name)"
    Write-Host "    Errors: $errors"
    if ($errors -gt 0) { Write-Host "    FAILED" } else { Write-Host "    PASSED" }
}
