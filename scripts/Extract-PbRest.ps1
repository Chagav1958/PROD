param(
    [string]$BaseDir = "C:\AIS\AI\Prod\PB_Current",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\pb_rest_metadata.json"
)
$ErrorActionPreference = 'Continue'

$extMap = @{
    '.srd' = 'DataWindow'
    '.srf' = 'Function'
    '.srp' = 'Proxy'
    '.srs' = 'Structure'
    '.srm' = 'Menu'
    '.srj' = 'Application'
    '.sra' = 'Ancestor'
}

$libs = Get-ChildItem $BaseDir -Directory | Sort-Object Name
$results = @{}

foreach ($lib in $libs) {
    $files = Get-ChildItem $lib.FullName -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in $extMap.Keys }
    if ($files.Count -eq 0) { continue }
    Write-Host "$($lib.Name): $($files.Count) files"
    $libResults = @()

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $ext = $f.Extension.ToLower()
        $objType = $extMap[$ext]
        $text = ""
        try { $sr = New-Object System.IO.StreamReader($f.FullName, [Text.Encoding]::GetEncoding(1251), $true); $text = $sr.ReadToEnd(); $sr.Close() } catch { continue }
        if (-not $text) { $libResults += [PSCustomObject]@{ Name=$name; Type=$objType; Library=$lib.Name; Sql='' }; continue }

        $sql = ""
        $ancestor = ""

        if ($ext -eq '.srd') {
            # DataWindow: extract SQL from table definition
            if ($text -match 'table\(column=\([^)]*dbname="(\w+)"') {
                $tblMatches = [regex]::Matches($text, 'dbname="([^"]+)"')
                $seen = @{}
                $tables = @()
                foreach ($tm in $tblMatches) {
                    $parts = $tm.Groups[1].Value.Split('.')
                    $tbl = $parts[-1]
                    if (-not $seen.ContainsKey($tbl)) { $tables += $tbl; $seen[$tbl] = $true }
                }
                $sql = ($tables -join ', ')
                if ($sql.Length -gt 200) { $sql = $sql.Substring(0, 200) }
            }
            # Also check for SQL in .srd procedure/text
            if ($text -match 'procedure\s+name=(\w+)') { $sql += " proc:" + $matches[1] }
        } elseif ($ext -eq '.srf') {
            # Function: extract signature
            if ($text -match 'global\s+type\s+(\w+)\s+from\s+(\w+)') { $ancestor = $matches[2] }
            if ($text -match 'function\s+(\w+)\s*\(([^)]*)\)') { $sql = "$($matches[1])($($matches[2]))" }
        } elseif ($ext -eq '.srm') {
            # Menu: extract items
            $menuItems = [regex]::Matches($text, "item\s*=\s*'([^']*)'")
            if ($menuItems.Count -gt 0) {
                $items = @()
                foreach ($mi in $menuItems) { if ($items.Count -lt 10) { $items += $mi.Groups[1].Value } }
                $sql = ($items -join ' > ')
            }
        }

        $libResults += [PSCustomObject]@{
            Name     = $name
            Type     = $objType
            Library  = $lib.Name
            Ancestor = $ancestor
            Sql      = $sql
        }
    }
    $results[$lib.Name] = $libResults
}

$total = 0; $byType = @{}
foreach ($k in $results.Keys) { 
    foreach ($o in $results[$k]) {
        $total++
        if (-not $byType.ContainsKey($o.Type)) { $byType[$o.Type] = 0 }
        $byType[$o.Type]++
    }
}

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$output = @{ total = $total; by_type = $byType; objects = $results }
$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "By type:"
foreach ($k in ($byType.Keys | Sort-Object { -$byType[$_] })) { Write-Host "  $k`: $($byType[$k])" }
Write-Host ("Saved: $OutFile ($total objects, $([math]::Round($json.Length/1024,1)) KB)")
