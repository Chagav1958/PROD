---
name: sborka-skill
description: Сервис СБОРКА: сборка golden.exe и *.pbd, выход Exe_yyyy_mm_dd__hh_mm, режим GALAXY, объекты *_CHAGA, повышение версии в golden.srj. Используй ТОЛЬКО при команде СБОРКА, сборке exe/pbd, реже — как подэтап TASK-сессии для тестирования. Не используй для обычных задач.
---

# Сервис «СБОРКА»

> Полный источник: `C:\AIS\AI\Prod\docs\services\sborka.md` и `C:\AIS\AI\Prod\rules\sborka-rules.md`

## Назначение и команды

| Команда | Действие |
|---------|----------|
| `СБОРКА` | Обычная сборка: exe + pbd + вспомогательные файлы (dll, ini, ocx) |
| `СБОРКА GALAXY` | Сборка для тестирования на galaxy + создание SQL-аналогов `*_CHAGA` |
| `СБОРКА <путь>` | Сборка с указанием папки выхода |

**Гибрид TASK:** если идёт выполнение ТЗ (TASK) — СБОРКА может быть подрежимом для тестирования доработанных объектов. Это не отдельный однодневный сервис.

## Инструменты

- `C:\AIS\AI\Prod\scripts\Sborka-Golden.ps1 -TaskName <имя> [-RunBuild|-DryRun] [-OutDir <путь>]` — консольный
- `C:\AIS\AI\Prod\scripts\Show-Sborka-GUI.ps1` — ДО (параметры: имя задачи, папка выгрузки, вариант 1/2)
- OrcaScript: `C:\Program Files (x86)\Sybase\Shared\PowerBuilder\orcascr125.exe`

## Выход `Exe_yyyy_mm_dd__hh_mm`

- Формат имени как у `Test_*`. Если папка за дату есть — создать новую с суффиксом времени (`_hh_mm`)
- Содержимое: `golden.exe`, `*.pbd`, `*.dll`, `*.ini`, `*.ocx`, `RELEASE_NOTES.txt`
- Копирование вспомогательных файлов из `C:\Work\gold\golden_start\EXE`

## Перед генерацией — golden.srj

| Поле | Требование |
|------|------------|
| `Copyright` | `(c) <сегодняшняя дата> Renaissance Insurance AI` |
| `Product version` / `File version` | Повышаются (X.Y.Z → X.Y.Z+1; File version в двух местах) |

Версия читается из `golden.srj` (`PVS`/`PVN`/`FVS`/`FVN`).

## Prинцип работы (OrcaScript)

- Генерация `.PBS` в `temp\sborka\sborka_*.pbs`: `start session`, `set liblist` (33 библиотеки из `gold.pbt`), `set application`, `set exeinfo property`, `build executable`
- `PbdFlags`: `N` для `golden_start.pbl` (в exe), `Y` для остальных (pbd)
- Комментарии в .PBS только `//` (символ `#` не поддерживается → Command syntax error)
- **Критично:** запускать `orcascr125.exe` из рабочего каталога `C:\Work\gold` (относительные пути liblist)
- Запуск из PS: `cmd /c "orcascr125.exe file.pbs > log 2>&1"` (прямой вызов PS ломает захват stdout)

## Режим GALAXY

НЕЛЬЗЯ менять рабочие SQL-объекты для теста в galaxy. Аналоги создаются с суффиксом **`_CHAGA`** (`usp_..._CHAGA`, `v_..._CHAGA`). Порядок:
1. Экспорт рабочих SQL из dev_golden
2. Создание `*_CHAGA`
3. Изменения ТОЛЬКО в `*_CHAGA`
4. PB-объекты в сборке вызывают `*_CHAGA`
5. Сборка exe
6. Тест на galaxy параллельно рабочему процессу
7. После подтверждения — перенос в рабочие объекты и снятие `_CHAGA`

## Проверка результата

- `golden.exe` существует, не пустой
- Список `*.pbd` совпадает с библиотеками workspace
- Продукт/File version увеличены, Copyright с сегодняшней датой
- Все dll/ini/ocx из EXE-набора присутствуют

## Документирование

- `RELEASE_NOTES.txt` — обязателен (версия, состав, дата, режим обычная/GALAXY)
- В `Describe\` — запись «СБОРКА YYYY-MM-DD HH:MM: версия X.Y.Z, состав, результат»