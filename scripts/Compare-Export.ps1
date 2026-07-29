param(
    [string]$TaskFolder,
    [string]$ConfigPath = "C:\AIS\AI\Prod\config\config.json",
    [string]$ReportPath = "C:\AIS\AI\Prod\release_report.txt",
    [string]$Password,
    [switch]$ShowDiff,
    [switch]$CreateRFC
)

$ErrorActionPreference = "Stop"

if (-not $Password) {
    $Password = Read-Host "Введите пароль Sybase"
}

if (-not (Test-Path $ConfigPath)) { throw "Конфиг не найден: $ConfigPath" }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (-not $TaskFolder -and -not $TaskName) {
    $taskDirs = Get-ChildItem $cfg.paths.release_root -Directory | Where-Object { $_.Name -like "SYBASE-*" } | Sort-Object LastWriteTime -Descending
    if ($taskDirs.Count -eq 0) { throw "Папки задач не найдены" }
    $taskPath = $taskDirs[0].FullName; $taskName = $taskDirs[0].Name
} elseif ($TaskFolder) {
    $taskPath = Join-Path $cfg.paths.release_root $TaskFolder
    $taskName = $TaskFolder
} else {
    $found = Get-ChildItem $cfg.paths.release_root -Directory | Where-Object { $_.Name -like "$TaskName*" } | Sort-Object Name -Descending | Select-Object -First 1
    if ($found) {
        $taskPath = $found.FullName
    } else {
        $taskPath = Join-Path $cfg.paths.release_root $TaskName
    }
}
Write-Host "Задача: $taskName" -ForegroundColor Cyan

# Поиск папок Ready
$readyDirs = Get-ChildItem $taskPath -Directory | Where-Object { $_.Name -like "Ready_*" -and $_.Name -ne "Ready_" } | Sort-Object LastWriteTime -Descending
if ($readyDirs.Count -eq 0) { throw "Папки Ready не найдены в $taskPath" }
Write-Host "Найдено папок Ready: $($readyDirs.Count)" -ForegroundColor Cyan

# Слияние папок Ready в ReadyMerged
$mergedRoot = Join-Path $cfg.paths.ready_merged_root $taskName
if (Test-Path $mergedRoot) { Remove-Item $mergedRoot -Recurse -Force }
New-Item -ItemType Directory -Path $mergedRoot -Force | Out-Null
$mergedCount = 0
foreach ($rd in $readyDirs) {
    $files = Get-ChildItem $rd.FullName -Recurse -File
    foreach ($f in $files) {
        $relPath = $f.FullName.Substring($rd.FullName.Length + 1)
        $destPath = Join-Path $mergedRoot $relPath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        if (-not (Test-Path $destPath)) {
            Copy-Item $f.FullName $destPath
            Write-Host "  $relPath" -ForegroundColor Green
            $mergedCount++
        } elseif ($f.LastWriteTime -gt (Get-Item $destPath).LastWriteTime) {
            Copy-Item $f.FullName $destPath -Force
            Write-Host "  ОБНОВЛЕНО: $relPath" -ForegroundColor DarkYellow
            $mergedCount++
        } else {
            # Пропускаем — в целевой папке уже актуальная версия
        }
    }
}
Write-Host "Слито файлов: $mergedCount" -ForegroundColor Cyan

# Пути для сравнения
$pbCR = $cfg.paths.pb_current_export
$pbMR = $cfg.paths.pb_main_export
$bdCR = $cfg.paths.bd_current_export
$bdMR = $cfg.paths.bd_main_export
$tmPath = $cfg.paths.tortoise_merge

$mergedFiles = Get-ChildItem $mergedRoot -Recurse -File
if ($mergedFiles.Count -eq 0) { Write-Host "Нет файлов в ReadyMerged" -ForegroundColor Red; exit }

$results = @()

