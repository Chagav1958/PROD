param(
    [string]$TaskName = "",
    [string]$OutDir = "",
    [string]$Version = "",
    [switch]$RunBuild,
    [switch]$DryRun
)

# Скрипт автоматической сборки golden.exe + *.pbd через OrcaScript (PB 12.5)
# Ядро сервиса «СБОРКА» (см. docs/services/sborka.md).

$ErrorActionPreference = "Stop"

# ---------- конфигурация и константы ----------
$configPath = Join-Path $PSScriptRoot "..\config\config.json"
$config = Get-Content -Path $configPath -Encoding UTF8 -Raw | ConvertFrom-Json

$goldRoot = $config.paths.pb_current_source        # C:\Work\gold (рабочая версия PB_Current)
$scriptsDir = $config.paths.scripts_dir
$tempDir = $config.paths.temp_dir

$orcaExe = "C:\Program Files (x86)\Sybase\Shared\PowerBuilder\orcascr125.exe"
$pbtFile = Join-Path $goldRoot "gold.pbt"
$srcDir = Join-Path $goldRoot "golden_start"
$srjFile = Join-Path $srcDir "golden.srj"

# ---------- функции ----------
function Read-SrjVersions {
    param([string]$SrjPath)
    $lines = Get-Content -Path $SrjPath -Encoding Default
    $pv = $fv = $pvn = $fvn = $cpy = ""
    foreach ($ln in $lines) {
        if ($ln -like "PVS:*") { $pv = $ln.Substring(4) }
        elseif ($ln -like "FVS:*") { $fv = $ln.Substring(4) }
        elseif ($ln -like "PVN:*") { $pvn = $ln.Substring(4) }
        elseif ($ln -like "FVN:*") { $fvn = $ln.Substring(4) }
        elseif ($ln -like "CPY:*") { $cpy = $ln.Substring(4) }
    }
    return [pscustomobject]@{ PV = $pv; FV = $fv; PVN = $pvn; FVN = $fvn; CPY = $cpy }
}

function Bump-Version {
    param([string]$Version)
    # формат X.Y.Z или X.Y.Z.W — повышается последний компонент
    $parts = $Version.Split(".")
    if ($parts.Count -eq 0) { return "1.0.1" }
    $last = [int]$parts[$parts.Count - 1]
    $parts[$parts.Count - 1] = [string]($last + 1)
    return [string]::Join(".", $parts)
}

function Bump-VersionNum {
    param([string]$Version)   # формат 12,5,282,8
    $parts = $Version.Split(",")
    if ($parts.Count -eq 0) { return "1,0,1" }
    $last = [int]$parts[$parts.Count - 1]
    $parts[$parts.Count - 1] = [string]($last + 1)
    return [string]::Join(",", $parts)
}

function Read-LibListFromPbt {
    param([string]$PbtPath)
    $content = Get-Content -Path $PbtPath -Encoding Default -Raw
    $m = [regex]::Match($content, 'LibList\s+"([^"]*)"')
    if (-not $m.Success) { throw "Не найдена строка LibList в $PbtPath" }
    $raw = $m.Groups[1].Value
    $libs = $raw.Split(";")
    $result = @()
    foreach ($lib in $libs) {
        $libFixed = $lib -replace "\\\\", "\"
        if ($libFixed.Trim().Length -gt 0) { $result += $libFixed }
    }
    return $result
}

function Build-PbdFlags {
    param([string[]]$Libs)
    # golden_start.pbl компилируется в exe (N), остальные — pbd (Y), готовые .pbd (Y)
    $flags = ""
    foreach ($lib in $Libs) {
        $name = Split-Path $lib -Leaf
        if ($name -ieq "golden_start.pbl") { $flags += "N" }
        else { $flags += "Y" }
    }
    return $flags
}

function New-OrcaScript {
    param(
        [string]$LibsFlag,
        [string]$AppName,
        [string]$ExeInfoCopyright,
        [string]$FileVersion,
        [string]$FileVersionNum,
        [string]$ProductVersion,
        [string]$ProductVersionNum,
        [string]$PbdFlags
    )
    $lines = @()
    $lines += "start session"
    $lines += "set debug false"
    $lines += "set liblist $LibsFlag"
    $lines += "set application `"golden_start\golden_start.pbl`" `"$AppName`""
    $lines += "set exeinfo property copyright `"$ExeInfoCopyright`""
    $lines += "set exeinfo property fileversion `"$FileVersion`""
    $lines += "set exeinfo property fileversionnum `"$FileVersionNum`""
    $lines += "set exeinfo property productversion `"$ProductVersion`""
    $lines += "set exeinfo property productversionnum `"$ProductVersionNum`""
    $lines += "build executable `"golden_start\golden.exe`" `"users.ico`" `"golden_start\golden.pbr`" `"$PbdFlags`""
    $lines += "end session"
    return $lines
}

