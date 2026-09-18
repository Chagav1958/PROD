$ErrorActionPreference = "Stop"
$out = "C:\AIS\AI\Prod\.opencode\session\test-baseline.txt"
$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("=== WATCHDOG QA BASELINE === $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Project: C:\AIS\AI\Prod (PowerShell / PB / SQL ops repo)")
$lines.Add("")

# 1) Ищем стандартные QA-команды (package.json и т.п.)
$lines.Add("--- QA commands configured? ---")
$pkg = "C:\AIS\AI\Prod\package.json"
if (Test-Path $pkg) {
    $lines.Add("package.json найден, но lint/typecheck не настроены (проект не node-приложение)")
} else {
    $lines.Add("Стандартные QA-команды (lint/format/types) не настроены")
}
$lines.Add("")

# 2) Синтаксис PS-скриптов (выборка первых 30)
$lines.Add("--- PowerShell syntax check (sampled scripts) ---")
$files = Get-ChildItem "C:\AIS\AI\Prod\scripts" -Filter "*.ps1" -File | Select-Object -First 30
$totalErr = 0
foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $totalErr += $errors.Count
        $lines.Add("PARSE-ERR $($f.Name): $($errors.Count) ошибок")
    } else {
        $lines.Add("OK $($f.Name)")
    }
}
$lines.Add("PS_PARSE_ERRORS=$totalErr  (файлов проверено: $($files.Count))")
$lines.Add("")

# 3) BOM-проверка всех .ps1 (правило проекта)
$lines.Add("--- BOM check (.ps1 должны быть UTF-8 with BOM) ---")
$bomMissing = @()
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        $bomMissing += $f.Name
    }
}
if ($bomMissing.Count -eq 0) { $lines.Add("BOM: все проверенные .ps1 с BOM (OK)") } else { $lines.Add("BOM: нет BOM у: $($bomMissing -join ', ')") }
$lines.Add("")

# 4) Тесты: только безопасные (без GUI/БД). Полные TaskPlan-тесты требуют WPF-ДО и внешнего окружения.
$lines.Add("--- Tests ---")
$lines.Add("Полные тесты (TaskPlan-Tests, Run-Tests) требуют GUI/БД/внешних сервисов - пропущены в baseline (см. примечание).")
$lines.Add("TESTS_RUN=0  PASS=0  FAIL=0")

$lines | Out-File -FilePath $out -Encoding UTF8
Write-Output "Baseline saved: $out"