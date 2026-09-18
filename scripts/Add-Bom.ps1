param(
    [Parameter(Position=0)]
    [string]$Path = '',
    [switch]$Recurse
)

$ErrorActionPreference = 'Stop'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8Plain = New-Object System.Text.UTF8Encoding($false)
$files = @()

if ($Path -ne '') {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host ('FILE_NOT_FOUND: ' + $Path)
        exit 1
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        $files = @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.ps1' -File -Recurse:$Recurse)
    } else {
        $files = @($item)
    }
} else {
    $files = @(Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot -Parent) -Filter '*.ps1' -File -Recurse:$Recurse)
}

$changed = 0
foreach ($file in $files) {
    if ($file.Extension -ne '.ps1') { continue }
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBom) {
        $text = [System.IO.File]::ReadAllText($file.FullName, $utf8Plain)
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8Bom)
        $changed++
        Write-Host ('BOM_ADDED: ' + $file.Name)
    }
}

Write-Host ('DONE: ' + $changed)
exit 0
