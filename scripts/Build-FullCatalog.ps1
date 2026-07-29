$outHtml = "C:\AIS\AI\Prod\docs\AIS-полный-каталог.html"
$outPdf  = "C:\AIS\AI\Prod\docs\AIS-полный-каталог.pdf"

function Enc($s) {
    if (-not $s) { return "" }
    $t = $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
    if ($t.Length -gt 250) { $t = $t.Substring(0, 250) + "..." }
    return $t
}

function Read-Purpose($filePath) {
    if (-not (Test-Path $filePath)) { return "" }
    $lines = Get-Content $filePath -TotalCount 20 -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { return "" }
    $comments = @()
    foreach ($l in $lines) {
        $t = $l.Trim()
        if ($t -match '^/\*|^--|^\*') {
            $c = $t -replace '^/\*+','' -replace '\*+/$','' -replace '^--\s*','' -replace '^\*\s*','' -replace '^\*',''
            $c = $c.Trim()
            if ($c.Length -gt 3 -and $c -notmatch '^(CREATE|SET|go\b|Name:)') {
                $comments += $c
            }
        }
        if ($t -match '^CREATE\s+(PROC|FUNC|TRIG|TABLE|VIEW)') { break }
    }
    $result = ($comments -join "; ").Trim()
    if ($result.Length -gt 300) { $result = $result.Substring(0, 300) }
    return $result
}

function Get-SqlPurpose($name, $type) {
    $p = ""
    $dir = ""
    if ($type -eq 'Procedure') { $dir = "C:\AIS\AI\Prod\BD\dev_golden\golden\Procedure" }
    elseif ($type -eq 'Functions') { $dir = "C:\AIS\AI\Prod\BD\dev_golden\golden\Functions" }
    elseif ($type -eq 'Triggers') { $dir = "C:\AIS\AI\Prod\BD\dev_golden\golden\Triggers" }
    elseif ($type -eq 'Views') { $dir = "C:\AIS\AI\Prod\BD\dev_golden\golden\Views" }
    if ($dir) { $p = Read-Purpose (Join-Path $dir "$name.sql") }
    if (-not $p) {
        if ($name -like 'usp_add_*') { $p = "Dobavlenie dannykh v sistemu" }
        elseif ($name -like 'usp_agent_*') { $p = "Agentskaya deyatelnost" }
        elseif ($name -like 'usp_ais_*') { $p = "Yadro AIS" }
        elseif ($name -like 'usp_bill_*') { $p = "Scheta i billing" }
        elseif ($name -like 'usp_boss_*') { $p = "Integratsiya BOSS" }
        elseif ($name -like 'usp_broker_*') { $p = "Brokerskaya komissiya" }
        elseif ($name -like 'usp_check_*') { $p = "Proverki i validatsiya" }
        elseif ($name -like 'usp_com_*' -or $name -like 'usp_commission_*') { $p = "Rabota s komissiei" }
        elseif ($name -like 'usp_correct_*') { $p = "Korrektirovka dannykh" }
        elseif ($name -like 'usp_create_*') { $p = "Sozdanie ob'ektov" }
        elseif ($name -like 'usp_curator_*') { $p = "Kuratorskaya nagruzka" }
        elseif ($name -like 'usp_dover_*') { $p = "Doverennosti" }
        elseif ($name -like 'usp_ecp_*') { $p = "Elektronnaya podpis" }
        elseif ($name -like 'usp_entity_*') { $p = "Yuridicheskie litsa" }
        elseif ($name -like 'usp_fill_*') { $p = "Zapolnenie dannykh" }
        elseif ($name -like 'usp_find_*') { $p = "Poisk i podbor" }
        elseif ($name -like 'usp_generate_*') { $p = "Generatsiya otchetov" }
        elseif ($name -like 'usp_get_*') { $p = "Poluchenie dannykh" }
        elseif ($name -like 'usp_ins_*') { $p = "Vstavka dannykh" }
        elseif ($name -like 'usp_load_*') { $p = "Zagruzka dannykh" }
        elseif ($name -like 'usp_onec_*') { $p = "Integratsiya 1S" }
        elseif ($name -like 'usp_oss_*') { $p = "Integratsiya OSS" }
        elseif ($name -like 'usp_partner_*') { $p = "Partnery" }
        elseif ($name -like 'usp_policy_*') { $p = "Polisy" }
        elseif ($name -like 'usp_report_*') { $p = "Otchety" }
        elseif ($name -like 'usp_sale_*') { $p = "Prodazhi" }
        elseif ($name -like 'usp_sel_*') { $p = "Vyborka dannykh" }
        elseif ($name -like 'usp_send_*') { $p = "Otpravka dannykh" }
        elseif ($name -like 'usp_siebel_*') { $p = "Integratsiya Siebel" }
        elseif ($name -like 'usp_sync_*') { $p = "Sinkhronizatsiya" }
        elseif ($name -like 'usp_transfer_*') { $p = "Perenos dannykh" }
        elseif ($name -like 'usp_update_*') { $p = "Obnovlenie dannykh" }
        elseif ($name -like 'usp_write_*') { $p = "Zapis dannykh" }
        elseif ($name -like 'usp_*') { $p = "Protsedura AIS" }
        elseif ($name -like 'web_act_*') { $p = "Veb-akty/otchety" }
        elseif ($name -like 'web_agent_*') { $p = "Veb-agenty" }
        elseif ($name -like 'web_bill_*') { $p = "Veb-scheta" }
        elseif ($name -like 'web_GetAISEntity*') { $p = "Veb-poluchenie yurlitsa (B2B/IRIS)" }
        elseif ($name -like 'web_GetEntity*') { $p = "Veb-informatsiya o yurlitse" }
        elseif ($name -like 'web_middleman_*') { $p = "Veb-posredniki" }
        elseif ($name -like 'web_*') { $p = "Veb-interfeis" }
        elseif ($name -like 'z_usp_*') { $p = "Finalnaya versiya protsedury" }
        elseif ($name -like 'fn_*') { $p = "Vspomogatelnaya funktsiya" }
        elseif ($name -like 'td_*') { $p = "Trigger pri izmenenii dannykh" }
        elseif ($name -like 'v_*') { $p = "Predstavlenie" }
        else { $p = "" }
    }
    return $p
}

