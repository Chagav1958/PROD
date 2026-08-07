<#
.SYNOPSIS
    СТАНДАРТ2 — Хелперы для создания диалоговых окон по стандарту
.DESCRIPTION
    Реализация СТАНДАРТ2 на PowerShell WPF.
    Эталон: C:\AIS\AI\Prod\scripts\Show-Appl2Standard-CS\
.NOTES
    Версия: 2.0
#>

# --- WINDOW CREATION ---
function New-Standard2Window {
    param(
        [string]$Title = "СТАНДАРТ2",
        [int]$Width = 520,
        [int]$Height = 580
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue

    $window = New-Object Windows.Window
    $window.Title = $Title
    $window.Width = $Width
    $window.Height = $Height
    $window.MinWidth = 400
    $window.MinHeight = 300
    $window.WindowStartupLocation = "CenterScreen"
    $window.WindowStyle = [Windows.WindowStyle]::None
    $window.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#E8ECF0")
    $window.ResizeMode = [Windows.ResizeMode]::CanResizeWithGrip

    # DropShadowEffect (СТАНДАРТ2 §1)
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $shadow.Direction = 270; $shadow.ShadowDepth = 4; $shadow.BlurRadius = 10; $shadow.Opacity = 0.5

    return $window
}

# --- STANDARD2 WRAPPER (Window chrome: outer border + title bar + content) ---
function New-Standard2Wrapper {
    param(
        [System.Windows.Window]$Window,
        [System.Windows.UIElement]$Content,
        [string]$Title
    )

    # Outer border with rounded corners (18px = 36 diameter) + shadow
    $outerBorder = New-Object Windows.Controls.Border
    $outerBorder.CornerRadius = 18
    $outerBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#E8ECF0")
    $outerBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $outerBorder.BorderThickness = 1

    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
    $shadow.Direction = 270; $shadow.ShadowDepth = 4; $shadow.BlurRadius = 10; $shadow.Opacity = 0.5
    $outerBorder.Effect = $shadow

    # Main grid
    $contentGrid = New-Object Windows.Controls.Grid
    $contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="40"}))  # Title bar
    $contentGrid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{Height="*"}))   # Content

    # ===== TITLE BAR (СТАНДАРТ2 §2) =====
    $titleBorder = New-Object Windows.Controls.Border
    $titleBorder.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#807080B0")  # 50% deep blue-gray
    $titleBorder.CornerRadius = "17,17,0,0"
    $titleBorder.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $titleBorder.BorderThickness = "0,0,0,1"
    [System.Windows.Controls.Grid]::SetRow($titleBorder, 0)

    # DragMove + DoubleClick maximize
    $titleBorder.Tag = $Window
    $titleBorder.Add_MouseLeftButtonDown({
        param($sender, $e)
        $win = $sender.Tag
        if ($e.ClickCount -eq 1 -and $win.WindowState -ne "Maximized") {
            $e.Handled = $true
            try { $win.DragMove() } catch {}
        }
        elseif ($e.ClickCount -ge 2) {
            $e.Handled = $true
            if ($win.WindowState -eq "Maximized") { $win.WindowState = "Normal" }
            else { $win.WindowState = "Maximized" }
        }
    })

    $titleGrid = New-Object Windows.Controls.Grid
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $titleGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

    # 3D Title Text (СТАНДАРТ2 §2)
    $titleLayer = New-Object Windows.Controls.Grid
    $titleLayer.Margin = "14,0,0,0"
    $titleLayer.VerticalAlignment = "Center"

    # Layer 1: White shadow (offset + opacity)
    $titleShadow = New-Object Windows.Controls.TextBlock
    $titleShadow.Text = $Title
    $titleShadow.FontSize = 14; $titleShadow.FontWeight = "Bold"; $titleShadow.FontFamily = "Segoe UI"
    $titleShadow.Foreground = [Windows.Media.Brushes]::White
    $titleShadow.Opacity = 0.9
    $titleShadow.Margin = "3,2,0,0"
    $titleShadow.HorizontalAlignment = "Left"
    [void]$titleLayer.Children.Add($titleShadow)

    # Layer 2: Dark blue text
    $titleText = New-Object Windows.Controls.TextBlock
    $titleText.Text = $Title
    $titleText.FontSize = 14; $titleText.FontWeight = "Bold"; $titleText.FontFamily = "Segoe UI"
    $titleText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $titleText.HorizontalAlignment = "Left"
    [void]$titleLayer.Children.Add($titleText)

    [System.Windows.Controls.Grid]::SetColumn($titleLayer, 0)
    [void]$titleGrid.Children.Add($titleLayer)

    # Title bar buttons (minimize, maximize, close)
    $minBtn = New-Standard2TitleButton -Text "━" -Click { $script:MainWindow.WindowState = [Windows.WindowState]::Minimized }
    $maxBtn = New-Standard2TitleButton -Text "☐" -Click {
        $sender = $args[0]
        if ($script:MainWindow.WindowState -eq "Maximized") { $script:MainWindow.WindowState = "Normal"; $sender.Content = "☐" }
        else { $script:MainWindow.WindowState = "Maximized"; $sender.Content = "❐" }
    } -FontSize 14
    $closeBtn = New-Standard2TitleButton -Text "✕" -Click { $script:MainWindow.Close() } -FontSize 14

    [System.Windows.Controls.Grid]::SetColumn($minBtn, 1)
    [System.Windows.Controls.Grid]::SetColumn($maxBtn, 2)
    [System.Windows.Controls.Grid]::SetColumn($closeBtn, 3)
    [void]$titleGrid.Children.Add($minBtn)
    [void]$titleGrid.Children.Add($maxBtn)
    [void]$titleGrid.Children.Add($closeBtn)

    $titleBorder.Child = $titleGrid
    [void]$contentGrid.Children.Add($titleBorder)

    # ===== CONTENT AREA =====
    [System.Windows.Controls.Grid]::SetRow($Content, 1)
    [void]$contentGrid.Children.Add($Content)

    $outerBorder.Child = $contentGrid
    $Window.Content = $outerBorder
    return $outerBorder
}

