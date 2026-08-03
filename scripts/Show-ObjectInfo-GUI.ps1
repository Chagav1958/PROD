<#
.SYNOPSIS Справочник объектов PB/SQL — WinForms DataGridView (v10)
#>
param([string]$TaskName="")
$R = if($PSScriptRoot -match '[\\/]scripts$'){Split-Path $PSScriptRoot -Parent}else{"C:\AIS\AI\Prod"}
. (Join-Path $R "scripts\Standard2-Helpers.ps1")
Add-Type -AssemblyName PresentationFramework,System.Windows.Forms,System.Drawing,System.Data -EA Stop

$script:TJPath = Join-Path $env:TEMP "objinfo_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function TJ($l,$m){Add-Content $script:TJPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [$l] $m" -Encoding UTF8 -EA SilentlyContinue}
TJ "INFO" "GUI start v10"

$script:PB = Get-Content (Join-Path $R "temp\pb_full.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$script:SQL = Get-Content (Join-Path $R "temp\sql_full.json") -Raw -Encoding UTF8 | ConvertFrom-Json

function New-DGV($items,$cols,$onDbl){
    $dt = New-Object System.Data.DataTable
    foreach($c in $cols.Keys){[void]$dt.Columns.Add($c)}
    foreach($i in $items){
        $row = $dt.NewRow()
        foreach($c in $cols.Keys){$row[$c] = & $cols[$c] $i}
        [void]$dt.Rows.Add($row)
    }
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.DataSource = $dt
    $dgv.ReadOnly = $true
    $dgv.AllowUserToAddRows = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dgv.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $dgv.RowHeadersVisible = $false
    $dgv.BackgroundColor = [System.Drawing.Color]::White
    $dgv.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
    $dgv.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $dgv.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $dgv.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26,58,96)
    $dgv.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    foreach($col in $dgv.Columns){$col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Automatic}
    # Double-click handler
    $dgv.Add_CellDoubleClick({
        if($_.RowIndex -ge 0){
            $name = $dgv.Rows[$_.RowIndex].Cells[0].Value.ToString()
            TJ "INFO" "DblClick: $name"
            & $onDbl $name
        }
    })
    # Selection handler for button
    $dgv.Add_SelectionChanged({
        if($dgv.SelectedRows.Count -gt 0){
            $script:SelName = $dgv.SelectedRows[0].Cells[0].Value.ToString()
        }
    })
    $dgv.Tag = $dt
    return $dgv
}

function New-WFH($dgv){
    $host = New-Object System.Windows.Forms.Integration.WindowsFormsHost
    $host.Child = $dgv
    return $host
}

function SortPanelWF($dgv,$cols){
    $sp = New-Object Windows.Controls.WrapPanel; $sp.Margin="4,2,4,2"
    [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{Text="Сорт:";FontSize=10;VerticalAlignment="Center";Margin="0,0,4,0"}))
    $cbF = New-Object Windows.Controls.ComboBox; $cbF.Width=130; $cbF.FontSize=10; $cbF.Margin="0,0,4,0"
    [void]$cbF.Items.Add("--поле--"); foreach($f in $cols){[void]$cbF.Items.Add($f)}; $cbF.SelectedIndex=0
    $cbD = New-Object Windows.Controls.ComboBox; $cbD.Width=70; $cbD.FontSize=10; $cbD.Margin="0,0,4,0"
    [void]$cbD.Items.Add("Asc"); [void]$cbD.Items.Add("Desc"); $cbD.SelectedIndex=0
    $lbl = New-Object Windows.Controls.TextBlock; $lbl.Text=""; $lbl.FontSize=10; $lbl.VerticalAlignment="Center"
    $bAdd = New-Standard2Button -Text "+" -Style "Small" -Click {
        if($cbF.SelectedIndex -le 0){return}
        $dt = $dgv.Tag
        $dt.DefaultView.Sort += if($dt.DefaultView.Sort){", "}else{""}
        $dt.DefaultView.Sort += "$($cbF.SelectedItem) " + $(if($cbD.SelectedIndex -eq 0){"ASC"}else{"DESC"})
        $lbl.Text = $dt.DefaultView.Sort
    } -Margin "0,0,4,0"
    $bClr = New-Standard2Button -Text "X" -Style "Small" -Click {$dgv.Tag.DefaultView.Sort="";$lbl.Text=""}
    [void]$sp.Children.Add($cbF); [void]$sp.Children.Add($cbD); [void]$sp.Children.Add($bAdd); [void]$sp.Children.Add($bClr); [void]$sp.Children.Add($lbl)
    return $sp
}

