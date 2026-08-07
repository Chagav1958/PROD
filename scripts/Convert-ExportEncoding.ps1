<#
.SYNOPSIS
    Конвертация выгруженных объектов в UTF-8 with BOM, переводы строк CRLF.
.DESCRIPTION
    Обходит папку и для файлов .sr* (PowerBuilder) и .sql (Sybase) приводит
    кодировку к UTF-8 with BOM и переводам строк CRLF. Исходная кодировка
    определяется автоматически по BOM (UTF-16LE/BE, UTF-8) или, если BOM нет,
    предполагается Windows-1251. Файлы уже в UTF-8 BOM только нормализуют CRLF.
.PARAMETER Path
    Папка с выгруженными объектами (обход рекурсивный).
.PARAMETER Extensions
    Маска расширений для обработки. По умолчанию @('*.sr*','*.sql').
.PARAMETER ReportOnly
    Только показать статистику, не изменять файлы.
.EXAMPLE
    .\Convert-ExportEncoding.ps1 -Path C:\AIS\AI\Prod\PB_Current
    .\Convert-ExportEncoding.ps1 -Path "C:\AIS\1 Release\SYBASE-19371_19365" -ReportOnly
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [string[]]$Extensions = @('*.sr*', '*.sql'),
    [switch]$ReportOnly
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "ОШИБКА: Папка не найдена: $Path" -ForegroundColor Red
    exit 1
}

# Чтение текста с автоопределением кодировки по BOM (fallback Windows-1251)
function Read-FileAuto {
    param([string]$FilePath)
    $sr = New-Object System.IO.StreamReader($FilePath, [System.Text.Encoding]::GetEncoding(1251), $true)
    try { return $sr.ReadToEnd() }
    finally { $sr.Close() }
}

# Проверка наличия BOM UTF-16 (первый байт FF FE или FE FF)
function Test-Utf16Bom {
    param([string]$FilePath)
    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            if ($fs.Length -ge 2) {
                $b0 = $fs.ReadByte(); $b1 = $fs.ReadByte()
                return (($b0 -eq 0xFF -and $b1 -eq 0xFE) -or ($b0 -eq 0xFE -and $b1 -eq 0xFF))
            }
        } finally { $fs.Close() }
    } catch { }
    return $false
}

# Проверка наличия BOM UTF-8 (EF BB BF)
function Test-Utf8Bom {
    param([string]$FilePath)
    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        try {
            if ($fs.Length -ge 3) {
                $b0 = $fs.ReadByte(); $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte()
                return ($b0 -eq 0xEF -and $b1 -eq 0xBB -and $b2 -eq 0xBF)
            }
        } finally { $fs.Close() }
    } catch { }
    return $false
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$files = @()
foreach ($ext in $Extensions) {
    $files += Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $ext -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

$converted = 0; $normalized = 0; $unchanged = 0; $errors = 0
$utf16Count = 0

foreach ($f in $files) {
    try {
        $wasUtf16 = Test-Utf16Bom -FilePath $f.FullName
        $wasUtf8Bom = Test-Utf8Bom -FilePath $f.FullName

        $text = Read-FileAuto -FilePath $f.FullName
        if ($null -eq $text -or $text.Length -eq 0) { $unchanged++; continue }

        # Нормализация переводов строк к CRLF
        $norm = $text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")

        $needWrite = $false
        if (-not $wasUtf8Bom) { $needWrite = $true }
        if ($norm -ne $text) { $needWrite = $true }

        # Выбор кодировки: .sql -> ANSI (1251), .sr* -> UTF-8 BOM
        $targetEncoding = if ($f.Extension -eq ".sql") { [System.Text.Encoding]::GetEncoding(1251) } else { $utf8Bom }

        if (-not $ReportOnly) {
            # Retry при временной блокировке файла (user-mapped section open)
            $written = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    [System.IO.File]::WriteAllText($f.FullName, $norm, $targetEncoding)
                    $written = $true
                    break
                } catch {
                    if ($attempt -lt 3) {
                        Start-Sleep -Milliseconds 500
                    } else {
                        throw
                    }
                }
            }
        }

        if ($wasUtf16) {
            $converted++; $utf16Count++
        } else {
            $normalized++
        }
    } catch {
        $errors++
        Write-Host "  ОШИБКА: $($f.FullName) : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "=== Конвертация кодировки: $Path ===" -ForegroundColor Cyan
Write-Host "  Файлов обработано:   $($files.Count)"
Write-Host "  Было UTF-16 -> UTF-8: $utf16Count"
Write-Host "  Нормализовано CRLF:  $normalized"
Write-Host "  Без изменений:       $unchanged"
if ($errors -gt 0) { Write-Host "  Ошибок:              $errors" -ForegroundColor Red }
Write-Host "###CONVERT###$($converted + $normalized)###"

exit 0
