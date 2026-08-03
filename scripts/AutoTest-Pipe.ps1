# File-тест ObjectInfo — команды через %TEMP%\objinfo_cmd.txt
$CMD = "$env:TEMP\objinfo_cmd.txt"
$RESP = "$env:TEMP\objinfo_resp.txt"

Write-Host "=== File Test ObjectInfo ==="
Remove-Item $CMD,$RESP -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Show-ObjectInfo" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$proc = Start-Process "C:\AIS\AI\Prod\bin\Show-ObjectInfo.exe" -PassThru
Start-Sleep -Seconds 4

function Send($c){
    Set-Content $CMD -Value $c -Encoding UTF8
    for($i=0;$i -lt 20;$i++){
        Start-Sleep -Milliseconds 300
        if(Test-Path $RESP){$r=Get-Content $RESP -Raw -Encoding UTF8;Remove-Item $RESP -EA SilentlyContinue;return $r.Trim()}
    }
    return "TIMEOUT"
}

$ok=0;$fail=0
function T($n,$chk){
    $r = Send $n
    $isOK = $false
    if($chk -is [scriptblock]){$isOK = (& $chk $r)}else{$isOK = ($r -eq $chk)}
    if($isOK){$script:ok++;Write-Host "  [OK] $n => $r"}else{$script:fail++;Write-Host "  [FAIL] $n => $r"}
}

T "ping" "pong"
T "sel_pb 93" "ok"
for($w=0;$w -lt 10;$w++){
    $st = Send "st_pb"
    if($st -match '^\d+,\d+$' -and $st -ne "0,0"){break}
    Start-Sleep -Milliseconds 500
}
T "st_pb" {param($r)$r -match '^\d+,\d+$' -and $r -ne "0,0"}
T "sel_sql 0" "ok"
for($w=0;$w -lt 10;$w++){
    $st = Send "st_sql"
    if($st -match '^\d+,\d+$' -and $st -ne "0,0"){break}
    Start-Sleep -Milliseconds 500
}
T "st_sql" {param($r)$r -match '^\d+,\d+$' -and $r -ne "0,0"}
T "close" "ok"
Start-Sleep -Seconds 2
if(-not $proc.HasExited){$proc.Kill()}

Write-Host "`n=== $fail/$($ok+$fail) FAILED ==="
if($fail -gt 0){Write-Host "FAILED";exit 1}else{Write-Host "PASSED";exit 0}
