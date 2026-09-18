---
name: taskplan-skill
description: Сервис TaskPlan — управление объёмными задачами через ДО: трекер этапов, диспетчер задач, автотесты, OUTPL-анализ ошибок. Используй ТОЛЬКО при командах TaskPl, работе с TaskPlan, ПЛАН_РЕАЛИЗАЦИИ.txt, plan_state.json, task_index.json, этапами [ ]/[~]/[x]/[!]. Не используй для обычных задач Jira.
---

# TaskPlan — планирование и управление задачами

> Полный источник: `C:\AIS\AI\Prod\docs\services\taskplan.md` и полное руководство `C:\AIS\AI\Prod\docs\taskplan-gui-guide.md`

## Файлы

- `C:\AIS\AI\Prod\scripts\Show-TaskPlanGUI.ps1` — WPF ДО (запуск: `TaskPl`)
- `C:\AIS\AI\Prod\scripts\TaskPlan-Tracker.ps1` — ядро логики этапов
- `C:\AIS\AI\Prod\scripts\TaskPlan-Manager.ps1` — диспетчер множества задач
- `C:\AIS\AI\Prod\scripts\TaskPlan-Tests.ps1` — 15 автотестов
- `C:\AIS\AI\Prod\scripts\TaskPlan-Logger.ps1` — единый лог `temp\taskplan_last_output.log`
- `C:\AIS\AI\Prod\scripts\Out-TaskPlan.ps1` — OUTPL-анализ ошибок лога

## Вкладки ДО

1. **Список задач** — таблица этапов с цветовой маркировкой + прогресс-бар
2. **Управление** — создание/редактирование планов, статусы, добавление этапов, «Подг. бриф», «Синхр. JSON»
3. **Тесты** — запуск полного цикла автотестов

## Статусы этапов

| Маркер | Статус | eng |
|--------|--------|-----|
| `[ ]` | не начат | todo |
| `[~]` | в работе | wip |
| `[x]` | готово | done |
| `[!]` | отложен на дорогую LLM | defer |

## Что создаёт «Новый план»

- Папка задачи (`Describe\`, `Git_YYYY_MM_DD`, `Test_YYYY_MM_DD`)
- `ПЛАН_РЕАЛИЗАЦИИ.txt` с чек-боксами
- `plan_state.json` — зеркало для ДО-индикатора

## Трекер (прямые вызовы)

```
& scripts\TaskPlan-Tracker.ps1 -Action new -TaskName X -Goal "..." -Stages @("S1","S2") -Force
```

Параметры: `-Action` (new|add|set|show|next|sync), `-TaskName`, `-Stages[]`, `-StageNum`, `-Status` (todo|wip|done|defer), `-DoneBy`, `-Goal`, `-ReleaseRoot`, `-Force`

## Диспетчер задач

- Хранит `task_index.json` в корне задач
- Команды: create, list, show, switch, suspend, resume, edit-prompt, delete
- Текущая задача — одна активная (`current`), остальные `paused`

## OUTPL — анализ ошибок

`Out-TaskPlan.ps1` читает `temp\taskplan_last_output.log`, распознаёт 8 типов ошибок (TASK_PATH_ERROR, TRACKER_MISSING_PLAN, TRACKER_JSON_ERROR, GUI_LAUNCH_FAIL, GUI_AUTOMATION_FAIL, PS51_SYNTAX_ERROR, TEST_FAILURE, LOGGER_MISSING), выдаёт `[ERROR]+[FIX]`. `-AutoFix` убивает зависшие GUI-процессы. Отчёт — `temp\taskplan_outpl_report.txt`.
Fix Cycle: `Out-TaskPlan-FixCycle.ps1 -RunTests [-RunTracker] [-RunGUI] -MaxIter N`.

## Автотесты

`powershell -NoLogo -File scripts\TaskPlan-Tests.ps1` — 15 тестов: трекер (создание, чтение, статусы, next, add, sync, show, brief) + GUI (запуск, поиск окна, закрытие).