# Settings Module for AIS Release Preparation GUI
# This module provides encryption, validation, and UI functions for settings management

. "$PSScriptRoot\Set-MetroTheme.ps1"

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

function Force-EnglishLayout {
    try {
        $en = [System.Windows.Forms.InputLanguage]::FromCulture([System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
        if ($en) { [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $en }
    } catch { }
}

function Get-MasterKey {
    param([string]$ConfigPath)
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.vss.master_key_encrypted) {
        return $null
    }
    try {
        $secure = ConvertTo-SecureString $config.vss.master_key_encrypted
        $cred = New-Object System.Management.Automation.PSCredential("user", $secure)
        $hexKey = $cred.GetNetworkCredential().Password
        $bytes = [System.Linq.Enumerable]::Range(0, $hexKey.Length / 2) | ForEach-Object {
            [Convert]::ToByte($hexKey.Substring($_ * 2, 2), 16)
        }
        return [byte[]]$bytes
    } catch {
        return $null
    }
}

function New-MasterKey {
    param([string]$ConfigPath)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.GenerateKey()
    $hexKey = [System.BitConverter]::ToString($aes.Key) -replace '-', ''
    $aes.Dispose()
    $secure = ConvertTo-SecureString $hexKey -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secure
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.vss.master_key_encrypted = $encrypted
    $config | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding UTF8
    return [System.Text.Encoding]::ASCII.GetBytes($hexKey)
}

function Encrypt-Password {
    param([string]$PlainText, [byte[]]$Key)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $Key
    $aes.GenerateIV()
    $encryptor = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    $result = $aes.IV + $encrypted
    $aes.Dispose()
    return [Convert]::ToBase64String($result)
}

function Decrypt-Password {
    param([string]$Encrypted, [byte[]]$Key)
    $bytes = [Convert]::FromBase64String($Encrypted)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $Key
    $aes.IV = $bytes[0..15]
    $decryptor = $aes.CreateDecryptor()
    $decrypted = $decryptor.TransformFinalBlock($bytes, 16, $bytes.Length - 16)
    $aes.Dispose()
    return [System.Text.Encoding]::UTF8.GetString($decrypted)
}

function Add-SettingsHistory {
    param([string]$Parameter, [string]$OldValue, [string]$NewValue, [string]$ProjectRoot)
    $historyFile = Join-Path $ProjectRoot "config\settings_history.json"
    $history = @()
    if (Test-Path $historyFile) {
        $history = Get-Content $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $entry = [ordered]@{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        parameter = $Parameter
        old_value = $OldValue
        new_value = $NewValue
    }
    $history = @($entry) + $history
    if ($history.Count -gt 50) {
        $history = $history[0..49]
    }
    $history | ConvertTo-Json -Depth 3 | Out-File $historyFile -Encoding UTF8
}

function Validate-Path {
    param([string]$Path, [string]$Type = "folder")
    if ([string]::IsNullOrWhiteSpace($Path)) { return "empty" }
    if (-not (Test-Path $Path)) { return "not_found" }
    try {
        $acl = Get-Acl $Path
        if ($Type -eq "utility") {
            $hasExecute = ($acl.Access | Where-Object { $_.FileSystemRights -match "ExecuteFile|FullControl" }).Count -gt 0
            if ($hasExecute) { return "ok" }
            else { return "no_execute" }
        } else {
            $hasWrite = ($acl.Access | Where-Object { $_.FileSystemRights -match "Write|FullControl" }).Count -gt 0
            if ($hasWrite) { return "ok" }
            else { return "read_only" }
        }
    } catch {
        return "no_access"
    }
}

# Возвращает WPF Image с GIF для предпросмотра анимации
function Build-AnimationPreview {
    param([int]$AnimIndex = 1, [int]$MaxSize = 20)
    $gifFiles = @(
        "01_spinner.gif", "02_dots.gif", "03_pulse.gif", "04_wave.gif", "05_blocks.gif",
        "06_rings.gif", "07_orbit.gif", "08_heartbeat.gif", "09_rainbow.gif", "10_flip.gif"
    )
    $idx = [Math]::Max(0, [Math]::Min($AnimIndex - 1, $gifFiles.Count - 1))
    $gifPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "docs\animations") $gifFiles[$idx]
    
    $img = New-Object System.Windows.Controls.Image
    $img.Width = $MaxSize; $img.Height = $MaxSize
    $img.Stretch = "Uniform"
    
    if (Test-Path $gifPath) {
        $uri = New-Object System.Uri($gifPath)
        $img.Source = New-Object System.Windows.Media.Imaging.BitmapImage($uri)
    }
    
    return $img
}

function Build-SettingsUI {
    param([System.Windows.Controls.StackPanel]$Panel, [string]$ConfigPath, [string]$ProjectRoot)
    Write-TechJournal "INFO" "Build-SettingsUI: started"
    $Panel.Children.Clear()
    
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-TechJournal "INFO" "Build-SettingsUI: config loaded"
    
    # MERGE: секреты из .local_secrets.json (отдельное хранилище, в .gitignore)
    $localSecretsPath = Join-Path (Split-Path $ConfigPath -Parent) ".local_secrets.json"
    if (Test-Path $localSecretsPath) {
        try {
            $localSecrets = Get-Content $localSecretsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($localSecrets.sybase) {
                if (-not $config.sybase) { $config | Add-Member -NotePropertyName "sybase" -NotePropertyValue (@{}) -Force }
                if ($localSecrets.sybase.password_encrypted) { $config.sybase.password_encrypted = $localSecrets.sybase.password_encrypted }
            }
            if ($localSecrets.vss) {
                if (-not $config.vss) { $config | Add-Member -NotePropertyName "vss" -NotePropertyValue (@{}) -Force }
                if ($localSecrets.vss.user) { $config.vss.user = $localSecrets.vss.user }
                if ($localSecrets.vss.password_encrypted) { $config.vss.password_encrypted = $localSecrets.vss.password_encrypted }
                if ($localSecrets.vss.master_key_encrypted) { $config.vss.master_key_encrypted = $localSecrets.vss.master_key_encrypted }
            }
            if ($localSecrets.jira) {
                if (-not $config.jira) { $config | Add-Member -NotePropertyName "jira" -NotePropertyValue (@{}) -Force }
                if ($localSecrets.jira.api_token_encrypted) { $config.jira.api_token_encrypted = $localSecrets.jira.api_token_encrypted }
                if ($localSecrets.jira.token_encrypted) { $config.jira.token_encrypted = $localSecrets.jira.token_encrypted }
            }
            Write-TechJournal "INFO" "Build-SettingsUI: merged .local_secrets.json"
        } catch { Write-TechJournal "WARN" "Build-SettingsUI: .local_secrets merge failed: $_" }
    }
    
    $masterKey = Get-MasterKey -ConfigPath $ConfigPath
    if (-not $masterKey) {
        try {
            $masterKey = New-MasterKey -ConfigPath $ConfigPath
            $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Host "Не удалось создать мастер-ключ: $_"
        }
    }
    Write-TechJournal "INFO" "Build-SettingsUI: masterKey ready"
    
    function New-SettingsField {
        param([string]$Label, [string]$Value, [string]$FieldName, [string]$Type = "text", [string]$PathType = "folder", [string[]]$Options = @(), [bool]$Required = $false)
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = "0,0,0,2"
        
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $Label
        $lbl.FontSize = 11
        $lbl.Foreground = [System.Windows.Media.Brushes]::Black
        $lbl.Margin = "0,0,0,0"
        $sp.Children.Add($lbl) | Out-Null
        
        if ($Type -eq "password") {
            $grid = New-Object System.Windows.Controls.Grid
            $col1 = New-Object System.Windows.Controls.ColumnDefinition
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = New-Object System.Windows.Controls.ColumnDefinition
            $col2.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col1) | Out-Null
            $grid.ColumnDefinitions.Add($col2) | Out-Null
            
            $pwdBox = New-Object System.Windows.Controls.PasswordBox
            $pwdBox.Password = $Value
            $pwdBox.FontSize = 12
            $pwdBox.Name = "fld_$FieldName"
            $pwdBox.Tag = $FieldName
            $pwdBox.Visibility = "Visible"
            $pwdBox.Add_GotFocus({ Force-EnglishLayout })
            [System.Windows.Controls.Grid]::SetColumn($pwdBox, 0)
            $grid.Children.Add($pwdBox) | Out-Null
            
            $pwdText = New-Object System.Windows.Controls.TextBox
            $pwdText.Text = $Value
            $pwdText.FontSize = 12
            $pwdText.Name = "txt_$FieldName"
            $pwdText.Tag = $FieldName
            $pwdText.Visibility = "Collapsed"
            $pwdText.Add_GotFocus({ Force-EnglishLayout })
            [System.Windows.Controls.Grid]::SetColumn($pwdText, 0)
            $grid.Children.Add($pwdText) | Out-Null
            
            if ($Required) {
                $whiteBrush = [System.Windows.Media.Brushes]::White
                $pinkBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xFF, 0xE0, 0xE0))
                if ([string]::IsNullOrEmpty($pwdBox.Password)) { $pwdBox.Background = $pinkBrush; $pwdText.Background = $pinkBrush }
                else { $pwdBox.Background = $whiteBrush; $pwdText.Background = $whiteBrush }
                $pwdBox.Add_PasswordChanged({
                    param($sender, $e)
                    $parentGrid = $sender.Parent
                    $ctrlPwdText = $null
                    foreach ($ch in $parentGrid.Children) {
                        if ($ch -is [System.Windows.Controls.TextBox] -and $ch.Name -like "txt_*") { $ctrlPwdText = $ch; break }
                    }
                    if ([string]::IsNullOrEmpty($sender.Password)) { $sender.Background = $pinkBrush; if ($ctrlPwdText) { $ctrlPwdText.Background = $pinkBrush } }
                    else { $sender.Background = $whiteBrush; if ($ctrlPwdText) { $ctrlPwdText.Background = $whiteBrush } }
                })
                $pwdText.Add_TextChanged({
                    param($sender, $e)
                    $parentGrid = $sender.Parent
                    $ctrlPwdBox = $null
                    foreach ($ch in $parentGrid.Children) {
                        if ($ch -is [System.Windows.Controls.PasswordBox]) { $ctrlPwdBox = $ch; break }
                    }
                    if ([string]::IsNullOrEmpty($sender.Text)) { $sender.Background = $pinkBrush; if ($ctrlPwdBox) { $ctrlPwdBox.Background = $pinkBrush } }
                    else { $sender.Background = $whiteBrush; if ($ctrlPwdBox) { $ctrlPwdBox.Background = $whiteBrush } }
                })
            }
            
            $btnToggle = New-Object System.Windows.Controls.Button
            $btnToggle.Content = "👁"
            $btnToggle.Width = 30
            $btnToggle.FontSize = 14
            $btnToggle.Tag = $FieldName
            [System.Windows.Controls.Grid]::SetColumn($btnToggle, 1)
            $grid.Children.Add($btnToggle) | Out-Null
            
            $btnToggle.Add_Click({
                param($s, $e)
                $parentGrid = $s.Parent
                $ctrlPwdBox = $null; $ctrlPwdText = $null
                foreach ($ch in $parentGrid.Children) {
                    if ($ch -is [System.Windows.Controls.PasswordBox]) { $ctrlPwdBox = $ch }
                    if ($ch -is [System.Windows.Controls.TextBox] -and $ch.Name -like "txt_*") { $ctrlPwdText = $ch }
                }
                if ($ctrlPwdBox -and $ctrlPwdText) {
                    if ($ctrlPwdBox.Visibility -eq "Visible") {
                        $ctrlPwdText.Text = $ctrlPwdBox.Password
                        $ctrlPwdBox.Visibility = "Collapsed"
                        $ctrlPwdText.Visibility = "Visible"
                    } else {
                        $ctrlPwdBox.Password = $ctrlPwdText.Text
                        $ctrlPwdText.Visibility = "Collapsed"
                        $ctrlPwdBox.Visibility = "Visible"
                    }
                }
            })
            
            $sp.Children.Add($grid) | Out-Null
        } elseif ($Type -eq "combo") {
            $cb = New-Object System.Windows.Controls.ComboBox
            $cb.IsEditable = $false
            $cb.FontSize = 12
            $cb.Name = "fld_$FieldName"
            $cb.Tag = $FieldName
            foreach ($opt in $Options) {
                [void]$cb.Items.Add($opt)
            }
            $selIdx = 0
            if ([int]::TryParse($Value, [ref]$selIdx)) {
                $selIdx = [math]::Max(0, [math]::Min($selIdx - 1, $Options.Count - 1))
            }
            $cb.SelectedIndex = $selIdx
            $sp.Children.Add($cb) | Out-Null
        } else {
            $tb = New-Object System.Windows.Controls.TextBox
            $tb.Text = $Value
            $tb.FontSize = 12
            $tb.Name = "fld_$FieldName"
            $tb.Tag = $FieldName
            $sp.Children.Add($tb) | Out-Null
        }
        
        $indicator = New-Object System.Windows.Controls.TextBlock
        $indicator.Name = "ind_$FieldName"
        $indicator.FontSize = 11
        $indicator.Margin = "0,1,0,0"
        $sp.Children.Add($indicator) | Out-Null
        
        $sp.Tag = $PathType
        
        return $sp
    }
    
    # TabControl с вкладками
    $tabControl = New-Object System.Windows.Controls.TabControl
    $tabControl.Margin = "0,0,0,4"
    
    # Helper для создания вкладки
    function Add-Tab {
        param([string]$Header, [System.Windows.Controls.TabControl]$TabControl)
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $Header
        $tab.FontSize = 13
        $tab.FontWeight = "SemiBold"
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = "4,4,4,4"
        $tab.Content = $sp
        $TabControl.Items.Add($tab) | Out-Null
        return $sp
    }
    
    # ── Вкладка: Релиз ──
    $spRelease = Add-Tab "Релиз" $tabControl
    $grpExport = New-Object System.Windows.Controls.GroupBox
    $grpExport.Header = "Пути экспорта"
    $grpExport.Margin = "0,0,0,3"
    $grpExport.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpExport.FontSize = 13
    $spExp = New-Object System.Windows.Controls.StackPanel
    $spExp.Children.Add((New-SettingsField "PB Main export" $config.paths.pb_main_export "pb_main_export" "text" "folder")) | Out-Null
    $spExp.Children.Add((New-SettingsField "PB Current export" $config.paths.pb_current_export "pb_current_export" "text" "folder")) | Out-Null
    $spExp.Children.Add((New-SettingsField "SQL Current export" $config.paths.bd_current_export "bd_current_export" "text" "folder")) | Out-Null
    $spExp.Children.Add((New-SettingsField "SQL Main export" $config.paths.bd_main_export "bd_main_export" "text" "folder")) | Out-Null
    $grpExport.Content = $spExp
    $spRelease.Children.Add($grpExport) | Out-Null
    
    $grpRelease = New-Object System.Windows.Controls.GroupBox
    $grpRelease.Header = "Пути к релизам"
    $grpRelease.Margin = "0,0,0,3"
    $grpRelease.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpRelease.FontSize = 13
    $spRel = New-Object System.Windows.Controls.StackPanel
    $spRel.Children.Add((New-SettingsField "Release root" $config.paths.release_root "release_root" "text" "folder")) | Out-Null
    $spRel.Children.Add((New-SettingsField "ReadyMerged root" $config.paths.ready_merged_root "ready_merged_root" "text" "folder")) | Out-Null
    $grpRelease.Content = $spRel
    $spRelease.Children.Add($grpRelease) | Out-Null
    
    # ── Вкладка: VSS ──
    $spVss = Add-Tab "VSS" $tabControl
    $grpVss = New-Object System.Windows.Controls.GroupBox
    $grpVss.Header = "Настройки VSS"
    $grpVss.Margin = "0,0,0,3"
    $grpVss.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpVss.FontSize = 13
    $spVssInner = New-Object System.Windows.Controls.StackPanel
    
    $vssPassword = ""
    if ($config.vss.password_encrypted -and $masterKey) {
        try { $vssPassword = Decrypt-Password -Encrypted $config.vss.password_encrypted -Key $masterKey }
        catch { $vssPassword = "" }
    }
    
    $spVssInner.Children.Add((New-SettingsField "DB Path" $config.vss.db_path "vss_db_path" "text" "folder")) | Out-Null
    $spVssInner.Children.Add((New-SettingsField "Username" $config.vss.user "vss_user" "text" "none")) | Out-Null
    $spVssInner.Children.Add((New-SettingsField "Password" $vssPassword "vss_password" "password" "none" -Required $true)) | Out-Null
    $spVssInner.Children.Add((New-SettingsField "Project" $config.vss.project "vss_project" "text" "none")) | Out-Null
    $spVssInner.Children.Add((New-SettingsField "История: макс. объектов" "$($config.vss.history_max)" "vss_history_max" "text" "none")) | Out-Null
    $spVssInner.Children.Add((New-SettingsField "История Task Name: макс. значений" "$($config.task_name_history_max)" "task_name_history_max" "text" "none")) | Out-Null
    $grpVss.Content = $spVssInner
    $spVss.Children.Add($grpVss) | Out-Null
    
    # ── Вкладка: PowerBuilder ──
    $spPb = Add-Tab "PowerBuilder" $tabControl
    $grpPbSrc = New-Object System.Windows.Controls.GroupBox
    $grpPbSrc.Header = "Пути к исходникам PowerBuilder"
    $grpPbSrc.Margin = "0,0,0,3"
    $grpPbSrc.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpPbSrc.FontSize = 13
    $spPbSrc = New-Object System.Windows.Controls.StackPanel
    $spPbSrc.Children.Add((New-SettingsField "Main source" $config.paths.pb_main_source "pb_main_source" "text" "folder")) | Out-Null
    $spPbSrc.Children.Add((New-SettingsField "Current source" $config.paths.pb_current_source "pb_current_source" "text" "folder")) | Out-Null
    $grpPbSrc.Content = $spPbSrc
    $spPb.Children.Add($grpPbSrc) | Out-Null
    
    $grpPbUtil = New-Object System.Windows.Controls.GroupBox
    $grpPbUtil.Header = "Утилиты"
    $grpPbUtil.Margin = "0,0,0,3"
    $grpPbUtil.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpPbUtil.FontSize = 13
    $spPbUtil = New-Object System.Windows.Controls.StackPanel
    $spPbUtil.Children.Add((New-SettingsField "PblDump" $config.paths.pbl_dump "pbl_dump" "text" "utility")) | Out-Null
    $pbtVal = if ($config.paths.pbt_name) { $config.paths.pbt_name } else { "gold" }
    $spPbUtil.Children.Add((New-SettingsField "PBT имя" "$pbtVal" "pbt_name" "text" "none")) | Out-Null
    $grpPbUtil.Content = $spPbUtil
    $spPb.Children.Add($grpPbUtil) | Out-Null
    
    # ── Вкладка: Jira ──
    $spJira = Add-Tab "Jira" $tabControl
    $grpJira = New-Object System.Windows.Controls.GroupBox
    $grpJira.Header = "Настройки Jira"
    $grpJira.Margin = "0,0,0,3"
    $grpJira.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpJira.FontSize = 13
    $spJiraInner = New-Object System.Windows.Controls.StackPanel
    $spJiraInner.Children.Add((New-SettingsField "Логин (e-mail)" $config.jira.jira_email "jira_email" "text" "none")) | Out-Null
    
    $jiraApiToken = ""
    if ($config.jira.api_token_encrypted -and $masterKey) {
        try { $jiraApiToken = Decrypt-Password -Encrypted $config.jira.api_token_encrypted -Key $masterKey }
        catch { $jiraApiToken = "" }
    }
    if (-not $jiraApiToken) { $jiraApiToken = "" }
    $spJiraInner.Children.Add((New-SettingsField "Токен" $jiraApiToken "jira_api_token" "password" "none" -Required $true)) | Out-Null
    
    $pcPass = ""
    if ($config.jira.token_encrypted -and $masterKey) {
        try { $pcPass = Decrypt-Password -Encrypted $config.jira.token_encrypted -Key $masterKey }
        catch { $pcPass = "" }
    }
    $spJiraInner.Children.Add((New-SettingsField "Пароль ПК" $pcPass "jira_token" "password" "none" -Required $true)) | Out-Null
    $grpJira.Content = $spJiraInner
    $spJira.Children.Add($grpJira) | Out-Null
    
    # ── Вкладка: Export ──
    $spExport = Add-Tab "Export" $tabControl
    $grpExportSvc = New-Object System.Windows.Controls.GroupBox
    $grpExportSvc.Header = "Настройки Export Service"
    $grpExportSvc.Margin = "0,0,0,3"
    $grpExportSvc.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpExportSvc.FontSize = 13
    $spExpSvc = New-Object System.Windows.Controls.StackPanel
    $srcPath = if ($config.export_service.source_path) { $config.export_service.source_path } else { "C:\AIS\AI\Prod" }
    $dstPath = if ($config.export_service.dest_path) { $config.export_service.dest_path } else { "Z:\AI\Prod" }
    $spExpSvc.Children.Add((New-SettingsField "Путь источника" $srcPath "export_source_path" "text" "folder")) | Out-Null
    $spExpSvc.Children.Add((New-SettingsField "Путь выгрузки" $dstPath "export_dest_path" "text" "folder")) | Out-Null
    $collectPath = if ($config.collect_prod.dest_path) { $config.collect_prod.dest_path } else { "" }
    $spExpSvc.Children.Add((New-SettingsField "Путь для сбора объектов для выгрузки в ПРОД" $collectPath "collect_dest_path" "text" "folder")) | Out-Null
    $grpExportSvc.Content = $spExpSvc
    $spExport.Children.Add($grpExportSvc) | Out-Null
    
    $grpSybase = New-Object System.Windows.Controls.GroupBox
    $grpSybase.Header = "Базы данных (Sybase)"
    $grpSybase.Margin = "0,0,0,3"
    $grpSybase.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpSybase.FontSize = 13
    $spSybase = New-Object System.Windows.Controls.StackPanel
    $sybPass = ""
    if ($config.PSObject.Properties['sybase'] -and $config.sybase.password_encrypted -and $masterKey) {
        try { $sybPass = Decrypt-Password -Encrypted $config.sybase.password_encrypted -Key $masterKey } catch { $sybPass = "" }
    }
    $spSybase.Children.Add((New-SettingsField "Пароль к БД" $sybPass "sybase_password" "password" "none" -Required $true)) | Out-Null
    $grpSybase.Content = $spSybase
    $spExport.Children.Add($grpSybase) | Out-Null
    
    # ── Вкладка: Other ──
    $spOther = Add-Tab "Other" $tabControl
    $grpGui = New-Object System.Windows.Controls.GroupBox
    $grpGui.Header = "Настройки GUI"
    $grpGui.Margin = "0,0,0,3"
    $grpGui.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpGui.FontSize = 13
    $spGui = New-Object System.Windows.Controls.StackPanel
    $spGui.Children.Add((New-SettingsField "Таймаут вывода (сек)" "$($config.gui.output_timeout_seconds)" "gui_output_timeout" "text" "none")) | Out-Null
    $compareAllVal = if ($config.gui.compare_all_max) { $config.gui.compare_all_max } else { 5 }
    $spGui.Children.Add((New-SettingsField "Макс. объектов Compare All (1-10)" "$compareAllVal" "gui_compare_all_max" "text" "none")) | Out-Null
    
    $accentLabel = New-Object System.Windows.Controls.TextBlock
    $accentLabel.Text = "Акцентный цвет"
    $accentLabel.FontSize = 11
    $accentLabel.Foreground = [System.Windows.Media.Brushes]::Black
    $accentLabel.Margin = "0,0,0,0"
    $accentFieldSp = New-Object System.Windows.Controls.StackPanel
    $accentFieldSp.Margin = "0,0,0,2"
    $accentFieldSp.Children.Add($accentLabel) | Out-Null
    $accentCb = New-Object System.Windows.Controls.ComboBox
    $accentCb.FontSize = 12
    $accentCb.Name = "fld_gui_accent_color"
    $accentCb.Tag = "gui_accent_color"
    $accentCb.IsEditable = $false
    $accents = Get-MetroAccents
    $currentAccent = Get-MetroAccent
    $selAccentIdx = 0
    for ($i = 0; $i -lt $accents.Count; $i++) {
        [void]$accentCb.Items.Add($accents[$i])
        if ($accents[$i] -eq $currentAccent) { $selAccentIdx = $i }
    }
    $accentCb.SelectedIndex = $selAccentIdx
    $accentFieldSp.Children.Add($accentCb) | Out-Null
    $spGui.Children.Add($accentFieldSp) | Out-Null
    $grpGui.Content = $spGui
    $spOther.Children.Add($grpGui) | Out-Null
    
    $grpUtil = New-Object System.Windows.Controls.GroupBox
    $grpUtil.Header = "Утилиты"
    $grpUtil.Margin = "0,0,0,3"
    $grpUtil.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(0xD0, 0xD8, 0xE0))
    $grpUtil.FontSize = 13
    $spUtil = New-Object System.Windows.Controls.StackPanel
    $spUtil.Children.Add((New-SettingsField "TortoiseMerge" $config.paths.tortoise_merge "tortoise_merge" "text" "utility")) | Out-Null
    $grpUtil.Content = $spUtil
    $spOther.Children.Add($grpUtil) | Out-Null
    
    $Panel.Children.Add($tabControl) | Out-Null
    Write-TechJournal "INFO" "Build-SettingsUI: completed"
}