foreach ($f in $mergedFiles) {
    $relPath = $f.FullName.Substring($mergedRoot.Length + 1)
    $isSql = ($f.Extension.ToLower() -eq ".sql")
    $objName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $sizeKB = [math]::Round($f.Length / 1KB, 1)

    $searchPath = $relPath
    $inCurrent = Join-Path $(if ($isSql) { $bdCR } else { $pbCR }) $searchPath
    $inMain = Join-Path $(if ($isSql) { $bdMR } else { $pbMR }) $searchPath
    
    # Если файл не найден по пути ReadyMerged — ищем по имени в PB_Current/PB_Main
    if (-not $isSql -and -not (Test-Path $inCurrent)) {
        $foundInCurrent = Get-ChildItem $pbCR -Recurse -File -Filter $f.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundInCurrent) { $inCurrent = $foundInCurrent.FullName }
    }
    if (-not $isSql -and -not (Test-Path $inMain)) {
        $foundInMain = Get-ChildItem $pbMR -Recurse -File -Filter $f.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundInMain) { $inMain = $foundInMain.FullName }
    }

    $currentHash = if (Test-Path $inCurrent) { (Get-FileHash $inCurrent -Algorithm MD5).Hash } else { $null }
    $mainHash = if (Test-Path $inMain) { (Get-FileHash $inMain -Algorithm MD5).Hash } else { $null }
    $readyHash = (Get-FileHash $f.FullName -Algorithm MD5).Hash

    $readyOk = $true; $reasonRu = @(); $reasonEn = @()

    if ($currentHash -eq $null) {
        $reasonRu += "НЕТ В CURRENT"
        $reasonEn += "NOT_IN_CURRENT"
        $readyOk = $false
    } elseif ($readyHash -ne $currentHash) {
        $reasonRu += "ОТЛИЧАЕТСЯ ОТ CURRENT"
        $reasonEn += "DIFF_CURRENT"
        $readyOk = $false
    }

    if ($mainHash -eq $null) {
        $reasonRu += "НОВЫЙ ОБЪЕКТ"
        $reasonEn += "NEW_OBJECT"
    } elseif ($readyHash -eq $mainHash) {
        $reasonRu += "СОВПАДАЕТ С MAIN"
        $reasonEn += "SAME_AS_MAIN"; $readyOk = $false
    }

    if ($reasonRu.Count -eq 0) { $reasonRu = @("OK"); $reasonEn = @("OK") }

    $results += [PSCustomObject]@{
        ObjectPath = $relPath
        ObjectName = $objName
        Type = if ($isSql) { "SQL" } else { "PB" }
        Size = "$sizeKB KB"
        Ready = if ($readyOk) { "READY" } else { "NOT_READY" }
        Reason = $reasonEn -join "; "
        ReasonRu = $reasonRu -join "; "
        ReadyFullPath = $f.FullName
        CurrentFullPath = $inCurrent
        MainFullPath = $inMain
        CurrentExists = ($currentHash -ne $null)
        MainExists = ($mainHash -ne $null)
    }

    # ShowDiff: показать различия через TortoiseMerge
    if ($ShowDiff -and -not $readyOk -and (Test-Path $tmPath)) {
        # Если есть Current — сравниваем Ready против Current
        if ($currentHash) {
            Write-Host "`nСравнение: $relPath" -ForegroundColor Cyan
            Write-Host "  Текущая (Current): $inCurrent" -ForegroundColor Gray
            Write-Host "  Готовая (Ready):   $f.FullName" -ForegroundColor Gray
            $diffArgs = @("/base", $inCurrent, "/mine", $f.FullName)
            Start-Process -FilePath $tmPath -ArgumentList $diffArgs
        # Если нет Current, но есть Main — сравниваем Ready против Main
        } elseif ($mainHash) {
            Write-Host "`nСравнение: $relPath (объекта нет в Current, сравнивается с Main)" -ForegroundColor Cyan
            Write-Host "  Промышленная (Main): $inMain" -ForegroundColor Gray
            Write-Host "  Готовая (Ready):     $f.FullName" -ForegroundColor Gray
            $diffArgs = @("/base", $inMain, "/mine", $f.FullName)
            Start-Process -FilePath $tmPath -ArgumentList $diffArgs
        }
    }

    # Структурированные маркеры для диалога сравнения (если объект можно сравнить)
    if (-not $readyOk -and (Test-Path $tmPath)) {
        if ($currentHash) {
            "###DIFF_OBJECT###$objName|$($reasonRu -join '; ')|$inCurrent|$($f.FullName)|Current"
        } elseif ($mainHash) {
            "###DIFF_OBJECT###$objName|$($reasonRu -join '; ')|$inMain|$($f.FullName)|Main"
        }
    }
}

