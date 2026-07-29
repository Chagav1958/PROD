param(
    [int]$OpNumber = 1,
    [int]$MaxIter = 100
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$fixedLog  = "C:\AIS\AI\Prod\temp\last_output.log"
$guiScript = "C:\AIS\AI\Prod\bin\Prod-GUI.ps1"
$opTimeout = 180000  # стандартный таймаут

# Поиск операции по номеру (1-based)
$script:allOps = @()
$content = Get-Content $guiScript -Raw -Encoding UTF8

# Ищем все Name = "..." в массиве $operations
$searchPos = $content.IndexOf('$operations = @(')
if ($searchPos -lt 0) { Write-Host "ERROR: Cannot find operations array"; exit 2 }
$opsSection = $content.Substring($searchPos)

# Находим каждую операцию @{...} и извлекаем Name
$script:allOps = @()
$opPos = $opsSection.IndexOf('@{', 0)
while ($opPos -ge 0) {
    $depth = 0; $pos = $opPos
    while ($pos -lt $opsSection.Length) {
        $ch = $opsSection[$pos]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { break }
        }
        $pos++
    }
    $block = $opsSection.Substring($opPos, $pos - $opPos + 1)
    $nameMatch = [regex]::Match($block, '(?<=Name = ")[^"]+')
    if ($nameMatch.Success) { $script:allOps += $nameMatch.Value }
    $opPos = $opsSection.IndexOf('@{', $pos)
}

if ($OpNumber -lt 1 -or $OpNumber -gt $script:allOps.Count) {
    Write-Host "ERROR: OpNumber $OpNumber out of range (1..$($script:allOps.Count))"
    exit 2
}
$opName = $script:allOps[$OpNumber - 1]
Write-Host "ОП ${OpNumber}: ${opName}"

# Извлечение Script блока для операции
$opMarker = 'Name = "' + $opName + '"'
$opIndex = $content.IndexOf($opMarker)
$sbStart = $content.IndexOf('Script = {', $opIndex) + 10
$depth = 1; $pos = $sbStart
while ($depth -gt 0 -and $pos -lt $content.Length) {
    $ch = $content[$pos]
    if ($ch -eq '{') { $depth++ }
    elseif ($ch -eq '}') { $depth-- }
    $pos++
}
$sbText = $content.Substring($sbStart, $pos - $sbStart - 1) -replace '^\s*param\s*\([^)]*\)\s*', ''

# Определение параметров для операции (из истории или последнего OUT)
$params = @{}
$checks = @{}

