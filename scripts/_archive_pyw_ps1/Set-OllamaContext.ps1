param([switch]$Force)

# Создаёт кастомные модели Ollama с num_ctx под CPU (Intel i7-13700T, ~18 GB free RAM)
$models = @()
$models += @{N="qwen2.5-coder:14b"; C=16384}
$models += @{N="qwen2.5-coder:32b"; C=4096}
$models += @{N="qwen2.5-coder:7b"; C=16384}
$models += @{N="qwen2.5:7b"; C=16384}
$models += @{N="qwen2.5:1.5b"; C=32768}
$models += @{N="deepseek-coder-v2:16b"; C=32768}
$models += @{N="codellama:34b"; C=4096}
$models += @{N="llama3.2:3b"; C=32768}
$models += @{N="phi3:mini"; C=32768}
$models += @{N="llava:7b"; C=4096}

$tmp = Join-Path $env:TEMP "ollama_ctx"
if (-not (Test-Path $tmp)) { [void](New-Item -ItemType Directory -Path $tmp -Force) }

$r = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
$tags = $r.Content | ConvertFrom-Json
$existingNames = @()
foreach ($t in $tags.models) { $existingNames += $t.name }

foreach ($m in $models) {
    $orig = $m.N
    $cust = $orig + "-ctx" + $m.C

    $skip = $false
    foreach ($en in $existingNames) { if ($en -eq $cust) { $skip = $true } }

    if ($skip -and (-not $Force)) {
        Write-Host "[SKIP] $cust exists (use -Force to recreate)"
        continue
    }

    $mf = "FROM $orig`nPARAMETER num_ctx $($m.C)"
    $mfPath = Join-Path $tmp ($orig.Replace(':','_') + ".Modelfile")
    Set-Content -Path $mfPath -Value $mf -Encoding ASCII

    Write-Host "[CREATE] $orig -> $cust (num_ctx=$($m.C))..."
    $result = ollama create $cust -f $mfPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK"
    } else {
        Write-Host "  FAIL: $result"
    }
}

Write-Host ""
Write-Host "Done. Custom models with CPU-optimized context created."
Write-Host "If a model fails with OOM, remove it (ollama rm <name>)"
Write-Host "and use the original model in opencode.jsonc."