# Вывод результатов
Write-Host ("`n=== РЕЗУЛЬТАТЫ ===") -ForegroundColor Yellow
$results | Format-Table ObjectName, Type, Size, @{N="Статус";E={if ($_.Ready -eq "READY") { "ГОТОВО" } else { "НЕ ГОТОВО" }}}, @{N="Причина";E={$_.ReasonRu}} -AutoSize

$rc = @($results | Where-Object { $_.Ready -eq "READY" }).Count
$nc = @($results | Where-Object { $_.Ready -ne "READY" }).Count
$fg = if ($nc -eq 0) { "Green" } else { "Red" }
Write-Host "ГОТОВО: $rc / НЕ ГОТОВО: $nc / ВСЕГО: $($results.Count)" -ForegroundColor $fg

# Показать полные пути для неготовых объектов
if ($nc -gt 0) {
    Write-Host ("`n--- Пути к файлам неготовых объектов ---") -ForegroundColor Yellow
    foreach ($r in $results) {
        if ($r.Ready -eq "NOT_READY") {
            Write-Host "  $($r.ObjectName): $($r.ReasonRu)" -ForegroundColor Cyan
            if ($r.CurrentExists) {
                Write-Host "    Current: $($r.CurrentFullPath)" -ForegroundColor Gray
            }
            if ($r.MainExists) {
                Write-Host "    Main:    $($r.MainFullPath)" -ForegroundColor Gray
            }
            Write-Host "    Ready:   $($r.ReadyFullPath)" -ForegroundColor Gray
            if ($r.CurrentExists -or $r.MainExists) {
                Write-Host "    (используйте флаг -ShowDiff для автоматического запуска TortoiseMerge)" -ForegroundColor DarkYellow
            }
        }
    }
}