# PB columns
$PBCols = [ordered]@{
    "Наименование"={param($o)$o.name}; "Тип"={param($o)$o.type}; "Библиотека"={param($o)$o.lib}
    "РазмерKB"={param($o)$o.size_kb}; "Изменён"={param($o)$o.modified}; "Предок"={param($o)$o.first_anc}
    "Версия"={param($o)$o.src}; "Совпадают"={param($o)$o.versions_match}; "Задачи"={param($o)$o.tasks}
}
$PBSort = @("Наименование","Тип","Библиотека","РазмерKB","Изменён","Предок","Версия","Совпадают","Задачи")

# SQL columns
$SQLCols = [ordered]@{
    "Наименование"={param($o)$o.name}; "Тип"={param($o)$o.type}; "Категория"={param($o)$o.category}
    "Сервер"={param($o)$o.server}; "БД"={param($o)$o.db}; "РазмерKB"={param($o)$o.size_kb}
    "Изменён"={param($o)$o.modified}; "Версия"={param($o)$o.src}; "Совпадают"={param($o)$o.versions_match}
    "Задачи"={param($o)$o.tasks}; "PB-ссылок"={param($o)$o.pb_refs_list.Count}
}
$SQLSort = @("Наименование","Тип","Категория","Сервер","БД","РазмерKB","Изменён","Версия","Совпадают","Задачи","PB-ссылок")

function Fill-PB($name){
    TJ "INFO" "PB: $name"
    $o = $script:PB | Where-Object {$_.name -eq $name} | Select-Object -First 1
    if(-not $o){$script:StatusBar.Text="Объект не найден: $name";return}
    $script:StatusBar.Text="Загрузка: $name..."; $script:ProgBar.IsIndeterminate=$true
    
    if($o.file_path -and (Test-Path $o.file_path)){
        try{$script:PBC.Text=(Get-Content $o.file_path -Raw -Encoding UTF8 -EA Stop).Substring(0,[Math]::Min(30000,99999))}catch{$script:PBC.Text="Ошибка чтения: $($o.file_path)"}
    }else{$script:PBC.Text="Файл не найден: $($o.file_path)`r`n`r`nОбъект: $name`r`nТип: $($o.type)`r`nБиблиотека: $($o.lib)"}
    
    $ct=New-Object System.Data.DataTable;[void]$ct.Columns.Add("Объект")
    if($o.contained_list.Count -eq 0){[void]$ct.Rows.Add("(нет)")}else{foreach($c in $o.contained_list){[void]$ct.Rows.Add($c)}}
    foreach($c in $o.contained_sql){[void]$ct.Rows.Add("$c (SQL)")}
    $script:PBO.DataSource=$ct
    
    $ci=New-Object System.Data.DataTable;[void]$ci.Columns.Add("Объект")
    if($o.contained_in_list.Count -eq 0){[void]$ci.Rows.Add("(нет)")}else{foreach($c in $o.contained_in_list){[void]$ci.Rows.Add($c)}}
    $script:PBI.DataSource=$ci
    
    $pr=New-Object System.Data.DataTable;[void]$pr.Columns.Add("Свойство");[void]$pr.Columns.Add("Значение")
    [void]$pr.Rows.Add("Тип",$o.type);[void]$pr.Rows.Add("Библиотека",$o.lib);[void]$pr.Rows.Add("Размер","$($o.size_kb) KB")
    [void]$pr.Rows.Add("Изменён",$o.modified);[void]$pr.Rows.Add("Предок",$o.first_anc);[void]$pr.Rows.Add("Версия",$o.src)
    [void]$pr.Rows.Add("Совпадают",$o.versions_match);[void]$pr.Rows.Add("Задачи",$o.tasks)
    [void]$pr.Rows.Add("Функций",$o.funcs.Count);[void]$pr.Rows.Add("Событий",$o.events.Count)
    if($o.funcs.Count -eq 0){[void]$pr.Rows.Add("Функции","(нет)")}else{foreach($f in $o.funcs){[void]$pr.Rows.Add("Функция",$f)}}
    $script:PBX.DataSource=$pr
    
    $script:ProgBar.IsIndeterminate=$false
    $script:StatusBar.Text="Готово: $name ($($o.type), $($o.lib))"
}

