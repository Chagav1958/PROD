param(
    [switch]$AutoConfirm
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archiveRoot = Join-Path $projectRoot 'archives\SNAPSHOT'
$stamp = Get-Date -Format 'yyyy_MM_dd_HHmmss'
$backupDir = Join-Path $archiveRoot $stamp

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
. (Join-Path $PSScriptRoot 'Set-MetroTheme.ps1')

$window = New-Object System.Windows.Window
$window.Title = 'СОХР - создание архива'
$window.Width = 520
$window.Height = 250
$window.WindowStartupLocation = 'CenterScreen'
$window.Topmost = $true
$window.ResizeMode = 'NoResize'

$grid = New-Object System.Windows.Controls.Grid
$grid.Margin = New-Object System.Windows.Thickness(16)
$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))
$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = '*' }))
$grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))

$title = New-Object System.Windows.Controls.TextBlock
$title.Text = 'Создание архива текущего состояния'
$title.FontSize = 16
$title.FontWeight = 'Bold'
[System.Windows.Controls.Grid]::SetRow($title, 0)
[void]$grid.Children.Add($title)

$info = New-Object System.Windows.Controls.TextBlock
$info.Text = "Архив будет создан в:`n$backupDir`n`nКопируются файлы проекта и настройки."
$info.TextWrapping = 'Wrap'
$info.Margin = New-Object System.Windows.Thickness(0, 12, 0, 12)
[System.Windows.Controls.Grid]::SetRow($info, 1)
[void]$grid.Children.Add($info)

$buttons = New-Object System.Windows.Controls.StackPanel
$buttons.Orientation = 'Horizontal'
$buttons.HorizontalAlignment = 'Right'
[System.Windows.Controls.Grid]::SetRow($buttons, 2)

$yes = New-Object System.Windows.Controls.Button
$yes.Content = 'Создать архив'
$yes.Width = 110
$yes.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
$yes.IsDefault = $true
$yes.Add_Click({ $window.DialogResult = $true })
[void]$buttons.Children.Add($yes)

$cancel = New-Object System.Windows.Controls.Button
$cancel.Content = 'Отмена'
$cancel.Width = 90
$cancel.IsCancel = $true
[void]$buttons.Children.Add($cancel)
[void]$grid.Children.Add($buttons)

$outer = New-Object System.Windows.Controls.Border
$outer.CornerRadius = New-Object System.Windows.CornerRadius(12)
$outer.Child = $grid
$window.Content = $outer
$themeCommand = Get-Command Set-MetroTheme -ErrorAction SilentlyContinue
if ($themeCommand) { Set-MetroTheme -Window $window -AccentColor 'Blue' }
$confirmed = $false
if ($AutoConfirm) {
    $confirmed = $true
} else {
    $confirmed = $window.ShowDialog()
}
if ($confirmed -ne $true) {
    Write-Host 'CANCELLED'
    exit 0
}

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$patterns = @(
    'bin\*.ps1', 'bin\*.bat', '*.json', '*.jsonc',
    'scripts\*.ps1', 'scripts\*.bat', 'config\*.json', 'config\*.txt',
    'docs\*.md', 'docs\*.html', 'docs\*.pdf', 'rules\*.md',
    '.opencode\*.mdc', '.opencode\plugins\*.js', '.opencode\command\*.md'
)

foreach ($pattern in $patterns) {
    $source = Join-Path $projectRoot $pattern
    $parent = Split-Path $pattern -Parent
    if ($parent -eq '.' -or $parent -eq '') {
        $destination = $backupDir
    } else {
        $destination = Join-Path $backupDir $parent
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path $source -Destination $destination -Recurse -Force -ErrorAction SilentlyContinue
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'AGENTS.md') -Destination $backupDir -Force -ErrorAction SilentlyContinue
Write-Host ('SNAPSHOT_CREATED: ' + $backupDir)
exit 0