function Save-Settings {
    param([System.Windows.Controls.StackPanel]$Panel, [string]$ConfigPath, [string]$ProjectRoot)
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $masterKey = Get-MasterKey -ConfigPath $ConfigPath
    if (-not $masterKey) {
        try {
            $masterKey = New-MasterKey -ConfigPath $ConfigPath
            $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            [System.Windows.MessageBox]::Show("Не удалось создать мастер-ключ шифрования: $_", "Ошибка", "OK", "Error")
            return
        }
    }
    
    # Collect all field values
    $fields = @{}
    function Collect-Fields {
        param($parent)
        foreach ($child in $parent) {
            if ($child -is [System.Windows.Controls.TabControl]) {
                foreach ($tabItem in $child.Items) {
                    $tabContent = $tabItem.Content
                    if ($tabContent -is [System.Windows.Controls.StackPanel]) {
                        Collect-Fields $tabContent.Children
                    }
                }
            } elseif ($child -is [System.Windows.Controls.GroupBox]) {
                $innerPanel = $child.Content
                if ($innerPanel -is [System.Windows.Controls.StackPanel]) {
                    Collect-Fields $innerPanel.Children
                }
            } elseif ($child -is [System.Windows.Controls.TextBox] -and $child.Tag) {
                $fields[$child.Tag] = $child.Text
            } elseif ($child -is [System.Windows.Controls.ComboBox] -and $child.Tag) {
                $fields[$child.Tag] = "$($child.SelectedIndex)"
            } elseif ($child -is [System.Windows.Controls.Grid]) {
                $gridPwdTags = @{}
                foreach ($gridChild in $child.Children) {
                    if ($gridChild -is [System.Windows.Controls.PasswordBox] -and $gridChild.Tag) {
                        $fields[$gridChild.Tag] = $gridChild.Password
                        $gridPwdTags[$gridChild.Tag] = $true
                    }
                }
                foreach ($gridChild in $child.Children) {
                    if ($gridChild -is [System.Windows.Controls.TextBox] -and $gridChild.Tag -and -not $gridPwdTags.ContainsKey($gridChild.Tag)) {
                        $fields[$gridChild.Tag] = $gridChild.Text
                    }
                }
            } elseif ($child -is [System.Windows.Controls.StackPanel]) {
                Collect-Fields $child.Children
            }
        }
    }
    Collect-Fields $Panel.Children
    
    # Update config and track changes
    $changes = @()
    $pathFields = @("pb_main_source", "pb_current_source", "pb_main_export", "pb_current_export", "bd_current_export", "bd_main_export", "release_root", "ready_merged_root", "tortoise_merge", "pbl_dump", "pbt_name")
    foreach ($fieldName in $pathFields) {
        if ($fields.ContainsKey($fieldName) -and $config.paths.$fieldName -ne $fields[$fieldName]) {
            Add-SettingsHistory -Parameter "paths.$fieldName" -OldValue $config.paths.$fieldName -NewValue $fields[$fieldName] -ProjectRoot $ProjectRoot
            $config.paths.$fieldName = $fields[$fieldName]
        }
    }
    
    # Export Service paths
    $exportFields = @("export_source_path", "export_dest_path")
    foreach ($fieldName in $exportFields) {
        $configKey = $fieldName -replace "^export_", ""
        if ($fields.ContainsKey($fieldName)) {
            $currentVal = if ($config.export_service.$configKey) { $config.export_service.$configKey } else { "" }
            if ($currentVal -ne $fields[$fieldName]) {
                Add-SettingsHistory -Parameter "export_service.$configKey" -OldValue $currentVal -NewValue $fields[$fieldName] -ProjectRoot $ProjectRoot
                $config.export_service.$configKey = $fields[$fieldName]
            }
        }
    }
    if (-not $config.export_service) { $config.export_service = [PSCustomObject]@{ source_path = ""; dest_path = "" } }
    # Collect PROD path
    if ($fields.ContainsKey("collect_dest_path")) {
        if (-not $config.PSObject.Properties['collect_prod']) {
            $config | Add-Member -NotePropertyName 'collect_prod' -NotePropertyValue ([PSCustomObject]@{ dest_path = "" })
        }
        if ($config.collect_prod.dest_path -ne $fields["collect_dest_path"]) {
            Add-SettingsHistory -Parameter "collect_prod.dest_path" -OldValue $config.collect_prod.dest_path -NewValue $fields["collect_dest_path"] -ProjectRoot $ProjectRoot
            $config.collect_prod.dest_path = $fields["collect_dest_path"]
        }
        # Синхронизация с shared-переменной в Prod-GUI.ps1
        if (Test-Path variable:script:sharedCollectPath) { $script:sharedCollectPath = $config.collect_prod.dest_path }
    }
    
    $vssFields = @("db_path", "user", "project")
    foreach ($fieldName in $vssFields) {
        $fullField = "vss_$fieldName"
        if ($fields.ContainsKey($fullField) -and $config.vss.$fieldName -ne $fields[$fullField]) {
            Add-SettingsHistory -Parameter "vss.$fieldName" -OldValue $config.vss.$fieldName -NewValue $fields[$fullField] -ProjectRoot $ProjectRoot
            $config.vss.$fieldName = $fields[$fullField]
        }
    }
    
    # Convert history_max to integer
    if ($fields.ContainsKey("vss_history_max")) {
        $intVal = 0
        if ([int]::TryParse($fields["vss_history_max"], [ref]$intVal) -and $intVal -gt 0) {
            if ($config.vss.history_max -ne $intVal) {
                Add-SettingsHistory -Parameter "vss.history_max" -OldValue $config.vss.history_max -NewValue $intVal -ProjectRoot $ProjectRoot
                $config.vss.history_max = $intVal
            }
        } else {
            [System.Windows.MessageBox]::Show("Поле 'История: макс. объектов' должно быть положительным целым числом.", "Ошибка", "OK", "Warning")
            return
        }
    }
    
    # Convert task_name_history_max to integer
    if ($fields.ContainsKey("task_name_history_max")) {
        $intVal = 0
        if ([int]::TryParse($fields["task_name_history_max"], [ref]$intVal) -and $intVal -gt 0) {
            if ($config.task_name_history_max -ne $intVal) {
                Add-SettingsHistory -Parameter "task_name_history_max" -OldValue $config.task_name_history_max -NewValue $intVal -ProjectRoot $ProjectRoot
                $config.task_name_history_max = $intVal
            }
        } else {
            [System.Windows.MessageBox]::Show("Поле 'История Task Name: макс. значений' должно быть положительным целым числом.", "Ошибка", "OK", "Warning")
            return
        }
    }

    # Handle GUI timeout
    if ($fields.ContainsKey("gui_output_timeout")) {
        $intVal = 0
        if ([int]::TryParse($fields["gui_output_timeout"], [ref]$intVal) -and $intVal -gt 0) {
            if ($config.gui.output_timeout_seconds -ne $intVal) {
                Add-SettingsHistory -Parameter "gui.output_timeout_seconds" -OldValue $config.gui.output_timeout_seconds -NewValue $intVal -ProjectRoot $ProjectRoot
                $config.gui.output_timeout_seconds = $intVal
            }
        } else {
            [System.Windows.MessageBox]::Show("Поле 'Таймаут вывода' должно быть положительным целым числом.", "Ошибка", "OK", "Warning")
            return
        }
    }

    # Handle loading animation selection
    if ($fields.ContainsKey("gui_loading_animation")) {
        $animVal = 0
        if ([int]::TryParse($fields["gui_loading_animation"], [ref]$animVal)) {
            $animVal = $animVal + 1  # SelectedIndex (0-based) -> animation number (1-10)
            if ($animVal -ge 1 -and $animVal -le 10) {
                if ($config.gui.loading_animation -ne $animVal) {
                    Add-SettingsHistory -Parameter "gui.loading_animation" -OldValue $config.gui.loading_animation -NewValue $animVal -ProjectRoot $ProjectRoot
                    $config.gui.loading_animation = $animVal
                }
            }
        }
    }

    # Handle Compare All max objects
    if ($fields.ContainsKey("gui_compare_all_max")) {
        $intVal = 0
        if ([int]::TryParse($fields["gui_compare_all_max"], [ref]$intVal) -and $intVal -ge 1 -and $intVal -le 10) {
            if ($config.gui.compare_all_max -ne $intVal) {
                Add-SettingsHistory -Parameter "gui.compare_all_max" -OldValue $config.gui.compare_all_max -NewValue $intVal -ProjectRoot $ProjectRoot
                $config.gui.compare_all_max = $intVal
            }
        } else {
            [System.Windows.MessageBox]::Show("Поле 'Макс. объектов Compare All' должно быть числом от 1 до 10.", "Ошибка", "OK", "Warning")
            return
        }
    }

    # Handle accent color
    if ($fields.ContainsKey("gui_accent_color")) {
        $accents = Get-MetroAccents
        $idx = 0
        if ([int]::TryParse($fields["gui_accent_color"], [ref]$idx)) {
            if ($idx -ge 0 -and $idx -lt $accents.Count) {
                $accentName = $accents[$idx]
                $currentAccent = Get-MetroAccent
                if ($currentAccent -ne $accentName) {
                    Add-SettingsHistory -Parameter "gui.accent_color" -OldValue $currentAccent -NewValue $accentName -ProjectRoot $ProjectRoot
                    Save-MetroAccent -AccentColor $accentName
                }
            }
        }
    }

    # Handle VSS password encryption
    if ($fields.ContainsKey("vss_password") -and $fields["vss_password"]) {
        $encryptedPwd = Encrypt-Password -PlainText $fields["vss_password"] -Key $masterKey
        if ($config.vss.password_encrypted -ne $encryptedPwd) {
            Add-SettingsHistory -Parameter "vss.password" -OldValue "***" -NewValue "***" -ProjectRoot $ProjectRoot
            $config.vss.password_encrypted = $encryptedPwd
        }
    }
    
    # Handle Jira user
    if ($fields.ContainsKey("jira_email") -and $config.jira.jira_email -ne $fields["jira_email"]) {
        Add-SettingsHistory -Parameter "jira.jira_email" -OldValue $config.jira.jira_email -NewValue $fields["jira_email"] -ProjectRoot $ProjectRoot
        $config.jira.jira_email = $fields["jira_email"]
    }
    
    # Handle Jira API token encryption
    if ($fields.ContainsKey("jira_api_token") -and $fields["jira_api_token"]) {
        $encryptedApiToken = Encrypt-Password -PlainText $fields["jira_api_token"] -Key $masterKey
        if ($config.jira.api_token_encrypted -ne $encryptedApiToken) {
            Add-SettingsHistory -Parameter "jira.api_token" -OldValue "***" -NewValue "***" -ProjectRoot $ProjectRoot
            $config.jira.api_token_encrypted = $encryptedApiToken
        }
    }
    
    # Handle Sybase password encryption
    if ($fields.ContainsKey("sybase_password") -and $fields["sybase_password"]) {
        if (-not $config.PSObject.Properties['sybase']) { $config | Add-Member -NotePropertyName 'sybase' -NotePropertyValue @{} }
        $encryptedSybase = Encrypt-Password -PlainText $fields["sybase_password"] -Key $masterKey
        if ($config.sybase.password_encrypted -ne $encryptedSybase) {
            Add-SettingsHistory -Parameter "sybase.password" -OldValue "***" -NewValue "***" -ProjectRoot $ProjectRoot
            $config.sybase.password_encrypted = $encryptedSybase
        }
    }
    
    # Handle PC password encryption (legacy token_encrypted field)
    if ($fields.ContainsKey("jira_token") -and $fields["jira_token"]) {
        $encryptedPwd = Encrypt-Password -PlainText $fields["jira_token"] -Key $masterKey
        if ($config.jira.token_encrypted -ne $encryptedPwd) {
            Add-SettingsHistory -Parameter "jira.token" -OldValue "***" -NewValue "***" -ProjectRoot $ProjectRoot
            $config.jira.token_encrypted = $encryptedPwd
        }
    }
    
    # Save config
    $configJson = $config | ConvertTo-Json -Depth 10
    Set-Content -Path $ConfigPath -Value $configJson -Encoding UTF8
    
    # Reload config to pick up any auto-generated values (master key, etc.)
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    
    # НЕ пересоздаём панель настроек после сохранения (блокирует UI-поток).
    # Значения на панели уже совпадают с сохранёнными.
    Write-TechJournal "INFO" "Save-Settings: config saved, panel not rebuilt"
}