function Fill-SQL($name){
    TJ "INFO" "SQL: $name"
    $o = $script:SQL | Where-Object {$_.name -eq $name} | Select-Object -First 1
    if(-not $o){$script:StatusBar.Text="Объект не найден: $name";return}
    $script:StatusBar.Text="Загрузка: $name..."; $script:ProgBar.IsIndeterminate=$true
    
    if($o.file_path -and (Test-Path $o.file_path)){
        try{$script:SQLC.Text=(Get-Content $o.file_path -Raw -Encoding UTF8 -EA Stop).Substring(0,[Math]::Min(30000,99999))}catch{$script:SQLC.Text="Ошибка чтения: $($o.file_path)"}
    }else{$script:SQLC.Text="Файл не найден: $($o.file_path)`r`n`r`nОбъект: $name`r`nТип: $($o.type)`r`nКатегория: $($o.category)"}
    
    $ct=New-Object System.Data.DataTable;[void]$ct.Columns.Add("Объект")
    if($o.contained_list.Count -eq 0){[void]$ct.Rows.Add("(нет)")}else{foreach($c in $o.contained_list){[void]$ct.Rows.Add($c)}}
    $script:SQLO.DataSource=$ct
    
    $ci=New-Object System.Data.DataTable;[void]$ci.Columns.Add("Объект")
    if($o.contained_in_list.Count -eq 0){[void]$ci.Rows.Add("(нет)")}else{foreach($c in $o.contained_in_list){[void]$ci.Rows.Add($c)}}
    foreach($c in $o.pb_refs_list){[void]$ci.Rows.Add("$c (PB)")}
    $script:SQLI.DataSource=$ci
    
    $pr=New-Object System.Data.DataTable;[void]$pr.Columns.Add("Свойство");[void]$pr.Columns.Add("Значение")
    [void]$pr.Rows.Add("Тип",$o.type);[void]$pr.Rows.Add("Категория",$o.category);[void]$pr.Rows.Add("Сервер",$o.server)
    [void]$pr.Rows.Add("БД",$o.db);[void]$pr.Rows.Add("Размер","$($o.size_kb) KB");[void]$pr.Rows.Add("Изменён",$o.modified)
    [void]$pr.Rows.Add("Версия",$o.src);[void]$pr.Rows.Add("Совпадают",$o.versions_match);[void]$pr.Rows.Add("Задачи",$o.tasks)
    [void]$pr.Rows.Add("Параметров",$o.params.Count);[void]$pr.Rows.Add("Таблиц",$o.tables.Count)
    $script:SQLX.DataSource=$pr
    
    $script:ProgBar.IsIndeterminate=$false
    $script:StatusBar.Text="Готово: $name ($($o.type))"
}

