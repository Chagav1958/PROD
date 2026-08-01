param(
    [string]$BaseDir = "C:\AIS\AI\Prod\BD\dev_golden\golden",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\sql_all_metadata.json"
)

$ErrorActionPreference = 'Stop'

$typeDirs = @("Procedure","Functions","Triggers","Tables","Views")
$allResults = @{}
$totalAll = 0

foreach ($typeDir in $typeDirs) {
    $dir = Join-Path $BaseDir $typeDir
    if (-not (Test-Path $dir)) { Write-Host "SKIP: $dir"; continue }

    $files = Get-ChildItem $dir -File -Filter '*.sql' | Sort-Object Name
    if ($files.Count -eq 0) { continue }

    Write-Host "$typeDir`: $($files.Count) files"
    $results = @()

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $lines = Get-Content $f.FullName -TotalCount 60 -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($lines.Count -eq 0) { continue }

        $text = ($lines | ForEach-Object { $_.Trim() }) -join " "
        $text = $text -replace '\s+', ' '

        $createMatch = [regex]::Match($text, 'CREATE\s+(PROC(?:EDURE)?|FUNCTION|TRIGGER|TABLE|VIEW)\s+(\w+\.)?(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $createMatch.Success) {
            $objType = $typeDir
            $objName = $name
        } else {
            $objType = $typeDir
            $objName = $createMatch.Groups[3].Value
        }

        $paramBlock = ""
        $asIdx = [regex]::Match($text, '\bAS\b\s|\bRETURNS\b|\bBEGIN\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($asIdx.Success -and $createMatch.Success) {
            $pLen = $asIdx.Index - $createMatch.Index - $createMatch.Length
            if ($pLen -gt 0) {
                $paramBlock = $text.Substring($createMatch.Index + $createMatch.Length, $pLen).Trim()
                if ($paramBlock.Length -gt 400) { $paramBlock = $paramBlock.Substring(0, 400) }
            }
        }

        $tables = @{}
        $tableMatches = [regex]::Matches($text, '(?:FROM|JOIN|INTO|ON)\s+(\w+\.)?(\w+\.)?(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($m in $tableMatches) {
            $tbl = $m.Groups[3].Value.ToLower()
            if ($tbl -notmatch '^(select|set|where|and|or|values|null|not|top|distinct|exists|case|when|then|else|end|begin|declare|varchar|int|numeric|datetime|char|float|smallint|tinyint|bigint|binary|text|image|cursor|output|as|desc|asc|order|group|having|inserted|deleted|sysobjects|syscomments|sysindexes)$') {
                if (-not $tables.ContainsKey($tbl)) { $tables[$tbl] = 1 }
            }
        }
        $tableList = ($tables.Keys | Sort-Object) -join ', '
        if ($tableList.Length -gt 200) { $tableList = $tableList.Substring(0, 200) + "..." }

        $results += [PSCustomObject]@{
            Name   = $objName
            Type   = $objType
            File   = $f.Name
            Params = $paramBlock
            Tables = $tableList
        }
    }

    $allResults[$typeDir] = $results
    $totalAll += $results.Count
}

# Output
$output = @{
    total = $totalAll
    by_type = @{}
    objects = @{}
}
foreach ($k in $allResults.Keys) {
    $output.by_type[$k] = $allResults[$k].Count
    $output.objects[$k] = $allResults[$k]
}

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== SUMMARY ==="
Write-Host ("Total: $totalAll objects")
foreach ($k in ($output.by_type.Keys | Sort-Object)) {
    Write-Host ("  $k`: " + $output.by_type[$k])
}
Write-Host ("Saved: $OutFile ($([math]::Round($json.Length/1024,1)) KB)")
