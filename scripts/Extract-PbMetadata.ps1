param(
    [string]$BaseDir = "C:\AIS\AI\Prod\PB_Current",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\pb_metadata.json"
)

$ErrorActionPreference = 'Continue'

$extMap = @{
    '.sru' = 'UserObject'
    '.srw' = 'Window'
    '.srd' = 'DataWindow'
    '.srf' = 'Function'
    '.srp' = 'Proxy'
    '.srs' = 'Structure'
    '.srm' = 'Menu'
    '.srj' = 'Application'
    '.sra' = 'Ancestor'
}

$libs = Get-ChildItem $BaseDir -Directory | Sort-Object Name
$allResults = @{}
$totalAll = 0

foreach ($lib in $libs) {
    $libName = $lib.Name
    $files = Get-ChildItem $lib.FullName -Recurse -File -ErrorAction SilentlyContinue | Sort-Object Name
    if ($files.Count -eq 0) { continue }

    Write-Host "$libName`: $($files.Count) files"
    $results = @()

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $ext = $f.Extension.ToLower()
        $objType = if ($extMap.ContainsKey($ext)) { $extMap[$ext] } else { $ext }

        # Read first 3 lines for context
        $context = ""
        try {
            $lines = Get-Content $f.FullName -TotalCount 3 -ErrorAction SilentlyContinue
            if ($lines) {
                $context = ($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join "; "
                if ($context.Length -gt 200) { $context = $context.Substring(0, 200) }
            }
        } catch { }

        # Detect SQL references
        $hasSql = $false
        if ($context -match '\b(SELECT|UPDATE|INSERT|DELETE|DECLARE\s+\w+\s+PROCEDURE|EXECUTE|sp_)\b') {
            $hasSql = $true
        }

        $results += [PSCustomObject]@{
            Name    = $name
            Type    = $objType
            Ext     = $ext
            Library = $libName
            HasSql  = $hasSql
            Context = $context
        }
    }

    $allResults[$libName] = $results
    $totalAll += $results.Count
}

# Save
$output = @{
    total    = $totalAll
    by_lib   = @{}
    by_type  = @{}
    objects  = @{}
}

$typeCount = @{}
foreach ($k in $allResults.Keys) {
    $output.by_lib[$k] = $allResults[$k].Count
    $output.objects[$k] = $allResults[$k]
    foreach ($obj in $allResults[$k]) {
        if (-not $typeCount.ContainsKey($obj.Type)) { $typeCount[$obj.Type] = 0 }
        $typeCount[$obj.Type]++
    }
}
$output.by_type = $typeCount

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "=== SUMMARY ==="
Write-Host ("Total: $totalAll objects")
Write-Host "By type:"
foreach ($k in ($typeCount.Keys | Sort-Object { -$typeCount[$_] })) {
    Write-Host ("  $k`: " + $typeCount[$k])
}
Write-Host ("Saved: $OutFile ($([math]::Round($json.Length/1024,1)) KB)")