# PB TAB
function Build-PB {
    $tab = New-Object Windows.Controls.TabItem; $tab.Header="PB"
    $inner = New-Object Windows.Controls.TabControl; $inner.FontSize=11
    
    $t1 = New-Object Windows.Controls.TabItem; $t1.Header="Объекты"
    $g1 = New-Object Windows.Controls.Grid
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    
    $script:PBDGV = New-DGV $script:PB $PBCols {param($n) Fill-PB $n}
    $wfh = New-WFH $script:PBDGV
    
    $fp = New-Object Windows.Controls.StackPanel; $fp.Orientation="Horizontal"; $fp.Margin="4,2,4,2"
    $ft = New-Object Windows.Controls.TextBox; $ft.Width=200; $ft.FontSize=11
    $ft.Add_TextChanged({
        $t = $ft.Text.ToLower()
        $dt = $script:PBDGV.Tag
        if($t.Length -eq 0){$dt.DefaultView.RowFilter=""}else{
            $filter = ""
            foreach($col in $dt.Columns){if($filter){$filter+=" OR "};$filter+="[$($col.ColumnName)] LIKE '*$t*'"}
            try{$dt.DefaultView.RowFilter=$filter}catch{}
        }
    })
    [void]$fp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{Text="Фильтр:";FontSize=11;VerticalAlignment="Center";Margin="0,0,4,0"}))
    [void]$fp.Children.Add($ft)
    [Windows.Controls.Grid]::SetRow($fp,0); [void]$g1.Children.Add($fp)
    [Windows.Controls.Grid]::SetRow((SortPanelWF $script:PBDGV $PBSort),1); [void]$g1.Children.Add((SortPanelWF $script:PBDGV $PBSort))
    [Windows.Controls.Grid]::SetRow($wfh,2); [void]$g1.Children.Add($wfh)
    $btn = New-Standard2Button -Text "Показать детали" -Style "Primary" -Click {if($script:SelName){Fill-PB $script:SelName}} -Margin "4,2,4,2"
    [Windows.Controls.Grid]::SetRow($btn,3); [void]$g1.Children.Add($btn)
    $t1.Content=$g1; [void]$inner.Items.Add($t1)
    
    $t2=New-Object Windows.Controls.TabItem; $t2.Header="Код"; $script:PBC=New-Object Windows.Controls.TextBox; $script:PBC.IsReadOnly=$true;$script:PBC.FontFamily="Consolas";$script:PBC.FontSize=10;$script:PBC.Background="#FFFFFF";$script:PBC.VerticalScrollBarVisibility="Auto";$script:PBC.HorizontalScrollBarVisibility="Auto";$t2.Content=$script:PBC; [void]$inner.Items.Add($t2)
    $t3=New-Object Windows.Controls.TabItem; $t3.Header="Содержит"; $script:PBO=New-DGV @() @{"Объект"={param($o)$o}} {param($n)@{}}; $t3.Content=New-WFH $script:PBO; [void]$inner.Items.Add($t3)
    $t4=New-Object Windows.Controls.TabItem; $t4.Header="Содержится в"; $script:PBI=New-DGV @() @{"Объект"={param($o)$o}} {param($n)@{}}; $t4.Content=New-WFH $script:PBI; [void]$inner.Items.Add($t4)
    $t5=New-Object Windows.Controls.TabItem; $t5.Header="Свойства"; $script:PBX=New-DGV @() @{"Свойство"={param($o)$o};"Значение"={param($o)$o}} {param($n)@{}}; $t5.Content=New-WFH $script:PBX; [void]$inner.Items.Add($t5)
    $t6=New-Object Windows.Controls.TabItem; $t6.Header="Merge"; $script:PBM=New-Object Windows.Controls.TextBlock; $script:PBM.TextWrapping="Wrap";$script:PBM.FontSize=11;$script:PBM.Margin="10";$t6.Content=$script:PBM; [void]$inner.Items.Add($t6)
    $tab.Content=$inner; return $tab
}

