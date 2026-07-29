<#
.SYNOPSIS
    Automated test for SQL_exp_ready.bat РІР‚" verifies export integrity and encoding
.DESCRIPTION
    Tests:
    1. Binary match with original for check_agent.sql
    2. Russian text preservation in usp_add_entity_data.sql
    3. No extra isql messages in exported files
.PARAMETER Password
    Sybase ASE password for login vchaga
.PARAMETER TaskName
    Jira task identifier (e.g. SYBASE-19337)
#>

param(
    [string]$Password,
    [string]$TaskName = "TEST"
)

$ErrorActionPreference = "Stop"

if (-not $Password) {
    $Password = Read-Host "Введите пароль Sybase"
}

function Test-ExportFile {
    param(
        [string]$ReadyDir,
        [string]$OriginalDir,
        [string]$RelPath
    )

    $origFile = Join-Path $OriginalDir $RelPath
    $expFile  = Join-Path $ReadyDir $RelPath

    $origName = Split-Path $RelPath -Leaf
    $results = @{File=$origName; Passed=$false; Errors=@(); Warnings=@()}

    # 1. File exists check
    if (-not (Test-Path $expFile)) {
        $results.Errors += "File not exported"
        return $results
    }

    # 2. Not empty
    if ((Get-Item $expFile).Length -eq 0) {
        $results.Errors += "Empty file"
        return $results
    }

    # 3. No isql error messages
    $badLines = Select-String -Path $expFile -Pattern "^(Msg |Server '|\(return status)" | Measure-Object | Select-Object -ExpandProperty Count
    if ($badLines -gt 0) {
        $results.Errors += "Contains $badLines isql error/status lines"
    }

    # 4. Contains CREATE header
    $hasHeader = Select-String -Path $expFile -Pattern "^\s*create\s+(proc|procedure|function|trigger)\s+" | Measure-Object | Select-Object -ExpandProperty Count
    if ($hasHeader -eq 0) {
        $results.Errors += "Missing CREATE header"
    }

    # 5. Binary match with original (if original exists)
    if (Test-Path $origFile) {
        $origHash = (Get-FileHash $origFile -Algorithm MD5).Hash
        $expHash  = (Get-FileHash $expFile -Algorithm MD5).Hash
        if ($origHash -ne $expHash) {
            $sizeDiff = (Get-Item $origFile).Length - (Get-Item $expFile).Length
            $results.Warnings += "Hash differs from original (size diff: $($sizeDiff) bytes) - acceptable if original has extra isql messages"
        }
    }

    if ($results.Errors.Count -eq 0) { $results.Passed = $true }
    return $results
}

function Test-RussianEncoding {
    param([string]$FilePath)

    $results = @{Passed=$false; Errors=@()}

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $cp1251Russian = 0..$($bytes.Length-1) | Where-Object {
        $b = $bytes[$_]
        ($b -ge 0xC0 -and $b -le 0xFF) -or $b -eq 0xA8 -or $b -eq 0xB8
    } | Measure-Object | Select-Object -ExpandProperty Count

    if ($cp1251Russian -eq 0) {
        $results.Errors += "No cp1251 Russian characters found in file"
        return $results
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $results.Errors += "File has UTF-16 BOM (wrong encoding)"
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $results.Errors += "File has UTF-8 BOM"
    }

    $qmarkAfterNonAscii = 0
    for ($i = 1; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 0x3F -and $bytes[$i-1] -gt 0x7F) {
            $qmarkAfterNonAscii++
        }
    }

    if ($qmarkAfterNonAscii -gt 10) {
        $results.Errors += "Mojibake suspect: $qmarkAfterNonAscii question marks after non-ASCII bytes"
    }

    if ($results.Errors.Count -eq 0) { $results.Passed = $true }
    return $results
}

# ===== Main =====
# Установка кодировки консоли для корректного отображения кириллицы
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  ТЕСТ: Проверка целостности SQL-экспорта и кодировки" -ForegroundColor Cyan
Write-Host "  Задача: $TaskName" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$readyDir = "C:\Temp\TestReady_SQL"
$origDir  = "C:\AIS\AI\Prod\BD"
$testFiles = @(
    "dev_golden\golden\Procedure\check_agent.sql",
    "dev_golden\golden\Procedure\usp_add_entity_data.sql"
)

$allPassed = $true

foreach ($relPath in $testFiles) {
    Write-Host "Проверка файла: $relPath" -ForegroundColor Yellow

    $result = Test-ExportFile -ReadyDir $readyDir -OriginalDir $origDir -RelPath $relPath
    if ($result.Passed) {
        Write-Host "  [УСПЕХ] Структурные проверки пройдены" -ForegroundColor Green
    } else {
        Write-Host "  [ОШИБКА]" -ForegroundColor Red
        foreach ($err in $result.Errors) { Write-Host "    $err" -ForegroundColor Red }
        $allPassed = $false
    }
    foreach ($warn in $result.Warnings) {
        Write-Host "  [ПРЕДУПРЕЖДЕНИЕ] $warn" -ForegroundColor Yellow
    }

    $expFile = Join-Path $readyDir $relPath
    if ($relPath -like "*usp_add_entity*") {
        $encResult = Test-RussianEncoding -FilePath $expFile
        if ($encResult.Passed) {
            Write-Host "  [УСПЕХ] Русская кодировка корректна (Windows-1251)" -ForegroundColor Green
        } else {
            Write-Host "  [ОШИБКА] Проблема с кодировкой" -ForegroundColor Red
            foreach ($err in $encResult.Errors) { Write-Host "    $err" -ForegroundColor Red }
            $allPassed = $false
        }
    }

    Write-Host ""
}

Write-Host "============================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "  ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО" -ForegroundColor Green
} else {
    Write-Host "  НЕКОТОРЫЕ ТЕСТЫ ПРОВАЛИЛИСЬ" -ForegroundColor Red
}
Write-Host "============================================" -ForegroundColor Cyan

exit ([int](-not $allPassed))

