# _build.ps1 - Show-TimeFIX.ps1 generator
# Run: powershell -NoLogo -File _build.ps1

$outputPath = "C:\AIS\AI\Prod\bin\Show-TimeFIX.ps1"
$null = New-Item -ItemType Directory -Path (Split-Path $outputPath) -Force -ErrorAction SilentlyContinue

$scriptCode = @'
# Show-TimeFIX.ps1 — учёт рабочего времени (WPF)
#requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Web

# === Построитель русских строк ===
function Set-RussianStrings {
    param([int[]]$codes)
    return [string]::Join('', ($codes | ForEach-Object { [char]$_ }))
}

# === Russian strings (codepoints) ===
$sTimeAccounting = Set-RussianStrings @(1059,1095,1077,1090,32,1074,1088,1077,1084,1077,1085,1080)
$sSettingsName  = Set-RussianStrings @(1055,1072,1088,1072,1084,1077,1090,1088,1099)
$sCalName       = Set-RussianStrings @(1050,1072,1083,1077,1085,1076,1072,1088,1100)
$sTasks         = Set-RussianStrings @(1047,1072,1076,1072,1095,1080)
$sExtraTasks    = Set-RussianStrings @(1044,1086,1087,46,32,1079,1072,1076,1072,1095,1080)
$sDashboard     = Set-RussianStrings @(1055,1072,1085,1077,1083,1100)
$sDate          = Set-RussianStrings @(1044,1072,1090,1072,58)
$sHoursDay      = Set-RussianStrings @(1063,1072,1089,1086,1074,47,1076,1077,1085,1100,58)
$sStartTime     = Set-RussianStrings @(1042,1088,1077,1084,1103,32,1085,1072,1095,1072,1083,1072)
$sDuration      = Set-RussianStrings @(1044,1083,1080,1090,1077,1083,1100,1085,1086,1089,1090,1100)
$sName          = Set-RussianStrings @(1053,1072,1080,1084,1077,1085,1086,1074,1072,1085,1080,1077)
$sComment       = Set-RussianStrings @(1050,1086,1084,1084,1077,1085,1090,1072,1088,1080,1081)
$sAddRow        = Set-RussianStrings @(1044,1086,1073,1072,1074,1080,1090,1100,32,1089,1090,1088,1086,1082,1091)
$sDelRow        = Set-RussianStrings @(1059,1076,1072,1083,1080,1090,1100,32,1089,1090,1088,1086,1082,1091)
$sSaveJira      = Set-RussianStrings @(1057,1086,1093,1088,1072,1085,1080,1090,1100,32,1074,32,74,105,114,97)
$sSaveSet       = Set-RussianStrings @(1057,1086,1093,1088,1072,1085,1080,1090,1100,32,1055,1072,1088,1072,1084,1077,1090,1088,1099)
$sLoadCal       = Set-RussianStrings @(1047,1072,1075,1088,1091,1079,1080,1090,1100,32,1050,1072,1083,1077,1085,1076,1072,1088,1100)
$sConfirmEvents = Set-RussianStrings @(1055,1086,1076,1090,1074,1077,1088,1076,1080,1090,1100,32,1084,1077,1088,1086,1087,1088,1080,1103,1090,1080,1103)
$sLoadTasks     = Set-RussianStrings @(1047,1072,1075,1088,1091,1079,1080,1090,1100,32,1079,1072,1076,1072,1095,1080)
$sClose         = Set-RussianStrings @(1047,1072,1082,1088,1099,1090,1100)
$sAdd           = Set-RussianStrings @(1044,1086,1073,1072,1074,1080,1090,1100)
$sDelete        = Set-RussianStrings @(1059,1076,1072,1083,1080,1090,1100)
$sSetSaved      = Set-RussianStrings @(1053,1072,1089,1090,1088,1086,1081,1082,1080,32,1089,1086,1093,1088,1072,1085,1077,1085,1099,46)
$sNotifyMin     = Set-RussianStrings @(1053,1072,1087,1086,1084,1080,1085,1072,1085,1080,1077,32,40,1084,1080,1085,41)
$sUser          = Set-RussianStrings @(1051,1086,1075,1080,1085)
$sBoardID       = Set-RussianStrings @(66,111,97,114,100,32,73,68)
$sSrvJira       = Set-RussianStrings @(74,105,114,97,32,85,82,76)
$sSrvKbn        = Set-RussianStrings @(75,97,110,98,97,110,32,85,82,76)
$sTokenAPI      = Set-RussianStrings @(65,80,73,32,84,111,107,101,110)
$sClientID      = Set-RussianStrings @(67,108,105,101,110,116,32,73,68)
$sClientSec     = Set-RussianStrings @(67,108,105,101,110,116,32,83,101,99,114,101,116)
$sTenantID      = Set-RussianStrings @(84,101,110,97,110,116,32,73,68)
$sAppTitle      = Set-RussianStrings @(1057,1080,1089,1090,1077,1084,1072,32,1091,1095,1077,1090,1072,32,1074,1088,1077,1084,1077,1085,1080,32,40,84,105,109,101,70,73,88,41)
$sLoadCalText   = Set-RussianStrings @(1047,1072,1075,1088,1091,1079,1082,1072,32,1082,1072,1083,1077,1085,1076,1072,1088,1103,32,79,117,116,108,111,111,107,46,46,46)
$sPriority      = Set-RussianStrings @(1055,1088,1080,1086,1088,1080,1090,1077,1090)
$sTimeLeft      = Set-RussianStrings @(1054,1089,1090,1072,1083,1086,1089,1100)
$sLoadKbnText   = Set-RussianStrings @(1047,1072,1075,1088,1091,1079,1082,1072,32,1079,1072,1076,1072,1095,32,75,97,110,98,97,110,46,46,46)
$sExtraInfo     = Set-RussianStrings @(1047,1072,1076,1072,1095,1080,44,32,1085,1077,32,1074,1093,1086,1076,1103,1097,1080,1077,32,1074,32,75,97,110,98,97,110,58)
$sDashWeek      = Set-RussianStrings @(83,121,115,116,101,109,32,68,97,115,104,98,111,97,114,100,32,1085,1072,32,1085,1077,1076,1077,1083,1102)
$sRefreshDash   = Set-RussianStrings @(1054,1073,1085,1086,1074,1080,1090,1100,32,68,97,115,104,98,111,97,114,100)
$sErrLoadCfg    = Set-RussianStrings @(1054,1096,1080,1073,1082,1072,32,1079,1072,1075,1088,1091,1079,1082,1080,32,99,111,110,102,105,103,58,32)
$sErrSaveCfg    = Set-RussianStrings @(1054,1096,1080,1073,1082,1072,32,1089,1086,1093,1088,1072,1085,1077,1085,1080,1103,32,99,111,110,102,105,103,58,32)