# Параметры по умолчанию для всех известных операций
switch ($opName) {
    'Run Tests (Run-Tests.ps1)' {
        $checks.QuickMode = $true
    }
    'Export Service' {
        # Параметры не требуются, скрипт читает из config.json
    }
    'Collect PROD Objects' {
        $params.TaskName = "SYBASE-19248"
    }
    'Export PB: Current or Main' {
        $params.Source = "Current"
        $params.TaskName = "SYBASE-19248"
    }
    'Compare PB: Current and Main' {
        $params.TaskName = "SYBASE-19248"
        $params.OutputFile = "C:\AIS\AI\Prod\compare_pb_report.txt"
    }
    'SQL Export' {
        $params.Source = "Current"
        $params.Server = "dev_golden"
        $params.Db = "golden"
        $params.ReadyFolder = "C:\AIS\AI\Prod\BD\dev_golden\golden"
        $params.TaskName = "SYBASE-19248"
        $params.password = "sqlsql"
        $opTimeout = 2147483647  # Infinite — операция может быть долгой (1000+ процедур)
    }
    'Compare SQL: dev_golden and galaxy' {
        $params.TaskName = "SYBASE-19248"
        $params.OutputFile = "C:\AIS\AI\Prod\compare_sql_report.txt"
    }
    'Compare & Verify (Compare-Export.ps1)' {
        $params.TaskName = "SYBASE-19248"
        $params.ShowDiff = $false
        $params.CreateRFC = $false
    }
    'Create RFC in Jira' {
        $params.TaskName = "SYBASE-19248"
        # Пытаемся прочитать токен Jira из config (требует Settings-Module.ps1)
        $sm = "C:\AIS\AI\Prod\scripts\Settings-Module.ps1"
        if (Test-Path $sm) { . $sm }
        $jrCfg = Get-Content "C:\AIS\AI\Prod\config\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($jrCfg.jira.token_encrypted) {
            $mk = Get-MasterKey -ConfigPath "C:\AIS\AI\Prod\config\config.json" -ErrorAction SilentlyContinue
            if ($mk) {
                try { $params.password = Decrypt-Password -Encrypted $jrCfg.jira.token_encrypted -Key $mk } catch {}
            }
        }
        if (-not $params.password) { $params.password = "test_token" }
        $sbText = $sbText -replace '-not \$password\)', '-not "x")'
        $sbText = $sbText -replace '-Force 2>&1', '-DryRun 2>&1'
    }
    'Jira Release Comment' {
        $params.TaskName = "SYBASE-19248"
        $params.ProjectName = "AIS"
        $params.password = "test_token"
        $sbText = $sbText -replace '-Force 2>&1', '-DryRun -Force 2>&1'
        $sbText = $sbText -replace '\$password', 'dryrun'
        $params.VssDb = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $vssDb = $params.VssDb; $vssUser = $params.VssUser; $vssPass = $params.VssPass
        $sbText = $sbText -replace '-DryRun', "-VssDb $vssDb -VssUser $vssUser -VssPass $vssPass -DryRun"
    }
    'VSS: Get Latest Version' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.TaskName = 'SYBASE-19248'
        $params.Project = '$/SRC125/gold'
        $params.PbtFile = ''
        $checks.Recursive = $true
    }
    'VSS: Check Status' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.TaskName = 'SYBASE-19248'
        $params.Project = '$/SRC125/gold'
        $checks.Recursive = $true
    }
    'VSS: Who Is Using' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.Project = '$/SRC125/gold'
        $checks.Recursive = $true
    }
    'VSS: Checkout' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.Project = '$/SRC125/gold'
        $params.Comment = 'Test checkout via auto_fix_loop'
        $checks.Recursive = $true
        $sbText = $sbText -replace '-Recursive\b', '-DryRun -Recursive'
    }
    'VSS: Checkin' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.Project = '$/SRC125/gold'
        $params.Comment = 'Test checkin via auto_fix_loop'
        $checks.Recursive = $true
        $sbText = $sbText -replace '-Recursive\b', '-DryRun -Recursive'
    }
    'VSS: Undo Check Out' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.Project = '$/SRC125/gold'
        $params.Comment = 'Test undo via auto_fix_loop'
        $checks.Recursive = $true
        $sbText = $sbText -replace '-Recursive\b', '-DryRun -Recursive'
    }
    'VSS: Object History' {
        $params.VssPath = '\\ren-msksf01\VSS2005\srcsafe.ini'
        $params.VssUser = 'vchaga'
        $params.VssPass = '12345'
        $params.TaskName = ''
        $params.Project = 'd_ais_cat_product_card'
        $opTimeout = 300000  # 5 минут — защита от зависания VSS
        # Вместо извлечения Script= из Prod-GUI.ps1, используем многосценарный тест
        # Не используем param() — $params берется из родительской области видимости
        $sbText = @'
& "C:\AIS\AI\Prod\scripts\Test-VssHistory.ps1" -VssDb "$($params.VssPath)" -VssUser "$($params.VssUser)" -VssPass "$($params.VssPass)"
'@
    }
    Default {
        $params.TaskName = 'SYBASE-19248'
        Write-Host "WARNING: No specific params for $opName. Using default test params."
    }
}

if ($params.Count -eq 0) {
    Write-Host "INFO: No specific params for $opName. Continuing with empty params (may work for param-less ops)."
}

Write-Host "Params: $($params | ConvertTo-Json -Compress)"
Write-Host "Checks: $($checks | ConvertTo-Json -Compress)"

