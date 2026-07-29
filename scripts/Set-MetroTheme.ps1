# Set-MetroTheme.ps1 - модуль темы MahApps.Metro
# Загружает MahApps.Metro DLL, применяет тему и акцентный цвет

# Fallback для запуска через .bat-лаунчер (где $PSScriptRoot = $null)
$script:metroScriptsDir = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\AIS\AI\Prod\scripts' }

$script:metroLoaded = $false
$script:metroAccents = @()
$script:metroThemeManager = $null
$script:metroDllDir = Join-Path (Split-Path $script:metroScriptsDir -Parent) "tools\MahApps"

# Загрузить модуль STELLS (скрытие консоли PS без P/Invoke — антивирус не детектит)
# Stells-HideConsole.ps1 может быть удалён антивирусом — обработка отсутствия
$stellsPath = Join-Path $script:metroScriptsDir "Stells-HideConsole.ps1"
if (Test-Path $stellsPath) {
    . $stellsPath
} else {
    # Stells не найден (удалён антивирусом) — без скрытия консоли
    function Invoke-StellsHide { } # пустая заглушка
}

function Import-MetroDlls {
    $dlls = @(
        Join-Path $script:metroDllDir "Microsoft.Xaml.Behaviors.dll"
        Join-Path $script:metroDllDir "ControlzEx.dll"
        Join-Path $script:metroDllDir "MahApps.Metro.dll"
    )
    foreach ($dll in $dlls) {
        if (Test-Path $dll) { Add-Type -Path $dll -ErrorAction SilentlyContinue }
    }
    $script:metroLoaded = $true
}

function Get-MetroAccents {
    if (-not $script:metroLoaded) { Import-MetroDlls }
    try {
        $tm = [MahApps.Metro.ThemeManager]::Instance
        $script:metroThemeManager = $tm
        $script:metroAccents = $tm.Themes | Where-Object { $_.Name -notmatch '^\(' } | ForEach-Object { $_.Name }
        $script:metroAccents = $script:metroAccents | Sort-Object -Unique
        return $script:metroAccents
    } catch {
        return @("Blue", "Red", "Green", "Purple", "Orange", "Teal", "Cyan", "Magenta")
    }
}

function Set-MetroTheme {
    param(
        [System.Windows.Window]$Window,
        [string]$AccentColor = "Blue",
        [string]$BaseTheme = "Light"
    )
    if (-not $script:metroLoaded) { Import-MetroDlls }
    try {
        $tm = [MahApps.Metro.ThemeManager]::Instance
        $theme = $tm.GetTheme("$BaseTheme.$AccentColor")
        if (-not $theme) {
            $base = $tm.GetBaseTheme($BaseTheme)
            $accent = $tm.GetAccent($AccentColor)
            $theme = $tm.CreateTheme($base, $accent)
        }
        if ($theme -and $Window) { [MahApps.Metro.ThemeManager]::ChangeTheme($Window, $theme) }
    } catch { }
    try {
        $conv = New-Object Windows.Media.BrushConverter
        $Window.Background = $conv.ConvertFromString("#E2E8F0")
    } catch {
        if ($Window) { $Window.Background = [Windows.Media.Brushes]::White }
    }
}

# ── Глянцевый стиль кнопок (Web 2.0 / Aqua) ──
function Apply-GlossyButtonStyle {
    param($Button, [string]$ColorTop = "#2A5080", [string]$ColorBottom = "#87CEEB")
    if (-not $Button) { return }
    try {
        $xaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
    <Border Name="border" CornerRadius="12" BorderThickness="1" BorderBrush="#1A3A60">
        <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                <GradientStop Color="$ColorTop" Offset="0"/>
                <GradientStop Color="$ColorBottom" Offset="1"/>
            </LinearGradientBrush>
        </Border.Background>
        <Border.Effect>
            <DropShadowEffect Color="#505050" Direction="270" ShadowDepth="3" BlurRadius="6" Opacity="0.5"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <ContentPresenter Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Rectangle Grid.Row="0" Margin="1,1,1,0" RadiusX="6" RadiusY="6" IsHitTestVisible="False">
                <Rectangle.Fill>
                    <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                        <GradientStop Color="#FFFFFF" Offset="0"/>
                        <GradientStop Color="#FFFFFF" Offset="0.2"/>
                        <GradientStop Color="Transparent" Offset="1"/>
                    </LinearGradientBrush>
                </Rectangle.Fill>
            </Rectangle>
        </Grid>
    </Border>
</ControlTemplate>
"@
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
        $Button.Template = [Windows.Markup.XamlReader]::Load($reader)
        $Button.Foreground = "White"
        $Button.FontWeight = "Bold"
        $Button.FontSize = 12
        $Button.Padding = "16,6"
        $Button.Cursor = "Hand"
    } catch { }
}

