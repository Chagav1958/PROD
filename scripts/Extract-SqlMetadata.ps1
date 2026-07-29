param(
    [string]$ProcDir = "C:\AIS\AI\Prod\BD\dev_golden\golden\Procedure",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\sql_metadata.json"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProcDir)) { throw "ProcDir not found: $ProcDir" }

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Write-Host "Scanning: $ProcDir"
$files = Get-ChildItem $ProcDir -File -Filter '*.sql' | Sort-Object Name
Write-Host ("Found " + $files.Count + " files")

$results = @()
$idx = 0

foreach ($f in $files) {
    $idx++
    if ($idx % 100 -eq 0) { Write-Host ("  " + $idx + "/" + $files.Count) }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $lines = Get-Content $f.FullName -TotalCount 60 -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($lines.Count -eq 0) { continue }

    # Join and normalize
    $text = ($lines | ForEach-Object { $_.Trim() }) -join " "
    $text = $text -replace '\s+', ' '

    # Extract CREATE statement
    $createMatch = [regex]::Match($text, 'CREATE\s+(PROC(?:EDURE)?|FUNCTION|TRIGGER|TABLE|VIEW)\s+(\w+\.)?(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $createMatch.Success) {
        $objType = "Unknown"
        $objName = $name
    } else {
        $objType = $createMatch.Groups[1].Value.ToUpper()
        $objName = $createMatch.Groups[3].Value
    }

    # Extract parameters (between CREATE...name and AS/BEGIN)
    $paramBlock = ""
    $asIdx = [regex]::Match($text, '\bAS\b\s+BEGIN\b|\bAS\b\s|\bBEGIN\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($asIdx.Success -and $createMatch.Success) {
        $pLen = $asIdx.Index - $createMatch.Index - $createMatch.Length
        if ($pLen -gt 0) {
            $paramBlock = $text.Substring($createMatch.Index + $createMatch.Length, $pLen).Trim()
        }
        $paramBlock = $paramBlock -replace '--.*?(\r|\n|$)', ' '
        $paramBlock = $paramBlock -replace '/\*.*?\*/', ' '
        $paramBlock = $paramBlock -replace '\s+', ' '
        if ($paramBlock.Length -gt 500) { $paramBlock = $paramBlock.Substring(0, 500) + "..." }
    }

    # Extract table references
    $tables = @{}
    $tableMatches = [regex]::Matches($text, '(?:FROM|JOIN|INTO|UPDATE|TABLE)\s+(\w+\.)?(\w+\.)?(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $tableMatches) {
        $tbl = $m.Groups[3].Value.ToLower()
        if ($tbl -notmatch '^(select|set|where|and|or|values|null|not|top|distinct|exists|case|when|then|else|end|begin|declare|varchar|int|numeric|datetime|char|float|smallint|tinyint|bigint|binary|text|image|cursor|output|as|desc|asc|order|group|having)$') {
            if (-not $tables.ContainsKey($tbl)) { $tables[$tbl] = 1 }
        }
    }
    $tableList = ($tables.Keys | Sort-Object) -join ', '
    if ($tableList.Length -gt 200) { $tableList = $tableList.Substring(0, 200) + "..." }

    # Extract Jira references from comments
    $jiraRefs = ""
    $jiraMatch = [regex]::Matches($text, 'SYBASE-\d+')
    if ($jiraMatch.Count -gt 0) {
        $jiraRefs = ($jiraMatch | ForEach-Object { $_.Value } | Select-Object -Unique) -join ', '
        if ($jiraRefs.Length -gt 100) { $jiraRefs = $jiraRefs.Substring(0, 100) }
    }

    $results += [PSCustomObject]@{
        Name       = $objName
        Type       = $objType
        FileName   = $f.Name
        Params     = $paramBlock
        Tables     = $tableList
        Jira       = $jiraRefs
    }
}

# Группировка по префиксу для удобной загрузки
$groups = $results | Group-Object { 
    $n = $_.Name
    if ($n -match '^(usp_\w+)') { return $matches[1] }
    if ($n -match '^(\w\w\w?)') { return $matches[1] }
    return "other"
} | Sort-Object Count -Descending

$summary = @{}
foreach ($g in $groups) {
    $summary[$g.Name] = $g.Count
}

Write-Host ""
Write-Host "=== Summary ==="
Write-Host ("Total objects: " + $results.Count)
Write-Host ("Groups: " + $groups.Count)
Write-Host "Top groups:"
$groups | Select-Object -First 20 | ForEach-Object { Write-Host ("  " + $_.Name + ": " + $_.Count) }

# Сохраняем в JSON
$output = @{
    total = $results.Count
    groups = $summary
    objects = $results
}

$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host ("Saved: " + $OutFile)
Write-Host ("Size: " + [math]::Round($json.Length / 1024, 1) + " KB")
