# Convert-Docs.ps1 — конвертация docs\*.md → docs\*.html + docs\*.pdf
param(
    [string]$DocsDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "docs"),
    [switch]$SkipPdf
)

$scriptsDir = $PSScriptRoot
if (-not $scriptsDir) { $scriptsDir = 'C:\AIS\AI\Prod\scripts' }

$mdFiles = Get-ChildItem -Path $DocsDir -Filter "*.md" -ErrorAction SilentlyContinue
if (-not $mdFiles) { Write-Host "No .md files found in $DocsDir"; exit 0 }

function Convert-MdToHtml {
    param([string]$Md, [string]$Title)
    $h = @()
    $h += "<!DOCTYPE html><html><head><meta charset='utf-8'>"
    $h += "<title>$Title</title>"
    $h += "<style>body{font-family:Segoe UI,sans-serif;max-width:800px;margin:20px auto;padding:0 20px;line-height:1.6}"
    $h += "h1,h2,h3{color:#1a3a60}code{background:#f0f0f0;padding:2px 4px;border-radius:3px}"
    $h += "pre{background:#f5f5f5;padding:10px;border-radius:5px;overflow-x:auto}"
    $h += "table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:6px}</style></head><body>"
    $inCode = $false; $inTable = $false
    foreach ($line in $Md -split "`n") {
        $t = $line.TrimEnd()
        if ($t -match '^```') { $inCode = -not $inCode
            if ($inCode) { $h += '<pre>' } else { $h += '</pre>' }; continue }
        if ($inCode) { $h += [System.Net.WebUtility]::HtmlEncode($t) + "`n"; continue }
        if ($t -match '^#{1,6}\s') {
            $l = $matches[0].Trim().Length
            $txt = $t.Substring($l).Trim()
            $h += "<h$l>$txt</h$l>"
        } elseif ($t -match '^\|') {
            $cells = $t -split '\|' | Where-Object { $_ -ne '' }
            $tag = if (-not $inTable) { $inTable = $true; 'th' } else { 'td' }
            $h += "<tr><$tag>" + ($cells -join "</$tag><$tag>") + "</$tag></tr>"
        } else {
            if ($inTable -and $t -eq '') { $inTable = $false; continue }
            $html = [System.Net.WebUtility]::HtmlEncode($t)
            $html = $html -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>'
            $html = $html -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
            $html = $html -replace '\*([^*]+)\*', '<em>$1</em>'
            $html = $html -replace '`([^`]+)`', '<code>$1</code>'
            if ($html -ne '') { $h += "<p>$html</p>" } else { $h += '<br>' }
        }
    }
    if ($inCode) { $h += '</pre>' }
    $h += '</body></html>'
    return $h -join "`n"
}

foreach ($md in $mdFiles) {
    $title = [System.IO.Path]::GetFileNameWithoutExtension($md.Name)
    $content = Get-Content -Path $md.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }
    $html = Convert-MdToHtml -Md $content -Title $title
    $htmlPath = Join-Path $DocsDir "$title.html"
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "HTML: $htmlPath"

    if (-not $SkipPdf) {
        if (Get-Command "wkhtmltopdf" -ErrorAction SilentlyContinue) {
            $pdfPath = Join-Path $DocsDir "$title.pdf"
            & wkhtmltopdf $htmlPath $pdfPath 2>&1 | Out-Null
            Write-Host "PDF:  $pdfPath"
        } else {
            Write-Host "PDF:  skipped (install wkhtmltopdf)"
        }
    }
}
