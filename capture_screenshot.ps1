# Ручной захват скриншотов GUI
# Запустите GUI, переключите в нужное состояние, затем запустите этот скрипт

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screenshotDir = "C:\AIS\AI\Prod\docs\screenshots"

Write-Host "=== GUI Screenshot Capture ==="
Write-Host ""
Write-Host "Instructions:"
Write-Host "1. Make sure GUI is open and in the desired state"
Write-Host "2. Press ENTER to capture screenshot"
Write-Host "3. Enter filename (or use default)"
Write-Host ""

$defaultNames = @(
    "gui_main_window.png",
    "gui_password_visible.png",
    "gui_password_hidden.png",
    "gui_compare_verify.png",
    "gui_running.png"
)

foreach ($defaultName in $defaultNames) {
    $path = Join-Path $screenshotDir $defaultName
    if (Test-Path $path) {
        Write-Host "[$defaultName] - already exists"
    } else {
        Write-Host "[$defaultName] - MISSING"
    }
}

Write-Host ""
Write-Host "Press ENTER to capture screenshot, or Q to quit..."
$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

if ($key.Character -ne 'q' -and $key.Character -ne 'Q') {
    Write-Host ""
    Write-Host "Enter filename (or press ENTER for auto-name):"
    $fileName = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "gui_screenshot_$timestamp.png"
    }
    
    Start-Sleep -Seconds 1
    
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    
    $path = Join-Path $screenshotDir $fileName
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    
    Write-Host "Screenshot saved: $path"
}