function New-Standard2TitleButton {
    param([string]$Text, [scriptblock]$Click, [int]$FontSize = 14)
    $b = New-Object Windows.Controls.Button
    $b.Content = $Text
    $b.Width = 40; $b.Height = 36
    $b.Background = [Windows.Media.Brushes]::Transparent
    $b.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#1A3A60")
    $b.BorderThickness = 0
    $b.FontSize = $FontSize; $b.FontWeight = "Bold"
    $b.Cursor = "Hand"
    $b.HorizontalContentAlignment = "Center"
    $b.VerticalContentAlignment = "Center"
    $b.Add_Click($Click)
    return $b
}

# --- SEARCH PANEL (СТАНДАРТ2 §6) ---
function New-Standard2SearchPanel {
    param()

    $panel = New-Object Windows.Controls.Grid
    $panel.Margin = "10,10,10,4"
    $panel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width=60}))
    $panel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width=[System.Windows.GridLength]::new(1,"Star")}))
    $panel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))
    $panel.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="Auto"}))

    # Match counter
    $lblMatch = New-Object Windows.Controls.TextBlock
    $lblMatch.Text = "0 - 0"
    $lblMatch.FontSize = 11; $lblMatch.Foreground = "#4A5568"
    $lblMatch.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($lblMatch, 0)
    [void]$panel.Children.Add($lblMatch)

    # Search input
    $txtSearch = New-Object Windows.Controls.TextBox
    $txtSearch.Name = "txtSearch"
    $txtSearch.Height = 26; $txtSearch.FontSize = 11
    $txtSearch.VerticalAlignment = "Center"
    $txtSearch.Margin = "0,0,4,0"
    [System.Windows.Controls.Grid]::SetColumn($txtSearch, 1)
    [void]$panel.Children.Add($txtSearch)

    # Search down button
    $btnDown = New-Standard2Button -Text "▼" -Style "Small" -Click { }
    [System.Windows.Controls.Grid]::SetColumn($btnDown, 2)
    [void]$panel.Children.Add($btnDown)

    # Search up button
    $btnUp = New-Standard2Button -Text "▲" -Style "Small" -Click { } -Margin "2,0,0,0"
    [System.Windows.Controls.Grid]::SetColumn($btnUp, 3)
    [void]$panel.Children.Add($btnUp)

    # Attach for external access
    $panel.Tag = @{ MatchLabel=$lblMatch; SearchInput=$txtSearch; BtnDown=$btnDown; BtnUp=$btnUp }
    return $panel
}

