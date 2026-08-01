$outJson = "C:\AIS\AI\Prod\temp\pb_graph.json"
$pbDir = "C:\AIS\AI\Prod\PB_Current"

# ===== 1. Extract all PB metadata with inheritance & usage =====
Write-Host "Scanning PB..."
$libs = Get-ChildItem $pbDir -Directory | Sort-Object Name
$allObjects = @{}  # name -> full info
$windows = @()     # .srw list
$ancGraph = @{}    # ancestor -> [descendants]
$usage = @{}       # object -> [windows that use it]

foreach ($lib in $libs) {
    $files = Get-ChildItem $lib.FullName -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $ext = $f.Extension.ToLower()
        $text = ""
        try { $sr = New-Object System.IO.StreamReader($f.FullName, [Text.Encoding]::GetEncoding(1251), $true); $text = $sr.ReadToEnd(); $sr.Close() } catch { continue }
        if (-not $text) { continue }
        
        $ancestor = ""
        $title = ""
        $controls = @()
        $functions = @()
        $sqlRefs = @()
        
        # Object type from extension
        $typeMap = @{'.sru'='UserObject';'.srw'='Window';'.srd'='DataWindow';'.srf'='Function';'.srp'='Proxy';'.srs'='Structure';'.srm'='Menu';'.srj'='Application'}
        $objType = if ($typeMap.ContainsKey($ext)) { $typeMap[$ext] } else { $ext }
        
        # Ancestor: global type X from Y
        if ($text -match 'global\s+type\s+(\w+)\s+from\s+(\w+)') {
            $ancestor = $matches[2]
            if (-not $ancGraph.ContainsKey($ancestor)) { $ancGraph[$ancestor] = @() }
            $ancGraph[$ancestor] += $name
        }
        
        # Window title
        if ($text -match 'string\s+title\s*=\s*"([^"]*)"') { $title = $matches[1] }
        
        # Controls
        $fwMatch = [regex]::Match($text, 'forward\s*([\s\S]*?)end\s+forward', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($fwMatch.Success) {
            $ctrlMatches = [regex]::Matches($fwMatch.Groups[1].Value, 'type\s+(\w+)\s+from\s+(\w+)\s+within\s+(\w+)')
            foreach ($cm in $ctrlMatches) {
                $ctrlName = $cm.Groups[1].Value
                $ctrlType = $cm.Groups[2].Value
                $controls += @{Name=$ctrlName; Type=$ctrlType}
                # Track usage: this window uses ctrlType
                if ($objType -eq 'Window' -or $objType -eq 'UserObject') {
                    if (-not $usage.ContainsKey($ctrlType)) { $usage[$ctrlType] = @() }
                    $usage[$ctrlType] += "$name($objType)"
                }
            }
        }
        
        # Functions
        $fnMatches = [regex]::Matches($text, '(?:public|private|protected)\s+(function|subroutine)\s+(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($fm in $fnMatches) { $functions += $fm.Groups[2].Value }
        
        # SQL references from embedded SQL
        $sqlMatch = [regex]::Matches($text, '(?:FROM|JOIN|INTO)\s+(\w+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $seenSql = @{}
        foreach ($sm in $sqlMatch) {
            $tbl = $sm.Groups[1].Value.ToLower()
            if ($tbl -notmatch '^(select|set|where|and|or|values|null|not|top|distinct|exists|case|when|then|else|end|begin|declare|varchar|int|numeric|datetime|char|float|dual)$') {
                if (-not $seenSql.ContainsKey($tbl)) { $sqlRefs += $tbl; $seenSql[$tbl] = $true }
            }
        }
        
        $allObjects[$name] = @{
            Name = $name
            Type = $objType
            Library = $lib.Name
            Ancestor = $ancestor
            Title = $title
            Controls = $controls
            Functions = $functions
            SqlRefs = $sqlRefs
        }
        
        if ($objType -eq 'Window') { $windows += $name }
    }
}

# ===== 2. Derive purposes =====
Write-Host "Deriving purposes..."
foreach ($name in $allObjects.Keys) {
    $obj = $allObjects[$name]
    $purpose = ""
    
    if ($obj.Type -eq 'Window' -and $obj.Title) {
        # Window purpose = its Title
        $purpose = "Окно: $($obj.Title)"
    }
    elseif ($obj.Type -eq 'Window') {
        # Window without title - derive from name
        if ($name -like 'w_report*') { $purpose = "Окно работы с отчётами" }
        elseif ($name -like 'w_entity*') { $purpose = "Окно карточки юрлица" }
        elseif ($name -like 'w_commission*') { $purpose = "Окно комиссии" }
        elseif ($name -like 'w_generate*') { $purpose = "Окно генерации" }
        elseif ($name -like 'w_bill*') { $purpose = "Окно счетов" }
        elseif ($name -like 'w_master*') { $purpose = "Мастер-окно (базовый класс)" }
        else { $purpose = "Окно $name" }
    }
    elseif ($obj.Type -eq 'UserObject') {
        # UserObject - used by windows
        if ($usage.ContainsKey($name)) {
            $users = ($usage[$name] | Select-Object -First 3) -join ', '
            $purpose = "Используется в: $users"
        }
        if ($name -like 'u_tabpg*') { $purpose = "Базовая вкладка (используется в: $($usage[$name] -join ', '))" }
        elseif ($name -like 'u_dw*') { $purpose = "Базовый DataWindow-контрол" }
        elseif ($name -like 'u_report*') { $purpose = "Компонент списка отчётов" }
        elseif ($name -like 'u_entity*') { $purpose = "Компонент карточки юрлица" }
        elseif ($name -like 'nvo_*') { $purpose = "Non-visual object (бизнес-логика)" }
        elseif ($name -like 'n_cst*') { $purpose = "Базовый NVO с константами" }
        if (-not $purpose) { $purpose = "UserObject: $name" }
    }
    elseif ($obj.Type -eq 'DataWindow') {
        if ($usage.ContainsKey($name)) {
            $users = ($usage[$name] | Select-Object -First 3) -join ', '
            $purpose = "DataWindow. Используется в: $users"
        }
        if ($name -like 'dddw_*') { $purpose = "Выпадающий список (DDDW)" }
        elseif ($name -like 'd_report*') { $purpose = "DataWindow отчётов" }
        elseif ($name -like 'd_commission*') { $purpose = "DataWindow комиссии" }
        elseif ($name -like 'd_entity*') { $purpose = "DataWindow юрлиц" }
        if (-not $purpose) { $purpose = "DataWindow: $name" }
    }
    elseif ($obj.Type -eq 'Function') { $purpose = "Глобальная функция" }
    elseif ($obj.Type -eq 'Menu') { $purpose = "Меню" }
    elseif ($obj.Type -eq 'Structure') { $purpose = "Структура данных" }
    elseif ($obj.Type -eq 'Proxy') { $purpose = "Прокси (веб-сервис)" }
    elseif ($obj.Type -eq 'Application') { $purpose = "Приложение" }
    
    $obj.Purpose = $purpose
}

# ===== 3. Build descendant lists =====
Write-Host "Building descendant lists..."
foreach ($name in $allObjects.Keys) {
    $desc = if ($ancGraph.ContainsKey($name)) { $ancGraph[$name] } else { @() }
    $allObjects[$name].Descendants = $desc
    $allObjects[$name].DescendantCount = $desc.Count
}

# ===== 4. Build ancestor chain =====
Write-Host "Building ancestor chains..."
foreach ($name in $allObjects.Keys) {
    $chain = @()
    $current = $allObjects[$name].Ancestor
    $depth = 0
    while ($current -and $depth -lt 10) {
        $chain += $current
        if ($allObjects.ContainsKey($current)) {
            $current = $allObjects[$current].Ancestor
        } else { break }
        $depth++
    }
    $allObjects[$name].AncestorChain = $chain
    $allObjects[$name].AncestorDepth = $chain.Count
}

# ===== 5. Build usage count =====
foreach ($name in $allObjects.Keys) {
    $allObjects[$name].UsedBy = if ($usage.ContainsKey($name)) { $usage[$name] } else { @() }
    $allObjects[$name].UsedByCount = $allObjects[$name].UsedBy.Count
}

# ===== Save =====
$output = @{
    total = $allObjects.Count
    windows = $windows
    objects = $allObjects
    ancestorGraph = $ancGraph
    usageGraph = $usage
    topAncestors = ($ancGraph.GetEnumerator() | Sort-Object { -$_.Value.Count } | Select-Object -First 20 | ForEach-Object { @{ Name=$_.Key; Descendants=$_.Value; Count=$_.Value.Count } })
    topUsed = ($usage.GetEnumerator() | Sort-Object { -$_.Value.Count } | Select-Object -First 20 | ForEach-Object { @{ Name=$_.Key; UsedBy=$_.Value; Count=$_.Value.Count } })
}

$json = $output | ConvertTo-Json -Depth 4 -Compress
[System.IO.File]::WriteAllText($outJson, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Saved: $outJson ($([math]::Round($json.Length/1024,1)) KB)"
Write-Host "Objects: $($allObjects.Count)"
Write-Host "Top ancestors:"
$output.topAncestors | ForEach-Object { Write-Host ("  $($_.Name): $($_.Count) descendants") }
Write-Host "Top used objects:"
$output.topUsed | ForEach-Object { Write-Host ("  $($_.Name): used by $($_.Count)") }
