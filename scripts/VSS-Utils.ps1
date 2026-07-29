<#
.SYNOPSIS
    VSS (Microsoft Visual SourceSafe) integration utilities.
.DESCRIPTION
    Provides functions to interact with VSS:
    - Get latest version from VSS
    - Check file status (Checked In/Out)
    - Find who is using a file
    - Checkout files for editing
.PARAMETER VssPath
    Path to VSS database (srcsafe.ini)
.PARAMETER Username
    VSS username
.PARAMETER Password
    VSS password
.EXAMPLE
    .\VSS-Utils.ps1 -VssPath "\\server\vss\srcsafe.ini" -Username "user" -Password "pass"
#>

param(
    [string]$VssPath = "",
    [string]$Username = "",
    [string]$Password = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Continue"

# VSS executable path
$ssExe = "C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe"

if (-not (Test-Path $ssExe)) {
    throw "VSS не найден по пути: $ssExe"
}

# Set VSS environment (strip srcsafe.ini filename if provided)
if ($VssPath) {
    $vssDir = $VssPath
    if ($vssDir -match 'srcsafe\.ini$') {
        $vssDir = [System.IO.Path]::GetDirectoryName($vssDir)
    }
    $env:SSDIR = $vssDir
}

function Invoke-VssCommand {
    param(
        [string]$Command,
        [string]$Project = "$/",
        [string]$Comment = "",
        [switch]$Recursive
    )
    
    $args = @($Command, $Project, "-I-Y")
    
    if ($Username) { $args += "-Y$Username,$Password" }
    if ($Comment) { $args += "-C`"$Comment`"" }
    if ($Recursive) { $args += "-R" }
    
    "# Выполнение: ss.exe $($args -join ' ')"
    & $ssExe @args 2>&1
}

function Get-VssLatest {
    param(
        [string]$Project = "$/",
        [switch]$Recursive
    )
    
    "--- Получение последней версии: $Project ---"
    Invoke-VssCommand -Command "Get" -Project $Project -Recursive:$Recursive | ForEach-Object {
        if ($_ -match "^You have the latest version of (.+)$") { "Последняя версия уже загружена: $($matches[1])" }
        elseif ($_ -match "^Getting (.+)$") { "Загрузка: $($matches[1])" }
        elseif ($_ -match "^You now have (.+)$") { "Загружено: $($matches[1])" }
        elseif ($_ -match "^(.*)already have(.*)$") { "$($matches[1])уже есть$($matches[2])" }
        else { $_ }
    }
    "--- Загрузка завершена ---"
}

function Get-VssStatus {
    param(
        [string]$Project = "$/",
        [switch]$Recursive
    )
    
    "--- Проверка статуса: $Project ---"
    $checkedOut = 0
    Invoke-VssCommand -Command "Status" -Project $Project -Recursive:$Recursive | ForEach-Object {
        if ($_ -eq "No checked out files found.") {
            $checkedOut = -1
            "Статус: извлечённые файлы не найдены (все Checked In)"
        } else {
            $_
            if ($_ -match "\s+(Exc|Out)\s+") { $checkedOut++ }
        }
    }
    if ($checkedOut -gt 0) { "Статус: найдено $checkedOut извлечённых файлов" }
    "--- Проверка завершена ---"
}

function Get-VssWhoIsUsing {
    param(
        [string]$Project = "$/",
        [switch]$Recursive
    )
    
    "--- Кто использует объект: $Project ---"
    $found = $false
    Invoke-VssCommand -Command "Status" -Project $Project -Recursive:$Recursive | ForEach-Object {
        if ($_ -match "^\s*No checked out files found\.?\s*$") {
            "Объект не извлечён никем"
        }
        elseif ($_ -match "\S") {
            $found = $true
            $_
        }
    }
    if (-not $found) {
        "Объект не извлечён никем"
    }
    "--- Проверка завершена ---"
}

function Set-VssCheckout {
    param(
        [string]$Project = "$/",
        [string]$Comment = "Checked out for editing",
        [switch]$Recursive
    )
    
    "--- Извлечение объекта: $Project ---"
    Invoke-VssCommand -Command "Checkout" -Project $Project -Comment $Comment -Recursive:$Recursive
    "--- Объект извлечён для редактирования ---"
}

function Set-VssCheckin {
    param(
        [string]$Project = "$/",
        [string]$Comment = "Checked in",
        [switch]$Recursive
    )
    
    "--- Сохранение объекта: $Project ---"
    Invoke-VssCommand -Command "Checkin" -Project $Project -Comment $Comment -Recursive:$Recursive
    "--- Объект сохранён ---"
}

function Set-VssUndoCheckout {
    param(
        [string]$Project = "$/",
        [string]$Comment = "",
        [switch]$Recursive
    )
    
    "--- Снятие резервирования: $Project ---"
    Invoke-VssCommand -Command "UndoCheckout" -Project $Project -Comment $Comment -Recursive:$Recursive
    "--- Резервирование снято ---"
}

# Export functions (only when imported as module)
if ($MyInvocation.MyCommand.CommandType -eq 'Script') {
    Export-ModuleMember -Function Get-VssLatest, Get-VssStatus, Get-VssWhoIsUsing, Set-VssCheckout, Set-VssCheckin, Set-VssUndoCheckout -ErrorAction SilentlyContinue
}

if (-not $Quiet) {
    "VSS Utils loaded. Команды:"
    "  Get-VssLatest [-Project `"`$/Project`"`"] [-Recursive] - получить последнюю версию"
    "  Get-VssStatus [-Project `"`$/Project`"`"] [-Recursive] - статус объектов"
    "  Get-VssWhoIsUsing [-Project `"`$/Project`"`"] - свойства / кто использует"
    "  Set-VssCheckout [-Project `"`$/Project`"`"] [-Comment `"text`"] [-Recursive] - извлечь"
    "  Set-VssCheckin [-Project `"`$/Project`"`"] [-Comment `"text`"] [-Recursive] - сохранить"
    "  Set-VssUndoCheckout [-Project `"`$/Project`"`"] [-Recursive] - снять резервирование"
}