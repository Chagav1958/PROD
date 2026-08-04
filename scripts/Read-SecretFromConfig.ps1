# Read-SecretFromConfig.ps1 — чтение секретов из config/.local_secrets.json
# Использование: Read-SecretFromConfig.ps1 -Path "sybase.password_encrypted"
#              или: . .\Read-SecretFromConfig.ps1; $val = Read-SecretFromConfig "jira.token_encrypted"
# Переносимый: использует $PSScriptRoot для относительного пути к config/

param(
    [string]$Path          # путь через точку: "sybase.password_encrypted"
)

function Read-SecretFromConfig {
    param([string]$KeyPath)

    $secretsFile = Join-Path $PSScriptRoot "..\config\.local_secrets.json"
    if (-not (Test-Path $secretsFile)) {
        Write-Error "Файл секретов не найден: $secretsFile"
        return $null
    }

    $secrets = Get-Content $secretsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $keys = $KeyPath -split '\.'
    $current = $secrets
    foreach ($k in $keys) {
        if ($current.PSObject.Properties.Name -contains $k) {
            $current = $current.$k
        } else {
            Write-Error "Ключ '$KeyPath' не найден (отсутствует '$k')"
            return $null
        }
    }
    return $current
}

if ($Path) {
    $result = Read-SecretFromConfig -KeyPath $Path
    if ($result) { Write-Output $result }
}