# ── Глянцевый стиль Прогресс-бара (по дизайну кнопки ОК, меньшая овальность) ──
function Apply-GlossyProgressStyle {
    param($ProgressBar, [string]$BarColorTop = "#2A5080", [string]$BarColorBottom = "#87CEEB")
    if (-not $ProgressBar) { return }
    try {
        $xaml = @"
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
                    <GradientStop Color="$BarColorTop" Offset="0"/>
                    <GradientStop Color="$BarColorBottom" Offset="1"/>
                </LinearGradientBrush>
            </Border.Background>
        </Border>
        <Rectangle Name="Gloss" Margin="1" RadiusX="3" RadiusY="3" IsHitTestVisible="False">
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
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml).DocumentElement
        $ProgressBar.Template = [Windows.Markup.XamlReader]::Load($reader)
        $ProgressBar.Height = 14
    } catch { }
}

# ── Серый стиль окна (для СОХР и подобных) ──
function Apply-GrayWindowStyle {
    param([System.Windows.Window]$Window)
    if (-not $Window) { return }
    try {
        $g = New-Object Windows.Media.LinearGradientBrush
        $g.StartPoint = "0,0"; $g.EndPoint = "0,1"
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x80,0x80,0x80), 0.0)))
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xD0,0xD0,0xD0), 0.5)))
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0x80,0x80,0x80), 1.0)))
        $Window.Background = $g
        $ws = New-Object Windows.Media.Effects.DropShadowEffect
        $ws.Color = [Windows.Media.Color]::FromRgb(0x40,0x40,0x40)
        $ws.Direction = 270; $ws.ShadowDepth = 4; $ws.BlurRadius = 10; $ws.Opacity = 0.5
        $Window.Effect = $ws
    } catch { }
}

# ── 3D-стилизация окна (для всех ДО) ──
function Apply-Metro3DStyle {
    param([System.Windows.Window]$Window)
    if (-not $Window) { return }
    try {
        $g = New-Object Windows.Media.LinearGradientBrush
        $g.StartPoint = "0,0"; $g.EndPoint = "0,1"
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xE8,0xE8,0xE8), 0.0)))
        [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromRgb(0xD0,0xD0,0xD0), 1.0)))
        $Window.Background = $g
        $ws = New-Object Windows.Media.Effects.DropShadowEffect
        $ws.Color = [Windows.Media.Color]::FromRgb(0x60,0x60,0x60)
        $ws.Direction = 270; $ws.ShadowDepth = 5; $ws.BlurRadius = 12; $ws.Opacity = 0.4
        $Window.Effect = $ws
    } catch { }
}

function Save-MetroAccent {
    param([string]$AccentColor)
    $cfgPath = Join-Path (Split-Path $script:metroScriptsDir -Parent) "config\config.json"
    try {
        $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $cfg.PSObject.Properties['gui']) { $cfg | Add-Member -NotePropertyName 'gui' -NotePropertyValue @{} }
        $cfg.gui.accent_color = $AccentColor
        $json = $cfg | ConvertTo-Json -Depth 10
        Set-Content -Path $cfgPath -Value $json -Encoding UTF8
    } catch { Write-Host "Ошибка Save-MetroAccent: $_" -ForegroundColor Red }
}

function Get-MetroAccent {
    $cfgPath = Join-Path (Split-Path $script:metroScriptsDir -Parent) "config\config.json"
    try {
        $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.gui.accent_color) { return $cfg.gui.accent_color }
    } catch {}
    return "Blue"
}

# Первичная загрузка DLL при импорте
Import-MetroDlls

# ── STELLS: скрыть консоль (если ещё не скрыта) ──
Invoke-StellsHide