# SQL TAB  
function Build-SQL {
    $tab = New-Object Windows.Controls.TabItem; $tab.Header="SQL"
    $inner = New-Object Windows.Controls.TabControl; $inner.FontSize=11
    
    $t1 = New-Object Windows.Controls.TabItem; $t1.Header="Объекты"
    $g1 = New-Object Windows.Controls.Grid
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
    $g1.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))
    
    $script:SQLDGV = New-DGV $script:SQL $SQLCols {param($n) Fill-SQL $n}
    $wfh = New-WFH $script:SQLDGV
    
    $fp = New-Object Windows.Controls.StackPanel; $fp.Orientation="Horizontal"; $fp.Margin="4,2,4,2"
    $ft = New-Object Windows.Controls.TextBox; $ft.Width=200; $ft.FontSize=11
    $ft.Add_TextChanged({
        $t = $ft.Text.ToLower()
        $dt = $script:SQLDGV.Tag
        if($t.Length -eq 0){$dt.DefaultView.RowFilter=""}else{
            $filter = ""
            foreach($col in $dt.Columns){if($filter){$filter+=" OR "};$filter+="[$($col.ColumnName)] LIKE '*$t*'"}
            try{$dt.DefaultView.RowFilter=$filter}catch{}
        }
    })
    [void]$fp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{Text="Фильтр:";FontSize=11;VerticalAlignment="Center";Margin="0,0,4,0"}))
    [void]$fp.Children.Add($ft)
    [Windows.Controls.Grid]::SetRow($fp,0); [void]$g1.Children.Add($fp)
    [Windows.Controls.Grid]::SetRow((SortPanelWF $script:SQLDGV $SQLSort),1); [void]$g1.Children.Add((SortPanelWF $script:SQLDGV $SQLSort))
    [Windows.Controls.Grid]::SetRow($wfh,2); [void]$g1.Children.Add($wfh)
    $btn = New-Standard2Button -Text "Показать детали" -Style "Primary" -Click {if($script:SelName){Fill-SQL $script:SelName}} -Margin "4,2,4,2"
    [Windows.Controls.Grid]::SetRow($btn,3); [void]$g1.Children.Add($btn)
    $t1.Content=$g1; [void]$inner.Items.Add($t1)
    
    $t2=New-Object Windows.Controls.TabItem; $t2.Header="Код"; $script:SQLC=New-Object Windows.Controls.TextBox; $script:SQLC.IsReadOnly=$true;$script:SQLC.FontFamily="Consolas";$script:SQLC.FontSize=10;$script:SQLC.Background="#FFFFFF";$script:SQLC.VerticalScrollBarVisibility="Auto";$script:SQLC.HorizontalScrollBarVisibility="Auto";$t2.Content=$script:SQLC; [void]$inner.Items.Add($t2)
    $t3=New-Object Windows.Controls.TabItem; $t3.Header="Содержит"; $script:SQLO=New-DGV @() @{"Объект"={param($o)$o}} {param($n)@{}}; $t3.Content=New-WFH $script:SQLO; [void]$inner.Items.Add($t3)
    $t4=New-Object Windows.Controls.TabItem; $t4.Header="Содержится в"; $script:SQLI=New-DGV @() @{"Объект"={param($o)$o}} {param($n)@{}}; $t4.Content=New-WFH $script:SQLI; [void]$inner.Items.Add($t4)
    $t5=New-Object Windows.Controls.TabItem; $t5.Header="Свойства"; $script:SQLX=New-DGV @() @{"Свойство"={param($o)$o};"Значение"={param($o)$o}} {param($n)@{}}; $t5.Content=New-WFH $script:SQLX; [void]$inner.Items.Add($t5)
    $t6=New-Object Windows.Controls.TabItem; $t6.Header="Merge"; $script:SQLM=New-Object Windows.Controls.TextBlock; $script:SQLM.TextWrapping="Wrap";$script:SQLM.FontSize=11;$script:SQLM.Margin="10";$t6.Content=$script:SQLM; [void]$inner.Items.Add($t6)
    $tab.Content=$inner; return $tab
}

