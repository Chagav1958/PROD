<#
.SYNOPSIS
    Восстановление настроек PowerShell из архива
.DESCRIPTION
    Восстанавливает:
    - Profile файлы
    - PSReadline history
    - Registry settings
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath
)

if (-not (Test-Path $ZipPath)) {
    Write-Host "[ERROR] Архив не найден: $ZipPath" -ForegroundColor Red
    exit 1
}

Write-Host "=== Восстановление PowerShell ==="
Write-Host "Архив: $ZipPath"
Write-Host ""

# Создать временную папку
$tempDir = Join-Path $env:TEMP "powershell_restore_$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Распаковать архив
Write-Host "Распаковка..."
Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force

# Найти распакованную папку
$extractedDir = Get-ChildItem $tempDir -Directory | Select-Object -First 1
if (-not $extractedDir) {
    Write-Host "[ERROR] Ошибка распаковки" -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force
    exit 1
}

Write-Host "[OK] Распаковка завершена"
Write-Host ""

# 1. Profile файлы
$profileMappings = @(
    @{
        Name = "CurrentUser_profile"
        Src = Join-Path $extractedDir.FullName "CurrentUser_profile"
        Dst = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    }
    @{
        Name = "CurrentUser_profile_base"
        Src = Join-Path $extractedDir.FullName "CurrentUser_profile_base"
        Dst = "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
    }
)

foreach ($m in $profileMappings) {
    if (Test-Path $m.Src) {
        # Создать папку если не существует
        $dir = Split-Path $m.Dst -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Copy-Item $m.Src $m.Dst -Force
        Write-Host "[OK] $($m.Name) восстановлен"
    }
}

# 2. PSReadline history
$historySrc = Join-Path $extractedDir.FullName "ConsoleHost_history.txt"
$historyDst = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $historySrc) {
    $dir = Split-Path $historyDst -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item $historySrc $historyDst -Force
    Write-Host "[OK] PSReadline history восстановлен"
}

# 3. Registry
$regSrc = Join-Path $extractedDir.FullName "powershell_settings.reg"
if (Test-Path $regSrc) {
    Write-Host "Импорт registry (ручное подтверждение)..."
    Write-Host "Правая кнопка -> Merge для файла: $regSrc"
}

# Удалить временную папку
Remove-Item $tempDir -Recurse -Force

Write-Host ""
Write-Host "=== Восстановление завершено ==="
Write-Host ""
Write-Host "Перезапустите PowerShell для применения настроек."
