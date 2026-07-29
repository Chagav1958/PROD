# Скрипт для захвата скриншотов GUI
# Запускает GUI и делает скриншоты в различных состояниях

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screenshotDir = "C:\AIS\AI\Prod\docs\screenshots"
if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
}

function Capture-Screenshot {
    param([string]$FileName)
    
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    
    $path = Join-Path $screenshotDir $FileName
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    Write-Host "Screenshot saved: $path"
}

Write-Host "=== GUI Screenshot Capture ==="
Write-Host "Screenshots will be saved to: $screenshotDir"
Write-Host ""
Write-Host "Instructions:"
Write-Host "1. GUI will start automatically"
Write-Host "2. Make screenshots manually or use the script below"
Write-Host "3. Save screenshots as:"
Write-Host "   - gui_main_window.png (main window with operation selected)"
Write-Host "   - gui_password_visible.png (password field with Show clicked)"
Write-Host "   - gui_password_hidden.png (password field with Hide clicked)"
Write-Host "   - gui_compare_verify.png (Compare & Verify with checkboxes)"
Write-Host "   - gui_running.png (during script execution)"
Write-Host ""
Write-Host "Starting GUI..."

# Запуск GUI
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File C:\AIS\AI\Prod\bin\Prod-GUI.ps1"

Start-Sleep -Seconds 3

Write-Host ""
Write-Host "GUI started. Now make screenshots manually:"
Write-Host "1. Main window - press PrintScreen and save as gui_main_window.png"
Write-Host "2. Click Show button - save as gui_password_visible.png"
Write-Host "3. Click Hide button - save as gui_password_hidden.png"
Write-Host "4. Select 'Compare & Verify' - save as gui_compare_verify.png"
Write-Host "5. Click Run and wait for output - save as gui_running.png"
Write-Host ""
Write-Host "Or use PowerShell to capture:"
Write-Host "  .\capture_screenshots.ps1 (this script in interactive mode)"
