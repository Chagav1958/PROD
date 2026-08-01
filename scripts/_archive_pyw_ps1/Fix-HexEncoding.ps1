param(
    [Parameter(Position=0)]
    [string]$Path = '',
    
    [switch]$Recurse,
    [switch]$Quiet
)

function Decode-HexBlock {
    param([string]$HexStr)
    $chars = @()
    for ($i = 0; $i -lt $HexStr.Length; $i += 4) {
        if ($i + 4 -le $HexStr.Length) {
            $lo = $HexStr.Substring($i, 2)
            $hi = $HexStr.Substring($i+2, 2)
            $code = [Convert]::ToInt32($hi + $lo, 16)
            $chars += [char]$code
        }
    }
    return [string]::new($chars)
}

if ($Path -and (Test-Path $Path)) {
    $files = @(if ((Get-Item $Path).PSIsContainer) { Get-ChildItem $Path -Recurse:$Recurse -File | Where-Object { $_.Extension -match '\.sr[^p]$' } } else { Get-Item $Path })
} else {
    Write-Host "Usage: Fix-HexEncoding.ps1 <path> [-Recurse]"
    Write-Host "Example: Fix-HexEncoding.ps1 'C:\AIS\1 Release\SYBASE-19298_19296' -Recurse"
    exit 1
}

$hexPattern = [regex]'\$\$HEX\d+\$\$([A-Fa-f0-9]+)\$\$ENDHEX\$\$'
$fixedCount = 0

foreach ($f in $files) {
    try {
        $content = [System.IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
        if (-not ($content -match '\$\$HEX\d+\$\$')) { continue }
        
        $decoded = $hexPattern.Replace($content, {
            param($m)
            return Decode-HexBlock -HexStr $m.Groups[1].Value
        })
        
        $f.IsReadOnly = $false
        [System.IO.File]::WriteAllText($f.FullName, $decoded, [Text.Encoding]::UTF8)
        $fixedCount++
        if (-not $Quiet) { Write-Host "  FIXED: $($f.FullName)" }
    } catch {
        if (-not $Quiet) { Write-Host "  ERROR: $($f.FullName) - $($_.Exception.Message)" }
    }
}

Write-Host "Fix-HexEncoding: $fixedCount files fixed"