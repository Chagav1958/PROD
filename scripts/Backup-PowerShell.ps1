<#
.SYNOPSIS
    Резервное копирование настроек PowerShell
.DESCRIPTION
    Сохраняет:
    - Profile: Microsoft.PowerShell_profile.ps1
    - Profile: profile.ps1
    - PSReadline history: ConsoleHost_history.txt
    - Пользовательские модули: $env:PSModulePath
    - Registry: HKCU\Software\Microsoft\PowerShell
#>

$projectRoot = "C:\AIS\AI\Prod"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $projectRoot "archives\powershell_backup\backup_$timestamp"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

Write-Host "=== Резервное копирование PowerShell ==="
Write-Host "Дата: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
Write-Host "Папка: $backupDir"
Write-Host ""

# 1. Profile файлы
$profilePaths = @(
    @{
        Name = "CurrentUser_profile"
        Path = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    }
    @{
        Name = "CurrentUser_profile_base"
        Path = "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1"
    }
    @{
        Name = "AllUsers_profile"
        Path = "C:\Windows\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1"
    }
    @{
        Name = "AllUsers_profile_base"
        Path = "C:\Windows\System32\WindowsPowerShell\v1.0\profile.ps1"
    }
)

foreach ($p in $profilePaths) {
    if (Test-Path $p.Path) {
        $dst = Join-Path $backupDir $p.Name
        Copy-Item $p.Path $dst -Force
        Write-Host "[OK] $($p.Name)"
    }
}

# 2. PSReadline history
$historyPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
if (Test-Path $historyPath) {
    $dst = Join-Path $backupDir "ConsoleHost_history.txt"
    Copy-Item $historyPath $dst -Force
    Write-Host "[OK] PSReadline history"
}

# 3. Export registry settings
$regPath = "HKCU:\Software\Microsoft\PowerShell"
if (Test-Path $regPath) {
    $regFile = Join-Path $backupDir "powershell_settings.reg"
    try {
        reg export $regPath $regFile /y 2>&1 | Out-Null
        if (Test-Path $regFile) {
            Write-Host "[OK] Настройки реестра"
        }
    } catch {
        Write-Host "[ПРОПУСК] Экспорт реестра не удался"
    }
}

# 4. Export module list
$modulesFile = Join-Path $backupDir "modules_list.txt"
Get-Module -ListAvailable | Select-Object Name, Version, ModuleBase | Format-Table -AutoSize | Out-File $modulesFile -Encoding UTF8
Write-Host "[OK] Список модулей"

# 5. Export PSModulePath
$modulePathFile = Join-Path $backupDir "psmodulepath.txt"
$env:PSModulePath -split ';' | Out-File $modulePathFile -Encoding UTF8
Write-Host "[OK] PSModulePath"

# Создать ZIP-архив
$zipPath = Join-Path $projectRoot "archives\powershell_backup\powershell_backup_$timestamp.zip"
Write-Host ""
Write-Host "Создание ZIP-архива..."
Compress-Archive -Path $backupDir -DestinationPath $zipPath -Force

# Удалить временную папку
Remove-Item $backupDir -Recurse -Force

Write-Host ""
Write-Host "=== Готово ==="
Write-Host "Архив: $zipPath"
Write-Host ""
Write-Host "Для восстановления:"
Write-Host "1. Распаковать архив во временную папку"
Write-Host "2. Скопировать profile файлы обратно в WindowsPowerShell"
Write-Host "3. Скопировать ConsoleHost_history.txt в AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline"
Write-Host "4. Импортировать registry если нужно (правая кнопка -> Merge)"
