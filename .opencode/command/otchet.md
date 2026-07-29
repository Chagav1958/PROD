---
description: "Открывает WPF-диалоговое окно отчёта по задаче. Формат: ОТЧЕТ [имя_задачи] или ОТЧЁТ [имя_задачи]."
---

# ОТЧЕТ / ОТЧЁТ

Если имя задачи указано после команды (например `ОТЧЕТ SYBASE-19298`), запусти скрытно (антивирус) с параметром `-TaskName`:
```
powershell -NoProfile -File scripts\Launch-Hidden.ps1 -Script "Show-Report.ps1" -Arguments "-TaskName <имя_задачи>"
```

Если имя задачи НЕ указано (просто `ОТЧЕТ`), запусти лаунчер:
```
powershell -NoProfile -File scripts\Launch-Hidden.ps1 -Script "Show-Report-Launcher.ps1"
```

Если скрипт не найден — сообщи что файл `Show-Report.ps1` не найден в папке `scripts\`.
