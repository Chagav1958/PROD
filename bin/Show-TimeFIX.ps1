Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$configDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.Show-TimeFIX'
$configFile = Join-Path $configDir 'settings.json'
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

$confirmed = @{}

$sCalName = 'Календарь'
$sLoadCal = 'Загрузить календарь'
$sConfirmEvents = 'Подтвердить мероприятия'

[xml]$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='TimeFIX - Calendar and Time' Height='700' Width='1100'
        WindowStartupLocation='CenterScreen'>
  <Grid Margin='5'>
    <Grid.RowDefinitions>
      <RowDefinition Height='Auto'/>
      <RowDefinition Height='*'/>
      <RowDefinition Height='Auto'/>
    </Grid.RowDefinitions>
    <TabControl Name='tabControl' Grid.Row='0' Grid.RowSpan='2'>
      <TabItem Header='$sCalName' Name='tabCalendar'>
        <Grid Margin='5'>
          <Grid.RowDefinitions>
            <RowDefinition Height='Auto'/>
            <RowDefinition Height='*'/>
          </Grid.RowDefinitions>
          <StackPanel Orientation='Horizontal' Grid.Row='0' Margin='0,0,0,5'>
            <Button Name='btnPrevWeek' Content='&lt; Week' Width='80' Height='28' FontSize='11' Margin='0,0,5,0'/>
            <TextBlock Name='lblWeekRange' Text='' VerticalAlignment='Center' FontSize='13' FontWeight='Bold' Width='280' TextAlignment='Center'/>
            <Button Name='btnNextWeek' Content='Week &gt;' Width='80' Height='28' FontSize='11' Margin='5,0,15,0'/>
            <Button Name='btnLoadCal' Content='$sLoadCal' Width='180' Margin='0,0,5,0'/>
            <Button Name='btnConfirmEvents' Content='$sConfirmEvents' Width='200'/>
          </StackPanel>
          <ScrollViewer Grid.Row='1' HorizontalScrollBarVisibility='Auto' VerticalScrollBarVisibility='Auto'>
            <Grid Name='calGrid' Background='White'/>
          </ScrollViewer>
        </Grid>
      </TabItem>
    </TabControl>
    <TextBlock Name='lblStatus' Grid.Row='2' Text='Ready' Background='#F0F0F0' Padding='5' FontSize='11'/>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$calGrid = $window.FindName('calGrid')
$lblWeekRange = $window.FindName('lblWeekRange')
$btnPrevWeek = $window.FindName('btnPrevWeek')
$btnNextWeek = $window.FindName('btnNextWeek')
$btnLoadCal = $window.FindName('btnLoadCal')
$btnConfirmEvents = $window.FindName('btnConfirmEvents')
$lblStatus = $window.FindName('lblStatus')

function Set-Status { param([string]$t) $lblStatus.Text = $t }

$calWeekStart = [DateTime]::Today.AddDays(-([int][DateTime]::Today.DayOfWeek - 1))
if ([int][DateTime]::Today.DayOfWeek -eq 0) { $calWeekStart = $calWeekStart.AddDays(-6) }
$calEvents = @()
$calConfirmed = @{}