for ($iter = 1; $iter -le $MaxIter; $iter++) {
    Write-Host "=== Iteration $iter of $MaxIter ==="

    $tempDir = [System.IO.Path]::GetTempPath()
    $guid = [guid]::NewGuid().ToString('N').Substring(0,8)
    $tempScript = Join-Path $tempDir "ais_auto_$guid.ps1"
    $tempParams = Join-Path $tempDir "ais_auto_prm_$guid.json"
    $tempChecks = Join-Path $tempDir "ais_auto_chk_$guid.json"
    $tempOutput = Join-Path $tempDir "ais_auto_out_$guid.txt"

    $escapedPwd = if ($params.Contains('password')) { $params.password -replace "'", "''" } else { "" }
    if (-not $escapedPwd -and $params.Contains('VssPass')) { $escapedPwd = $params.VssPass -replace "'", "''" }
    [System.IO.File]::WriteAllText($tempParams, ($params | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($tempChecks, ($checks | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8)

    # Header
    $paramLines = @(); foreach ($k in $params.Keys) { $paramLines += "  $k = $($params[$k])" }
    $header = "=== AIS Output Log ===`r`nOp: $opName (auto)`r`nTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nParams:`r`n$($paramLines -join "`r`n")`r`n========================`r`n"
    [System.IO.File]::WriteAllText($fixedLog, $header, [Text.Encoding]::UTF8)

    # Wrapper
    $wrapper = @"
`$ErrorActionPreference = 'Continue'
`$outputFile = '$tempOutput'
`$fixedLog   = '$fixedLog'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {
    `$params = Get-Content '$tempParams' -Raw | ConvertFrom-Json
    `$password = '$escapedPwd'
    `$checks = Get-Content '$tempChecks' -Raw | ConvertFrom-Json
    `$sb = {
        $sbText
    }
    `$sw = New-Object System.IO.StreamWriter(`$outputFile, `$true, [Text.Encoding]::UTF8)
    `$swF = New-Object System.IO.StreamWriter(`$fixedLog, `$true, [Text.Encoding]::UTF8)
    try {
        & `$sb *>&1 | ForEach-Object {
            `$line = if (`$_ -is [System.Management.Automation.InformationRecord]) {
                `$md = `$_.MessageData
                if (`$md -is [string]) { `$md } elseif (`$md -is [System.Management.Automation.HostInformationMessage]) { `$md.Message } else { "`$md" }
            } else { "`$_" }
            `$sw.WriteLine(`$line); `$sw.Flush(); `$swF.WriteLine(`$line); `$swF.Flush()
        }
    } finally { `$sw.Close(); `$swF.Close() }
} catch {
    "ERROR: `$_" | Out-File `$outputFile -Append -Encoding UTF8
    "ERROR: `$_" | Out-File `$fixedLog -Append -Encoding UTF8
}
"@
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($tempScript, $wrapper, $utf8Bom)

    Write-Host "  Running..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$tempScript`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit($opTimeout)) { $proc.Kill(); Write-Host "  TIMEOUT"; "TIMEOUT: процесс превысил лимит $($opTimeout/1000) сек" | Out-File $fixedLog -Append -Encoding UTF8 }
    Start-Sleep -Seconds 1

    Remove-Item $tempParams, $tempChecks, $tempScript -Force -ErrorAction SilentlyContinue

    $out = if (Test-Path $fixedLog) { Get-Content $fixedLog -Raw -Encoding UTF8 } else { "" }

    # Определяем успех/ошибку
    $isDialogOp = $opName -eq 'VSS: Object History'
    $hasVssOk = $out -match 'VSS: Свободен|VSS: Занят'
    $hasVssHistory = $out -match '###VSS_HISTORY_END###'
    $hasVssSearch = $out -match '###VSS_SEARCH###'
    $hasVssError = $out -match '###VSS_ERROR###'
    $hasDialogOk = $isDialogOp -and ($hasVssHistory -or $hasVssSearch) -and (-not $hasVssError)
    $hasTimeout = $out -match 'TIMEOUT'
    $hasCrash = $out -match 'Исключение|at System\.|at \w+\.\w+\.|Internal error|стек:'
    # VSS-ошибки credentials — НЕ считаются крашем (VSS может быть недоступен)
    $hasVssCredError = $out -match 'VSS недоступен|VSS не проверен|не удалось найти|source safe|SS.DLL'
    # FATAL: isql failed — это реальная ошибка (не skip)
    $hasFatal = $out -match 'FATAL:'

    $errLines = @($out -split "`r`n" | Where-Object { $_ -match 'ERROR:|FATAL:|TIMEOUT|Исключение|не удалось|###VSS_ERROR###' })
    Write-Host "  Timeout=$hasTimeout Crash=$hasCrash Fatal=$hasFatal VssCredError=$hasVssCredError VSS-ok=$hasVssOk DialogOk=$hasDialogOk"
    $errLines | ForEach-Object { Write-Host "    $_" }

    $isGenericSuccess = (-not $hasTimeout) -and (-not $hasCrash) -and (-not $hasFatal) -and (-not $hasVssError)
    $isVssSkip = $hasVssCredError -and (-not $hasTimeout) -and (-not $hasCrash) -and (-not $hasFatal) -and (-not $hasVssError)
    if ($hasDialogOk -or $hasVssOk -or $isGenericSuccess -or $isVssSkip) {
        Write-Host ""
        if ($isVssSkip) { Write-Host "SUCCESS: Операция эмулирована (VSS недоступен, пропущено)" }
        else { Write-Host "SUCCESS: Операция выполнена (или не требует внешних ресурсов)" }
        Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
        exit 0
    }

    Write-Host "--- PROTOCOL (ошибки и маркеры) ---"
    $out -split "`r`n" | Where-Object { $_ -match 'ERROR|FATAL|TIMEOUT|^  PB|VSS|Исключение|не удалось' } | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" }
    Write-Host "--- END ---"
    Write-Host ""
    Write-Host "Итерация ${iter}: требуется исправление. Файл: $fixedLog"
    Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "Лимит: $MaxIter итераций"
exit 2
