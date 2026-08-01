param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Ps1Path,

    [Parameter(Position=1)]
    [string]$OutputPath = ''
)

if (-not (Test-Path $Ps1Path)) {
    Write-Host "File not found: $Ps1Path"
    exit 1
}

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::ChangeExtension($Ps1Path, '.bat')
}

# Читаем .ps1
$content = [System.IO.File]::ReadAllText($Ps1Path, [Text.Encoding]::UTF8)

# Кодируем в base64
$bytes = [Text.Encoding]::UTF8.GetBytes($content)
$b64 = [Convert]::ToBase64String($bytes)

# Разбиваем на куски по 4000 символов
$chunkSize = 4000
$numChunks = [Math]::Ceiling($b64.Length / $chunkSize)

# Собираем BAT — base64 в temp-файл (не в переменные окружения, чтобы не переполнить блок среды)
$bat = @()
$bat += '@echo off'
$bat += 'REM Auto-generated launcher (base64 PS1 via temp file)'
$bat += 'set TEMP_B64=%TEMP%\morda2_b64_tmp.txt'
$bat += ''

# Записываем base64 в файл построчно
for ($i = 0; $i -lt $numChunks; $i++) {
    $start = $i * $chunkSize
    $count = [Math]::Min($chunkSize, $b64.Length - $start)
    $chunk = $b64.Substring($start, $count)
    $bat += "echo $chunk>>%TEMP_B64%"
}

$bat += ''
$bat += 'start /min "" powershell -NoLogo -ExecutionPolicy RemoteSigned -Command "$b=Get-Content $env:TEMP_B64 -Raw; Remove-Item $env:TEMP_B64 -Force -ErrorAction SilentlyContinue; $d=[Convert]::FromBase64String($b); $s=[Text.Encoding]::UTF8.GetString($d); & ([ScriptBlock]::Create($s)) %*"'
$bat += 'endlocal'

$batText = $bat -join "`r`n"
[System.IO.File]::WriteAllText($OutputPath, $batText, [Text.Encoding]::Default)

Write-Host ("Created: " + $OutputPath)
Write-Host ("PS1: " + $Ps1Path)
Write-Host ("Chunks: " + $numChunks)
Write-Host ("Size: " + (Get-Item $OutputPath).Length + " bytes")