# Файловый канал автотеста
$script:CmdFile=Join-Path $env:TEMP "objinfo_cmd.txt";$script:RespFile=Join-Path $env:TEMP "objinfo_resp.txt"
$cmdTimer=New-Object System.Windows.Threading.DispatcherTimer;$cmdTimer.Interval=[TimeSpan]::FromSeconds(1)
$cmdTimer.Add_Tick({try{if(Test-Path $script:CmdFile){$cmd=Get-Content $script:CmdFile -Raw -Encoding UTF8;Remove-Item $script:CmdFile -Force -EA SilentlyContinue
    if($cmd.Trim()-eq"ping"){Set-Content $script:RespFile -Value "pong" -Encoding UTF8}
    elseif($cmd.Trim()-match'^sel_pb\s+(\d+)$'){Set-Content $script:RespFile -Value "ok" -Encoding UTF8;$idx=[int]$Matches[1];$i=0;foreach($o in $script:PB){if($i -eq $idx){Fill-PB $o.name;break};$i++}}
    elseif($cmd.Trim()-match'^sel_sql\s+(\d+)$'){Set-Content $script:RespFile -Value "ok" -Encoding UTF8;$idx=[int]$Matches[1];$i=0;foreach($o in $script:SQL){if($i -eq $idx){Fill-SQL $o.name;break};$i++}}
    elseif($cmd.Trim()-eq"st_pb"){Set-Content $script:RespFile -Value "$($script:PBC.Text.Length),$(($script:PBX.DataSource|Measure-Object).Count)" -Encoding UTF8}
    elseif($cmd.Trim()-eq"st_sql"){Set-Content $script:RespFile -Value "$($script:SQLC.Text.Length),$(($script:SQLX.DataSource|Measure-Object).Count)" -Encoding UTF8}
    elseif($cmd.Trim()-eq"close"){Set-Content $script:RespFile -Value "ok" -Encoding UTF8;$script:MainWindow.Close()}
    else{Set-Content $script:RespFile -Value "unknown" -Encoding UTF8}}}catch{}});$cmdTimer.Start()

# MAIN
$w=New-Standard2Window -Title "Справочник объектов AIS" -Width 960 -Height 680
$g=New-Object Windows.Controls.Grid
[void]$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))
[void]$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="Auto"}))

$mt=New-Object Windows.Controls.TabControl
[void]$mt.Items.Add((Build-PB));[void]$mt.Items.Add((Build-SQL))
[Windows.Controls.Grid]::SetRow($mt,0);[void]$g.Children.Add($mt)

$sb=New-Object Windows.Controls.Grid;$sb.Margin="10,4,10,4"
$sb.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$sb.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
$sb.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
$st=New-Object Windows.Controls.TextBlock;$st.Text="Готов";$st.FontSize=10;$st.Foreground="#4A5568";$st.VerticalAlignment="Center";$st.Margin="0,0,6,0"
$script:StatusBar=$st;[Windows.Controls.Grid]::SetColumn($st,0);[void]$sb.Children.Add($st)
$pb=New-Object Windows.Controls.ProgressBar;$pb.Height=12;$pb.Minimum=0;$pb.Maximum=100;$pb.IsIndeterminate=$false;$pb.VerticalAlignment="Center";$pb.Margin="0,0,6,0"
$script:ProgBar=$pb;[Windows.Controls.Grid]::SetColumn($pb,1);[void]$sb.Children.Add($pb)
$be=New-Object Windows.Controls.Button
$be.Content="Закрыть";$be.Width=70;$be.Height=26;$be.FontSize=10;$be.FontWeight="Bold"
$be.Background="#A0AEC0";$be.Foreground="White";$be.Cursor="Hand";$be.Add_Click({TJ "INFO" "Close";$w.Close()})
[Windows.Controls.Grid]::SetColumn($be,2);[void]$sb.Children.Add($be)
[Windows.Controls.Grid]::SetRow($sb,1);[void]$g.Children.Add($sb)

$w.Content=New-Standard2Wrapper -Window $w -Content $g -Title "Справочник объектов"
$w.Add_KeyDown({if($_.Key -eq "Escape"){$w.Close()}})
TJ "INFO" "Show";$w.ShowDialog()|Out-Null;TJ "INFO" "Closed"
