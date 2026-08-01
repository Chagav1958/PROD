param(
    [string]$MisRoot = 'C:\SRC125\gold',
    [string]$OutRoot = 'C:\AIS\AI\AIS\PB',
    [string]$PbldumpExe = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\pbldump-1.3.1stable\PblDump.exe'),
    [string]$PbtName = 'gold',
    [string]$LogDir = (Join-Path $PSScriptRoot 'Log'),
    [switch]$CleanArtifactsOnly
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $LogDir 'work.log'
$migLogPath = Join-Path $LogDir 'gold_mig.log'

function Clear-PbExportArtifacts {
    <#
      Removes previous PowerBuilder / pbldump export under OutRoot (per-library folders, .sr*, copied pbw/pbt/...).
      Preserves: .cursor folder, export_*.sql (DDL export), MIS_DDL*.sql (legacy DDL dump name).
    #>
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }
    $preserveDirs = @('.cursor')
    Get-ChildItem -LiteralPath $Root -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($preserveDirs -contains $_.Name) {
                return
            }
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
            return
        }
        $n = $_.Name
        if ($n -like 'export_*') {
            return
        }
        if ($n -like 'MIS_DDL*.sql') {
            return
        }
        $ext = $_.Extension.ToLowerInvariant()
        $pbRootExtensions = @('.pbw', '.pbt', '.pbp', '.pbr', '.ini', '.cfg', '.txt', '.log', '.sql')
        if ($pbRootExtensions -contains $ext -or $n -match '\.sr[^.]*$') {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    }
}

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding Default
    Write-Host $line
}

function Get-LibListEntries {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Файл проекта не найден: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw -notmatch 'LibList\s+"([^"]+)"') {
        throw "Строка LibList не найдена в: $Path"
    }
    $inner = $matches[1]
    $inner -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

function Normalize-PbtPath {
    param([string]$Entry)
    $Entry -replace '\\+', '\'
}

function Get-UniqueExportDirName {
    param(
        [string]$BaseName,
        [hashtable]$UsedCounts
    )
    if (-not $UsedCounts.ContainsKey($BaseName)) {
        $UsedCounts[$BaseName] = 0
    }
    $UsedCounts[$BaseName]++
    $n = $UsedCounts[$BaseName]
    if ($n -eq 1) { return $BaseName }
    return "${BaseName}_$n"
}

function Copy-LocalSrOverlay {
    # Локальные .sr* рядом с PBL (SCC/checkout) перекрывают дамп pbldump.
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        return 0
    }
    $count = 0
    Get-ChildItem -LiteralPath $SourceDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.sr[^.]*$' } |
        ForEach-Object {
            $dest = Join-Path $TargetDir $_.Name
    try {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                Set-ItemProperty -LiteralPath $dest -Name IsReadOnly -Value $false
                $null = Remove-HaPrefix -Path $dest
                Write-Log "LOCAL SR overlay: $($_.Name) <- $SourceDir"
                $count++
            } catch {
                Write-Log "WARN: Cannot copy locked file $($_.FullName): $($_.Exception.Message)"
            }
        }
    return $count
}

function Remove-HaPrefix {
    param([string]$Path)
    try {
        $bytes = Get-Content -LiteralPath $Path -Encoding Byte -TotalCount 4
        if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x48 -and $bytes[1] -eq 0x41) {
            $content = Get-Content -LiteralPath $Path -Raw -Encoding Default
            $stripped = $content.Substring(2)
            Set-ItemProperty -LiteralPath $Path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $Path -Value $stripped -Encoding Default -NoNewline
            Write-Log "STRIPPED HA prefix in $Path"
            return $true
        }
    } catch {
        Write-Log "WARN: Cannot strip HA prefix in $($Path): $($_.Exception.Message)"
    }
    return $false
}

function Convert-HexEncodedText {
    param([string]$Text)
    $regex = [regex]'\$\$HEX(\d+)\$\$([0-9A-Fa-f]+)\$\$ENDHEX\$\$'
    $result = $Text
    $matches = $regex.Matches($Text)
    for ($i = $matches.Count - 1; $i -ge 0; $i--) {
        $m = $matches[$i]
        $hex = $m.Groups[2].Value
        $bytes = @()
        for ($j = 0; $j -lt $hex.Length; $j += 2) {
            $bytes += [Convert]::ToByte($hex.Substring($j, 2), 16)
        }
        $decoded = [System.Text.Encoding]::Unicode.GetString($bytes)
        $result = $result.Remove($m.Index, $m.Length).Insert($m.Index, $decoded)
    }
    return $result
}

New-Item -ItemType Directory -Path $OutRoot -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

if ($CleanArtifactsOnly) {
    Clear-PbExportArtifacts -Root $OutRoot
    Write-Host "Очищены артефакты экспорта PowerBuilder в: $OutRoot"
    exit 0
}

