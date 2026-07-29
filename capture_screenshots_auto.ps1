# Автоматический захват скриншотов GUI
# Запускает GUI и делает скриншоты в различных состояниях

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient

$screenshotDir = "C:\AIS\AI\Prod\docs\screenshots"

function Capture-Screenshot {
    param([string]$FileName, [int]$Delay = 2)
    
    Start-Sleep -Seconds $Delay
    
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    
    $path = Join-Path $screenshotDir $FileName
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    Write-Host "Saved: $FileName"
    return $path
}

Write-Host "=== GUI Screenshot Capture ==="
Write-Host "Starting GUI..."

# Запуск GUI
$guiProcess = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File C:\AIS\AI\Prod\bin\Prod-GUI.ps1" -PassThru

Start-Sleep -Seconds 4

# 1. Главное окно
Write-Host "Capturing main window..."
Capture-Screenshot "gui_main_window.png" 2

# 2. Показать пароль (нужно кликнуть Show)
Write-Host "Clicking Show button..."
# Найти окно GUI
$guiWindow = Get-Process | Where-Object { $_.MainWindowTitle -like "*AIS Release*" }
if ($guiWindow) {
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 2
    Capture-Screenshot "gui_password_visible.png" 1
    
    # Скрыть пароль
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 2
    Capture-Screenshot "gui_password_hidden.png" 1
}

# 3. Compare & Verify
Write-Host "Selecting Compare & Verify..."
[System.Windows.Forms.SendKeys]::SendWait("%{DOWN}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
[System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
[System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 2
Capture-Screenshot "gui_compare_verify.png" 1

# 4. Запуск скрипта
Write-Host "Running script..."
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 5
Capture-Screenshot "gui_running.png" 1

Write-Host ""
Write-Host "All screenshots captured!"
Write-Host "Location: $screenshotDir"

# Закрыть GUI
$guiProcess.Kill()
