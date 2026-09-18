---
name: out-obr-skill
description: Анализ свежего вывода операций и автоисправление ошибок: команды ОБР/OUT/OUTPL, чтение temp\last_output.log и tech_journal_*.log, распознавание ошибок, циклы автоисправления ЦИКЛ N. Используй ТОЛЬКО при командах ОБР, OUT, OUTPL, ОБРВСЕ, ЦИКЛ, анализе журналов операций GUI. Не используй для обычных вопросов.
---

# ОБР / OUT / OUTPL — анализ вывода и диагностика

> Полный источник: `C:\AIS\AI\Prod\AGENTS.md` (команды OUT/ОБР, OUTPL) и `C:\AIS\AI\Prod\scripts\Out-LastOutput.ps1`

## Команды

| Команда | Суть |
|---------|------|
| **OUT / ОБР** | Анализ свежего вывода: `scripts\Out-LastOutput.ps1` |
| **ОБРВСЕ** | Анализ ошибки → исправить → проверить |
| **OUTPL** | Анализ ошибок TaskPlan: `Out-TaskPlan.ps1` (лог `temp\taskplan_last_output.log`) |

## Out-LastOutput.ps1 сам выбирает источник

- **МОРДА** (STANDART1): `temp\last_output.log` (заголовок `=== AIS Output Log ===`)
- **МОРДА2** (STANDART2): свежий `%TEMP%\tech_journal_*.log` (первая строка `[..] [INFO] MORDA started (ST2)`) за последние 2 часа

## Порядок действий при ОБР

1. Запустить `powershell -NoLogo -File C:\AIS\AI\Prod\scripts\Out-LastOutput.ps1`
2. Найти ошибку/исключение в журнале
3. Проанализировать причину (искать в `search_bug` / Knowledge First)
4. Исправить код
5. Повторить операцию и убедиться, что ошибки нет

## ЦИКЛ N — автоисправление операции

`ЦИКЛ <номер_ОП>` → запуск `scripts\auto_fix_loop.ps1 -OpNumber N` → чтение `temp\last_output.log` → исправление и повтор (макс. 100 итераций). Критерий успеха: `SUCCESS: Операция выполнена`/`эмулирована`. Таймаут команды ≥ 300000 ms; внутренний таймаут 180000 ms (обычные ОП), infinite для диалоговых (ОП 18).

## OUTPL (TaskPlan)

- 8 типов ошибок: TASK_PATH_ERROR, TRACKER_MISSING_PLAN, TRACKER_JSON_ERROR, GUI_LAUNCH_FAIL, GUI_AUTOMATION_FAIL, PS51_SYNTAX_ERROR, TEST_FAILURE, LOGGER_MISSING
- Диагностика `[ERROR]+[FIX]` по каждому типу
- `-AutoFix` убивает зависшие GUI-процессы
- Fix Cycle: `Out-TaskPlan-FixCycle.ps1`

## Важно

- Запуск PS через bash: `powershell -NoLogo -File ...` (НИКОГДА `-NoProfile` — Bug-046)
- Кракозябры в выводе → проверить `[Console]::OutputEncoding`, убрать `-NoProfile`