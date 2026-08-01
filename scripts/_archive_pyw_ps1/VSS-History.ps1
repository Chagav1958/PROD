# VSS-History.ps1 — работа с историей версий VSS

function Get-VssExe {
    $common = "${env:ProgramFiles(x86)}\Microsoft Visual SourceSafe\ss.exe"
    if (Test-Path $common) { return $common }
    $alt = "${env:ProgramFiles}\Microsoft Visual SourceSafe\ss.exe"
    if (Test-Path $alt) { return $alt }
    $fromConfig = try { (Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json).paths.vss_exe } catch { $null }
    if ($fromConfig -and (Test-Path $fromConfig)) { return $fromConfig }
    return $null
}

function Convert-VssHexText {
    param([string]$Text)
    # Формат: $$HEX<число>$$<utf16le_hex>$$ENDHEX$$
    $hexRegex = [regex]'\$\$HEX\d+\$\$([0-9A-Fa-f]+)\$\$ENDHEX\$\$'
    $result = $hexRegex.Replace($Text, {
        param($m)
        $hex = $m.Groups[1].Value
        if ($hex.Length -lt 2 -or ($hex.Length % 2) -ne 0) { return $m.Value }
        $bytes = New-Object byte[] ($hex.Length / 2)
        for ($i = 0; $i -lt $hex.Length; $i += 2) {
            $bytes[$i / 2] = [Convert]::ToByte($hex.Substring($i, 2), 16)
        }
        try { return [System.Text.Encoding]::Unicode.GetString($bytes) }
        catch { return $m.Value }
    })
    # На всякий случай удаляем незакрытые $$ENDHEX$$ без пары
    $result = $result -replace '\$\$ENDHEX\$\$', ''
    return $result
}

