# Invoke-HiddenDialog.ps1 — безопасный запуск Show-*.ps1 без видимой консоли
# Чистый .NET (ProcessStartInfo + CreateNoWindow) — антивирус не детектит
# Использование: powershell -NoProfile -File Invoke-HiddenDialog.ps1 -Script "Show-LLMs.ps1"
#                powershell -NoProfile -File Invoke-HiddenDialog.ps1 -Script "Show-Prompts.ps1" -Args @{TaskName="SYBASE-12345"}

param(
    [Parameter(Mandatory=$true)]
    [string]$Script,
    [string]$ScriptArgs = ""
)

$scriptsDir = $PSScriptRoot
$scriptPath = Join-Path $scriptsDir $Script

if (-not (Test-Path $scriptPath)) {
    Write-Host "Файл не найден: $scriptPath"
    exit 1
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$fullArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$scriptPath`""
if ($ScriptArgs -and $ScriptArgs -ne "") {
    $fullArgs += " $ScriptArgs"
}
$psi.Arguments = $fullArgs
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = "Hidden"
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false

# Устанавливаем AIS_HIDDEN_CONSOLE=1 — Hide-ConsoleWindow не будет перезапускать
# (скрипт уже запущен в скрытом окне через CreateNoWindow)
$psi.EnvironmentVariables["AIS_HIDDEN_CONSOLE"] = "1"

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit()
exit $proc.ExitCode