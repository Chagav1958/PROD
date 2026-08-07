' VBS Launcher для СТАНДАРТ2 — безопасный (Shell.Application, без WScript.Shell)
Set objShell = CreateObject("Shell.Application")
objShell.ShellExecute "powershell", "-NoLogo -ExecutionPolicy RemoteSigned -File ""C:\AIS\AI\Prod\bin\Prod-GUI_STANDART2.ps1""", "", "open", 1
