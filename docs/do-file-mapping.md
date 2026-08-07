# Соответствие исполняемых файлов и задач (ДО / DO)

## Назначение документа

Этот документ однозначно сопоставляет каждое исполняемое файловое ДО (диалоговое окно) с задачей Jira / внутренней задачей AIS. Используется при формировании промптов для LLM — чтобы однозначно понять, о каком интерфейсе идёт речь.

---

## Таблица: короткие имена ДО, отсортированные по задачам

### Задача: SYNTAX-19371-MORDA (МОРДА — STANDART1)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `MORDAS1` | SYNTAX-19371-MORDA | МОРДА (STANDART1) — главное окно мониторинга. Sync-версия: ПБ, ОП, ДО «Обработка», ДО «Экспорт». Файлы: `bin/Prod-GUI.bat`, `bin/Prod-GUI.ps1` |
| `MORDAS1L` | SYNTAX-19371-MORDA | Алиас STANDART1 (launcher): `bin/Prod-GUI_STANDART1.bat`, `bin/Prod-GUI_STANDART1.ps1`. Используется для быстрого переключения на STANDART1 |
| `PRODBTN` | SYNTAX-19371-MORDA | ПРОД (ProdObr) — диалог «Обработка»: операции PB/SQL (текущая/история). Вызывается командой `ПРОДОБР` из МОРДА. Файлы: `bin/Show-ProdObr.bat`, `scripts/Show-ProdObr-GUI.ps1` |

### Задача: SYNTAX-19371-MORDA2 (МОРДА2 — STANDART2, async)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `MORDAS2` | SYNTAX-19371-MORDA2 | МОРДА2 (STANDART2) — главное окно async: Runspace + DispatcherTimer, ПБ в реальном времени (10%→100%). Файлы: `bin/Prod-GUI_STANDART2.bat`, `bin/Prod-GUI_STANDART2.ps1`, `bin/Prod-GUI_STANDART2.vbs` |

### Задача: SYNTAX-* (SQL/PB экспорт)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `SQLEXP` | SYNTAX-* | SQL Export — выгрузка одного SQL-объекта из `dev_golden` через `isql`. Файл: `bin/SQL_exp_single.bat` |
| `PBEXP` | SYNTAX-* | PB Export — выгрузка PB-библиотек из `PB_Current`/`PB_Main`. Файл: `bin/AIS_export.bat` |

### Задача: TASKFIX (TimeFIX Calendar)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `TIMEFIX` | TASKFIX | TimeFIX Calendar — WPF-календарь: рабочая неделя (Mon-Fri, 8:00–19:00), интеграция с Outlook OLE, автопроверка Дейли AIS в 9:30. Файлы: `bin/Show-TimeFIX.bat`, `bin/Show-TimeFIX.ps1`, `bin/Show-TimeFIX.vbs` |

### Задача: TASKPLAN-001 (TaskPlan — планировщик задач)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `TASKPLN` | TASKPLAN-001 | TaskPlan GUI — ДО планировщика задач с 4 вкладками: «Список задач», «Управление», «Тесты», «Импорт из TASK». Файл: `scripts/Show-TaskPlanGUI.ps1` |
| `TASKPL` | TASKPLAN-001 | TaskPlan Launcher — скрытый лаунчер Show-TaskPlanGUI.ps1. Файл: `scripts/Show-TaskPlan.ps1` |

### Сервисные ДО (без привязки к задаче)

| Короткое имя | Задача | Описание |
|--------------|--------|----------|
| `OBJINFO` | (сервисное) | ObjectInfo GUI — справка по объектам PB/SQL: поиск по названию, содержит SQL, описание. Файлы: `bin/Show-ObjectInfo.bat`, `scripts/Show-ObjectInfo-GUI.ps1`, `bin/Show-ObjectInfo.exe` |
| `LLMMGR` | (сервисное) | LLM Manager — выбор и управление LLM-моделями, просмотр баланса и лимитов. Файл: `scripts/Show-LLMs.ps1` |
| `ABBRVI` | (сервисное) | СОКР (Abbreviations) — справочник сокращений проекта. Файл: `scripts/Show-Abbreviations.ps1` |
| `OPSTAT` | (сервисное) | ОП Status — график статуса операций ПБ в реальном времени. Файл: `scripts/Show-OpStatus.ps1` |
| `PBSTATE` | (сервисное) | ПБ State — индикатор состояния всех фоновых задач и ПБ. Файл: `scripts/Show-ProgressState.ps1` |
| `PROMTP` | (сервисное) | Промпты — управление промптами OpenCode: создание, редактирование, история. Файл: `scripts/Show-Prompts.ps1` |
| `REPORTS` | (сервисное) | Отчёты — просмотр и формирование отчётов по задаче. Файлы: `scripts/Show-Report.ps1`, `scripts/Show-Report-Launcher.ps1` |
| `RULES` | (сервисное) | Правила — просмотр бизнес- и технических правил проекта. Файл: `scripts/Show-Rules.ps1` |
| `RESTORE` | (сервисное) | Восстановление — диалог восстановления после аварии или удаления антивирусом. Файл: `scripts/Show-RestoreDialog.ps1` |

---

## Использование в промптах

В промптах для LLM используйте короткое имя в квадратных скобках `[NAME]`:

| Пример | Что обозначает |
|--------|----------------|
| `[MORDAS2]` | МОРДА2 (STANDART2) |
| `[MORDAS1]` | МОРДА (STANDART1) |
| `[TASKPLN]` | TaskPlan GUI |
| `[TIMEFIX]` | TimeFIX Calendar |
| `[PRODBTN]` | ПРОД (ProdObr) |
| `[OBJINFO]` | ObjectInfo GUI |
| `[SQLEXP]` | SQL Export |
| `[PBEXP]` | PB Export |
| `[LLMMGR]` | LLM Manager |
| `[ABBRVI]` | Справочник сокращений |
| `[OPSTAT]` | ОП Status |
| `[PBSTATE]` | ПБ State |
| `[PROMTP]` | Управление промптами |
| `[REPORTS]` | Отчёты |
| `[RULES]` | Правила проекта |
| `[RESTORE]` | Диалог восстановления |
