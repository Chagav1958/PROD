# Test-ShowTimeFIX.ps1 — автотест Show-TimeFIX.ps1
$scriptPath = "C:\AIS\AI\Prod\bin\Show-TimeFIX.ps1"

# Проверка синтаксиса
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "[FAIL] Syntax errors: $($errors.Count)"
    exit 1
}
Write-Host "[OK] Syntax check passed"

# Запуск
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-NoLogo -STA -File `"$scriptPath`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $false
$proc = [Diagnostics.Process]::Start($psi)

# Поиск окна
$found = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Milliseconds 500
    $procs = @([Diagnostics.Process]::GetProcesses())
    foreach ($p in $procs) {
        $title = $p.MainWindowTitle
        if ($title -like "*TimeFIX*" -or $title -like "*учета*") {
            $found = $true
            Write-Host ("[OK] Window found: '" + $title + "'")
            $closed = $p.CloseMainWindow()
            if ($closed) {
                Write-Host "[OK] Window closed via CloseMainWindow"
                $p.WaitForExit(3000) | Out-Null
            }
            break
        }
    }
    if ($found) { break }
}

if (-not $found) {
    Write-Host "[FAIL] Window not found after 7.5s"
    if (-not $proc.HasExited) { $proc.Kill() }
    exit 1
}

Write-Host "[OK] Test passed"
exit 0