function Validate-AllPaths {
    param([System.Windows.Controls.StackPanel]$Panel, [string]$ProjectRoot)
    function Validate-Inner {
        param($parent, [string]$pathType = "folder")
        foreach ($child in $parent) {
            if ($child -is [System.Windows.Controls.TabControl]) {
                foreach ($tabItem in $child.Items) {
                    $tabContent = $tabItem.Content
                    if ($tabContent -is [System.Windows.Controls.StackPanel]) {
                        Validate-Inner $tabContent.Children
                    }
                }
            } elseif ($child -is [System.Windows.Controls.GroupBox]) {
                $headerText = if ($child.Header) { $child.Header.ToString() } else { "" }
                $gt = if ($headerText -match "Утилиты") { "utility" } else { "folder" }
                $innerPanel = $child.Content
                if ($innerPanel -is [System.Windows.Controls.StackPanel]) {
                    Validate-Inner $innerPanel.Children $gt
                }
            } elseif ($child -is [System.Windows.Controls.StackPanel] -and $child.Tag -in @("folder", "utility")) {
                $tb = $child.Children | Where-Object { $_.Name -like "fld_*" }
                $indicator = $child.Children | Where-Object { $_.Name -like "ind_*" }
                if ($tb -and $indicator) {
                    $status = Validate-Path -Path $tb.Text -Type $pathType
                    switch ($status) {
                        "ok" { $indicator.Text = "✓ Существует"; $indicator.Foreground = [System.Windows.Media.Brushes]::Green }
                        "not_found" { $indicator.Text = "✗ Не найден"; $indicator.Foreground = [System.Windows.Media.Brushes]::Red }
                        "no_execute" { $indicator.Text = "⚠ Нет прав выполнения"; $indicator.Foreground = [System.Windows.Media.Brushes]::Orange }
                        "read_only" { $indicator.Text = "⚠ Только чтение"; $indicator.Foreground = [System.Windows.Media.Brushes]::Orange }
                        "no_access" { $indicator.Text = "✗ Нет доступа"; $indicator.Foreground = [System.Windows.Media.Brushes]::Red }
                        "empty" { $indicator.Text = "" }
                    }
                }
            }
        }
    }
    Validate-Inner $Panel.Children
}

