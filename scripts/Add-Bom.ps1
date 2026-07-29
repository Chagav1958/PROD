param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Path = '',
    
    [switch]$Recurse
)

if ($Path) {
    if (Test-Path $Path) {
        $files = @(Get-Item $Path)
    } else {
        Write-Host "File not found: $Path"
        exit 1
    }
} else {
    $files = @(Get-ChildItem 'C:\AIS\AI\Prod' -Filter '*.ps1' -Recurse:$Recurse -ErrorAction SilentlyContinue)
}

$count = 0
$bom = New-Object System.Text.UTF8Encoding $true
foreach ($f in $files) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        if (-not $hasBom) {
            $content = [System.IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText($f.FullName, $content, $bom)
            $count++
            Write-Host "  + BOM added: $($f.Name)"
        }
    } catch {
        Write-Host "  ! Error: $($f.Name) - $($_.Exception.Message)"
    }
}
Write-Host "Done. $count files updated with BOM."