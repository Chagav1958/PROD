<#
.SYNOPSIS
    Логгер для TaskPlan — единый файл логов для анализа командой OUTPL.
.DESCRIPTION
    Все скрипты TaskPlan используют эту функцию для записи событий, ошибок и результатов.
    Лог-файл: temp\taskplan_last_output.log
#>
$script:TaskPlanLogFile = "C:\AIS\AI\Prod\temp\taskplan_last_output.log"

function Write-TaskPlanLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','PASS','FAIL','DEBUG')]
        [string]$Level = 'INFO',
        [string]$Source = ''
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $src = if ($Source) { " [$Source]" } else { '' }
    $line = "$timestamp [$Level]$src $Message"
    # Создаём файл если не существует (с BOM для PS 5.1 читаемости)
    if (-not (Test-Path $script:TaskPlanLogFile)) {
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($script:TaskPlanLogFile, "=== TaskPlan Log ===`r`n", $utf8Bom)
    }
    $line | Out-File $script:TaskPlanLogFile -Append -Encoding UTF8
}

function Clear-TaskPlanLog {
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($script:TaskPlanLogFile, "=== TaskPlan Log ===`r`n", $utf8Bom)
}

function Get-TaskPlanLog {
    param([int]$LastLines = 50)
    if (-not (Test-Path $script:TaskPlanLogFile)) { return @() }
    $lines = Get-Content $script:TaskPlanLogFile -Encoding UTF8
    if ($lines.Count -le $LastLines) { return $lines }
    return $lines[-$LastLines..-1]
}

# Функции доступны при dot-sourcing (не требуется Export-ModuleMember для . $path)
