# Правило: Сервис СБОРКА

## Назначение

Сборка `golden.exe` и `*.pbd` из объектов PB для задач `TASK`, `SYBASE-*`, `SUPRT-*`.

**Спецификация:** `docs/services/sborka.md`

## Краткое правило

| Команда | Действие |
|---------|----------|
| `СБОРКА` | Открыть ДО `Show-Sborka-GUI.ps1` (имя задачи, папка выгрузки, вариант 1/2) |
| `СБОРКА GALAXY` | Сборка + тестирование на galaxy параллельно рабочему процессу |
| `СБОРКА DEBUG` | Debug-сборка |

## Инструменты

| Инструмент | Назначение |
|-----------|------------|
| `C:\AIS\AI\Prod\scripts\Show-Sborka-GUI.ps1` | ДО: параметры, фоновый запуск, лог, прогресс |
| `C:\AIS\AI\Prod\scripts\Sborka-Golden.ps1` | Консольный скрипт: `-TaskName` (имя задачи), `-OutDir` (папка выгрузки), `-DryRun` (вариант 1, PBS без сборки) / `-RunBuild` (вариант 2, сразу собрать) |
| `C:\Program Files (x86)\Sybase\Shared\PowerBuilder\orcascr125.exe` | OrcaScript PB 12.5 — генерация exe + pbd |

Запуск из рабочего каталога `C:\Work\gold` (относительные пути в liblist). Комментарии `.PBS` — только `//`.

## Выходной каталог

`Exe_yyyy_mm_dd__hh_mm` — по тем же правилам, что и `Test_yyyy_mm_dd`.

## Версия

- Copyright: `(c) dd.mm.yyyy Renaissance Insurance AI` (сегодняшняя дата)
- Product/File version: повышается на 1 с каждой сборкой
- Источник версии: `golden.srj` (библиотека `golden_start`)

## Режим GALAXY

- SQL-объекты создаются с суффиксом `_CHAGA`
- PB-объекты сборки вызывают **только** `_CHAGА` версии SQL-объектов
- Изменение рабочих SQL-объектов в galaxy **запрещено**
