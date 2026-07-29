# Copy-ApiKeysToMachine.ps1 — миграция API-ключей User -> Machine
# Требует прав администратора для Machine-уровня.
# Без админ-прав: копирует в Process и показывает инструкцию.
param([switch]$Force)

$ErrorActionPreference = "Continue"

$keyNames = @(
    "ROUTERAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "DEEPSEEK_API_KEY",
    "ARTEMOX_API_KEY",
    "YANDEX_API_KEY",
    "GOOGLE_API_KEY",
    "OPENROUTER_API_KEY"
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "=== Миграция API-ключей User -> Machine ===" -ForegroundColor Cyan
Write-Host "Администратор: $(if($isAdmin){'ДА'}else{'НЕТ (ключи будут скопированы только в Process)'})"
Write-Host ""

$copied = 0
$errors = 0

foreach ($name in $keyNames) {
    $userKey = [Environment]::GetEnvironmentVariable($name, "User")
    if (-not $userKey) {
        Write-Host "  SKIP $name — отсутствует в User" -ForegroundColor DarkYellow
        continue
    }

    # Копируем в Process (всегда работает)
    [Environment]::SetEnvironmentVariable($name, $userKey, "Process")
    Write-Host "  OK   $name -> Process" -ForegroundColor Green

    # Копируем в Machine (только с админ-правами)
    if ($isAdmin -or $Force) {
        try {
            [Environment]::SetEnvironmentVariable($name, $userKey, "Machine")
            Write-Host "  OK   $name -> Machine" -ForegroundColor Green
        } catch {
            Write-Host "  ERR  $name -> Machine: $_" -ForegroundColor Red
            $errors++
        }
    }
    $copied++
}

Write-Host ""
Write-Host "Скопировано: $copied ключей в Process" -ForegroundColor $(if($copied -gt 0){'Green'}else{'DarkYellow'})

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "!!! Для постоянного решения запустите от администратора:" -ForegroundColor Yellow
    Write-Host "    powershell -NoLogo -File '$PSCommandPath'" -ForegroundColor White
    Write-Host "!!! Или добавьте ключи через: Система -> Дополнительные параметры -> Переменные среды" -ForegroundColor Yellow
}