function Get-VssHistory {
    param([string]$VssPath, [string]$VssDb, [string]$VssUser, [string]$VssPass, [int]$MaxVersions = 0)
    $exe = Get-VssExe
    if (-not $exe) { throw "ss.exe not found" }
    if ($VssDb) { $env:SSDIR = if (Test-Path $VssDb -PathType Container) { $VssDb } else { Split-Path $VssDb -Parent } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $verArg = if ($MaxVersions -eq 1) { " -V~" } else { "" }
    $psi.Arguments = "History `"$VssPath`" -I-Y -Y`"${VssUser},${VssPass}`"$verArg"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(1251)
    $proc = [System.Diagnostics.Process]::Start($psi)
    $exited = $proc.WaitForExit(30000)
    if (-not $exited) {
        $proc.Kill()
        $output = ""
        throw "ss.exe timeout (30s) — VSS сервер не отвечает или неверный пароль"
    }
    $output = $proc.StandardOutput.ReadToEnd()
    # Детектим запрос пароля (Username/Password prompt) — признак неверного пароля
    if ($output -match '^Username:' -or $output -match '^Password:') {
        throw "Неверный VSS пароль — ss.exe запросил интерактивный ввод (Username/Password). Проверьте пароль в настройках МОРДЫ"
    }
    # DEBUG: запись сырого вывода
    $debugFile = Join-Path $env:TEMP "vss_history_debug_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    "VssPath: $VssPath`nOutput length: $($output.Length)`n`n=== RAW OUTPUT ===`n$output" | Out-File -FilePath $debugFile -Encoding UTF8
    "DEBUG written to: $debugFile" | Out-File -FilePath $debugFile -Append
    $versions = @()
    $lines = $output -split "`r`n|`n"
    $current = $null
    foreach ($l in $lines) {
        if ($l -match '^\*+\s*Version\s+(\d+)\s*\*+') {
            if ($current) { $versions += $current }
            $current = [PSCustomObject]@{ Version = [int]$matches[1]; User = ""; Date = ""; Time = ""; Action = ""; Comment = "" }
        }
        if ($current -and $l -match '^User:\s*(\S+)') {
            $current.User = $matches[1]
        }
        if ($current -and $l -match '(\d{1,2}\.\d{1,2}\.\d{2})\s+Time:\s*(\d{1,2}:\d{2})') {
            $current.Date = $matches[1]
            $current.Time = $matches[2]
        }
        if ($current -and $l -match '^Checked\s+in\s') { $current.Action = "Checked in" }
        if ($current -and $l -match '^Created') { $current.Action = "Created" }
        if ($current -and $l -match '^Comment:\s*(.*)') { $current.Comment = $matches[1].Trim() }
    }
    if ($current) { $versions += $current }
    # Конвертация U+XXXX последовательностей (только 4 hex цифр) в русский текст
    $unicodeRegex = [regex]'U\+([0-9A-Fa-f]{4})'
    foreach ($ver in $versions) {
        if ($ver.Comment -match $unicodeRegex) {
            $ver.Comment = $unicodeRegex.Replace($ver.Comment, { param($m) 
                try { [char][int]::Parse($m.Groups[1].Value, [System.Globalization.NumberStyles]::HexNumber) } catch { $m.Value }
            })
        }
    }
    return $versions
}

function Get-VssVersionFile {
    param([string]$VssPath, [int]$Version, [string]$VssDb, [string]$VssUser, [string]$VssPass, [string]$OutputDir)
    $exe = Get-VssExe
    if (-not $exe) { throw "ss.exe not found" }
    if ($VssDb) { $env:SSDIR = if (Test-Path $VssDb -PathType Container) { $VssDb } else { Split-Path $VssDb -Parent } }
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
    $fileName = [System.IO.Path]::GetFileName($VssPath)
    $cleanName = $fileName -replace '\*$', ''
    $base = [System.IO.Path]::GetFileNameWithoutExtension($cleanName)
    Push-Location $OutputDir
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = "Get `"$VssPath`" -V$Version -I-Y -Y`"${VssUser},${VssPass}`" -G"
        $psi.WorkingDirectory = $OutputDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc.WaitForExit(30000)) { $proc.Kill() }
        Start-Sleep -Milliseconds 300
        $found = Get-ChildItem $OutputDir -File -Filter "${base}.sr*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
            $content = [System.IO.File]::ReadAllBytes($found.FullName)
            $hasUtf8Bom = $content.Length -gt 2 -and $content[0] -eq 239 -and $content[1] -eq 187 -and $content[2] -eq 191
            $hasUtf16Bom = $content.Length -gt 1 -and $content[0] -eq 255 -and $content[1] -eq 254
            if (-not $hasUtf8Bom -and -not $hasUtf16Bom) {
                # Проверка: может ли файл быть UTF-16LE без BOM?
                # Ищем паттерн: ASCII-символ + нулевой байт на чётных позициях
                $isUtf16LeNoBom = $false
                if ($content.Length -gt 40) {
                    $asciiNullCount = 0
                    for ($i = 0; $i -lt 40 -and $i -lt $content.Length; $i+=2) {
                        if ($content[$i] -ge 0x20 -and $content[$i] -le 0x7E -and $content[$i+1] -eq 0) { $asciiNullCount++ }
                    }
                    $isUtf16LeNoBom = $asciiNullCount -gt 10
                }
                if ($isUtf16LeNoBom) {
                    # UTF-16LE без BOM — декодируем как UTF-16LE
                    $text = [System.Text.Encoding]::Unicode.GetString($content)
                    Remove-Item $found.FullName -Force -ErrorAction SilentlyContinue
                    [System.IO.File]::WriteAllText($found.FullName, $text, [Text.Encoding]::Unicode)
                } else {
                    # Нет BOM, не UTF-16LE — файл в ASCII/CP1251 (как VSS выгружает PB .sr*)
                    # Конвертируем в UTF-16LE с BOM (формат PB_Current) для корректного сравнения
                    $text = [System.Text.Encoding]::GetEncoding(1251).GetString($content)
                    Remove-Item $found.FullName -Force -ErrorAction SilentlyContinue
                    [System.IO.File]::WriteAllText($found.FullName, $text, [Text.Encoding]::Unicode)
                }
            }
            # Декодируем $$HEX...$$ последовательности (PB export hex-encoding русских символов)
            $fileBytes = [System.IO.File]::ReadAllBytes($found.FullName)
            $fileText = [System.Text.Encoding]::Unicode.GetString($fileBytes)
            if ($fileText -match '\$\$HEX\d+\$\$') {
                $decodedText = Convert-VssHexText -Text $fileText
                [System.IO.File]::WriteAllText($found.FullName, $decodedText, [Text.Encoding]::Unicode)
            }
            return $found.FullName
        }
        return $null
    } finally { Pop-Location }
}

