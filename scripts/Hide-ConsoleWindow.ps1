# Hide-ConsoleWindow.ps1 — устаревшая обёртка (DEPRECATED)
# Используйте Stells-HideConsole.ps1 + Invoke-StellsHide
# Оставлено для обратной совместимости (Prod-GUI.ps1, voice-prompt.ps1)

. (Join-Path $PSScriptRoot "Stells-HideConsole.ps1")

function Hide-ConsoleWindow {
    Invoke-StellsHide
}
