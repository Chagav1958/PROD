param(
    [string]$Script,
    [string]$Arguments = ""
)

if ([string]::IsNullOrWhiteSpace($Script)) {
    Write-Host "Укажите имя скрипта: Launch-Hidden.ps1 -Script Show-*.ps1 [-Arguments \"-param value\"]"
    exit 1
}

$fullPath = if (Test-Path $Script) { $Script } else { Join-Path $PSScriptRoot $Script }
if (-not (Test-Path $fullPath)) {
    $name = Split-Path $Script -Leaf
    $altPath = Join-Path $PSScriptRoot $name
    if (Test-Path $altPath) { $fullPath = $altPath }
}

if (-not (Test-Path $fullPath)) {
    Write-Host "Скрипт не найден: $Script"
    exit 1
}

$argLine = "-NoProfile -STA -File `"$fullPath`""
if ($Arguments) { $argLine += " $Arguments" }

# Start-Process -WindowStyle Hidden — единственное, что не блокирует антивирус
Start-Process powershell -ArgumentList $argLine -WindowStyle Hidden