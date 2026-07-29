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

# Собираем BAT
$bat = @()
$bat += '@echo off'
$bat += 'REM Auto-generated launcher (base64 PS1)'
$bat += 'setlocal enabledelayedexpansion'
$bat += 'set B64='

for ($i = 0; $i -lt $numChunks; $i++) {
    $start = $i * $chunkSize
    $count = [Math]::Min($chunkSize, $b64.Length - $start)
    $chunk = $b64.Substring($start, $count)
    $bat += "set B64_$i=$chunk"
}

# Команда PowerShell для сборки и запуска
# %args% в конце — пробрасывает ВСЕ аргументы, переданные в .bat, ВНУТРЬ -Command
$psCmd = "powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `""
$psCmd += "`$b=''"
for ($i = 0; $i -lt $numChunks; $i++) {
    $psCmd += " + [Environment]::GetEnvironmentVariable('B64_$i','Process')"
}
# Invoke-Expression не поддерживает splatting @args, используем [ScriptBlock]::Create + & @args
# %* встраивается ВНУТРЬ команды (в кавычках), иначе PowerShell их игнорирует
$psCmd += ";If(`$b){`$d=[Convert]::FromBase64String(`$b);`$s=[Text.Encoding]::UTF8.GetString(`$d);& ([ScriptBlock]::Create(`$s)) %*}"
$psCmd += '"'

$bat += ''
$bat += $psCmd
$bat += 'endlocal'

$batText = $bat -join "`r`n"
[System.IO.File]::WriteAllText($OutputPath, $batText, [Text.Encoding]::Default)

Write-Host ("Created: " + $OutputPath)
Write-Host ("PS1: " + $Ps1Path)
Write-Host ("Chunks: " + $numChunks)
Write-Host ("Size: " + (Get-Item $OutputPath).Length + " bytes")