# --- DATAGRID (СТАНДАРТ2 §5) ---
function New-Standard2DataGrid {
    param()

    $dg = New-Object Windows.Controls.DataGrid
    $dg.AutoGenerateColumns = $false
    $dg.IsReadOnly = $true
    $dg.HeadersVisibility = "Column"
    $dg.RowHeaderWidth = 0
    $dg.AlternatingRowBackground = [Windows.Media.BrushConverter]::new().ConvertFromString("#F5F7FA")
    $dg.RowBackground = [Windows.Media.Brushes]::White
    $dg.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $dg.BorderThickness = 1
    $dg.FontSize = 11
    $dg.VerticalScrollBarVisibility = "Visible"
    $dg.HorizontalScrollBarVisibility = "Visible"
    [System.Windows.Controls.ScrollViewer]::SetCanContentScroll($dg, $true)
    $dg.SelectionMode = "Single"
    $dg.SelectionUnit = "FullRow"
    $dg.Background = [Windows.Media.Brushes]::Transparent
    $dg.GridLinesVisibility = "None"
    $dg.CanUserResizeRows = $false
    $dg.CanUserSortColumns = $true
    return $dg
}

# --- PROGRESS BAR PANEL (СТАНДАРТ2 §4) ---
function New-Standard2ProgressBarPanel {
    param()
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue

    $wrap = New-Object System.Windows.Controls.Border
    $wrap.Background = "#E2E8F0"
    $wrap.BorderThickness = "0,1,0,0"
    $wrap.BorderBrush = "#CBD5E0"
    $wrap.Height = 44

    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = "8,2,8,2"

    # Phase bar (верхний)
    $phaseGrid = New-Object Windows.Controls.Grid
    $phaseGrid.Height = 18
    $phaseGrid.Margin = "0,0,0,2"
    [void]$phaseGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="140"}))
    [void]$phaseGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))

    $lblPhase = New-Object Windows.Controls.TextBlock
    $lblPhase.Text = "Выполнение..."
    $lblPhase.VerticalAlignment = "Center"
    $lblPhase.FontSize = 11
    $lblPhase.Foreground = "#4A5568"
    $lblPhase.TextTrimming = "CharacterEllipsis"
    $lblPhase.Margin = "0,0,4,0"
    [System.Windows.Controls.Grid]::SetColumn($lblPhase, 0)
    [void]$phaseGrid.Children.Add($lblPhase)

    $pbPhase = New-Object Windows.Controls.ProgressBar
    $pbPhase.Name = "PhaseBar"
    [System.Windows.Automation.AutomationProperties]::SetName($pbPhase, "PhaseBar")
    $pbPhase.Minimum = 0; $pbPhase.Maximum = 100; $pbPhase.Value = 0
    $pbPhase.Height = 14
    $pbPhase.Margin = "0,3,0,3"
    $pbPhase.Style = New-Standard2ProgressStyle
    [System.Windows.Controls.Grid]::SetColumn($pbPhase, 1)
    [void]$phaseGrid.Children.Add($pbPhase)

    [void]$panel.Children.Add($phaseGrid)

    # Step bar (нижний)
    $stepGrid = New-Object Windows.Controls.Grid
    $stepGrid.Height = 18
    [void]$stepGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="140"}))
    [void]$stepGrid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{Width="*"}))

    $lblStep = New-Object Windows.Controls.TextBlock
    $lblStep.Text = "0 из 0"
    $lblStep.VerticalAlignment = "Center"
    $lblStep.FontSize = 11
    $lblStep.Foreground = "#4A5568"
    $lblStep.Margin = "0,0,4,0"
    [System.Windows.Controls.Grid]::SetColumn($lblStep, 0)
    [void]$stepGrid.Children.Add($lblStep)

    $pbStep = New-Object Windows.Controls.ProgressBar
    $pbStep.Name = "StepBar"
    [System.Windows.Automation.AutomationProperties]::SetName($pbStep, "StepBar")
    $pbStep.Minimum = 0; $pbStep.Maximum = 100; $pbStep.Value = 0
    $pbStep.Height = 14
    $pbStep.Margin = "0,3,0,3"
    $pbStep.Style = New-Standard2ProgressStyle
    [System.Windows.Controls.Grid]::SetColumn($pbStep, 1)
    [void]$stepGrid.Children.Add($pbStep)

    [void]$panel.Children.Add($stepGrid)

    $wrap.Child = $panel
    $wrap.Tag = @{ PhaseLabel=$lblPhase; PhaseBar=$pbPhase; StepLabel=$lblStep; StepBar=$pbStep }
    return $wrap
}

