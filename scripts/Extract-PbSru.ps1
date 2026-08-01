param(
    [string]$BaseDir = "C:\AIS\AI\Prod\PB_Current",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\pb_sru_metadata.json"
)
$ErrorActionPreference = 'Continue'
$libs = Get-ChildItem $BaseDir -Directory | Sort-Object Name
$results = @{}

foreach ($lib in $libs) {
    $files = Get-ChildItem $lib.FullName -Recurse -File -Filter '*.sru' -ErrorAction SilentlyContinue
    if ($files.Count -eq 0) { continue }
    Write-Host "$($lib.Name): $($files.Count) .sru"
    $libResults = @()

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $text = ""
        try { $sr = New-Object System.IO.StreamReader($f.FullName, [Text.Encoding]::GetEncoding(1251), $true); $text = $sr.ReadToEnd(); $sr.Close() } catch { continue }
        if (-not $text) { continue }

        $ancestor = ""
        $controls = @()
        $variables = @()
        $functionNames = @()
        $sqlRefs = @()

        # Object + ancestor: global type <name> from <ancestor>
        if ($text -match 'global\s+type\s+(\w+)\s+from\s+(\w+)') {
            $ancestor = $matches[2]
        }

        # Controls in forward block
        $fwMatch = [regex]::Match($text, 'forward\s*([\s\S]*?)end\s+forward', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($fwMatch.Success) {
            $fwBlock = $fwMatch.Groups[1].Value
            $ctrlMatches = [regex]::Matches($fwBlock, 'type\s+(\w+)\s+from\s+(\w+)\s+within\s+(\w+)')
            foreach ($cm in $ctrlMatches) {
                $controls += "$($cm.Groups[1].Value)($($cm.Groups[2].Value))"
            }
            if ($controls.Count -gt 15) { $controls = $controls[0..14] }
        }

        # Instance variables between global type end and first function/event
        if ($text -match 'global\s+type\s+\w+\s+from\s+\w+([\s\S]*?)(?:(?:public|private|protected)\s+(?:function|subroutine|event)|end\s+type)') {
            $varBlock = $matches[1]
            $varMatches = [regex]::Matches($varBlock, '^\s*(\w+)\s+(\w+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($vm in $varMatches) {
                $vType = $vm.Groups[1].Value
                $vName = $vm.Groups[2].Value
                if ($vType -notmatch '^(integer|string|long|boolean|date|time|decimal|real|double|char|blob|any|window|userobject|datawindow)') { continue }
                $variables += "$($vName):$vType"
            }
            if ($variables.Count -gt 10) { $variables = $variables[0..9] }
        }

        # Function signatures
        $fnMatches = [regex]::Matches($text, '(?:public|private|protected)\s+(function|subroutine)\s+(\w+)\s*\(([^)]*)\)\s+returns\s+(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($fm in $fnMatches) {
            $functionNames += $fm.Groups[2].Value
        }
        if ($functionNames.Count -gt 15) { $functionNames = $functionNames[0..14] }

        # Embedded SQL
        if ($text -match '\b(SELECT|UPDATE\s+\w+\s+SET|INSERT\s+INTO|DELETE\s+FROM|DECLARE\s+\w+\s+PROCEDURE|EXECUTE\s+(?:immediate\s+)?)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) {
            $sqlMatch = [regex]::Matches($text, '(?:DECLARE\s+(\w+)\s+PROCEDURE|FROM\s+(\w+)|JOIN\s+(\w+)|INTO\s+(\w+)|UPDATE\s+(\w+))', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $seen = @{}
            foreach ($sm in $sqlMatch) {
                for ($i = 1; $i -le 5; $i++) {
                    $tbl = $sm.Groups[$i].Value
                    if ($tbl -and -not $seen.ContainsKey($tbl) -and $tbl -notmatch '^(where|set|and|or|values|select|from)$') {
                        $sqlRefs += $tbl
                        $seen[$tbl] = $true
                    }
                }
            }
            if ($sqlRefs.Count -gt 10) { $sqlRefs = $sqlRefs[0..9] }
        }

        $libResults += [PSCustomObject]@{
            Name      = $name
            Type      = 'UserObject'
            Library   = $lib.Name
            Ancestor  = $ancestor
            Controls  = ($controls -join ', ')
            Vars      = ($variables -join ', ')
            Functions = ($functionNames -join ', ')
            SqlTables = ($sqlRefs -join ', ')
        }
    }
    $results[$lib.Name] = $libResults
}

$total = 0
foreach ($k in $results.Keys) { $total += $results[$k].Count }
$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$output = @{ total = $total; objects = $results }
$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Saved: $OutFile ($total .sru, $([math]::Round($json.Length/1024,1)) KB)")
