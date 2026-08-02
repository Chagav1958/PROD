<# 
.SYNOPSIS
    Монитор прерываний Nemotron 3 Ultra Free — автопродолжение по "ОО"
.DESCRIPTION
    Запускает opencode в фоне, следит за stdout/stderr за строкой 
    "Streaming response failed" и при обнаружении посылает "ОО" в stdin.
    Работает как wrapper: `.\Nemotron-Watchdog.ps1 [опции opencode]`
#>

param(
    [string[]]$OpencodeArgs = @(),
    [int]$CheckIntervalMs = 500,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$OpencodeExe = "opencode"
if (-not (Get-Command $OpencodeExe -ErrorAction SilentlyContinue)) {
    $OpencodeExe = "C:\Users\vchaga\AppData\Local\Programs\opencode\opencode.exe"
}

Write-Host "[Watchdog] Запуск: $OpencodeExe $($OpencodeArgs -join ' ')" -ForegroundColor Cyan

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $OpencodeExe
$psi.Arguments = $OpencodeArgs -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

$proc = [System.Diagnostics.Process]::Start($psi)

$stdoutBuffer = [System.Text.StringBuilder]::new()
$stderrBuffer = [System.Text.StringBuilder]::new()

# Простой цикл опроса вместо Tasks (совместимо с PS 5.1)
while (-not $proc.HasExited) {
    # Читаем доступный stdout
    while ($proc.StandardOutput.Peek() -ge 0) {
        $ch = $proc.StandardOutput.Read()
        if ($ch -ge 0) {
            $c = [char]$ch
            $stdoutBuffer.Append($c) | Out-Null
            if ($Verbose) { Write-Host $c -NoNewline }
            
            if ($stdoutBuffer.ToString() -match 'Streaming response failed') {
                Write-Host "`n[Watchdog] Обнаружено: 'Streaming response failed' — посылаю 'ОО'" -ForegroundColor Yellow
                try { $proc.StandardInput.WriteLine("ОО") } catch { }
                $stdoutBuffer.Clear()
            }
        }
    }
    
    # Читаем доступный stderr
    while ($proc.StandardError.Peek() -ge 0) {
        $ch = $proc.StandardError.Read()
        if ($ch -ge 0) {
            $c = [char]$ch
            $stderrBuffer.Append($c) | Out-Null
            if ($Verbose) { Write-Host $c -NoNewline -ForegroundColor Red }
            
            if ($stderrBuffer.ToString() -match 'Streaming response failed') {
                Write-Host "`n[Watchdog] Обнаружено в stderr: 'Streaming response failed' — посылаю 'ОО'" -ForegroundColor Yellow
                try { $proc.StandardInput.WriteLine("ОО") } catch { }
                $stderrBuffer.Clear()
            }
        }
    }
    
    Start-Sleep -Milliseconds $CheckIntervalMs
}

# Дочитать остатки
while ($proc.StandardOutput.Peek() -ge 0) { $null = $proc.StandardOutput.Read() }
while ($proc.StandardError.Peek() -ge 0) { $null = $proc.StandardError.Read() }

Write-Host "`n[Watchdog] Opencode завершён с кодом $($proc.ExitCode)" -ForegroundColor Cyan
exit $proc.ExitCode