# PB-Service.ps1 — СЕРВИС PB: управление мерами защиты разработки PB/SQL
#
# Команда проекта: PBSERV / СЕРВИС PB
#
# Назначение:
#   - показать статус всех 5 мер защиты (включены/отключены);
#   - включить/отключить любую меру (rollback при блокировке разработки);
#   - запустить линтер Lint-PB.ps1 (мера M3) для папок Test_/Diag_;
#   - показать статистику срабатываний мер.
#
# Конфиг: config/pb_service.json
#
# Использование:
#   powershell -NoLogo -File scripts\PB-Service.ps1            # статус всех мер
#   powershell -NoLogo -File scripts\PB-Service.ps1 -On  m1    # включить меру M1
#   powershell -NoLogo -File scripts\PB-Service.ps1 -Off m1    # отключить меру M1
#   powershell -NoLogo -File scripts\PB-Service.ps1 -Lint -Dir <папка>  # прогнать линтер
#   powershell -NoLogo -File scripts\PB-Service.ps1 -Stats     # статистика

param(
    [string]$On,        # включить меру: m1..m5 или all
    [string]$Off,       # отключить меру: m1..m5 или all
    [switch]$Lint,      # запустить линтер
    [string]$Dir,       # папка для линтера (по умолчанию: C:\AIS\1 Release\SUPRT-19100\Test_*)
    [switch]$Stats      # показать статистику
)

$ErrorActionPreference = 'Stop'
$configFile = Join-Path $PSScriptRoot "..\config\pb_service.json"
$scriptRoot = $PSScriptRoot

function Load-Config {
    if (-not (Test-Path -LiteralPath $configFile)) {
        Write-Error "Конфиг не найден: $configFile"
        exit 1
    }
    return (Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Save-Config {
    param($Config)
    $json = $Config | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($configFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Show-Status {
    param($Config)
    Write-Output "=== СЕРВИС PB: статус мер ==="
    Write-Output ("Конфиг: " + $configFile)
    Write-Output ""
    $i = 0
    foreach ($p in $Config.measures.PSObject.Properties) {
        $i++
        $m = $p.Value
        $flag = if ($m.enabled) { "[ВКЛ]" } else { "[ВЫКЛ]" }
        Write-Output ("$flag $($p.Name) — $($m.name)")
        Write-Output ("      $($m.description)")
    }
    Write-Output ""
    $active = 0
    $total = 0
    foreach ($p in $Config.measures.PSObject.Properties) {
        $total++
        if ($p.Value.enabled) { $active++ }
    }
    Write-Output ("Активных мер: $active из $total")
}

function Set-Measure {
    param($Config, [string]$Key, [bool]$Enable)
    if ($Key -eq 'all') {
        foreach ($p in $Config.measures.PSObject.Properties) {
            $p.Value.enabled = $Enable
        }
        Save-Config -Config $Config
        Write-Output "Все меры: $(if ($Enable) {'включены'} else {'отключены'}). Сохранено."
        return
    }
    $norm = $Key.ToLower()
    # маппинг коротких имён m1..m5 на ключи конфига
    $keyMap = @{
        'm1' = 'm1_enforcer_allowlist'
        'm2' = 'm2_no_bash_bypass'
        'm3' = 'm3_linter'
        'm4' = 'm4_mandatory_claude'
        'm5' = 'm5_wait_mcp'
    }
    $cfgKey = $norm
    if ($keyMap.ContainsKey($norm)) { $cfgKey = $keyMap[$norm] }
    if ($Config.measures.PSObject.Properties.Name -notcontains $cfgKey) {
        Write-Error "Мера '$Key' не найдена. Допустимо: m1..m5 или all"
        exit 1
    }
    $Config.measures.$cfgKey.enabled = $Enable
    Save-Config -Config $Config
    $stateWord = if ($Enable) { 'включена' } else { 'отключена' }
    Write-Output "Мера ${cfgKey}: $stateWord. Сохранено."
}

function Show-Stats {
    param($Config)
    Write-Output "=== СЕРВИС PB: статистика ==="
    $s = $Config.stats
    Write-Output "  M1 (enforcer блокировок):  $($s.m1_enforcer_blocks)"
    Write-Output "  M3 (запусков линтера):     $($s.m3_lint_runs)"
    Write-Output "  M3 (находок линтера):      $($s.m3_lint_findings)"
    Write-Output "  M4 (валидаций claude_*):   $($s.m4_claude_validations)"
    Write-Output ""
    Write-Output "=== История (последние 20) ==="
    if ($Config.history.Count -eq 0) {
        Write-Output "  (пусто)"
    } else {
        $tail = @($Config.history) | Select-Object -Last 20
        foreach ($h in $tail) {
            Write-Output ("  [{0}] {1}" -f $h.time, $h.action)
        }
    }
}

function Add-History {
    param($Config, [string]$Action)
    $entry = [ordered]@{ time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss"); action = $Action }
    $Config.history = @($Config.history) + @($entry)
    if ($Config.history.Count -gt 100) {
        $Config.history = @($Config.history)[-100..-1]
    }
}

# --- разбор и выполнение ---
$config = Load-Config
$didSomething = $false

if ($On) {
    Set-Measure -Config $config -Key $On -Enable $true
    Add-History -Config $config -Action "включена мера $On"
    $didSomething = $true
}
if ($Off) {
    Set-Measure -Config $config -Key $Off -Enable $false
    Add-History -Config $config -Action "отключена мера $Off"
    $didSomething = $true
}
if ($Lint) {
    $lintArgs = @()
    if ($Dir) { $lintArgs += @('-Dir', $Dir) }
    $lintScript = Join-Path $scriptRoot "Lint-PB.ps1"
    if (-not (Test-Path -LiteralPath $lintScript)) {
        Write-Error "Линтер не найден: $lintScript"
        exit 1
    }
    Write-Output "Запуск линтера..."
    & powershell -NoLogo -File $lintScript @lintArgs
    $config.stats.m3_lint_runs = [int]$config.stats.m3_lint_runs + 1
    Add-History -Config $config -Action "запущен линтер (Dir=$Dir)"
    $didSomething = $true
}
if ($Stats) {
    Show-Stats -Config $config
    $didSomething = $true
}

if ($didSomething) {
    Save-Config -Config $config
}

if (-not $didSomething -or $Lint) {
    Show-Status -Config $config
    if ($Stats) { Show-Stats -Config $config }
}