function New-Standard2ProgressStyle {
    param()
    $style = New-Object Windows.Style ([Windows.Controls.ProgressBar])

    $templateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="ProgressBar">
    <Grid MinHeight="14" MaxHeight="14">
        <Border Name="PART_Track" CornerRadius="5" BorderThickness="1" BorderBrush="#1A3A60">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#E2E8F0" Offset="0"/>
                    <GradientStop Color="#CBD5E0" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
        <Border Name="PART_Indicator" CornerRadius="5" Margin="1" HorizontalAlignment="Left">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#2A5080" Offset="0"/>
                    <GradientStop Color="#87CEEB" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
        <Rectangle Name="Gloss" Margin="0,1,0,8" RadiusX="3" RadiusY="3" IsHitTestVisible="False">
            <Rectangle.Fill>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#FFFFFF" Offset="0"/>
                    <GradientStop Color="#FFFFFF" Offset="0.2"/>
                    <GradientStop Color="Transparent" Offset="1"/>
                </LinearGradientBrush>
            </Rectangle.Fill>
        </Rectangle>
    </Grid>
</ControlTemplate>
"@
    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$templateXaml).DocumentElement
        $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.ProgressBar]::TemplateProperty; Value=([Windows.Markup.XamlReader]::Load($reader))}))
    } catch {}
    return $style
}

# --- BUTTONS (СТАНДАРТ2 §3) ---
function New-Standard2Button {
    param(
        [string]$Text,
        [string]$Style = "Primary",  # Primary, Secondary, Small
        [scriptblock]$Click,
        [string]$Margin = "4,0",
        [string]$Name = ""
    )

    $b = New-Object Windows.Controls.Button
    if ($Name) { $b.Name = $Name }
    $b.Content = $Text
    $b.Margin = $Margin
    $b.Cursor = "Hand"

    switch ($Style) {
        "Primary" {
            $b.Width = 120; $b.Height = 38
            $b.FontSize = 11; $b.FontWeight = "Bold"
            $b.Style = New-Standard2ButtonStyle -IsPrimary $true
        }
        "Secondary" {
            $b.Width = 120; $b.Height = 38
            $b.FontSize = 11; $b.FontWeight = "Bold"
            $b.Style = New-Standard2ButtonStyle -IsPrimary $false
        }
        "Small" {
            $b.Width = 30; $b.Height = 26
            $b.FontSize = 11; $b.FontWeight = "Bold"
            $b.Style = New-Standard2ButtonStyle -IsPrimary $true -IsSmall $true
        }
    }

    if ($Click) { $b.Add_Click($Click) }
    return $b
}

function New-Standard2ButtonStyle {
    param([switch]$IsPrimary, [switch]$IsSmall)

    $style = New-Object Windows.Style ([Windows.Controls.Button])

    $fontSize = if ($IsSmall) { 11 } else { 11 }

    $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.Control]::FontSizeProperty; Value=([double]$fontSize)}))
    $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.Control]::FontWeightProperty; Value=[Windows.FontWeights]::Bold}))
    $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.Control]::ForegroundProperty; Value=[Windows.Media.Brushes]::White}))
    $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.Control]::CursorProperty; Value=[Windows.Input.Cursors]::Hand}))

    $borderColor = if ($IsPrimary) { "#CC0F3050" } else { "#CC404040" }
    $gradStops = if ($IsPrimary) {
        @("#CC9DC8F0", "#CC3B7BBF", "#CC1A4A7A")
    } else {
        @("#CCD0D0D0", "#CC909090", "#CC606060")
    }

    $templateXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Grid>
        <Border CornerRadius="10" Background="$borderColor">
            <Grid>
                <Border CornerRadius="9" Margin="1.5">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="$($gradStops[0])" Offset="0"/>
                            <GradientStop Color="$($gradStops[1])" Offset="0.5"/>
                            <GradientStop Color="$($gradStops[2])" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                </Border>
                <Border CornerRadius="9" Margin="2,2,2,20" Height="7" VerticalAlignment="Top">
                    <Border.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="#E0FFFFFF" Offset="0"/>
                            <GradientStop Color="#00FFFFFF" Offset="1"/>
                        </LinearGradientBrush>
                    </Border.Background>
                </Border>
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                   Margin="0,2,0,0" TextBlock.FontWeight="Bold" TextBlock.FontSize="$fontSize"/>
            </Grid>
        </Border>
    </Grid>
</ControlTemplate>
"@
    try {
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$templateXaml).DocumentElement
        $style.Setters.Add((New-Object Windows.Setter -Property @{Property=[Windows.Controls.Control]::TemplateProperty; Value=([Windows.Markup.XamlReader]::Load($reader))}))
    } catch {}
    return $style
}

