param(
    [string]$BaseDir = "C:\AIS\AI\Prod\PB_Current",
    [string]$OutFile = "C:\AIS\AI\Prod\temp\pb_srw_metadata.json"
)
$ErrorActionPreference = 'Continue'
$libs = Get-ChildItem $BaseDir -Directory | Sort-Object Name
$results = @{}

foreach ($lib in $libs) {
    $files = Get-ChildItem $lib.FullName -Recurse -File -Filter '*.srw' -ErrorAction SilentlyContinue
    if ($files.Count -eq 0) { continue }
    Write-Host "$($lib.Name): $($files.Count) .srw"
    $libResults = @()

    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $text = ""
        try { $sr = New-Object System.IO.StreamReader($f.FullName, [Text.Encoding]::GetEncoding(1251), $true); $text = $sr.ReadToEnd(); $sr.Close() } catch { continue }
        if (-not $text) { continue }

        $ancestor = ""
        $title = ""
        $menuName = ""
        $controls = @()
        $functionNames = @()

        if ($text -match 'global\s+type\s+(\w+)\s+from\s+(\w+)') { $ancestor = $matches[2] }
        if ($text -match 'string\s+title\s*=\s*"([^"]*)"') { $title = $matches[1] }
        if ($text -match 'string\s+menuname\s*=\s*"([^"]*)"') { $menuName = $matches[1] }

        $fwMatch = [regex]::Match($text, 'forward\s*([\s\S]*?)end\s+forward', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($fwMatch.Success) {
            $ctrlMatches = [regex]::Matches($fwMatch.Groups[1].Value, 'type\s+(\w+)\s+from\s+(\w+)\s+within\s+(\w+)')
            foreach ($cm in $ctrlMatches) {
                $controls += "$($cm.Groups[1].Value)($($cm.Groups[2].Value))"
            }
            if ($controls.Count -gt 20) { $controls = $controls[0..19] }
        }

        $fnMatches = [regex]::Matches($text, '(?:public|private|protected)\s+(function|subroutine)\s+(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($fm in $fnMatches) { $functionNames += $fm.Groups[2].Value }
        if ($functionNames.Count -gt 15) { $functionNames = $functionNames[0..14] }

        $libResults += [PSCustomObject]@{
            Name      = $name
            Type      = 'Window'
            Library   = $lib.Name
            Ancestor  = $ancestor
            Title     = $title
            Menu      = $menuName
            Controls  = ($controls -join ', ')
            Functions = ($functionNames -join ', ')
        }
    }
    $results[$lib.Name] = $libResults
}

$total = 0; foreach ($k in $results.Keys) { $total += $results[$k].Count }
$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$output = @{ total = $total; objects = $results }
$json = $output | ConvertTo-Json -Depth 3 -Compress
[System.IO.File]::WriteAllText($OutFile, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Saved: $OutFile ($total .srw, $([math]::Round($json.Length/1024,1)) KB)")
