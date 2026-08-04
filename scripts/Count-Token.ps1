# Count-Token.ps1 — подсчёт токенов через tiktoken (OpenAI)
# Использование: Count-Token.ps1 [-Text "текст"] [-File "путь"] [-Model "cl100k_base"]
# Требуется: pip install tiktoken
# Переносимый: все пути относительные, авто-кэш кодировки через PowerShell

param(
    [string]$Text,
    [string]$File,
    [string]$Model = "cl100k_base"
)

if (-not $Text -and -not $File) {
    Write-Host "Count-Token.ps1 — подсчёт токенов через tiktoken (OpenAI/Claude)" -ForegroundColor Cyan
    Write-Host "  -Text `"строка`"      — текст для подсчёта" -ForegroundColor Gray
    Write-Host "  -File путь           — файл для подсчёта" -ForegroundColor Gray
    Write-Host "  -Model имя           — модель токенизации (по умолч. cl100k_base)" -ForegroundColor Gray
    Write-Host "  Пример: .\Count-Token.ps1 -File temp\prompt.txt" -ForegroundColor Gray
    exit 0
}

$input = ""
if ($Text) { $input = $Text }
if ($File) { $input = Get-Content -LiteralPath $File -Raw }

if (-not $input) {
    Write-Host "Ошибка: нет входных данных" -ForegroundColor Red
    exit 1
}

# Авто-кэш: скачать кодировку через PowerShell (сертификаты Windows), если ещё нет
$cacheDir = "$env:TEMP\data-gym-cache"
$cacheUrl = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken"
$cacheKey = "9b5ad71b2ce5302211f9c61530b329a4922fc6a4"
$cacheFile = "$cacheDir\$cacheKey"
if (-not (Test-Path $cacheFile)) {
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    try { Invoke-WebRequest -Uri $cacheUrl -OutFile $cacheFile -UseBasicParsing | Out-Null }
    catch { Write-Host "Предупреждение: не удалось скачать кодировку в кэш" -ForegroundColor Yellow }
}

$env:TIKTOKEN_CACHE_DIR = $cacheDir

$pyScript = @"
import sys, json
import tiktoken
try:
    enc = tiktoken.get_encoding('$Model')
    text = sys.stdin.read()
    tokens = enc.encode(text)
    result = {'model': '$Model', 'tokens': len(tokens), 'chars': len(text)}
    print(json.dumps(result, ensure_ascii=False, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"@

$input | python -c $pyScript 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Ошибка tiktoken. Установи: pip install tiktoken" -ForegroundColor Red
}