function Update-VisualCalendar {
    $weekStart = $calWeekStart
    $weekEnd = $weekStart.AddDays(4)
    $mn = @('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')
    $dn = @('Mon','Tue','Wed','Thu','Fri')
    $lblWeekRange.Text = $weekStart.Day.ToString() + ' ' + $mn[$weekStart.Month-1] + ' - ' + $weekEnd.Day.ToString() + ' ' + $mn[$weekEnd.Month-1] + ' ' + $weekEnd.Year.ToString()

    $hourStart = 8; $hourEnd = 19; $hourHeight = 60
    $calGrid.Children.Clear()

    $calEvents = @()
    try {
        $outlook = $null
        try { $outlook = New-Object -ComObject Outlook.Application } catch {
            Set-Status 'Outlook COM failed'; return
        }
        $ns = $outlook.GetNamespace('MAPI')
        $folder = $ns.GetDefaultFolder(9)
        $allItems = $folder.Items
        $allItems.Sort('[Start]')
        $allItems.IncludeRecurrences = $true
        $weekEndNext = $weekEnd.AddDays(1)
        $filterStr = "[Start] >= '" + $weekStart.ToString('yyyy-MM-dd HH:mm') + "' AND [Start] < '" + $weekEndNext.ToString('yyyy-MM-dd HH:mm') + "'"
        $filtered = $allItems.Restrict($filterStr)

        foreach ($a in $filtered) {
            try {
                $s = [DateTime]$a.Start
                if ($s -lt $weekStart -or $s -ge $weekEndNext) { continue }
                $subj = [string]$a.Subject
                if ($subj -like 'Canceled:*' -or $subj -like 'Отменено:*') { continue }
                $dur = 60; try { $dur = [int]$a.Duration } catch {}
                $e = $s.AddMinutes($dur)
                $di = [int]($s.Date - $weekStart).TotalDays
                if ($di -lt 0 -or $di -gt 4) { continue }
                $keyVal = $s.Ticks.ToString() + '_' + $subj
                $confirmedFlag = $false
                if ($calConfirmed.ContainsKey($keyVal)) { $confirmedFlag = $calConfirmed[$keyVal] }
                $calEvents += [PSCustomObject]@{
                    DayIndex = $di; Start = $s.ToString('HH:mm'); End = $e.ToString('HH:mm')
                    StartMin = ($s.Hour*60)+$s.Minute; DurMin = $dur
                    Duration = $dur.ToString()+'min'
                    Subject = $subj; Confirmed = $confirmedFlag; Key = $keyVal
                }
            } catch {}
        }
    } catch { Set-Status ('Error: ' + $_.Exception.Message) }

    $totalHeight = ($hourEnd - $hourStart) * $hourHeight + 32
    $wrapper = New-Object System.Windows.Controls.Grid
    $wrapper.Width = 900; $wrapper.Height = $totalHeight
    [void]$wrapper.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition Width='50'))
    for ($c = 0; $c -lt 5; $c++) { [void]$wrapper.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition Width='170')) }
    [void]$wrapper.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition Height='28'))

    $crn = New-Object System.Windows.Controls.Border
    $crn.Background = '#F5F5F5'; $crn.BorderBrush = '#DDD'; $crn.BorderThickness = '0,0,1,1'
    [System.Windows.Controls.Grid]::SetRow($crn,0); [System.Windows.Controls.Grid]::SetColumn($crn,0)
    [void]$wrapper.Children.Add($crn)

    for ($c = 0; $c -lt 5; $c++) {
        $d = $weekStart.AddDays($c)
        $isT = ($d.Date -eq [DateTime]::Today.Date)
        $hdr = New-Object System.Windows.Controls.Border
        $hdr.Background = if ($isT) { '#2196F3' } else { '#F5F5F5' }
        $hdr.BorderBrush = '#DDD'; $hdr.BorderThickness = '0,0,1,1'
        $hdr.Child = New-Object System.Windows.Controls.TextBlock
        $hdr.Child.Text = $dn[$c] + ' ' + $d.Day.ToString() + '.' + $d.Month.ToString()
        $hdr.Child.FontSize = 11; $hdr.Child.FontWeight = 'Bold'
        $hdr.Child.HorizontalAlignment = 'Center'; $hdr.Child.VerticalAlignment = 'Center'
        $hdr.Child.Foreground = if ($isT) { 'White' } else { 'Black' }
        [System.Windows.Controls.Grid]::SetRow($hdr,0); [System.Windows.Controls.Grid]::SetColumn($hdr,$c+1)
        [void]$wrapper.Children.Add($hdr)
    }

    for ($h = $hourStart; $h -le $hourEnd; $h++) {
        $ri = $h - $hourStart + 1
        [void]$wrapper.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition Height="$hourHeight"))
        $tc = New-Object System.Windows.Controls.Border
        $tc.Background = '#FAFAFA'; $tc.BorderBrush = '#DDD'; $tc.BorderThickness = '0,0,1,1'
        $tc.Child = New-Object System.Windows.Controls.TextBlock
        $tc.Child.Text = $h.ToString('00') + ':00'
        $tc.Child.FontSize = 10; $tc.Child.Foreground = 'Gray'
        $tc.Child.HorizontalAlignment = 'Right'; $tc.Child.Margin = '0,0,6,0'; $tc.Child.VerticalAlignment = 'Top'
        [System.Windows.Controls.Grid]::SetRow($tc,$ri); [System.Windows.Controls.Grid]::SetColumn($tc,0)
        [void]$wrapper.Children.Add($tc)

        for ($c = 0; $c -lt 5; $c++) {
            $d = $weekStart.AddDays($c)
            $isT = ($d.Date -eq [DateTime]::Today.Date)
            $cb = New-Object System.Windows.Controls.Border
            $cb.Background = if ($isT) { '#E3F2FD' } else { 'White' }
            $cb.BorderBrush = '#E0E0E0'; $cb.BorderThickness = '0,0,1,1'
            $cb.Tag = 'cell_' + $c.ToString() + '_' + $ri.ToString()
            [System.Windows.Controls.Grid]::SetRow($cb,$ri); [System.Windows.Controls.Grid]::SetColumn($cb,$c+1)
            [void]$wrapper.Children.Add($cb)
        }
    }

    foreach ($evt in $calEvents) {
        if ($evt.DayIndex -lt 0 -or $evt.DayIndex -gt 4) { continue }
        $col = $evt.DayIndex + 1
        $sr = [Math]::Floor(($evt.StartMin/60) - $hourStart) + 1
        $sr = [Math]::Max(1, [Math]::Min($sr, $hourEnd - $hourStart))
        $tag = 'cell_' + $evt.DayIndex.ToString() + '_' + $sr.ToString()
        $target = $null
        foreach ($ch in $wrapper.Children) {
            if ($ch -is [System.Windows.Controls.Border] -and $ch.Tag -eq $tag) { $target = $ch; break }
        }
        if (-not $target) { continue }
        if (-not ($target.Child -is [System.Windows.Controls.StackPanel])) {
            $target.Child = New-Object System.Windows.Controls.StackPanel
            $target.Child.Margin = '2'
        }
        $sp = $target.Child

        $eb = New-Object System.Windows.Controls.Border
        $eb.CornerRadius = '3'; $eb.Padding = '4,2'; $eb.Margin = '0,1'
        if ($evt.Confirmed) {
            $eb.Background = '#C8E6C9'; $eb.BorderBrush = '#4CAF50'
        } else {
            $eb.Background = '#FFF3E0'; $eb.BorderBrush = '#FF9800'
        }
        $eb.BorderThickness = '1'

        $es = New-Object System.Windows.Controls.StackPanel
        $tr = New-Object System.Windows.Controls.DockPanel
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.IsChecked = $evt.Confirmed
        $chk.Margin = '0,0,3,0'; $chk.VerticalAlignment = 'Center'; $chk.Tag = $evt.Key
        $chk.Add_Checked({ param($s,$e) $calConfirmed[$s.Tag] = $true; Update-VisualCalendar })
        $chk.Add_Unchecked({ param($s,$e) $calConfirmed[$s.Tag] = $false; Update-VisualCalendar })
        [System.Windows.Controls.DockPanel]::SetDock($chk,'Left')
        [void]$tr.Children.Add($chk)
        $tt = New-Object System.Windows.Controls.TextBlock
        $tt.Text = $evt.Start + '-' + $evt.End + ' (' + $evt.Duration + ')'
        $tt.FontSize = 9; $tt.Foreground = 'Gray'
        [void]$tr.Children.Add($tt); [void]$es.Children.Add($tr)
        $st = New-Object System.Windows.Controls.TextBlock
        $st.Text = $evt.Subject; $st.FontSize = 11; $st.TextWrapping = 'Wrap'; $st.Margin = '18,0,0,0'
        [void]$es.Children.Add($st)
        $eb.Child = $es
        [void]$sp.Children.Add($eb)
    }
    [void]$calGrid.Children.Add($wrapper)
    Set-Status ('Calendar: ' + $weekStart.Day.ToString() + '.' + $weekStart.Month.ToString() + '-' + $weekEnd.Day.ToString() + '.' + $weekEnd.Month.ToString() + ', ' + $calEvents.Count.ToString() + ' events')
}

