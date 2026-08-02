<#
.SYNOPSIS
    Сборка тела объекта SQL из hex-фрагментов isql.
.DESCRIPTION
    Читает файл с выводом isql: строки вида "0xHEX  num  colid".
    Собирает байты по (number,colid) → CP1251 тело.
    Сохраняет в CP1251 (без конвертации в UTF-8 — это делает Convert-ExportEncoding.ps1 позже).
.PARAMETER Frags
    Путь к файлу с hex-фрагментами (вывод isql).
.PARAMETER Out
    Путь к выходному файлу с телом объекта.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Frags,
    [Parameter(Mandatory=$true)]
    [string]$Out
)

if (-not (Test-Path -LiteralPath $Frags)) {
    Write-Host "ERROR: File not found: $Frags"
    exit 1
}

$bytes = [System.IO.File]::ReadAllBytes($Frags)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$raw = $latin1.GetString($bytes)

$pattern = '0x([0-9a-fA-F]+)\s+(\d+)\s+(\d+)'
$matches = [regex]::Matches($raw, $pattern)

if ($matches.Count -eq 0) {
    Write-Host "ERROR: No hex fragments found in $Frags"
    exit 2
}

$items = @()
foreach ($m in $matches) {
    $items += [PSCustomObject]@{
        Number = [int]$m.Groups[2].Value
        Colid  = [int]$m.Groups[3].Value
        Hex    = $m.Groups[1].Value
    }
}

$sorted = $items | Sort-Object Number, Colid

$sb = New-Object System.Text.StringBuilder
foreach ($it in $sorted) {
    [void]$sb.Append($it.Hex)
}

$hexStr = $sb.ToString()
$bodyLen = $hexStr.Length / 2
if ($hexStr.Length % 2 -ne 0) {
    Write-Host "WARNING: odd hex length"
}
$body = New-Object byte[] $bodyLen
for ($i = 0; $i -lt $body.Length; $i++) {
    $body[$i] = [Convert]::ToByte($hexStr.Substring($i * 2, 2), 16)
}

if ($body.Length -lt 1 -or ($body[$body.Length - 1] -ne 10 -and $body[$body.Length - 1] -ne 13)) {
    $body += @(13, 10)
}

[System.IO.File]::WriteAllBytes($Out, $body)
Write-Host ('Rebuild: {0} frags, {1} bytes -> {2}' -f $matches.Count, $body.Length, $Out)
exit 0