# === Конфиг ===
$script:configDir = [System.IO.Path]::Combine($env:USERPROFILE, '.timefix')
$script:configPath = [System.IO.Path]::Combine($script:configDir, 'config.json')
$script:config = @{
    JiraServer   = ''
    KbnServer    = ''
    ApiToken     = ''
    ClientId     = ''
    ClientSecret = ''
    TenantId     = ''
    BoardId      = ''
    UserName     = ''
    NotifyMin    = 15
}

function Load-Config {
    if (Test-Path $script:configPath) {
        try {
            $json = Get-Content $script:configPath -Raw -Encoding UTF8
            $loaded = $json | ConvertFrom-Json
            $keys = @($script:config.Keys)
            foreach ($key in $keys) {
                if ($loaded.PSObject.Properties.Name -contains $key) {
                    $script:config[$key] = $loaded.$key
                }
            }
        } catch {
            Write-Warning ('Ошибка загрузки config: ' + $_.Exception.Message)
        }
    }
}

function Save-Config {
    try {
        $null = New-Item -ItemType Directory -Path $script:configDir -Force -ErrorAction SilentlyContinue
        $json = $script:config | ConvertTo-Json
        [System.IO.File]::WriteAllText($script:configPath, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Warning ('Ошибка сохранения config: ' + $_.Exception.Message)
    }
}

Load-Config

# === XAML ===
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$sAppTitle" Height="650" Width="900" WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" FontSize="13">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TabControl Grid.Row="1" Name="tabMain" Margin="5">
            <TabItem Header="$sTimeAccounting" Name="tabTime">
                <Grid Margin="5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
                        <TextBlock Text="$sDate" VerticalAlignment="Center" Margin="0,0,5,0"/>
                        <DatePicker Name="dpDate" SelectedDate="{x:Null}" Width="120" Margin="0,0,10,0"/>
                        <TextBlock Text="$sHoursDay" VerticalAlignment="Center" Margin="0,0,5,0"/>
                        <TextBox Name="txtHoursDay" Width="60" Text="8" Margin="0,0,10,0"/>
                        <TextBox Name="txtComment" Width="200" ToolTip="$sComment"/>
                    </StackPanel>
                    <DataGrid Name="dgTasks" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="True"
                              IsReadOnly="False" SelectionMode="Single">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="$sStartTime" Binding="{Binding StartTime}" Width="100"/>
                            <DataGridTextColumn Header="$sDuration" Binding="{Binding Duration}" Width="80"/>
                            <DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/>
                            <DataGridTextColumn Header="$sComment" Binding="{Binding Comment}" Width="150"/>
                        </DataGrid.Columns>
                    </DataGrid>
                    <StackPanel Orientation="Horizontal" Grid.Row="2" HorizontalAlignment="Right" Margin="0,5,0,0">
                        <Button Name="btnAddRow" Content="$sAddRow" Width="140" Margin="0,0,5,0"/>
                        <Button Name="btnDelRow" Content="$sDelRow" Width="130" Margin="0,0,5,0"/>
                        <Button Name="btnSaveJira" Content="$sSaveJira" Width="140" Margin="0,0,5,0"/>
                        <Button Name="btnClose" Content="$sClose" Width="100"/>
                    </StackPanel>
                </Grid>
            </TabItem>
            <TabItem Header="$sSettingsName" Name="tabSettings">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="250"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="35"/><RowDefinition Height="35"/>
                            <RowDefinition Height="35"/><RowDefinition Height="35"/>
                            <RowDefinition Height="35"/><RowDefinition Height="35"/>
                            <RowDefinition Height="35"/><RowDefinition Height="35"/>
                            <RowDefinition Height="35"/><RowDefinition Height="50"/>
                        </Grid.RowDefinitions>
                        <TextBlock Text="$sSrvJira" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtJiraServer" Grid.Row="0" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="Kanban URL" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtKbnServer" Grid.Row="1" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="API Token" Grid.Row="2" Grid.Column="0" VerticalAlignment="Center"/>
                        <PasswordBox Name="txtApiToken" Grid.Row="2" Grid.Column="1" Margin="0,3"/>
                        <TextBlock Text="Client ID" Grid.Row="3" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtClientId" Grid.Row="3" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="Client Secret" Grid.Row="4" Grid.Column="0" VerticalAlignment="Center"/>
                        <PasswordBox Name="txtClientSecret" Grid.Row="4" Grid.Column="1" Margin="0,3"/>
                        <TextBlock Text="Tenant ID" Grid.Row="5" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtTenantId" Grid.Row="5" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="Board ID" Grid.Row="6" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtBoardId" Grid.Row="6" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="Логин" Grid.Row="7" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtUserName" Grid.Row="7" Grid.Column="1" Text="" Margin="0,3"/>
                        <TextBlock Text="Напоминание (мин)" Grid.Row="8" Grid.Column="0" VerticalAlignment="Center"/>
                        <TextBox Name="txtNotifyMin" Grid.Row="8" Grid.Column="1" Text="" Margin="0,3"/>
                        <Button Name="btnSaveSettings" Grid.Row="9" Grid.Column="0" Content="$sSaveSet" Width="150" Height="30" Margin="0,5"/>
                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="$sCalName" Name="tabCalendar">
                <Grid Margin="5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
                        <Button Name="btnLoadCal" Content="$sLoadCal" Width="200" Margin="0,0,5,0"/>
                        <Button Name="btnConfirmEvents" Content="$sConfirmEvents" Width="200"/>
                    </StackPanel>
                    <DataGrid Name="dgEvents" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="True">
                        <DataGrid.Columns>
                            <DataGridCheckBoxColumn Header="OK" Binding="{Binding IsConfirmed}" Width="40"/>
                            <DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="100"/>
                            <DataGridTextColumn Header="$sDuration" Binding="{Binding Duration}" Width="70"/>
                            <DataGridTextColumn Header="$sName" Binding="{Binding Subject}" Width="*"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
            </TabItem>
            <TabItem Header="$sTasks" Name="tabTasks">
                <Grid Margin="5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
                        <Button Name="btnLoadTasks" Content="$sLoadTasks" Width="200"/>
                    </StackPanel>
                    <DataGrid Name="dgTasksKbn" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="ID" Binding="{Binding Id}" Width="80"/>
                            <DataGridTextColumn Header="$sPriority" Binding="{Binding Priority}" Width="80">
                                <DataGridTextColumn.ElementStyle>
                                    <Style TargetType="TextBlock">
                                        <Setter Property="TextAlignment" Value="Center"/>
                                        <Setter Property="VerticalAlignment" Value="Center"/>
                                    </Style>
                                </DataGridTextColumn.ElementStyle>
                            </DataGridTextColumn>
                            <DataGridTextColumn Header="$sName" Binding="{Binding Title}" Width="*"/>
                            <DataGridTextColumn Header="$sTimeLeft" Binding="{Binding TimeLeft}" Width="100"/>
                            <DataGridTextColumn Header="URL" Binding="{Binding JiraUrl}" Width="150"/>
                        </DataGrid.Columns>
                    </DataGrid>
                </Grid>
            </TabItem>
            <TabItem Header="$sExtraTasks" Name="tabExtra">
                <Grid Margin="5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="$sExtraInfo" Grid.Row="0" TextWrapping="Wrap" Margin="0,0,0,5"/>
                    <DataGrid Name="dgExtraTasks" Grid.Row="1" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="True">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="URL" Binding="{Binding Url}" Width="*"/>
                            <DataGridTextColumn Header="$sName" Binding="{Binding Name}" Width="200"/>
                        </DataGrid.Columns>
                    </DataGrid>
                    <StackPanel Orientation="Horizontal" Grid.Row="2" HorizontalAlignment="Right" Margin="0,5,0,0">
                        <Button Name="btnAddExtra" Content="$sAdd" Width="100" Margin="0,0,5,0"/>
                        <Button Name="btnDelExtra" Content="$sDelete" Width="100"/>
                    </StackPanel>
                </Grid>
            </TabItem>
            <TabItem Header="$sDashboard" Name="tabDash">
                <Grid Margin="5">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,5">
                        <TextBlock Text="$sDashWeek" VerticalAlignment="Center" Margin="0,0,10,0" FontWeight="Bold"/>
                        <Button Name="btnRefreshDash" Content="$sRefreshDash" Width="160"/>
                    </StackPanel>
                    <TabControl Name="tabDays" Grid.Row="1">
                        <TabItem Name="dashMon" Header="Пн"><DataGrid Name="dgDashMon" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashTue" Header="Вт"><DataGrid Name="dgDashTue" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashWed" Header="Ср"><DataGrid Name="dgDashWed" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashThu" Header="Чт"><DataGrid Name="dgDashThu" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashFri" Header="Пт"><DataGrid Name="dgDashFri" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashSat" Header="Сб"><DataGrid Name="dgDashSat" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                        <TabItem Name="dashSun" Header="Вс"><DataGrid Name="dgDashSun" AutoGenerateColumns="False" IsReadOnly="True"><DataGrid.Columns><DataGridTextColumn Header="$sStartTime" Binding="{Binding Start}" Width="80"/><DataGridTextColumn Header="$sName" Binding="{Binding TaskName}" Width="*"/><DataGridTextColumn Header="$sHoursDay" Binding="{Binding Hours}" Width="70"/></DataGrid.Columns></DataGrid></TabItem>
                    </TabControl>
                </Grid>
            </TabItem>
        </TabControl>
        <StatusBar Grid.Row="2" Name="statusBar">
            <StatusBarItem>
                <TextBlock Name="lblStatus" Text="Ready"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# === Привязка контролов ===
$tabMain       = $window.FindName('tabMain')
$dpDate        = $window.FindName('dpDate')
$txtHoursDay   = $window.FindName('txtHoursDay')
$txtComment    = $window.FindName('txtComment')
$dgTasks       = $window.FindName('dgTasks')
$btnAddRow     = $window.FindName('btnAddRow')
$btnDelRow     = $window.FindName('btnDelRow')
$btnSaveJira   = $window.FindName('btnSaveJira')
$btnClose      = $window.FindName('btnClose')
$txtJiraServer = $window.FindName('txtJiraServer')
$txtKbnServer  = $window.FindName('txtKbnServer')
$txtApiToken   = $window.FindName('txtApiToken')
$txtClientId   = $window.FindName('txtClientId')
$txtClientSecret = $window.FindName('txtClientSecret')
$txtTenantId   = $window.FindName('txtTenantId')
$txtBoardId    = $window.FindName('txtBoardId')
$txtUserName   = $window.FindName('txtUserName')
$txtNotifyMin  = $window.FindName('txtNotifyMin')
$btnSaveSettings = $window.FindName('btnSaveSettings')
$btnLoadCal    = $window.FindName('btnLoadCal')
$btnConfirmEvents = $window.FindName('btnConfirmEvents')
$dgEvents      = $window.FindName('dgEvents')
$btnLoadTasks  = $window.FindName('btnLoadTasks')
$dgTasksKbn    = $window.FindName('dgTasksKbn')
$dgExtraTasks  = $window.FindName('dgExtraTasks')
$btnAddExtra   = $window.FindName('btnAddExtra')
$btnDelExtra   = $window.FindName('btnDelExtra')
$btnRefreshDash = $window.FindName('btnRefreshDash')
$tabDays       = $window.FindName('tabDays')
$dgDashMon     = $window.FindName('dgDashMon')
$dgDashTue     = $window.FindName('dgDashTue')
$dgDashWed     = $window.FindName('dgDashWed')
$dgDashThu     = $window.FindName('dgDashThu')
$dgDashFri     = $window.FindName('dgDashFri')
$dgDashSat     = $window.FindName('dgDashSat')
$dgDashSun     = $window.FindName('dgDashSun')
$lblStatus     = $window.FindName('lblStatus')

# === Установка значений из конфига ===
$txtJiraServer.Text   = $script:config['JiraServer']
$txtKbnServer.Text    = $script:config['KbnServer']
$txtClientId.Text     = $script:config['ClientId']
$txtTenantId.Text     = $script:config['TenantId']
$txtBoardId.Text      = $script:config['BoardId']
$txtUserName.Text     = $script:config['UserName']
$txtNotifyMin.Text    = $script:config['NotifyMin'].ToString()
if ($script:config['ApiToken'])     { $txtApiToken.Password = $script:config['ApiToken'] }
if ($script:config['ClientSecret']) { $txtClientSecret.Password = $script:config['ClientSecret'] }

# === Вспомогательная функция ===
function Set-Status {
    param([string]$text)
    $script:lblStatus.Text = $text
}

# === Обработчики ===

# Кнопка "Добавить строку"
$btnAddRow.Add_Click({
    $data = $dgTasks.ItemsSource
    if (-not $data) {
        $data = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    }
    $data.Add([PSCustomObject]@{
        StartTime = [DateTime]::Now.ToString('HH:mm')
        Duration  = '0:00'
        TaskName  = ''
        Comment   = ''
    })
    $dgTasks.ItemsSource = $data
    Set-Status ($sAddRow + ' OK')
})

# Кнопка "Удалить строку"
$btnDelRow.Add_Click({
    $selected = $dgTasks.SelectedItem
    if ($selected -and $dgTasks.ItemsSource) {
        $dgTasks.ItemsSource.Remove($selected)
    }
})

# Кнопка "Закрыть"
$btnClose.Add_Click({
    $window.Close()
})

# Кнопка "Сохранить настройки"
$btnSaveSettings.Add_Click({
    $script:config['JiraServer']   = $txtJiraServer.Text
    $script:config['KbnServer']    = $txtKbnServer.Text
    $script:config['ClientId']     = $txtClientId.Text
    $script:config['TenantId']     = $txtTenantId.Text
    $script:config['BoardId']      = $txtBoardId.Text
    $script:config['UserName']     = $txtUserName.Text
    $nt = 0; [int]::TryParse($txtNotifyMin.Text, [ref]$nt) | Out-Null; $script:config['NotifyMin'] = $nt
    if ($txtApiToken.Password) { $script:config['ApiToken'] = $txtApiToken.Password }
    if ($txtClientSecret.Password) { $script:config['ClientSecret'] = $txtClientSecret.Password }
    Save-Config
    Set-Status $sSetSaved
    [System.Windows.MessageBox]::Show($sSetSaved, $sSettingsName, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
})

# Кнопка "Сохранить в Jira"
$btnSaveJira.Add_Click({
    Set-Status ($sSaveJira + '...')
    $data = @()
    if ($dgTasks.ItemsSource) {
        $data = @($dgTasks.ItemsSource)
    }
    $date = if ($dpDate.SelectedDate) { $dpDate.SelectedDate.Value.ToString('yyyy-MM-dd') } else { [DateTime]::Now.ToString('yyyy-MM-dd') }
    $entry = @{
        date    = $date
        hours   = $txtHoursDay.Text
        comment = $txtComment.Text
        tasks   = $data | ForEach-Object {
            @{ start = $_.StartTime; duration = $_.Duration; name = $_.TaskName; comment = $_.Comment }
        }
    }
    $logPath = [System.IO.Path]::Combine($script:configDir, 'timelog.json')
    $log = @()
    if (Test-Path $logPath) {
        try { $log = @(Get-Content $logPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    $log += $entry
    [System.IO.File]::WriteAllText($logPath, ($log | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    Set-Status ($sSaveJira + ' OK')
})

# === Функция обновления календаря ===
function Update-Calendar {
    $targetDate = if ($dpDate.SelectedDate) { $dpDate.SelectedDate.Value } else { [DateTime]::Today }
    Set-Status ('Загрузка календаря Outlook...')
    try {
        $outlook = $null
        try { $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application') } catch {}
        if (-not $outlook) { $outlook = New-Object -ComObject Outlook.Application }
        $ns = $outlook.GetNamespace('MAPI')
        $folder = $ns.GetDefaultFolder(9)
        $dayStart = $targetDate.Date
        $dayEnd = $dayStart.AddDays(1)
        $appts = $folder.Items
        $appts.Sort('[Start]')
        $restriction = "[Start] >= '$($dayStart.ToString('yyyy-MM-dd'))' AND [Start] < '$($dayEnd.ToString('yyyy-MM-dd'))'"
        $filtered = $appts.Restrict($restriction)
        $events = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $filtered | ForEach-Object {
            if (-not $_.Cancelled -and -not $_.AllDayEvent) {
                $isConfirmed = $false
                $subj = $_.Subject
                if ($subj -like '*Дейли*' -or $subj -like '*Daily*') {
                    $isConfirmed = $true
                    $taskData = $dgTasks.ItemsSource
                    if (-not $taskData) {
                        $taskData = New-Object System.Collections.ObjectModel.ObservableCollection[object]
                    }
                    $alreadyAdded = $false
                    foreach ($t in $taskData) {
                        if ($t.TaskName -like '*Дейли*' -or $t.TaskName -like '*Daily*') { $alreadyAdded = $true; break }
                    }
                    if (-not $alreadyAdded) {
                        $taskData.Insert(0, [PSCustomObject]@{
                            StartTime = $_.Start.ToString('HH:mm')
                            Duration  = [math]::Round($_.Duration / 60, 1).ToString() + 'h'
                            TaskName  = $subj
                            Comment   = 'авто'
                        })
                    }
                    $dgTasks.ItemsSource = $taskData
                }
                $events.Add([PSCustomObject]@{
                    Start       = $_.Start.ToString('HH:mm')
                    Duration    = if ($_.Duration) { [math]::Round($_.Duration / 60, 1).ToString() + 'h' } else { '' }
                    Subject     = $subj
                    IsConfirmed = $isConfirmed
                })
            }
        }
        $sorted = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $events | Sort-Object Start | ForEach-Object { $sorted.Add($_) }
        $dgEvents.ItemsSource = $sorted
        Set-Status ('Загрузка календаря OK: ' + $sorted.Count + ' событий')
    } catch {
        $msg = 'Ошибка загрузки календаря: ' + $_.Exception.Message
        Set-Status ($msg)
        Write-Host $msg
    }
}

# Кнопка "Загрузить календарь"
$btnLoadCal.Add_Click({
    Update-Calendar
})

# Автообновление календаря при смене даты
$dpDate.Add_SelectedDateChanged({
    if ($script:windowLoaded) { Update-Calendar }
})

# Кнопка "Подтвердить мероприятия"
$btnConfirmEvents.Add_Click({
    Set-Status ($sConfirmEvents)
    [System.Windows.MessageBox]::Show($sConfirmEvents, $sCalName) | Out-Null
})

# Двойной клик по задаче — открыть URL в браузере (ВКЛ4)
$dgTasksKbn.Add_MouseDoubleClick({
    $selected = $dgTasksKbn.SelectedItem
    if ($selected -and $selected.JiraUrl) {
        Start-Process $selected.JiraUrl
        Set-Status ('Открыт: ' + $selected.JiraUrl)
    }
})

# Форматирование оставшегося времени
function Format-TimeLeft {
    param($dueDate, $timeEst)
    if ($dueDate) {
        try {
            $d = [DateTime]::Parse($dueDate)
            $diff = ($d - [DateTime]::Today).TotalDays
            if ($diff -lt 0) { return 'просрочено' }
            if ($diff -lt 1) { return [math]::Round($diff * 24).ToString() + ' ч' }
            return [math]::Round($diff).ToString() + ' дн'
        } catch { return '' }
    }
    if ($timeEst) {
        $hours = [math]::Round($timeEst / 3600, 1)
        return $hours.ToString() + ' ч'
    }
    return ''
}

# Кнопка "Загрузить задачи" — Jira REST
$btnLoadTasks.Add_Click({
    Set-Status ('Загрузка задач из Jira...')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
        $baseUrl = $script:config['JiraServer']
        if (-not $baseUrl -or $baseUrl -eq '') { throw 'Jira URL не настроен (вкладка Параметры)' }
        $user = $script:config['UserName']
        $token = $script:config['ApiToken']
        if (-not $token -or $token -eq '') { throw 'API Token не настроен (вкладка Параметры)' }
        $baseUrl = $baseUrl -replace '/secure/.*$', ''
        $baseUrl = $baseUrl -replace '/browse/.*$', ''
        $baseUrl = $baseUrl.TrimEnd('/')
        if ($baseUrl -eq '' -or $baseUrl -notlike 'http*') { throw 'Jira URL должен начинаться с http:// или https://' }
        $assignee = if ($user -and $user -ne '') { "assignee=""$user""" } else { 'assignee=currentUser()' }
        $jqlRaw = "project=SYBASE AND $assignee AND status NOT IN (Done,Closed,Resolved) ORDER BY priority DESC,updated DESC"
        $jql = [System.Web.HttpUtility]::UrlEncode($jqlRaw)
        $fullUrl = $baseUrl + '/rest/api/2/search?jql=' + $jql + '&maxResults=50&fields=key,summary,priority,duedate,timeestimate,customfield_10030'
        Set-Status ('Запрос Jira: ' + $fullUrl)
        # PAT: Bearer token (как в ОП10/ОП11 — Create-RFC.ps1)
        $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
        $response = $null
        try {
            $response = Invoke-RestMethod -Uri $fullUrl -Headers $headers -Method Get -TimeoutSec 20 -UseBasicParsing
        } catch {
            $resp = $_.Exception.Response
            $statusCode = if ($resp) { [int]$resp.StatusCode } else { 0 }
            if ($statusCode -eq 401 -and $token -match '^[a-zA-Z0-9+/=]{20,}$') {
                # Fallback: Basic Auth если токен похож на base64
                Set-Status ('Bearer 401, пробую Basic Auth...')
                $authBytes = [Text.Encoding]::ASCII.GetBytes("${user}:${token}")
                $authHdr = "Basic " + [Convert]::ToBase64String($authBytes)
                $headers2 = @{ Authorization = $authHdr; Accept = 'application/json' }
                try {
                    $response = Invoke-RestMethod -Uri $fullUrl -Headers $headers2 -Method Get -TimeoutSec 20 -UseBasicParsing
                } catch {
                    $resp2 = $_.Exception.Response
                    $sc2 = if ($resp2) { [int]$resp2.StatusCode } else { '??' }
                    $rdr2 = if ($resp2) { New-Object System.IO.StreamReader($resp2.GetResponseStream()) } else { $null }
                    $body2 = if ($rdr2) { $rdr2.ReadToEnd() } else { '' }
                    throw ("HTTP " + $sc2 + " (Bearer и Basic не прошли): " + $body2)
                }
            } else {
                $reader = if ($resp) { New-Object System.IO.StreamReader($resp.GetResponseStream()) } else { $null }
                $body = if ($reader) { $reader.ReadToEnd() } else { '' }
                throw "HTTP $statusCode : $body"
            }
        }
        $tasks = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        foreach ($issue in $response.issues) {
            $tasks.Add([PSCustomObject]@{
                Id          = $issue.key
                Priority    = if ($issue.fields.customfield_10030 -ne $null) { [math]::Round([double]$issue.fields.customfield_10030).ToString() } else { '' }
                Title       = $issue.fields.summary
                TimeLeft    = Format-TimeLeft -dueDate $issue.fields.duedate -timeEst $issue.fields.timeestimate
                JiraUrl     = $baseUrl + '/browse/' + $issue.key
            })
        }
        $dgTasksKbn.ItemsSource = $tasks
        Set-Status ('Загрузка задач OK: ' + $tasks.Count + ' задач')
    } catch {
        $errMsg = $_.Exception.Message
        Set-Status ('Ошибка задач: ' + $errMsg)
        Write-Host ('Jira error: ' + $errMsg)
        $null = [System.Windows.MessageBox]::Show('Jira: ' + $errMsg, 'Ошибка', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Кнопки доп. задач (ВКЛ5)
$btnAddExtra.Add_Click({
    $data = $dgExtraTasks.ItemsSource
    if (-not $data) {
        $data = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    }
    $data.Add([PSCustomObject]@{
        Url  = 'https://'
        Name = ''
    })
    $dgExtraTasks.ItemsSource = $data
    Set-Status ('Строка добавлена')
})

$btnDelExtra.Add_Click({
    $selected = $dgExtraTasks.SelectedItem
    if ($selected -and $dgExtraTasks.ItemsSource) {
        $dgExtraTasks.ItemsSource.Remove($selected)
        Set-Status ('Строка удалена')
    }
})

# Двойной клик по доп. задаче — добавить в учёт времени (ВКЛ1)
$dgExtraTasks.Add_MouseDoubleClick({
    $selected = $dgExtraTasks.SelectedItem
    if ($selected) {
        $taskData = $dgTasks.ItemsSource
        if (-not $taskData) {
            $taskData = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        }
        $taskData.Insert(0, [PSCustomObject]@{
            StartTime = [DateTime]::Now.ToString('HH:mm')
            Duration  = '0:00'
            TaskName  = $selected.Name
            Comment   = $selected.Url
        })
        $dgTasks.ItemsSource = $taskData
        $tabMain.SelectedItem = $tabTime
        Set-Status ('Задача добавлена в учёт: ' + $selected.Name)
    }
})

# === Обновление Dashboard (подвкладки по дням) ===
function Update-Dashboard {
    Set-Status ($sRefreshDash)
    $logPath = [System.IO.Path]::Combine($script:configDir, 'timelog.json')
    $data = @()
    if (Test-Path $logPath) {
        try { $data = @(Get-Content $logPath -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    $today = [DateTime]::Today
    $dow = [int]$today.DayOfWeek
    $dowMon = if ($dow -eq 0) { 6 } else { $dow - 1 }
    $monday = $today.AddDays(-$dowMon)
    $dgs = @($dgDashMon, $dgDashTue, $dgDashWed, $dgDashThu, $dgDashFri, $dgDashSat, $dgDashSun)
    for ($i = 0; $i -lt 7; $i++) {
        $day = $monday.AddDays($i)
        $dayStr = $day.ToString('yyyy-MM-dd')
        $entries = $data | Where-Object { $_.date -eq $dayStr }
        $dayData = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        if ($entries) {
            foreach ($entry in $entries) {
                $tasks = if ($entry.tasks) { @($entry.tasks) } else { @() }
                foreach ($t in $tasks) {
                    $dayData.Add([PSCustomObject]@{
                        Start    = $t.start
                        TaskName = $t.name
                        Hours    = $t.duration
                    })
                }
            }
        }
        $sorted = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $dayData | Sort-Object Start | ForEach-Object { $sorted.Add($_) }
        $dgs[$i].ItemsSource = $sorted
    }
    # Выбрать подвкладку текущего дня
    $tabDays.SelectedIndex = $dowMon
    Set-Status ($sRefreshDash + ' OK')
}

$btnRefreshDash.Add_Click({
    Update-Dashboard
})

# Установка даты по умолчанию
$dpDate.SelectedDate = [DateTime]::Today

# Загрузка данных за сегодня
$logPath = [System.IO.Path]::Combine($script:configDir, 'timelog.json')
if (Test-Path $logPath) {
    try {
        $log = @(Get-Content $logPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $todayStr = [DateTime]::Today.ToString('yyyy-MM-dd')
        $todayEntry = $log | Where-Object { $_.date -eq $todayStr } | Select-Object -First 1
        if ($todayEntry) {
            $txtHoursDay.Text = $todayEntry.hours
            $txtComment.Text = $todayEntry.comment
        }
    } catch {}
}

# Автозагрузка Dashboard (после показа окна)
$window.Add_Loaded({
    $script:windowLoaded = $true
    try { Update-Dashboard } catch { Set-Status ('Ошибка Dashboard: ' + $_.Exception.Message) }
})

# === Запуск ===
$window.ShowDialog()

'@

# Запись с UTF8 BOM
[System.IO.File]::WriteAllText($outputPath, $scriptCode, [System.Text.UTF8Encoding]::new($true))
Write-Host "Show-TimeFIX.ps1 created: $outputPath"
Write-Host "Size: $((Get-Item $outputPath).Length) bytes"
