param(
    [switch]$Silent
)

function Remove-Bom {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $newBytes = $bytes[3..($bytes.Length - 1)]
            [System.IO.File]::WriteAllBytes($Path, $newBytes)
            if (-not $Silent) { Write-Host "BOM removed: $Path" }
            return $true
        }
    } catch {}
    return $false
}

$count = 0
$configs = @(
    "$env:USERPROFILE\.config\opencode\opencode.jsonc"
    "C:\AIS\AI\Prod\opencode.jsonc"
    "C:\AIS\AI\Prod\config\config.json"
)

foreach ($cfg in $configs) {
    if (Remove-Bom -Path $cfg) { $count++ }
}

if (-not $Silent) {
    if ($count -gt 0) { Write-Host "Удалено BOM: $count" } else { Write-Host "BOM не найдены" }
}