# ---------- основной ход ----------
if (-not (Test-Path $orcaExe)) { throw "orcascr125.exe не найден: $orcaExe" }
if (-not (Test-Path $pbtFile)) { throw "target не найден: $pbtFile" }
if (-not (Test-Path $srjFile)) { throw "проект EXE не найден: $srjFile" }

$srj = Read-SrjVersions -SrjPath $srjFile

if ($Version -and $Version.Trim() -ne "") {
    $newProduct = $Version.Trim()
    $newFile = $Version.Trim()
    $newProductNum = ($Version.Trim() -replace '\.', ',')
    $newFileNum = $newProductNum
} else {
    $newProduct = Bump-Version -Version $srj.PV
    $newFile   = Bump-Version -Version $srj.FV
    $newProductNum = Bump-VersionNum -Version $srj.PVN
    $newFileNum   = Bump-VersionNum -Version $srj.FVN
}
$dateToday = Get-Date -Format "dd.MM.yyyy"
$newCopyright = "(c) $dateToday Renaissance Insurance AI"

$libs = Read-LibListFromPbt -PbtPath $pbtFile
$pbdFlags = Build-PbdFlags -Libs $libs

$libListArg = @()
foreach ($lib in $libs) { $libListArg += ('"{0}"' -f $lib) }
$libsArg = [string]::Join(" ", $libListArg)

# имя выходной папки Exe_yyyy_mm_dd__hh_mm
$stamp = (Get-Date -Format "yyyy_MM_dd__HH_mm")
$exeStamp = "Exe_$stamp"
if ($OutDir.Trim().Length -eq 0) {
    if ($TaskName.Trim().Length -gt 0) {
        $baseTask = $TaskName
        if (Test-Path (Join-Path "C:\AIS\1 Release" $TaskName)) { $OutDir = Join-Path "C:\AIS\1 Release" $TaskName }
        elseif (Test-Path (Join-Path "C:\AIS\AI\Prod\tasks" $TaskName)) { $OutDir = Join-Path "C:\AIS\AI\Prod\tasks" $TaskName }
        else { $OutDir = Join-Path "C:\AIS\AI\Prod\temp" $baseTask }
    }
    else { $OutDir = Join-Path $tempDir "sborka" }
}
$outFull = Join-Path $OutDir $exeStamp

# генерация .PBS
$pbsLines = New-OrcaScript `
    -LibsFlag $libsArg `
    -AppName "golden" `
    -ExeInfoCopyright $newCopyright `
    -FileVersion $newFile `
    -FileVersionNum $newFileNum `
    -ProductVersion $newProduct `
    -ProductVersionNum $newProductNum `
    -PbdFlags $pbdFlags

$pbsText = ($pbsLines -join "`r`n")

Write-Output "=== ПЛАН СБОРКИ ==="
Write-Output "Рабочий корень : $goldRoot"
Write-Output "Текущие версии : Product=$($srj.PV) File=$($srj.FV)"
if ($Version -and $Version.Trim() -ne "") {
    Write-Output ("Новые версии   : Product=$newProduct File=$newFile (РУЧНАЯ)")
} else {
    Write-Output ("Новые версии   : Product=$newProduct File=$newFile (авто, было $($srj.PV))")
}
Write-Output "Copyright      : $newCopyright"
Write-Output "Библиотек в liblist: $($libs.Count)"
Write-Output "PBD-флаги      : $pbdFlags"
Write-Output "Выходная папка : $outFull"

$pbsDir = Join-Path $tempDir "sborka"
if (-not (Test-Path $pbsDir)) { New-Item -ItemType Directory -Path $pbsDir -Force | Out-Null }
$pbsFile = Join-Path $pbsDir "sborka_$stamp.pbs"
$logFile = Join-Path $pbsDir "sborka_$stamp.log"

$pbsContent = @()
$pbsContent += "; OrcaScript batch - generate golden.exe + PBD"
$pbsContent += "; Generated by Sborka-Golden.ps1 $dateToday"
$pbsContent += $pbsText
# передать пользователю готовый текст скрипта OrcaScript
$pbsFull = ($pbsContent -join "`r`n")

Set-Content -Path $pbsFile -Value $pbsFull -Encoding ASCII

Write-Output ""
Write-Output "=== СОДЕРЖИМОЕ .PBS ==="
Write-Output $pbsFull
Write-Output ""
Write-Output "PBS файл: $pbsFile"

if ($DryRun) {
    Write-Output ""
    Write-Output "[DRY RUN] Реальная сборка НЕ выполняется. Для запуска используйте -RunBuild."
    exit 0
}

if (-not $RunBuild) {
    Write-Output ""
    Write-Output "PBS создан. Для реальной сборки запустите с параметром -RunBuild."
    exit 0
}

