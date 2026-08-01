param(
    [string]$Path = 'C:\AIS\AI\Prod',
    [switch]$AutoFix
)

$dangerousPatterns = @(
    @{ Pattern = 'ExecutionPolicy Bypass'; Replacement = 'RemoteSigned'; Severity = 'HIGH' },
    @{ Pattern = 'WScript\.Shell\.Run.*,\s*0,\s*False'; Replacement = 'Shell.Application.ShellExecute, open, 1'; Severity = 'HIGH' },
    @{ Pattern = 'Runtime\.InteropServices\.Marshal]::GetActiveObject'; Replacement = 'New-Object -ComObject (с проверкой Get-Process)'; Severity = 'HIGH' },
    @{ Pattern = 'WindowStyle\s+Hidden'; Replacement = 'WindowStyle Normal или не указывать'; Severity = 'MEDIUM' },
    @{ Pattern = 'IEX|Invoke-Expression'; Replacement = 'Избегать; использовать .NET методы'; Severity = 'MEDIUM' }
)

Write-Host "=== Preflight Scanner ==="
Write-Host ("Path: " + $Path)
Write-Host ("AutoFix: " + $AutoFix)
Write-Host ""

$ps1Files = Get-ChildItem $Path -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue
$totalScanned = 0
$issuesFound = 0
$issuesFixed = 0

foreach ($f in $ps1Files) {
    $totalScanned++
    try {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $content = [Text.Encoding]::UTF8.GetString($bytes)
        
        $fileIssues = @()
        if (-not $hasBom) { $fileIssues += "NO_BOM" }
        
        foreach ($dp in $dangerousPatterns) {
            if ($content -match $dp.Pattern) {
                $fileIssues += "$($dp.Severity):$($dp.Pattern)"
            }
        }
        
        if ($fileIssues.Count -gt 0) {
            $issuesFound++
            $relPath = $f.FullName.Replace('C:\AIS\AI\Prod\', '')
            Write-Host ("ISSUE: " + $relPath)
            foreach ($issue in $fileIssues) { Write-Host ("  - " + $issue) }
            
            if ($AutoFix) {
                $f.IsReadOnly = $false
                if ($fileIssues -contains 'NO_BOM') {
                    $bom = New-Object System.Text.UTF8Encoding $true
                    [System.IO.File]::WriteAllText($f.FullName, $content, $bom)
                    Write-Host "  FIXED: BOM added"
                    $issuesFixed++
                }
            }
        }
    } catch {
        Write-Host ("ERROR: " + $f.FullName + " - " + $_.Exception.Message)
    }
}

Write-Host ""
Write-Host ("Total scanned: " + $totalScanned)
Write-Host ("Issues found: " + $issuesFound)
if ($AutoFix) { Write-Host ("Issues fixed: " + $issuesFixed) }