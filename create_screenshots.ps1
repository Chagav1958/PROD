<#
.SYNOPSIS
    Автоматическое создание скриншотов GUI
.DESCRIPTION
    Запускает GUI и делает скриншоты различных состояний
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screenshotDir = "C:\AIS\AI\Prod\docs\screenshots"
if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
}

function Take-Screenshot {
    param([string]$FileName, [int]$Delay = 1000)
    
    Start-Sleep -Milliseconds $Delay
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bounds = $screen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    
    $path = Join-Path $screenshotDir $FileName
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    
    $graphics.Dispose()
    $bitmap.Dispose()
    
    Write-Host "Screenshot saved: $path"
}

Write-Host "Starting GUI..."
$guiProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File C:\AIS\AI\Prod\bin\Prod-GUI.ps1" -PassThru

Start-Sleep -Seconds 3

# Скриншот 1: Главное окно
Write-Host "Taking screenshot 1: Main window..."
Take-Screenshot "gui_main_window.png" 2000

# Скриншот 2: Показать пароль (нужно кликнуть на Show)
Write-Host "Taking screenshot 2: Password visible..."
# Эмуляция клика на кнопку Show сложна без UI Automation
# Пропускаем автоматический скриншот

# Скриншот 3: Compare & Verify
Write-Host "Taking screenshot 3: Compare & Verify..."
# Нужно изменить операцию в ComboBox - сложно автоматизировать

# Скриншот 4: Выполнение скрипта
Write-Host "Taking screenshot 4: Running..."
# Нужно запустить скрипт - сложно автоматизировать

Write-Host "`nScreenshots process completed."
Write-Host "Please manually create additional screenshots for:"
Write-Host "- Password visible (Show mode)"
Write-Host "- Password hidden (Hide mode)"
Write-Host "- Compare & Verify with checkboxes"
Write-Host "- Script execution with output"
Write-Host "`nSave them to: $screenshotDir"