function Get-VssCheckoutInfo {
    param([string]$VssPath, [string]$VssDb, [string]$VssUser, [string]$VssPass)
    $exe = Get-VssExe
    if (-not $exe) { throw "ss.exe not found" }
    if ($VssDb) { $env:SSDIR = if (Test-Path $VssDb -PathType Container) { $VssDb } else { Split-Path $VssDb -Parent } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "Status `"$VssPath`" -I-Y -Y`"${VssUser},${VssPass}`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $output = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit(30000) | Out-Null
    $result = @{ CheckedOut = $false; User = ""; Free = $false }
    $lines = $output -split "`r`n|`n"
    foreach ($l in $lines) {
        if ($l -match '\s(\w+)\s+(Exc|Out)\s') {
            $result.CheckedOut = $true
            $result.User = $matches[1]
            return $result
        }
    }
    if ($output -match 'No checked out files found') { $result.Free = $true; return $result }
    $result.Free = $true
    return $result
}

function Find-VssOldPbPath {
    param([string]$ObjectName, [string]$Library, [string]$TaskPath, [string]$VssDb, [string]$VssUser, [string]$VssPass, [string]$CurrentUserName)
    $vssPath = "`$/SRC125/gold/$Library/$ObjectName.sr*"
    $coInfo = Get-VssCheckoutInfo -VssPath $vssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
    if ($coInfo.CheckedOut -and $coInfo.User -eq $CurrentUserName) {
        # Занят мной — берём последнюю версию из истории
        $history = Get-VssHistory -VssPath $vssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass
        if ($history.Count -gt 0) {
            $lastVersion = $history | Sort-Object { $_.Version } -Descending | Select-Object -First 1
            $tempDate = Get-Date -Format 'yyyy_MM_dd'
            $outDir = Join-Path $TaskPath "TEMP_${tempDate}\PB\$Library"
            $file = Get-VssVersionFile -VssPath $vssPath -Version $lastVersion.Version -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -OutputDir $outDir
            return @{ Path = $file; Source = "VSS (v$($lastVersion.Version))"; Version = $lastVersion.Version; HistoryUser = $lastVersion.User }
        }
    }
    return @{ Path = $null; Source = "VSS (not found)"; Version = $null }
}

function Search-InVssHistory {
    param([string]$VssPath, [string]$SearchText, [string]$VssDb, [string]$VssUser, [string]$VssPass, [switch]$CaseSensitive, [object]$ProgressBars = $null, [array]$History = $null)
    if ($History) { $history = $History } else { $history = Get-VssHistory -VssPath $VssPath -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass }
    if ($history.Count -eq 0) { return @() }
    # Нормализуем искомый текст: LF → CRLF для совпадения с файлами
    $normalizedSearch = $SearchText -replace "`r`n", "`n" -replace "`r", "`n"
    $results = @()
    $sorted = $history | Sort-Object { $_.Version }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vss_search_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    $searchStart = Get-Date
    $searchTimeout = 180  # секунд
    try {
        if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
        foreach ($ver in $sorted) {
            # Проверка таймаута поиска
            if ((Get-Date) -gt $searchStart.AddSeconds($searchTimeout)) {
                Write-Warning "Поиск прерван по таймауту ($searchTimeout сек). Обработано $($results.Count) версий из $($sorted.Count)."
                break
            }
            Write-Progress -Activity "Поиск в истории VSS" -Status "Версия $($ver.Version) ($($ver.User))" -PercentComplete (($ver.Version - $sorted[0].Version) / [Math]::Max(1, $sorted[-1].Version - $sorted[0].Version) * 100)
            # Обновление прогресс-баров в окне (если переданы)
            $verIdx = [array]::IndexOf($sorted, $ver)
            if ($ProgressBars) {
                if ($ProgressBars.PhaseLabel) { $ProgressBars.PhaseLabel.Text = "Версия $($ver.Version) (из $($sorted.Count))" }
                if ($ProgressBars.PhaseBar) { $ProgressBars.PhaseBar.Value = [Math]::Min(100, [Math]::Round(($verIdx + 1) / $sorted.Count * 100)) }
                if ($ProgressBars.StepBar) { $ProgressBars.StepBar.Value = 0 }
                # Принудительная отрисовка WPF через Dispatcher
                if ($ProgressBars.Dispatcher) { $ProgressBars.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background) }
            }
            $file = Get-VssVersionFile -VssPath $VssPath -Version $ver.Version -VssDb $VssDb -VssUser $VssUser -VssPass $VssPass -OutputDir $tempDir
            $foundInVersion = $false
            $foundLine = 0
            if ($file -and (Test-Path $file)) {
                $content = [System.IO.File]::ReadAllText($file, [Text.Encoding]::Unicode)
                if ($ProgressBars -and $ProgressBars.StepBar) { $ProgressBars.StepBar.Value = 50; if ($ProgressBars.Dispatcher) { $ProgressBars.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background) } }
                if ($content) {
                    $normalizedContent = $content -replace "`r`n", "`n" -replace "`r", "`n"
                    $foundInVersion = if ($CaseSensitive) { $normalizedContent.Contains($normalizedSearch) } else { $normalizedContent.IndexOf($normalizedSearch, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
                    if ($foundInVersion) {
                        # Определяем номер строки с найденным контекстом
                        $lines = $normalizedContent -split "`n"
                        for ($li = 0; $li -lt $lines.Count; $li++) {
                            $lineMatch = if ($CaseSensitive) { $lines[$li].Contains($normalizedSearch) } else { $lines[$li].IndexOf($normalizedSearch, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
                            if ($lineMatch) { $foundLine = $li + 1; break }
                        }
                        $results += [PSCustomObject]@{ Version = $ver.Version; User = $ver.User; Date = $ver.Date; Time = $ver.Time; Comment = $ver.Comment; Line = $foundLine }
                    }
                }
                Remove-Item $file -Force -ErrorAction SilentlyContinue
            }
            # Обновляем Found сразу если есть callback (передаём индекс версии)
            if ($ProgressBars -and $ProgressBars.OnVersionDone) {
                & $ProgressBars.OnVersionDone $verIdx $foundInVersion $foundLine
            }
        }
        Write-Progress -Activity "Поиск в истории VSS" -Completed
    } finally {
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $results
}

if ($MyInvocation.InvocationName -eq '.') {
} elseif ($MyInvocation.InvocationName -ne '') {
    try { Export-ModuleMember -Function Get-VssHistory, Get-VssVersionFile, Get-VssCheckoutInfo, Find-VssOldPbPath, Search-InVssHistory -ErrorAction SilentlyContinue } catch {}
}

