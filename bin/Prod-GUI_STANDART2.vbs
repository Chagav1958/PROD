' VBS Launcher for МОРДА2 — скрытый запуск без видимых окон
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell -NoLogo -ExecutionPolicy RemoteSigned -File ""C:\AIS\AI\Prod\bin\Prod-GUI_STANDART2.ps1""", 0, False
