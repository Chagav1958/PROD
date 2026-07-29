$file = "C:\AIS\AI\Prod\scripts\Build-ObjectCatalog.ps1"
$c = Get-Content $file -Raw -Encoding UTF8
$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($file, $c, $enc)
$b = [System.IO.File]::ReadAllBytes($file)[0..2] -join ','
Write-Host ("BOM bytes: " + $b)