# Автообновление отсутствующих объектов
$notInCurrent = $results | Where-Object { $_.Ready -eq "NOT_READY" -and $_.CurrentExists -eq $false }
if ($notInCurrent.Count -gt 0) {
    Write-Host ("`n--- Обновление объектов, отсутствующих в Current ---") -ForegroundColor Yellow
    Write-Host "  Обнаружено: $($notInCurrent.Count) объектов" -ForegroundColor Cyan
    $pbldumpExe = $cfg.paths.pbl_dump
    $pbCurrentSource = $cfg.paths.pb_current_source
    $pbCurrentExport = $cfg.paths.pb_current_export
    $updatedCount = 0
    $stillMissing = @()

    foreach ($r in $notInCurrent) {
        Write-Host "  Обработка: $($r.ObjectName) ($($r.Type))" -ForegroundColor Cyan

        if ($r.Type -eq "PB" -and $pbCurrentSource -and (Test-Path $pbCurrentSource)) {
            # Шаг 1: ищем .sr* файл в исходной папке Current
            $sourceSrFile = Join-Path $pbCurrentSource $r.ObjectPath
            $foundSr = Get-ChildItem $sourceSrFile -ErrorAction SilentlyContinue
            if (-not $foundSr) {
                # Поиск без учёта расширения (если расширение другое)
                $foundSr = Get-ChildItem "$($sourceSrFile.Substring(0, $sourceSrFile.LastIndexOf('.'))).sr*" -ErrorAction SilentlyContinue
            }

            if ($foundSr) {
                $targetFile = Join-Path $pbCurrentExport $r.ObjectPath
                $targetDir = Split-Path $targetFile -Parent
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                Copy-Item $foundSr.FullName $targetFile -Force
                Write-Host "    Скопирован из Current source: $($foundSr.FullName)" -ForegroundColor Green
                $updatedCount++
                continue
            }

            # Шаг 2: .sr* не найден — пробуем pbldump
            if ($pbldumpExe -and (Test-Path $pbldumpExe)) {
                $parts = $r.ObjectPath -split '\\'
                $pblName = if ($parts.Count -gt 1) { $parts[0] } else { "" }
                $pblSearch = if ($pblName) { "$pblName.pbl" } else { "*.pbl" }
                $pblFile = Get-ChildItem $pbCurrentSource -Filter $pblSearch -Recurse -File | Select-Object -First 1
                if (-not $pblFile) {
                    # Если PBL не найден по имени — ищем файл в PB_Main, чтобы определить библиотеку
                    $foundInMain = Get-ChildItem $pbMR -Recurse -File -Filter "$($r.ObjectName).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($foundInMain) {
                        $pblName = $foundInMain.Directory.Name
                        $pblSearch = "$pblName.pbl"
                        $pblFile = Get-ChildItem $pbCurrentSource -Filter $pblSearch -Recurse -File | Select-Object -First 1
                    }
                }
                if (-not $pblFile) {
                    $pblFile = Get-ChildItem $pbCurrentSource -Filter "*.pbl" -Recurse -File | Select-Object -First 1
                }
                if ($pblFile) {
                    Write-Host "    PBL: $($pblFile.FullName)" -ForegroundColor Gray
                    # Определяем правильный путь в PB_Current по имени PBL
                    $exportDirName = [System.IO.Path]::GetFileNameWithoutExtension($pblFile.Name)
                    # Ищем расширение файла в PB_Main
                    $foundFile = Get-ChildItem $pbMR -Recurse -File -Filter "$($r.ObjectName).sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
                    $ext = if ($foundFile) { $foundFile.Extension } else { ".srw" }
                    $targetFile = Join-Path $pbCurrentExport ($exportDirName + "\" + $r.ObjectName + $ext)
                    $targetDir = Split-Path $targetFile -Parent
                    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                    Push-Location $targetDir
                    try {
                        & $pbldumpExe -esu $pblFile.FullName "$($r.ObjectName).*"
                        $exportedFile = Get-ChildItem $targetDir -Filter "$($r.ObjectName).sr*" -File | Select-Object -First 1
                        if ($exportedFile) {
                            Write-Host "    Экспортирован pbldump: $($exportedFile.Name)" -ForegroundColor Green
                            $updatedCount++
                        } else {
                            Write-Host "    pbldump не создал файл для $($r.ObjectName)" -ForegroundColor Red
                            $stillMissing += $r
                        }
                    } catch {
                        Write-Host "    pbldump ошибка: $_" -ForegroundColor Red
                        $stillMissing += $r
                    }
                    Pop-Location
                } else {
                    Write-Host "    PBL не найден в $pbCurrentSource" -ForegroundColor Red
                    $stillMissing += $r
                }
            } else {
                Write-Host "    pbldump не найден по пути: $pbldumpExe" -ForegroundColor DarkYellow
                $stillMissing += $r
            }
        } elseif ($r.Type -eq "SQL") {
            Write-Host "    SQL-объекты не поддерживают автообновление" -ForegroundColor DarkYellow
            $stillMissing += $r
        } else {
            Write-Host "    Тип объекта не поддерживается" -ForegroundColor DarkYellow
            $stillMissing += $r
        }
    }

    Write-Host "`n  Обновлено объектов: $updatedCount" -ForegroundColor Green

    # Повторное сравнение, если были обновления
    if ($updatedCount -gt 0) {
        Write-Host ("`n=== Повторное сравнение после обновления ===") -ForegroundColor Yellow
        $results = @()
        $mergedFiles = Get-ChildItem $mergedRoot -Recurse -File
        foreach ($f in $mergedFiles) {
            $relPath = $f.FullName.Substring($mergedRoot.Length + 1)
            $isSql = ($f.Extension.ToLower() -eq ".sql")
            $objName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $sizeKB = [math]::Round($f.Length / 1KB, 1)
            $searchPath = $relPath
            $inCurrent = Join-Path $(if ($isSql) { $bdCR } else { $pbCR }) $searchPath
            $inMain = Join-Path $(if ($isSql) { $bdMR } else { $pbMR }) $searchPath
            $currentHash = if (Test-Path $inCurrent) { (Get-FileHash $inCurrent -Algorithm MD5).Hash } else { $null }
            $mainHash = if (Test-Path $inMain) { (Get-FileHash $inMain -Algorithm MD5).Hash } else { $null }
            $readyHash = (Get-FileHash $f.FullName -Algorithm MD5).Hash
            $readyOk = $true; $reasonRu = @(); $reasonEn = @()
            if ($currentHash -eq $null) {
                $reasonRu += "НЕТ В CURRENT"; $reasonEn += "NOT_IN_CURRENT"; $readyOk = $false
            } elseif ($readyHash -ne $currentHash) {
                $reasonRu += "ОТЛИЧАЕТСЯ ОТ CURRENT"; $reasonEn += "DIFF_CURRENT"; $readyOk = $false
            }
            if ($mainHash -eq $null) {
                $reasonRu += "НОВЫЙ ОБЪЕКТ"; $reasonEn += "NEW_OBJECT"
            } elseif ($readyHash -eq $mainHash) {
                $reasonRu += "СОВПАДАЕТ С MAIN"; $reasonEn += "SAME_AS_MAIN"; $readyOk = $false
            }
            if ($reasonRu.Count -eq 0) { $reasonRu = @("OK"); $reasonEn = @("OK") }
            $results += [PSCustomObject]@{
                ObjectPath = $relPath; ObjectName = $objName
                Type = if ($isSql) { "SQL" } else { "PB" }
                Size = "$sizeKB KB"; Ready = if ($readyOk) { "READY" } else { "NOT_READY" }
                Reason = $reasonEn -join "; "; ReasonRu = $reasonRu -join "; "
                ReadyFullPath = $f.FullName; CurrentFullPath = $inCurrent; MainFullPath = $inMain
                CurrentExists = ($currentHash -ne $null); MainExists = ($mainHash -ne $null)
            }
        }
        $rc = @($results | Where-Object { $_.Ready -eq "READY" }).Count
        $nc = @($results | Where-Object { $_.Ready -ne "READY" }).Count
        Write-Host ("`n=== РЕЗУЛЬТАТЫ ПОСЛЕ ОБНОВЛЕНИЯ ===") -ForegroundColor Yellow
        $results | Format-Table ObjectName, Type, Size, @{N="Статус";E={if ($_.Ready -eq "READY") { "ГОТОВО" } else { "НЕ ГОТОВО" }}}, @{N="Причина";E={$_.ReasonRu}} -AutoSize
        $fg = if ($nc -eq 0) { "Green" } else { "Red" }
        Write-Host "ГОТОВО: $rc / НЕ ГОТОВО: $nc / ВСЕГО: $($results.Count)" -ForegroundColor $fg

        if ($stillMissing.Count -gt 0) {
            Write-Host ("`n--- Объекты, которые не удалось обновить ---") -ForegroundColor Red
            foreach ($m in $stillMissing) {
                Write-Host "  $($m.ObjectName) ($($m.ReasonRu))" -ForegroundColor Red
                Write-Host "    Ready: $($m.ReadyFullPath)" -ForegroundColor Gray
            }
        }
    }

    if ($stillMissing.Count -gt 0) {
        Write-Host "`nНе удалось обновить $($stillMissing.Count) из $($notInCurrent.Count) объектов, отсутствующих в Current." -ForegroundColor Red
        foreach ($m in $stillMissing) {
            Write-Host "  $($m.ObjectName) — не найден ни как .sr* в $pbCurrentSource, ни через pbldump" -ForegroundColor Yellow
            Write-Host "    Выполните экспорт объекта из PowerBuilder или VSS и повторите проверку." -ForegroundColor Gray
        }
    }
}

