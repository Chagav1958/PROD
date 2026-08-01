<#
.SYNOPSIS
  Диалоговое окно для выбора снапшота и восстановления конфигов OpenCode.
  Запускает scripts\Restore-OpenCode.ps1 с выбранной датой.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$restoreScript = Join-Path $scriptRoot 'Restore-OpenCode.ps1'
$projectRoot = Split-Path $scriptRoot -Parent
$archiveRoot = Join-Path $projectRoot 'archives\OpenCode'

# ============================================================
# Сбор доступных снапшотов
# ============================================================
$snapshotsList = @()
if (Test-Path $archiveRoot) {
    $dirs = Get-ChildItem $archiveRoot -Directory -Filter 'Snapshot_*' | Sort-Object Name -Descending
    foreach ($d in $dirs) {
        $metaPath = Join-Path $d.FullName '_meta.json'
        $label = ''
        if (Test-Path $metaPath) {
            try {
                $meta = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $label = $meta.label
            } catch {}
        }
        $fileCount = (Get-ChildItem $d.FullName -File | Where-Object { $_.Name -ne '_meta.json' }).Count
        $snapshotsList += @{
            Folder = $d.Name
            Date   = $d.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            Label  = $label
            Files  = $fileCount
        }
    }
}

# ============================================================
# Форма
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Восстановление конфигов OpenCode'
$form.Size = New-Object Drawing.Size(560, 360)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($restoreScript)

# Заголовок
$header = New-Object System.Windows.Forms.Label
$header.Text = 'Выберите снапшот для восстановления:'
$header.Location = New-Object Drawing.Point(20, 20)
$header.Size = New-Object Drawing.Size(500, 25)
$header.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($header)

# Список снапшотов
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object Drawing.Point(20, 50)
$listBox.Size = New-Object Drawing.Size(500, 150)
$listBox.Font = New-Object Drawing.Font('Consolas', 9)

if ($snapshotsList.Count -gt 0) {
    $selectedIndex = 0
    for ($i = 0; $i -lt $snapshotsList.Count; $i++) {
        $s = $snapshotsList[$i]
        $display = "{0,-45} {1,-18} {2,-5} {3}" -f $s.Folder, $s.Date, ("$($s.Files)ф"), $s.Label
        $listBox.Items.Add($display) | Out-Null
    }
    $listBox.SelectedIndex = 0
} else {
    $listBox.Items.Add('--- Нет снапшотов ---') | Out-Null
}
$form.Controls.Add($listBox)

# Подпись: ручной ввод даты
$labelManual = New-Object System.Windows.Forms.Label
$labelManual.Text = 'Или введите дату вручную (YYYYMMDD_HHMMSS):'
$labelManual.Location = New-Object Drawing.Point(20, 215)
$labelManual.Size = New-Object Drawing.Size(500, 20)
$labelManual.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.Controls.Add($labelManual)

$txtDate = New-Object System.Windows.Forms.TextBox
$txtDate.Location = New-Object Drawing.Point(20, 238)
$txtDate.Size = New-Object Drawing.Size(200, 22)
$txtDate.Font = New-Object Drawing.Font('Consolas', 10)
$form.Controls.Add($txtDate)

# Статус
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ''
$statusLabel.Location = New-Object Drawing.Point(20, 270)
$statusLabel.Size = New-Object Drawing.Size(500, 20)
$statusLabel.ForeColor = [Drawing.Color]::Gray
$form.Controls.Add($statusLabel)

# ============================================================
# Кнопки
# ============================================================
$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Восстановить'
$btnRestore.Location = New-Object Drawing.Point(310, 290)
$btnRestore.Size = New-Object Drawing.Size(100, 30)
$btnRestore.BackColor = [Drawing.Color]::SteelBlue
$btnRestore.ForeColor = [Drawing.Color]::White
$btnRestore.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRestore)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Отмена'
$btnCancel.Location = New-Object Drawing.Point(420, 290)
$btnCancel.Size = New-Object Drawing.Size(100, 30)
$form.Controls.Add($btnCancel)

# ============================================================
# Обработчики
# ============================================================
$btnCancel.Add_Click({ $form.Close() })

$btnRestore.Add_Click({
    $dateParam = ''
    $selectedText = $listBox.SelectedItem

    if ($txtDate.Text.Trim() -ne '') {
        $dateParam = $txtDate.Text.Trim()
    } elseif ($selectedText -and $snapshotsList.Count -gt 0) {
        $idx = $listBox.SelectedIndex
        $folderName = $snapshotsList[$idx].Folder
        # Извлекаем дату из имени папки Snapshot_YYYYMMDD_HHMMSS или Snapshot_label
        if ($folderName -match 'Snapshot_(\d{8}_\d{6})') {
            $dateParam = $matches[1]
        } else {
            $dateParam = ''
        }
    }

    $btnRestore.Enabled = $false
    $statusLabel.Text = 'Восстановление...'
    $statusLabel.Refresh()

    # Запускаем restore без отдельного окна
    if ($dateParam -ne '') {
        $result = powershell -NoLogo -File $restoreScript -Date $dateParam 2>&1
    } else {
        $result = powershell -NoLogo -File $restoreScript 2>&1
    }

    $outputText = $result | Out-String

    # Показываем результат
    if ($LASTEXITCODE -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($outputText, 'Восстановление завершено', 'OK', 'Information')
    } else {
        [System.Windows.Forms.MessageBox]::Show($outputText, 'Ошибка при восстановлении', 'OK', 'Error')
    }

    $form.Close()
})

# Enter в поле даты = нажать Восстановить
$txtDate.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Enter') {
        $btnRestore.PerformClick()
    }
})

# ============================================================
# Запуск
# ============================================================
$form.ShowDialog() | Out-Null