if (-not (Test-Path -LiteralPath $MisRoot)) {
    throw "Исходный каталог не найден: $MisRoot"
}
if (-not (Test-Path -LiteralPath $PbldumpExe)) {
    throw "pbldump.exe не найден: $PbldumpExe"
}

Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

Write-Log "=== PBL export from LibList in $PbtName.pbt ==="
Write-Log "MIS root: $MisRoot"
Write-Log "Output: $OutRoot"

$entries = Get-LibListEntries -Path $(Join-Path $MisRoot "$PbtName.pbt")
$seenFullPath = @{}
$usedDirNames = @{}
$ok = 0
$fail = 0
$skippedPbd = 0
$skippedMissing = 0
$skippedDup = 0
$overlayCount = 0

foreach ($entry in $entries) {
    $rel = Normalize-PbtPath -Entry $entry
    $full = $null
    try {
        $full = [System.IO.Path]::GetFullPath((Join-Path $MisRoot $rel))
    } catch {
        Write-Log "PATH ERROR (skip): $entry - $($_.Exception.Message)"
        $fail++
        continue
    }

    $ext = [System.IO.Path]::GetExtension($full)
    if ($ext -eq '.pbd') {
        Write-Log "SKIP PBD (not handled by pbldump): $rel"
        $skippedPbd++
        continue
    }

    if ($ext -ne '.pbl') {
        Write-Log "SKIP unknown extension [$ext]: $rel"
        continue
    }

    if ($seenFullPath.ContainsKey($full)) {
        Write-Log "SKIP duplicate LibList entry: $full"
        $skippedDup++
        continue
    }
    $seenFullPath[$full] = $true

    if (-not (Test-Path -LiteralPath $full)) {
        Write-Log "SKIP file not found: $full"
        $skippedMissing++
        continue
    }

    $libBase = [System.IO.Path]::GetFileNameWithoutExtension($full)
    $dirName = Get-UniqueExportDirName -BaseName $libBase -UsedCounts $usedDirNames
    $targetDir = Join-Path $OutRoot $dirName

    try {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    } catch {
        Write-Log "MKDIR ERROR $targetDir - $($_.Exception.Message)"
        $fail++
        continue
    }

    Write-Log ">>> $full -> $targetDir"
    Push-Location -LiteralPath $targetDir
    try {
        & $PbldumpExe -esu $full '*.*'
        if ($null -eq $LASTEXITCODE) {
            $rc = -1
        } else {
            $rc = [int]$LASTEXITCODE
        }
    } catch {
        Write-Log "PBLDUMP LAUNCH ERROR: $($_.Exception.Message)"
        $rc = -1
    } finally {
        Pop-Location
    }

    if ($rc -eq 0) {
        Write-Log "OK exit=$rc $full"
        $ok++
        $pblDir = [System.IO.Path]::GetDirectoryName($full)
        $overlayCount += Copy-LocalSrOverlay -SourceDir $pblDir -TargetDir $targetDir
    } else {
        Write-Log "PBLDUMP ERROR exit=$rc $full"
        $fail++
    }
}

$overlayCount += Copy-LocalSrOverlay -SourceDir $MisRoot -TargetDir $OutRoot

Write-Log "=== Post-processing: decoding HEX-encoded Russian text in .sr* files ==="
$hexFiles = Get-ChildItem -LiteralPath $OutRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\.sr[^.]*$' }
$fixedFiles = 0
$fixedBlocks = 0
foreach ($f in $hexFiles) {
    try {
        $null = Remove-HaPrefix -Path $f.FullName
        $content = Get-Content -LiteralPath $f.FullName -Raw -Encoding Default
        $newContent = Convert-HexEncodedText -Text $content
        if ($newContent -ne $content) {
            $blockCount = [regex]::Matches($content, '\$\$HEX\d+\$\$[0-9A-Fa-f]+\$\$ENDHEX\$\$').Count
            Set-ItemProperty -LiteralPath $f.FullName -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $f.FullName -Value $newContent -Encoding Default -NoNewline
            $fixedFiles++
            $fixedBlocks += $blockCount
            Write-Log "DECODED $($blockCount) blocks in $($f.FullName)"
        }
    } catch {
        Write-Log "WARN: Cannot decode $($f.FullName): $($_.Exception.Message)"
    }
}
Write-Log "=== Decoding done: $fixedFiles files, $fixedBlocks blocks fixed ==="

# Удаление лишних файлов из папки с объектами
$extraFiles = @("$PbtName.pbt", "gold_mig.log")
foreach ($f in $extraFiles) {
    $p = Join-Path $OutRoot $f
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force
        Write-Log "REMOVED $f from $OutRoot"
    }
}

Write-Log "=== Summary: OK=$ok errors=$fail skipped_pbd=$skippedPbd missing=$skippedMissing duplicates=$skippedDup local_sr_overlay=$overlayCount decoded_files=$fixedFiles decoded_blocks=$fixedBlocks ==="
if ($fail -gt 0) {
    exit 1
}
exit 0