# ===== HTML HEAD =====
$h = @'
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><title>AIS - Polnii katalog</title>
<style>
body{font-family:Segoe UI,Arial;max-width:1200px;margin:0 auto;padding:15px;background:#f5f7fa;color:#333}
h1{color:#6B2D8B;border-bottom:3px solid #3182CE;padding-bottom:10px;font-size:20px}
h2{color:#3182CE;border-bottom:1px solid #ddd;padding-bottom:5px;margin-top:30px;font-size:16px}
h3{color:#4A5568;margin-top:22px;font-size:14px}
h4{color:#555;margin-top:16px;font-size:13px}
table{border-collapse:collapse;width:100%;margin:6px 0;font-size:11px}
th,td{border:1px solid #ddd;padding:3px 6px;text-align:left;vertical-align:top}
th{background:#3182CE;color:white;font-size:11px}
tr:nth-child(even){background:#f9f9f9}
code{background:#e9ecef;padding:1px 3px;border-radius:2px;font-size:10px}
.toc{background:white;border:1px solid #ddd;padding:12px 20px;border-radius:6px;margin:15px 0}
.toc a{text-decoration:none;color:#3182CE}.toc ol{padding-left:18px}
.n{color:#888;font-size:9px}
.fld-table{margin:4px 0 4px 10px;width:95%}
.fld-table th{background:#6B2D8B;font-size:10px}
.fld-table td{font-size:10px}
@media print{body{font-size:9px}h1{font-size:14px}h2{font-size:12px}table{font-size:8px}}
</style></head><body>
<h1>Polnii katalog objektov AIS</h1>
<p>Obekty SQL i PowerBuilder, uchastvuyushchie v proekte AIS. Iyul 2026.</p>
<div class="toc"><h3>Soderzhanie</h3><ol>
<li><a href="#sql">SQL-obekty</a></li>
<li><a href="#tables">Tablitsy top-50</a></li>
<li><a href="#pb">PowerBuilder-obekty</a></li>
</ol></div>
'@

# ===== LOAD DATA =====
Write-Host "Loading JSON data..."
$sqlAll = Get-Content "C:\AIS\AI\Prod\temp\sql_all_metadata.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$sruJ   = Get-Content "C:\AIS\AI\Prod\temp\pb_sru_metadata.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$srwJ   = Get-Content "C:\AIS\AI\Prod\temp\pb_srw_metadata.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$restJ  = Get-Content "C:\AIS\AI\Prod\temp\pb_rest_metadata.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "Data loaded. Processing..."

# ===== BUILD PB SQL REFERENCE SET =====
$pbSqlRefs = @{}
foreach ($lib in $sruJ.objects.Keys) {
    foreach ($o in $sruJ.objects.$lib) {
        if ($o.SqlTables) {
            foreach ($tbl in ($o.SqlTables -split ', ')) {
                $tc = $tbl.Trim()
                if ($tc.Length -gt 1) {
                    if (-not $pbSqlRefs.ContainsKey($tc)) { $pbSqlRefs[$tc] = @() }
                    $pbSqlRefs[$tc] += "$($o.Name).sru"
                }
            }
        }
    }
}
foreach ($lib in $restJ.objects.Keys) {
    foreach ($o in $restJ.objects.$lib) {
        if ($o.Type -eq 'DataWindow' -and $o.Sql) {
            foreach ($tbl in ($o.Sql -split ', ')) {
                $tc = $tbl.Trim() -replace ' proc:.*',''
                if ($tc.Length -gt 1 -and $tc -notmatch '^\d|^proc:') {
                    if (-not $pbSqlRefs.ContainsKey($tc)) { $pbSqlRefs[$tc] = @() }
                    $pbSqlRefs[$tc] += "$($o.Name).srd"
                }
            }
        }
    }
}
Write-Host "PB SQL refs: $($pbSqlRefs.Count) tables"

# ===== SECTION 1: SQL =====
$h += "<h2 id='sql'>1. SQL-obekty AIS</h2>"
$h += "<p>Vklyucheny obekty, ispolzuemye v PB (ssylki iz .sru/.srd), isklyuchaya sistemnye i vremennye.</p>"

$sqlTypes = @('Procedure','Functions','Triggers','Views')
$typeLabel = @{Procedure='Protsedury'; Functions='Funktsii'; Triggers='Triggery'; Views='Predstavleniya'}
$excludeNames = @('_tmp_unload_address','aaa','aaaaaa','ADM_update_stats','blurb_blob_breaker',
    'o_info_proc','prc_procedure_new','prc_procedure_text','sonic_add_message',
    'limit_user_sessions','limit_user_sessions_16','limit_user_sessions_cdp',
    'limit_user_sessions_commgen','limit_user_sessions_host_riga',
    'ttt','ttt_middleman_policy_async','test_chaga')
$totalShown = 0

foreach ($type in $sqlTypes) {
    $all = $sqlAll.objects.$type | Where-Object {
        $n = $_.Name
        if ($n -like 'rs_*' -or $n -like 'tmp_*' -or $n -like 'temp_*' -or $n -like 'tmP_*') { return $false }
        if ($n -like 'limit_user*' -or $n -like 'prc_procedure*') { return $false }
        if ($n -in $excludeNames) { return $false }
        return ($pbSqlRefs.ContainsKey($n) -or $type -in @('Functions','Triggers'))
    }
    if (@($all).Count -eq 0) { continue }
    $label = $typeLabel[$type]
    $h += "<h3>$label ($(@($all).Count))</h3>"
    $h += "<table><tr><th>Imya</th><th>Naznachenie</th><th>Parametry</th><th>Tablitsy</th><th>Ispolzuetsya v PB</th></tr>"
    foreach ($o in $all | Sort-Object Name) {
        $purp = Enc (Get-SqlPurpose $o.Name $type)
        $p = Enc($o.Params)
        $t = Enc($o.Tables)
        $pbUse = ""
        if ($pbSqlRefs.ContainsKey($o.Name)) {
            $pbUse = ($pbSqlRefs[$o.Name] | Select-Object -First 4) -join ', '
        }
        $h += "<tr><td><code>$($o.Name)</code></td><td>$purp</td><td>$p</td><td>$t</td><td><span class='n'>$pbUse</span></td></tr>"
        $totalShown++
    }
    $h += "</table>"
}

Write-Host "SQL objects shown: $totalShown"

# ===== SECTION 2: TOP 50 TABLES =====
$h += "<h2 id='tables'>2. Tablitsy - top-50 s opisaniem polei</h2>"

$tblFreq = @{}
foreach ($type in $sqlTypes) {
    foreach ($o in $sqlAll.objects.$type) {
        if ($o.Tables) {
            foreach ($tbl in ($o.Tables -split ', ')) {
                $tc = $tbl.Trim()
                if ($tc.Length -gt 1 -and $tc -notmatch '^\d|^(select|set|where|and|or|values|null|not|top|distinct)$') {
                    if (-not $tblFreq.ContainsKey($tc)) { $tblFreq[$tc] = @{ Count=0; Procs=@{} } }
                    $tblFreq[$tc].Count++
                    $tblFreq[$tc].Procs[$o.Name] = $true
                }
            }
        }
    }
}
foreach ($k in $pbSqlRefs.Keys) {
    if (-not $tblFreq.ContainsKey($k)) { $tblFreq[$k] = @{ Count=0; Procs=@{} } }
    $tblFreq[$k].Count += $pbSqlRefs[$k].Count
}

$top50 = $tblFreq.GetEnumerator() | Sort-Object { -$_.Value.Count } | Select-Object -First 50
$rank = 0

foreach ($t in $top50) {
    $rank++
    $tblName = $t.Key
    $procsList = ($t.Value.Procs.Keys | Select-Object -First 5) -join ', '
    
    $h += "<h4>$rank. <code>$tblName</code> ($($t.Value.Count) ssylok)</h4>"
    $h += "<p class='n'>Ispolzuetsya v: $procsList</p>"
    
    $tblFile = "C:\AIS\AI\Prod\BD\dev_golden\golden\Tables\$tblName.sql"
    if (Test-Path $tblFile) {
        $ddl = Get-Content $tblFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($ddl) {
            $h += "<table class='fld-table'><tr><th>Pole</th><th>Tip</th><th>Naznachenie</th></tr>"
            $lines = $ddl -split "`r`n"
            $inTable = $false
            $fcount = 0
            foreach ($l in $lines) {
                $lt = $l.Trim()
                if ($lt -match '^CREATE\s+TABLE') { $inTable = $true; continue }
                if (-not $inTable) { continue }
                if ($lt -match '^\)\s*$' -or $lt -match '^\s*\)') { break }
                if ($lt -match '^\s*,?\s*(\w+)\s+([\w\s\(\),\d]+?)\s+(NOT\s+NULL|NULL|IDENTITY)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) {
                    $fName = $matches[1]
                    $fType = ($matches[2] -replace '\s+',' ').Trim()
                    $fNull = $matches[3]
                    if ($fName -eq 'CONSTRAINT' -or $fName -match '^(PRIMARY|FOREIGN|UNIQUE|CHECK)$') { continue }
                    $fPurp = ""
                    if ($fName -match '_id$' -and $fName -ne 'id') { $fPurp = "Vneshnii klyuch" }
                    elseif ($fName -match '^date_|^datetime') { $fPurp = "Data/vremya" }
                    elseif ($fName -match '^is_|^flag_|^blocked') { $fPurp = "Priznak (0/1)" }
                    elseif ($fName -match '^num_|^number|^code') { $fPurp = "Nomer/kod" }
                    elseif ($fName -match '^sum|^amount|^percent|^premium') { $fPurp = "Summa/protsent" }
                    elseif ($fName -match '^name|^title|^info|^comment') { $fPurp = "Tekst" }
                    elseif ($fName -match '^state|^status') { $fPurp = "Status" }
                    elseif ($fName -match '^system$') { $fPurp = "Sistema-istochnik" }
                    elseif ($fName -match '^insure') { $fPurp = "Vid strakhovaniya" }
                    elseif ($fName -match '^subj_id') { $fPurp = "Subekt" }
                    elseif ($fName -match '^entity_id') { $fPurp = "Yurlitso" }
                    elseif ($fName -match '^register|^create_|^last_') { $fPurp = "Data registratsii" }
                    $h += "<tr><td><code>$fName</code></td><td>$fType</td><td>$fPurp</td></tr>"
                    $fcount++
                }
            }
            if ($fcount -eq 0) { $h += "<tr><td colspan='3' class='n'>Polei ne naideno</td></tr>" }
            $h += "</table>"
        }
    }
}

# ===== SECTION 3: PB =====
$h += "<h2 id='pb'>3. PowerBuilder-obekty</h2>"

# ancestor->descendant
$ancDesc = @{}
foreach ($lib in $sruJ.objects.Keys) {
    foreach ($o in $sruJ.objects.$lib) {
        if ($o.Ancestor) {
            if (-not $ancDesc.ContainsKey($o.Ancestor)) { $ancDesc[$o.Ancestor] = @() }
            $ancDesc[$o.Ancestor] += "$($o.Name)"
        }
    }
}
foreach ($lib in $srwJ.objects.Keys) {
    foreach ($o in $srwJ.objects.$lib) {
        if ($o.Ancestor) {
            if (-not $ancDesc.ContainsKey($o.Ancestor)) { $ancDesc[$o.Ancestor] = @() }
            $ancDesc[$o.Ancestor] += "$($o.Name)"
        }
    }
}

function Get-PbPurpose($name, $lib) {
    if ($name -like 'dddw_*') { return "Vypadayushchii spisok (DropDown DataWindow)" }
    if ($name -like 'd_*') { return "DataWindow otobrazheniya dannykh" }
    if ($name -like 'w_*') { return "Okno interfeisa" }
    if ($name -like 'nvo_*') { return "Non-visual object - biznes-logika" }
    if ($name -like 'u_*') { return "UserObject - komponent" }
    if ($name -like 'm_*') { return "Menyu" }
    return ""
}

# .sru
$h += "<h3>3.1. UserObjects (.sru) - $($sruJ.total)</h3>"
foreach ($lib in ($sruJ.objects.Keys | Sort-Object)) {
    $objs = $sruJ.objects.$lib
    $h += "<h4>$lib ($($objs.Count))</h4><table><tr><th>Imya</th><th>Naznachenie</th><th>Predok</th><th>Potomki</th><th>Kontroly</th><th>Funktsii</th><th>SQL</th></tr>"
    foreach ($o in $objs | Sort-Object Name) {
        $purp = Get-PbPurpose $o.Name $lib
        $desc = ""
        if ($ancDesc.ContainsKey($o.Name)) {
            $desc = ($ancDesc[$o.Name] | Select-Object -First 4) -join ', '
            if ($ancDesc[$o.Name].Count -gt 4) { $desc += " +$($ancDesc[$o.Name].Count-4)" }
        }
        $h += "<tr><td><code>$($o.Name)</code></td><td>$purp</td><td>$($o.Ancestor)</td><td><span class='n'>$desc</span></td><td>$(Enc $o.Controls)</td><td>$(Enc $o.Functions)</td><td>$(Enc $o.SqlTables)</td></tr>"
    }
    $h += "</table>"
}

# .srw
$h += "<h3>3.2. Windows (.srw) - $($srwJ.total)</h3>"
foreach ($lib in ($srwJ.objects.Keys | Sort-Object)) {
    $objs = $srwJ.objects.$lib
    $h += "<h4>$lib ($($objs.Count))</h4><table><tr><th>Imya</th><th>Naznachenie</th><th>Predok</th><th>Potomki</th><th>Zagolovok</th><th>Menyu</th><th>Kontroly</th><th>Funktsii</th></tr>"
    foreach ($o in $objs | Sort-Object Name) {
        $purp = Get-PbPurpose $o.Name $lib
        $desc = ""
        if ($ancDesc.ContainsKey($o.Name)) {
            $desc = ($ancDesc[$o.Name] | Select-Object -First 3) -join ', '
            if ($ancDesc[$o.Name].Count -gt 3) { $desc += " +$($ancDesc[$o.Name].Count-3)" }
        }
        $h += "<tr><td><code>$($o.Name)</code></td><td>$purp</td><td>$($o.Ancestor)</td><td><span class='n'>$desc</span></td><td>$($o.Title)</td><td>$($o.Menu)</td><td>$(Enc $o.Controls)</td><td>$(Enc $o.Functions)</td></tr>"
    }
    $h += "</table>"
}

# .srd/.srf/.srp/.srs/.srm/.srj
$h += "<h3>3.3. DataWindow, Functions, Proxy, Structure, Menu, App ($($restJ.total))</h3>"
foreach ($lib in ($restJ.objects.Keys | Sort-Object)) {
    $objs = $restJ.objects.$lib
    $h += "<h4>$lib ($($objs.Count))</h4><table><tr><th>Imya</th><th>Tip</th><th>Naznachenie</th><th>SQL / Detali</th></tr>"
    foreach ($o in $objs | Sort-Object Name) {
        $purp = Get-PbPurpose $o.Name $lib
        $h += "<tr><td><code>$($o.Name)</code></td><td>$($o.Type)</td><td>$purp</td><td>$(Enc $o.Sql)</td></tr>"
    }
    $h += "</table>"
}

$h += "<hr><p style='text-align:center;color:#888;font-size:9px'>Sgenerirovano: 16.07.2026. Istochnik: ais-catalog.</p></body></html>"

# ===== SAVE HTML (no BOM) =====
Write-Host "Saving HTML..."
[System.IO.File]::WriteAllText($outHtml, $h, [System.Text.UTF8Encoding]::new($false))
$sz = [math]::Round((Get-Item $outHtml).Length/1024, 1)
Write-Host "HTML: $sz KB"

# ===== PDF =====
Write-Host "Generating PDF..."
$edge = @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe","C:\Program Files\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($edge) {
    & $edge --headless --disable-gpu --print-to-pdf="$outPdf" $outHtml 2>&1
    Start-Sleep -Seconds 12
    if (Test-Path $outPdf) { Write-Host ("PDF: " + [math]::Round((Get-Item $outPdf).Length/1024,1) + " KB") }
    else { Write-Host "PDF FAIL" }
} else { Write-Host "Edge not found" }