# ---------- реальная сборка ----------
Write-Output ""
Write-Output "=== ЗАПУСК orcascr125.exe ==="
Write-Output "Рабочий каталог: $goldRoot"

$logOutFile = Join-Path $pbsDir "sborka_out_$stamp.out"
$logErrFile = Join-Path $pbsDir "sborka_err_$stamp.out"
$p1 = Start-Process -FilePath $orcaExe `
    -ArgumentList $pbsFile `
    -WorkingDirectory $goldRoot `
    -RedirectStandardOutput $logOutFile `
    -RedirectStandardError $logErrFile `
    -NoNewWindow -Wait -PassThru

$exitCode = $p1.ExitCode
if (Test-Path $logOutFile) {
    Get-Content -Path $logOutFile -Encoding Default | Out-File -FilePath $logFile -Encoding UTF8
    Write-Output (Get-Content -Path $logOutFile -Encoding Default)
}
if (Test-Path $logErrFile) {
    $errContent = Get-Content -Path $logErrFile -Encoding Default
    if ($errContent) {
        Write-Output "--- STDERR ---"
        Write-Output $errContent
        $errContent | Out-File -FilePath $logFile -Encoding UTF8 -Append
    }
}
Write-Output "Exit code orcascr125: $exitCode"

if ($exitCode -ne 0) {
    Write-Output "ОШИБКА: сборка завершилась с кодом $exitCode. Лог: $logFile"
    exit $exitCode
}

$exeBuilt = Join-Path $srcDir "golden.exe"
if (-not (Test-Path $exeBuilt)) {
    Write-Output "ОШИБКА: golden.exe не создан. Лог: $logFile"
    exit 2
}

# ---------- копирование результата ----------
Write-Output ""
Write-Output "=== КОПИРОВАНИЕ В $outFull ==="
if (-not (Test-Path $outFull)) { New-Item -ItemType Directory -Path $outFull -Force | Out-Null }

Copy-Item -Path $exeBuilt -Destination $outFull -Force

# PBD — из рабочих каталогов по LibList
foreach ($lib in $libs) {
    if ($lib -like "*.pbd") { continue }
    $pbdName = [System.IO.Path]::ChangeExtension((Split-Path $lib -Leaf), ".pbd")
    $pbdDir = Join-Path $goldRoot (Split-Path $lib -Parent)
    $pbdFile = Join-Path $pbdDir $pbdName
    if (-not (Test-Path $pbdFile)) { continue }
    Copy-Item -Path $pbdFile -Destination $outFull -Force
}

# вспомогательные файлы из EXE-набора
$exeSet = Join-Path $srcDir "EXE"
if (Test-Path $exeSet) {
    Get-ChildItem -Path $exeSet -File | Where-Object { $_.Extension -in @(".dll",".ini",".ocx",".pbd") } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $outFull -Force
    }
}

# RELEASE_NOTES.txt
$releaseNotes = @(
    "AIS СБОРКА golden.exe",
    "Дата: $dateToday",
    "Версия Product: $newProduct  (File: $newFile)",
    "Папка сборки: $exeStamp",
    "Задача: $TaskName",
    "",
    "Состав:",
    "  golden.exe",
    "  *.pbd — по LibList из gold.pbt ($($libs.Count) библиотек)",
    "  *.dll/ini/ocx — из EXE-набора golden_start\EXE",
    ""
) -join "`r`n"
Set-Content -Path (Join-Path $outFull "RELEASE_NOTES.txt") -Value $releaseNotes -Encoding Default

# ---------- обновление golden.srj (требование спеки 5.1) ----------
$srjLines = Get-Content -Path $srjFile -Encoding Default
for ($i = 0; $i -lt $srjLines.Count; $i++) {
    if ($srjLines[$i] -like "CPY:*") { $srjLines[$i] = "CPY:$newCopyright" }
    elseif ($srjLines[$i] -like "PVS:*") { $srjLines[$i] = "PVS:$newProduct" }
    elseif ($srjLines[$i] -like "PVN:*") { $srjLines[$i] = "PVN:$newProductNum" }
    elseif ($srjLines[$i] -like "FVS:*") { $srjLines[$i] = "FVS:$newFile" }
    elseif ($srjLines[$i] -like "FVN:*") { $srjLines[$i] = "FVN:$newFileNum" }
}
Set-Content -Path $srjFile -Value $srjLines -Encoding Default
Write-Output "golden.srj обновлён: версия $newProduct, Copyright $dateToday"

Write-Output ""
Write-Output "=== ГОТОВО ==="
Write-Output "Сборка: $outFull"
Write-Output "Версия повышена: $($srj.PV) -> $newProduct"
Write-Output "Log: $logFile"