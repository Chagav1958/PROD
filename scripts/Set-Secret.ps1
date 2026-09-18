# Set-Secret.ps1 — безопасно записать секрет в ~/.ais-secrets/opencode/<файл>
#
# Значение пишется БЕЗ BOM и БЕЗ перевода строки (именно так его читает подстановка
# OpenCode {file:...}). Значение не печатается.
#
# Использование:
#   powershell -NoLogo -File scripts\Set-Secret.ps1 -Name confluence_password.txt
#       (значение запрашивается скрытно, в истории команд не остаётся)
#   powershell -NoLogo -File scripts\Set-Secret.ps1 -Name jira_token.txt -Value "..."
#   powershell -NoLogo -File scripts\Set-Secret.ps1 -Name confluence_password.txt -Verify
#       (-Verify дополнительно запускает Test-Secrets.ps1 -Online)
#
# После смены значения ОБЯЗАТЕЛЬНО перезапустить OpenCode (значения читаются при старте).

Param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Value,
    [switch]$Verify
)

$ErrorActionPreference = "Stop"

$Allowed = @(
    "jira_token.txt",
    "confluence_password.txt",
    "google_api_key.txt"
)

if ($Allowed -notcontains $Name) {
    Write-Host ("Недопустимое имя '{0}'. Разрешены: {1}" -f $Name, ($Allowed -join ", ")) -ForegroundColor Red
    exit 1
}

$dir = Join-Path $env:USERPROFILE ".ais-secrets\opencode"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-Host "[создано] $dir" -ForegroundColor Green
}
$path = Join-Path $dir $Name

if ([string]::IsNullOrEmpty($Value)) {
    $sec = Read-Host -Prompt "Введите значение для $Name" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $Value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if ([string]::IsNullOrWhiteSpace($Value)) {
    Write-Host "Пустое значение — отмена." -ForegroundColor Red
    exit 1
}

$Value = $Value.Trim()

# Запись без BOM (UTF-8 no BOM), без завершающего перевода строки
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $Value, $enc)

$bytes = [System.IO.File]::ReadAllBytes($path)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

Write-Host ("[записано] {0}" -f $path) -ForegroundColor Green
Write-Host ("            длина: {0} симв.; BOM: {1}" -f $Value.Length, $hasBom)
Write-Host "Перезапустите OpenCode, чтобы значение применилось." -ForegroundColor Yellow

if ($Verify) {
    & (Join-Path $PSScriptRoot "Test-Secrets.ps1") -Online
}
