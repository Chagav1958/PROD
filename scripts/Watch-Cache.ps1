# Фоновый монитор кэша OpenCode — удаляет новые файлы мгновенно
# Запускать перед Start-OpenCode.ps1, убивать после закрытия OpenCode
$cacheDir = "C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\Cache\Cache_Data"

while ($true) {
    if (Test-Path $cacheDir) {
        try {
            Get-ChildItem $cacheDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Start-Sleep -Milliseconds 500
}