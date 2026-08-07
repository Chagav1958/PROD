# Convert-Docs.ps1 — конвертация docs\*.md → docs\*.html + docs\*.pdf
param(
    [string]$DocsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "docs"),
    [switch]$SkipPdf
)

$scriptsDir = $PSScriptRoot
if (-not $scriptsDir) { $scriptsDir = 'C:\AIS\AI\Prod\scripts' }

$mdFiles = Get-ChildItem -Path $DocsDir -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
if (-not $mdFiles) { Write-Host "No .md files found in $DocsDir"; exit 0 }

function Convert-MdToHtml {
    param([string]$Md, [string]$Title)
    $h = @()
    $h += "<!DOCTYPE html><html><head><meta charset='utf-8'>"
    $h += "<title>$Title</title>"
    $h += "<style>body{font-family:Segoe UI,sans-serif;max-width:800px;margin:20px auto;padding:0 20px;line-height:1.6}"
    $h += "h1,h2,h3{color:#1a3a60}code{background:#f0f0f0;padding:2px 4px;border-radius:3px}"
    $h += "pre{background:#f5f5f5;padding:10px;border-radius:5px;overflow-x:auto}"
    $h += "table{border-collapse:collapse;width:100%;margin:8px 0}td,th{border:1px solid #ccc;padding:6px;text-align:left}"
    $h += "th{background:#eef2f7;font-weight:bold}tr:nth-child(even){background:#f9fafb}</style></head><body>"
    $inCode = $false; $inTable = $false; $inRawHtml = $false; $tableRows = @()
    $lines = $Md -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].TrimEnd()
        if ($t -match '^\s*<(style|div|/div)\b') { $h += $t; $inRawHtml = ($t -notmatch '</(style|div)>\s*$'); continue }
        if ($inRawHtml) { $h += $t; continue }
        if ($t -match '^```') { 
            if ($inTable) { $h += Build-TableHtml $tableRows; $inTable = $false; $tableRows = @() }
            $inCode = -not $inCode
            if ($inCode) { $h += '<pre>' } else { $h += '</pre>' }; continue 
        }
        if ($inCode) { $h += [System.Net.WebUtility]::HtmlEncode($t) + "`n"; continue }
        if ($t -match '^#{1,6}\s') {
            if ($inTable) { $h += Build-TableHtml $tableRows; $inTable = $false; $tableRows = @() }
            $l = $matches[0].Trim().Length
            $txt = $t.Substring($l).Trim()
            $h += "<h$l>$txt</h$l>"
            continue
        }
        if ($t -match '^\|') {
            $cells = ($t -split '\|' | Select-Object -Skip 1 | Select-Object -SkipLast 1 | ForEach-Object { $_.Trim() })
            # Пропускаем строку-разделитель (|---|)
            if ($t -match '^\|[\s\-:]+\|') { continue }
            if (-not $inTable) { $inTable = $true; $tableRows = @() }
            $tableRows += ,$cells
            continue
        }
        if ($inTable) { $h += Build-TableHtml $tableRows; $inTable = $false; $tableRows = @() }
        $html = [System.Net.WebUtility]::HtmlEncode($t)
        $html = $html -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>'
        $html = $html -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
        $html = $html -replace '\*([^*]+)\*', '<em>$1</em>'
        $html = $html -replace '`([^`]+)`', '<code>$1</code>'
        if ($html -ne '') { $h += "<p>$html</p>" } else { $h += '<br>' }
    }
    if ($inTable) { $h += Build-TableHtml $tableRows }
    if ($inCode) { $h += '</pre>' }
    $h += '</body></html>'
    return $h -join "`n"
}

function Build-TableHtml {
    param([array]$Rows)
    if (-not $Rows -or $Rows.Count -eq 0) { return '' }
    $html = '<table>'
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $tag = if ($r -eq 0) { 'th' } else { 'td' }
        $html += '<tr>'
        foreach ($cell in $Rows[$r]) {
            # HtmlEncode сохраняет [ ] ( ) * ` — только экранирует < > & "
            $v = [System.Net.WebUtility]::HtmlEncode($cell)
            # Применяем markdown-форматирование ПОСЛЕ экранирования
            $v = $v -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
            $v = $v -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>'
            $v = $v -replace '`([^`]+)`', '<code>$1</code>'
            $html += "<$tag>$v</$tag>"
        }
        $html += '</tr>'
    }
    $html += '</table>'
    return $html
}


foreach ($md in $mdFiles) {
    $title = [System.IO.Path]::GetFileNameWithoutExtension($md.Name)
    $content = Get-Content -Path $md.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    $html = Convert-MdToHtml -Md $content -Title $title
    $outDir = $md.DirectoryName
    $htmlPath = Join-Path $outDir "$title.html"
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "HTML: $htmlPath"

    if (-not $SkipPdf) {
        if (Get-Command "wkhtmltopdf" -ErrorAction SilentlyContinue) {
            $pdfPath = Join-Path $outDir "$title.pdf"
            & wkhtmltopdf $htmlPath $pdfPath 2>&1 | Out-Null
            Write-Host "PDF:  $pdfPath"
        } else {
            $edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
            if (-not (Test-Path $edge)) { $edge = "C:\Program Files\Microsoft\Edge\Application\msedge.exe" }
            if (Test-Path $edge) {
                $pdfPath = Join-Path $outDir "$title.pdf"
                $absHtml = (Resolve-Path $htmlPath).Path
                & $edge --headless --no-pdf-header-footer --print-to-pdf="$pdfPath" "$absHtml" 2>&1 | Out-Null
                Write-Host "PDF:  $pdfPath"
            } else {
                Write-Host "PDF:  skipped (install wkhtmltopdf or Edge)"
            }
        }
    }
}
