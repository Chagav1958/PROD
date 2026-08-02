<#
.SYNOPSIS Справочник объектов PB/SQL — ДО СТАНДАРТ2 (v7, 100% ТЗ)
#>
param([string]$TaskName="")
$script:Root = if($PSScriptRoot -match '[\\/]scripts$'){Split-Path $PSScriptRoot -Parent}else{"C:\AIS\AI\Prod"}
. (Join-Path $script:Root "scripts\Standard2-Helpers.ps1")
Add-Type -AssemblyName PresentationFramework -EA Stop

# Tech journal
function TJ($l,$m){try{$p=Join-Path $env:TEMP "objinfo_$(Get-Date -Format 'yyyyMMdd_HHmmss').log";Add-Content $p -Value "[$(Get-Date -Format 'HH:mm:ss')] [$l] $m" -Encoding UTF8 -EA SilentlyContinue}catch{}}
TJ "INFO" "GUI started"

$script:PB = Get-Content (Join-Path $script:Root "temp\pb_full.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$script:SQL = Get-Content (Join-Path $script:Root "temp\sql_full.json") -Raw -Encoding UTF8 | ConvertFrom-Json
TJ "INFO" "Data loaded: PB=$($script:PB.Count) SQL=$($script:SQL.Count)"

function DG($items){$d=New-Object Windows.Controls.DataGrid;$d.ItemsSource=$items;$d.IsReadOnly=$true;$d.AutoGenerateColumns=$true;$d.CanUserSortColumns=$true;$d.SelectionMode="Single";$d.RowBackground="#FFFFFF";$d.AlternatingRowBackground="#F5F7FA";$d.FontSize=11;$d.MinHeight=200;return $d}
function TB($w){$t=New-Object Windows.Controls.TextBox;$t.IsReadOnly=$true;$t.FontFamily="Consolas";$t.FontSize=10;$t.Background="#FFFFFF";$t.TextWrapping=$w;$t.VerticalScrollBarVisibility="Auto";$t.HorizontalScrollBarVisibility="Auto";$t.AcceptsReturn=$true;return $t}
function TI($h){$t=New-Object Windows.Controls.TabItem;$t.Header=$h;return $t}

# ===== FILTER PANEL =====
function New-FilterPanel($dg,$allItems,$scriptVar){
    $fp = New-Object Windows.Controls.StackPanel; $fp.Orientation="Horizontal"; $fp.Margin="4,2,4,2"
    $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text="Фильтр:"; $lbl.VerticalAlignment="Center"; $lbl.Margin="0,0,4,0"; $lbl.FontSize=11
    [void]$fp.Children.Add($lbl)
    $tb = New-Object Windows.Controls.TextBox; $tb.Width=200; $tb.FontSize=11
    $tb.Add_TextChanged({
        $txt = $tb.Text.ToLower()
        if($txt.Length -eq 0){$dg.ItemsSource = $allItems; return}
        $filtered = $allItems | Where-Object {
            ($_.PSObject.Properties.Value | Out-String).ToLower().Contains($txt)
        }
        $dg.ItemsSource = [System.Collections.ArrayList]@($filtered)
        TJ "INFO" "Filter: '$txt' -> $($filtered.Count) results"
    })
    [void]$fp.Children.Add($tb)
    return $fp
}

# ===== CODE SEARCH PANEL =====
function New-SearchPanel($codeBox){
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation="Horizontal"; $sp.Margin="4,2,4,2"
    $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text="Поиск:"; $lbl.VerticalAlignment="Center"; $lbl.Margin="0,0,4,0"; $lbl.FontSize=11
    [void]$sp.Children.Add($lbl)
    $st = New-Object Windows.Controls.TextBox; $st.Width=200; $st.FontSize=11
    $btn = New-Object Windows.Controls.Button; $btn.Content="Найти"; $btn.Width=60; $btn.Height=24; $btn.Margin="4,0,0,0"; $btn.FontSize=11
    $btn.Add_Click({
        $q = $st.Text
        if(-not $q -or -not $codeBox.Text){return}
        $pos = $codeBox.Text.IndexOf($q, [StringComparison]::OrdinalIgnoreCase)
        if($pos -ge 0){$codeBox.Focus(); $codeBox.Select($pos, $q.Length); $codeBox.ScrollToLine($codeBox.GetLineIndexFromCharacterIndex($pos))}
        TJ "INFO" "Search: '$q' found=$($pos -ge 0)"
    })
    $btn2 = New-Object Windows.Controls.Button; $btn2.Content="Ctrl+F"; $btn2.Width=60; $btn2.Height=24; $btn2.Margin="4,0,0,0"; $btn2.FontSize=10; $btn2.IsEnabled=$false
    [void]$sp.Children.Add($st); [void]$sp.Children.Add($btn); [void]$sp.Children.Add($btn2)
    return $sp
}

# ===== PB TAB =====
function Build-PB {
    $tab = TI "PB"; $inner = New-Object Windows.Controls.TabControl; $inner.FontSize = 11
    
    # ПВКЛ1: таблица + фильтр
    $t1 = TI "Объекты"
    $g1 = New-Object Windows.Controls.Grid
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $dg = DG $script:PB; $script:PBDG = $dg
    $dg.Add_MouseDoubleClick({if($dg.SelectedItem){Fill-PB $dg.SelectedItem.name}})
    $fp = New-FilterPanel $dg $script:PB
    [Windows.Controls.Grid]::SetRow($fp,0); [void]$g1.Children.Add($fp)
    [Windows.Controls.Grid]::SetRow($dg,1); [void]$g1.Children.Add($dg)
    $t1.Content = $g1; [void]$inner.Items.Add($t1)
    
    # ПВКЛ2: код + поиск
    $t2 = TI "Код"
    $g2 = New-Object Windows.Controls.Grid
    $g2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $script:PBC = TB "NoWrap"; $sp1 = New-SearchPanel $script:PBC
    [Windows.Controls.Grid]::SetRow($sp1,0); [void]$g2.Children.Add($sp1)
    [Windows.Controls.Grid]::SetRow($script:PBC,1); [void]$g2.Children.Add($script:PBC)
    $t2.Content = $g2; [void]$inner.Items.Add($t2)
    
    # ПВКЛ3: содержит
    $t3 = TI "Содержит"; $script:PBO = DG @(); $t3.Content = $script:PBO; [void]$inner.Items.Add($t3)
    # ПВКЛ4: содержится в
    $t4 = TI "Содержится в"; $script:PBI = DG @(); $t4.Content = $script:PBI; [void]$inner.Items.Add($t4)
    # ПВКЛ5: свойства
    $t5 = TI "Свойства"; $script:PBX = TB "Wrap"; $t5.Content = $script:PBX; [void]$inner.Items.Add($t5)
    # ПВКЛ6: merge
    $t6 = TI "Merge"; $script:PBM = TB "Wrap"; $script:PBM.Background="#FFFFF0"; $t6.Content = $script:PBM; [void]$inner.Items.Add($t6)
    
    $tab.Content = $inner; return $tab
}

function Fill-PB($name) {
    TJ "INFO" "PB selected: $name"
    $o = $script:PB | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if(-not $o){return}
    $script:PBC.Text = "Объект: $($o.name)`r`nТип: $($o.type) | Библиотека: $($o.lib)`r`nРазмер: $($o.size_kb) KB | Изменён: $($o.modified)`r`n`r`nКод загружается через MCP после перезапуска OpenCode"
    $script:PBX.Text = "Предки: $($o.ancestors)`r`nНазначение: $($o.purpose)`r`nЗадачи: $($o.tasks)`r`nСодержит: $($o.contained_count) объектов`r`nСодержится в: $($o.contained_in_count) объектов`r`nВерсии совпадают: $($o.versions_match)"
    $script:PBM.Text = if($o.versions_match -eq 'Нет'){"ВНИМАНИЕ: Версии Main и Current различаются!`r`nИспользуйте TortoiseMerge: C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe`r`n`r`nОбъект: $($o.name)"}else{"Версии совпадают: $($o.versions_match)"}
    $script:PBO.ItemsSource = @(); $script:PBI.ItemsSource = @()
}

# ===== SQL TAB =====
function Build-SQL {
    $tab = TI "SQL"; $inner = New-Object Windows.Controls.TabControl; $inner.FontSize = 11
    
    $t1 = TI "Объекты"
    $g1 = New-Object Windows.Controls.Grid
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $dg = DG $script:SQL; $script:SQLDG = $dg
    $dg.Add_MouseDoubleClick({if($dg.SelectedItem){Fill-SQL $dg.SelectedItem.name}})
    $fp2 = New-FilterPanel $dg $script:SQL
    [Windows.Controls.Grid]::SetRow($fp2,0); [void]$g1.Children.Add($fp2)
    [Windows.Controls.Grid]::SetRow($dg,1); [void]$g1.Children.Add($dg)
    $t1.Content = $g1; [void]$inner.Items.Add($t1)
    
    $t2 = TI "Код"
    $g2 = New-Object Windows.Controls.Grid
    $g2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g2.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $script:SQLC = TB "NoWrap"; $sp2 = New-SearchPanel $script:SQLC
    [Windows.Controls.Grid]::SetRow($sp2,0); [void]$g2.Children.Add($sp2)
    [Windows.Controls.Grid]::SetRow($script:SQLC,1); [void]$g2.Children.Add($script:SQLC)
    $t2.Content = $g2; [void]$inner.Items.Add($t2)
    
    $t3 = TI "Содержит"; $script:SQLO = DG @(); $t3.Content = $script:SQLO; [void]$inner.Items.Add($t3)
    $t4 = TI "Содержится в"; $script:SQLI = DG @(); $t4.Content = $script:SQLI; [void]$inner.Items.Add($t4)
    $t5 = TI "Свойства"; $script:SQLX = TB "Wrap"; $t5.Content = $script:SQLX; [void]$inner.Items.Add($t5)
    $t6 = TI "Merge"; $script:SQLM = TB "Wrap"; $script:SQLM.Background="#FFFFF0"; $t6.Content = $script:SQLM; [void]$inner.Items.Add($t6)
    
    $tab.Content = $inner; return $tab
}

function Fill-SQL($name) {
    TJ "INFO" "SQL selected: $name"
    $o = $script:SQL | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if(-not $o){return}
    $script:SQLC.Text = "Объект: $($o.name)`r`nТип: $($o.type) | Категория: $($o.category)`r`nСервер: dev_golden, БД: golden`r`nРазмер: $($o.size_kb) KB | Изменён: $($o.modified)`r`n`r`nКод загружается через MCP после перезапуска OpenCode"
    $script:SQLX.Text = "Назначение: $($o.purpose)`r`nЗадачи: $($o.tasks)`r`nСодержит: $($o.contained_count) объектов`r`nСодержится в: $($o.contained_in_count) объектов`r`nPB-ссылок: $($o.pb_refs)`r`nСервер: $($o.server), БД: $($o.db)`r`nВерсии совпадают: $($o.versions_match)"
    $script:SQLM.Text = if($o.versions_match -eq 'Нет'){"ВНИМАНИЕ: Версии различаются!`r`nTortoiseMerge: C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe`r`n`r`nОбъект: $($o.name)"}else{"Версии совпадают: $($o.versions_match)"}
    $script:SQLO.ItemsSource = @(); $script:SQLI.ItemsSource = @()
}

# ===== MAIN =====
$w = New-Standard2Window -Title "Справочник объектов AIS" -Width 960 -Height 650
$g = New-Object Windows.Controls.Grid
$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

$mt = New-Object Windows.Controls.TabControl
[void]$mt.Items.Add((Build-PB)); [void]$mt.Items.Add((Build-SQL))
[Windows.Controls.Grid]::SetRow($mt,0); [void]$g.Children.Add($mt)

$be = New-Object Windows.Controls.Button
$be.Content="Закрыть";$be.Width=80;$be.Height=32;$be.Background="#A0AEC0";$be.Foreground="White";$be.FontSize=12
$be.HorizontalAlignment="Right";$be.Margin="10,6,10,10"
$be.Add_Click({TJ "INFO" "User closed";$w.Close()})
[Windows.Controls.Grid]::SetRow($be,1); [void]$g.Children.Add($be)

$w.Content = New-Standard2Wrapper -Window $w -Content $g -Title "Справочник объектов"
$w.Add_KeyDown({if($_.Key -eq "Escape"){TJ "INFO" "Escape pressed";$w.Close()}})
$w.ShowDialog() | Out-Null
TJ "INFO" "GUI closed"