# Маркеры для диалога сравнения (по финальным результатам)
if ($nc -gt 0 -and (Test-Path $tmPath)) {
    foreach ($r in $results) {
        if ($r.Ready -eq "NOT_READY") {
            if ($r.CurrentExists) {
                "###DIFF_OBJECT###$($r.ObjectName)|$($r.ReasonRu)|$($r.CurrentFullPath)|$($r.ReadyFullPath)|Current"
            } elseif ($r.MainExists) {
                "###DIFF_OBJECT###$($r.ObjectName)|$($r.ReasonRu)|$($r.MainFullPath)|$($r.ReadyFullPath)|Main"
            }
        }
    }
}

# Отчёт
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("  ОТЧЁТ ПРОВЕРКИ ВЫПУСКА (RELEASE VERIFICATION)")
[void]$sb.AppendLine("  Задача: $taskName")
[void]$sb.AppendLine("  Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("==============================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== Проверенные объекты ===")
[void]$sb.AppendLine("")

[void]$sb.AppendLine("Объект                          Тип   Размер    Статус      Причина")
[void]$sb.AppendLine("----------------------------------------------------------------")
foreach ($r in $results) {
    $statusText = if ($r.Ready -eq "READY") { "ГОТОВО" } else { "НЕ ГОТОВО" }
    $line = $r.ObjectName.PadRight(30) + " " + $r.Type.PadRight(4) + " " + $r.Size.PadRight(8) + " " + $statusText.PadRight(10) + " " + $r.ReasonRu
    [void]$sb.AppendLine($line)
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("ГОТОВО: $rc / НЕ ГОТОВО: $nc / ВСЕГО: $($results.Count)")
[void]$sb.AppendLine("")

# JIRA table - build strings in variables to avoid pipe parsing issues
[void]$sb.AppendLine("=== JIRA Comment Table ===")
$jiraHdr = "Project/Server|Library/DB|Object Name|Info|"
[void]$sb.AppendLine($jiraHdr)
$jiraSep = "---|---|---|---|"
[void]$sb.AppendLine($jiraSep)
foreach ($r in $results) {
    $parts = $r.ObjectPath -split '\\'
    $name = $r.ObjectName
    if ($r.Type -eq "SQL") {
        $srv = if ($parts.Count -gt 0) { $parts[0] } else { "N/A" }
        $db = if ($parts.Count -gt 1) { $parts[1] } else { "N/A" }
        $jiraLine = "$srv|$db|$name|$($r.Reason)|"
        [void]$sb.AppendLine($jiraLine)
    } else {
        $lib = if ($parts.Count -gt 0) { $parts[0] } else { "N/A" }
        $jiraLine = "AIS|$lib|$name|$($r.Reason)|"
        [void]$sb.AppendLine($jiraLine)
    }
}

[System.IO.File]::WriteAllText($ReportPath, $sb.ToString(), [System.Text.Encoding]::Default)
Write-Host ("`nОтчёт сохранён: $ReportPath") -ForegroundColor Green

# Логика создания RFC
$allReady = ($nc -eq 0)
$createRfc = $false

if ($CreateRFC) {
    $createRfc = $true
    Write-Host ("`n=== Создание RFC (принудительно через -CreateRFC) ===") -ForegroundColor Cyan
}

if ($allReady -and -not $CreateRFC) {
    Write-Host ("`n=== Все объекты ГОТОВЫ ===") -ForegroundColor Green
    $answer = Read-Host "Создать RFC в Jira для задачи '$taskName'? (д/Н)"
    if ($answer -eq "д" -or $answer -eq "Д" -or $answer -eq "y" -or $answer -eq "Y") { $createRfc = $true }
}

if ($createRfc) {
    $rfcScript = Join-Path (Split-Path $Script:MyInvocation.MyCommand.Path) "Create-RFC.ps1"
    if (Test-Path $rfcScript) {
        Write-Host "Запуск Create-RFC.ps1 для задачи '$taskName'..." -ForegroundColor Cyan
        & $rfcScript -TaskName $taskName
    } else {
        Write-Host "Create-RFC.ps1 не найден: $rfcScript" -ForegroundColor Red
        Write-Host "Невозможно создать RFC автоматически."
    }
} elseif ($allReady -and -not $createRfc) {
    Write-Host ("`nRFC не создан. Для создания позже выполните:") -ForegroundColor Yellow
    Write-Host "  powershell -ExecutionPolicy Bypass -File Create-RFC.ps1 -TaskName $taskName" -ForegroundColor Gray
} elseif (-not $allReady) {
    Write-Host ("`nНекоторые объекты НЕ ГОТОВЫ. RFC не создан.") -ForegroundColor Yellow
    Write-Host "  Исправьте проблемы и запустите Compare-Export.ps1 повторно." -ForegroundColor Gray
}