$btnPrevWeek.Add_Click({ $calWeekStart = $calWeekStart.AddDays(-7); Update-VisualCalendar })
$btnNextWeek.Add_Click({ $calWeekStart = $calWeekStart.AddDays(7); Update-VisualCalendar })
$btnLoadCal.Add_Click({ Update-VisualCalendar })

$btnConfirmEvents.Add_Click({
    $cnt = 0
    foreach ($k in $calConfirmed.Keys) { if ($calConfirmed[$k]) { $cnt++ } }
    [System.Windows.MessageBox]::Show('Confirmed: ' + $cnt.ToString() + ' events', 'Confirm Events')
})

$window.Add_Loaded({
    try { Update-VisualCalendar } catch { Set-Status ('Error: ' + $_.Exception.Message) }
    try {
        $now = [DateTime]::Now
        if ($now.DayOfWeek -notin @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday) -and
            $now.Hour -ge 9 -and $now.Minute -ge 30 -and $now.Hour -lt 10) {
            $ol = $null
            try { $ol = New-Object -ComObject Outlook.Application } catch { continue }
            $ns = $ol.GetNamespace('MAPI'); $f = $ns.GetDefaultFolder(9)
            $today = $now.Date; $tomorrow = $today.AddDays(1)
            $all = $f.Items; $all.Sort('[Start]'); $all.IncludeRecurrences = $true
            $filterStr = "[Start] >= '" + $today.ToString('yyyy-MM-dd HH:mm') + "' AND [Start] < '" + $tomorrow.ToString('yyyy-MM-dd HH:mm') + "'"
            $fd = $all.Restrict($filterStr)
            $hasDaily = $false
            foreach ($a in $fd) {
                try {
                    $subj = [string]$a.Subject
                    if ($subj -like '*Дейли*' -or $subj -like '*Daily*' -or $subj -like '*AIS*') { $hasDaily = $true; break }
                } catch {}
            }
            if (-not $hasDaily) {
                $choice = [System.Windows.MessageBox]::Show("No 'Daily AIS' today. Create?", 'Auto-check', 'YesNo','Question')
                if ($choice -eq 'Yes') {
                    $a = $f.Items.Add(1); $a.Subject = "Daily AIS"
                    $a.Start = [DateTime]::Today.AddHours(9).AddMinutes(30); $a.Duration = 15
                    $a.ReminderSet = $true; $a.ReminderMinutesBeforeStart = 5; $a.Save()
                    Set-Status 'Daily created'
                }
            }
        }
    } catch { Set-Status ('Auto-check error: ' + $_.Exception.Message) }
})

$window.ShowDialog()