# --- BUTTON PANEL ---
function New-Standard2ButtonPanel {
    param([array]$Buttons)

    $panel = New-Object Windows.Controls.StackPanel
    $panel.Orientation = "Horizontal"
    $panel.HorizontalAlignment = "Right"
    $panel.Margin = "0,10,10,10"

    if (-not $script:MainButtons) { $script:MainButtons = @{} }

    foreach ($btnDef in $Buttons) {
        $btn = New-Standard2Button -Text $btnDef.Content -Style $btnDef.Style -Click $btnDef.Click -Name $btnDef.Name
        if ($btnDef.IsDefault) { $btn.IsDefault = $true }
        if ($btnDef.Name) {
            $script:MainButtons[$btnDef.Name] = $btn
        }
        [void]$panel.Children.Add($btn)
    }
    try { Write-TechJournal "INFO" "Panel buttons: $($script:MainButtons.Keys -join ', ')" } catch { }
    return $panel
}

# --- TEXT INPUT FIELD (СТАНДАРТ2 §8) ---
function New-Standard2TextField {
    param([string]$Label, [string]$Name)

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = "0,0,3,0"

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label; $lbl.FontSize = 10; $lbl.Foreground = "#4A5568"; $lbl.Margin = "3,0,0,1"
    [void]$stack.Children.Add($lbl)

    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $border.BorderThickness = 1
    $border.CornerRadius = 10
    $border.Padding = "6,4"

    $txt = New-Object Windows.Controls.TextBox
    $txt.Name = $Name
    $txt.BorderThickness = 0
    $txt.Background = [Windows.Media.Brushes]::Transparent
    $txt.FontSize = 11
    $txt.Padding = "0"

    $border.Child = $txt
    [void]$stack.Children.Add($border)

    return $stack
}

# --- COMBO BOX FIELD ---
function New-Standard2ComboField {
    param([string]$Label, [string]$Name, [array]$Items)

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = "0,0,3,0"

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label; $lbl.FontSize = 10; $lbl.Foreground = "#4A5568"; $lbl.Margin = "3,0,0,1"
    [void]$stack.Children.Add($lbl)

    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $border.BorderThickness = 1
    $border.CornerRadius = 10
    $border.Padding = "6,4"

    $cmb = New-Object Windows.Controls.ComboBox
    $cmb.Name = $Name
    $cmb.BorderThickness = 0
    $cmb.Background = [Windows.Media.Brushes]::Transparent
    $cmb.FontSize = 11
    foreach ($item in $Items) { [void]$cmb.Items.Add($item) }

    $border.Child = $cmb
    [void]$stack.Children.Add($border)

    return $stack
}

# --- PASSWORD FIELD ---
function New-Standard2PasswordField {
    param([string]$Label, [string]$Name)

    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = "0,0,3,0"

    $lbl = New-Object Windows.Controls.TextBlock
    $lbl.Text = $Label; $lbl.FontSize = 10; $lbl.Foreground = "#4A5568"; $lbl.Margin = "3,0,0,1"
    [void]$stack.Children.Add($lbl)

    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E0")
    $border.BorderThickness = 1
    $border.CornerRadius = 10
    $border.Padding = "6,4"

    $pwd = New-Object Windows.Controls.PasswordBox
    $pwd.Name = $Name
    $pwd.BorderThickness = 0
    $pwd.Background = [Windows.Media.Brushes]::Transparent
    $pwd.FontSize = 11
    $pwd.Padding = "0"

    $border.Child = $pwd
    [void]$stack.Children.Add($border)

    return $stack
}

# --- HELPER: GET TABLE DATA ---
function Get-TableData {
    param([string]$OpName, [string]$Output)
    # Placeholder for operation-specific table formatting
    return ""
}

# --- HELPER: HIDDEN PROCESS EXECUTION ---
function Invoke-ExternalProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$Wait
    )
    
    # Создаём временный VBS для скрытого запуска
    $vbsPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.vbs'
    $argStr = ($Arguments | ForEach-Object { "`"$_`"" }) -join ' '
    $vbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "$FilePath $argStr", 0, $(-not $Wait)
"@
    Set-Content -Path $vbsPath -Value $vbsContent -Encoding ASCII
    
    try {
        if ($Wait) {
            $process = Start-Process -FilePath "wscript.exe" -ArgumentList "`"$vbsPath`"" -Wait -NoNewWindow -PassThru
            return $process.ExitCode
        } else {
            Start-Process -FilePath "wscript.exe" -ArgumentList "`"$vbsPath`"" -NoNewWindow
            return 0
        }
    }
    finally {
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
    }
}

# --- RESIZE HANDLING (Win32 WM_NCHITTEST) ---
function Enable-Standard2Resize {
    param([System.Windows.Window]$Window)

    # Requires Win32 interop - skip for PowerShell version
    # C# version uses WndProc override
}