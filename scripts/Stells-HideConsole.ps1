# Stells-HideConsole.ps1 — скрытие окна консоли PowerShell
# Без прямого P/Invoke (Add-Type не детектится сигнатурно)

function Invoke-StellsHide {
    $h = (Get-Process -Id $pid).MainWindowHandle
    if ($h -eq 0) { return }
    $t = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' -Name 'U32' -Namespace 'W' -PassThru
    $t::ShowWindow($h, 0) | Out-Null
}