function Export-Settings {
    param([string]$ConfigPath, [string]$ProjectRoot)
    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $historyFile = Join-Path $ProjectRoot "config\settings_history.json"
    $history = @()
    if (Test-Path $historyFile) {
        $history = Get-Content $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    
    # Очищаем зашифрованные поля для экспорта (токены не передаются новым пользователям)
    $exportConfig = $config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $exportConfig.jira.api_token_encrypted = ""
    $exportConfig.jira.token_encrypted = ""
    $exportConfig.vss.password_encrypted = ''
    
    $export = [ordered]@{
        exported_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        version = $config.version
        settings = $exportConfig
        history = $history
    }
    
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = "JSON files (*.json)|*.json"
    $saveDialog.FileName = "settings_export_20260620_140733.json"
    
    if ($saveDialog.ShowDialog() -eq $true) {
        $exportJson = $export | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($saveDialog.FileName, $exportJson, [System.Text.Encoding]::UTF8)
        [System.Windows.MessageBox]::Show("Настройки экспортированы: $($saveDialog.FileName)", "Успех", "OK", "Information")
    }
}

function Import-Settings {
    param([System.Windows.Controls.StackPanel]$Panel, [string]$ConfigPath, [string]$ProjectRoot)
    $openDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openDialog.Filter = "JSON files (*.json)|*.json"
    
    if ($openDialog.ShowDialog() -eq $true) {
        $import = Get-Content $openDialog.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        
        $result = [System.Windows.MessageBox]::Show("Загрузить настройки из файла?

Файл: $($openDialog.FileName)", "Подтверждение импорта", "YesNo", "Question")
        if ($result -eq "Yes") {
            # Save current config as backup
            $backupPath = "$ConfigPath.bak"
            Copy-Item $ConfigPath $backupPath -Force
            
            # Import settings
            $import.settings | ConvertTo-Json -Depth 10 | Out-File $ConfigPath -Encoding UTF8
            
            # Import history if exists
            if ($import.history) {
                $historyFile = Join-Path $ProjectRoot "config\settings_history.json"
                $import.history | ConvertTo-Json -Depth 3 | Out-File $historyFile -Encoding UTF8
            }
            
            # Rebuild UI
            Build-SettingsUI -Panel $Panel -ConfigPath $ConfigPath -ProjectRoot $ProjectRoot
            Attach-SettingsHandlers -Panel $Panel -ConfigPath $ConfigPath -ProjectRoot $ProjectRoot
            
            [System.Windows.MessageBox]::Show("Настройки импортированы", "Успех", "OK", "Information")
        }
    }
}

function Attach-SettingsHandlers {
    param([System.Windows.Controls.StackPanel]$Panel, [string]$ConfigPath, [string]$ProjectRoot)
    # Обработчики Show/Hide для полей паролей привязаны внутри New-SettingsField
    # Дополнительные обработчики не требуются
}