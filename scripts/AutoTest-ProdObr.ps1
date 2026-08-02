# Автотест ПРОДОБР — полный цикл
$ErrorActionPreference = "Continue"
$scriptDir = Split-Path $PSCommandPath -Parent
$projDir = Split-Path $scriptDir -Parent

$guiScript = Join-Path $projDir "scripts\Show-ProdObr-GUI.ps1"
$cmdFile = Join-Path $projDir "temp\prodobr_autotest_cmds.txt"
$logDir = $env:TEMP

Write-Host "=== PRODOBR AUTOTEST ==="
Write-Host "[1] Checking prerequisites..."

if (-not (Test-Path $guiScript)) { Write-Host "FATAL: GUI script not found"; exit 1 }
if (-not (Test-Path $cmdFile)) { Write-Host "FATAL: commands file not found"; exit 1 }

# Get existing journals
$beforeJournals = @(Get-ChildItem $logDir -Filter "prodobr_journal_*.log" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

Write-Host "[2] Launching GUI autotest..."
$proc = Start-Process powershell -ArgumentList @(
    "-NoLogo", "-ExecutionPolicy", "RemoteSigned",
    "-File", "`"$guiScript`"",
    "-AutoTestFile", "`"$cmdFile`""
) -PassThru -WindowStyle Normal

Write-Host "    PID=$($proc.Id) — waiting for completion (max 5 min)..."
$done = $proc.WaitForExit(300000)
if (-not $done) {
    Write-Host "    TIMEOUT — killing process"
    $proc.Kill()
    exit 1
}
Write-Host "    Process exited: code=$($proc.ExitCode)"

Write-Host "[3] Reading tech journal..."
Start-Sleep -Seconds 2
$afterJournals = @(Get-ChildItem $logDir -Filter "prodobr_journal_*.log" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
$newJournals = $afterJournals | Where-Object { $_ -notin $beforeJournals }

if (-not $newJournals) {
    Write-Host "    WARN: no new journal, checking all..."
    $newJournals = $afterJournals | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if ($newJournals) {
    $jpath = $newJournals | Select-Object -First 1
    Write-Host "    Journal: $jpath"
    $content = Get-Content $jpath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($content) {
        Write-Host $content
        $errors = ($content | Select-String '\[ERROR\]|\[FATAL\]').Count
        if ($errors -gt 0) {
            Write-Host "`n    ERRORS: $errors"
            Write-Host "    FAILED"
            exit 1
        }
    }
} else {
    Write-Host "    No journal files found — GUI did not start properly"
    exit 1
}

Write-Host "[4] PASSED"
exit 0
