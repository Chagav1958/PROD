# Каталог сервисов и исполняемых файлов проекта AIS

**Дата обновления:** 14.09.2026  
**Всего сервисов:** 24

---

## Содержание

1. [Консольные сервисы](#1-консольные-сервисы)
2. [WPF приложения](#2-wpf-приложения)
3. [Git хуки](#3-git-хуки)

---

## 1. Консольные сервисы

### 1.1. Library (Сервис «Библиотека»)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\services\Library\Library\Library.csproj` |
| **Описание** | Сканирование docs/ и Specs/ для создания каталога документации в форматах MD, HTML, PDF |
| **Входные файлы** | `docs\*.md`, `docs\*.html`, `docs\*.pdf`, `C:\AIS\AI\Test\Specs\*` |
| **Выходные файлы** | `docs\catalog.md`, `docs\catalog.html`, `docs\catalog.pdf` |
| **Фреймворк** | .NET 6.0 |
| **Зависимости** | PdfSharpCore |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\services\Library\Library
dotnet run
```

---

### 1.2. SqlExport (Экспорт SQL объектов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\SqlExport\SqlExport.csproj` |
| **Описание** | Экспорт SQL-объектов из Sybase ASE через SQL_exp_param.bat (восстановлено 01.09.2026: Found 2250 / OK 2250) |
| **Параметры вызова** | `server`, `db`, `password`, `exportPath`, `objectType (optional)` |
| **Выходные файлы** | Экспортированные SQL объекты |
| **Фреймворк** | .NET 6.0 |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\SqlExport
dotnet run -- <server> <db> <password> <exportPath> [objectType]
```

---

### 1.3. CountToken (Подсчёт токенов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\CountToken\CountToken.csproj` |
| **Описание** | Подсчёт токенов текста с использованием SharpToken |
| **Параметры вызова** | `model (optional, default: cl100k_base)`, `file path или stdin` |
| **Выходные файлы** | JSON: `{model, tokens, chars}` |
| **Фреймворк** | .NET 6.0 |
| **Зависимости** | SharpToken |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\CountToken
dotnet run -- [model] <file.txt>
```

---

### 1.4. ExportFull (Полный экспорт PB/SQL)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\ExportFull\ExportFull.csproj` |
| **Описание** | Полный экспорт всех PB и SQL объектов из БД каталога в JSON файлы |
| **Входные файлы** | `C:\AIS\AI\Prod\scripts\ais_objects_mcp\objects.db` |
| **Выходные файлы** | `temp\pb_full.json`, `temp\sql_full.json` |
| **Фреймворк** | .NET 6.0 |
| **Зависимости** | Microsoft.Data.Sqlite |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\ExportFull
dotnet run
```

---

## 2. WPF приложения

### 2.1. Show-Abbreviations-CS (Сокращения)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Abbreviations-CS\Show-Abbreviations.csproj` |
| **Описание** | Просмотр сокращений проекта. Загружает данные из abbreviations_data.json |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `config\abbreviations_data.json` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Abbreviations-CS
dotnet run
```

---

### 2.2. Show-Diagrams-CS (Диаграммы)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Diagrams-CS\Show-Diagrams.csproj` |
| **Описание** | Просмотрщик диаграмм (Mermaid, PlantUML, Graphviz DOT, SVG) |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `C:\AIS\AI\Visualization\diagrams\*`, `C:\AIS\AI\BP\docs\*` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Diagrams-CS
dotnet run
```

---

### 2.3. Show-LLMs-CS (Тестирование LLM)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-LLMs-CS\Show-LLMs.csproj` |
| **Описание** | Тестирование доступности LLM моделей. Загружает конфиг из opencode.jsonc |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `opencode.jsonc` |
| **Выходные файлы** | `temp\llm_test_results.json` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-LLMs-CS
dotnet run
```

---

### 2.4. Show-TaskPlan-CS (Лаунчер TaskPlan)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-TaskPlan-CS\Show-TaskPlan.csproj` |
| **Описание** | Лаунчер TaskPlan — запускает Show-TaskPlanGUI.ps1 |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-TaskPlan-CS
dotnet run
```

---

### 2.5. Show-Report-CS (Отчёт по задаче)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Report-CS\Show-Report.csproj` |
| **Описание** | WPF окно отчёта по задаче — показывает изменённые объекты |
| **Параметры вызова** | `taskName`, `--autotest <file> (optional)` |
| **Входные файлы** | `C:\AIS\1 Release\<taskName>\*` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Report-CS
dotnet run -- <taskName>
```

---

### 2.6. Show-Rules-CS (Правила)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Rules-CS\Show-Rules.csproj` |
| **Описание** | Просмотрщик правил проекта (.mdc файлы). Группирует по категориям |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `.opencode\*.mdc`, `rules\*.mdc` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Rules-CS
dotnet run
```

---

### 2.7. Show-OpStatus-CS (Статус операций)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-OpStatus-CS\Show-OpStatus.csproj` |
| **Описание** | Дерево объектов с цветовой маркировкой статусов (OK, FIX, ERROR, SKIP) |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `config\operation_status.json` |
| **Выходные файлы** | `config\operation_status.json` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-OpStatus-CS
dotnet run
```

---

### 2.8. Show-TimeFIX-CS (Календарь + EWS)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-TimeFIX-CS\Show-TimeFIX.csproj` |
| **Описание** | Календарь рабочей недели с интеграцией EWS (Exchange) |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-TimeFIX-CS
dotnet run
```

---

### 2.9. Show-ProgressState-CS (Индикатор прогресса)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-ProgressState-CS\Show-ProgressState.csproj` |
| **Описание** | Опрашивает temp\progress_state.json и показывает прогресс-бары задач |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `temp\progress_state.json` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-ProgressState-CS
dotnet run
```

---

### 2.10. Show-Appl2Standard-CS (Миграция объектов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Appl2Standard-CS\ShowAppl2Standard.csproj` |
| **Описание** | Миграция объектов Application → Standard. Таблица объектов с фильтрацией |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Appl2Standard-CS
dotnet run
```

---

### 2.11. Show-Prompts-CS (Промпты)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Prompts-CS\Show-Prompts.csproj` |
| **Описание** | Просмотрщик промптов пользователя. Загружает из temp\user_prompts.log |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `temp\user_prompts.log` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Prompts-CS
dotnet run
```

---

### 2.12. Show-RestoreDialog-CS (Восстановление из снапшотов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-RestoreDialog-CS\ShowRestoreDialog.csproj` |
| **Описание** | Диалог восстановления OpenCode из снапшотов |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `archives\OpenCode\Snapshot_*\*` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-RestoreDialog-CS
dotnet run
```

---

### 2.13. Show-TestMsg-CS (Тестовое окно)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-TestMsg-CS\Show-TestMsg.csproj` |
| **Описание** | Тестовое окно с прогресс-барами и анимацией. Для отладки GUI |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-TestMsg-CS
dotnet run
```

---

### 2.14. Show-Report-Launcher-CS (Лаунчер отчётов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-Report-Launcher-CS\Show-Report-Launcher.csproj` |
| **Описание** | Выбор задачи из C:\AIS\1 Release и запуск Show-Report.ps1 |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `C:\AIS\1 Release\SYBASE-*\*`, `C:\AIS\1 Release\SUPRT-*\*` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-Report-Launcher-CS
dotnet run
```

---

### 2.15. Show-RestoreFromBackup-CS (Восстановление из бэкапов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-RestoreFromBackup-CS\ShowRestoreFromBackup.csproj` |
| **Описание** | Восстановление критичных файлов из бэкапов |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `archives\SNAPSHOT\*`, `Restore\*`, `archives\FIX\*` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-RestoreFromBackup-CS
dotnet run
```

---

### 2.16. Show-TaskPlanGUI-CS (GUI TaskPlan)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\Show-TaskPlanGUI-CS\Show-TaskPlanGUI.csproj` |
| **Описание** | GUI для TaskPlan — список скриптов и файлов задачи |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `scripts\*.ps1` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\Show-TaskPlanGUI-CS
dotnet run
```

---

### 2.17. SetupSecrets (Настройка секретов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\SetupSecrets\SetupSecrets.csproj` |
| **Описание** | Шифрование/дешифрование паролей Sybase, VSS, Jira, EWS |
| **Параметры вызова** | `--autotest <file> (optional)` |
| **Входные файлы** | `config\.local_secrets.json`, `~\.config\ews-mcp\credentials.env` |
| **Выходные файлы** | `config\.local_secrets.json`, `~\.config\ews-mcp\credentials.env` |
| **Фреймворк** | .NET 6.0-windows |

**Запуск:**
```bash
cd C:\AIS\AI\Prod\scripts\SetupSecrets
dotnet run
```

---

## 3. Git хуки

### 3.1. PreCommitHook (Блокировка секретов)

| Параметр | Значение |
|----------|----------|
| **Путь** | `C:\AIS\AI\Prod\scripts\PreCommitHook\PreCommitHook.csproj` |
| **Описание** | Блокирует коммиты с паролями, токенами, логинами, API-ключами |
| **Входные файлы** | git staged files |
| **Фреймворк** | .NET 6.0 |

**Установка:**
```bash
# Скопировать в .git/hooks/pre-commit
```

---

## 4. Сервисы задач (TASK)

> Полные спецификации: [sborka.md](services/sborka.md) (СБОРКА), [extra.md](services/extra.md) (ЭКСТРА)

### 4.1. СБОРКА (Сборка дистрибутива PB)

| Параметр | Значение |
|----------|----------|
| **Описание** | Сборка `golden.exe` + `*.pbd` + вспомогательных файлов (dll/ini/ocx) из исходных PB-объектов и свежих объектов из `Test_*` |
| **Выходные файлы** | `Exe_yyyy_mm_dd__hh_mm\` (по правилам папок `Test_`), `RELEASE_NOTES.txt` |
| **Входные файлы** | `C:\AIS\AI\Prod\PB_Current\*`, `C:\SRC125\gold\*`, `Test_*\*`, `C:\Work\gold\golden_start\EXE\*` |
| **Версионирование** | `golden.srj` (библиотека `golden_start`): Copyright `(c) dd.mm.yyyy Renaissance Insurance AI`; Product/File version повышаются с каждой сборкой |
| **Режимы** | `СБОРКА` (обычная), `СБОРКА GALAXY` (тестирование на galaxy), `СБОРКА DEBUG` |
| **Режим GALAXY** | SQL-объекты для теста создаются с суффиксом `_CHAGA`; PB-объекты сборки вызывают только `*_CHAGA` версии; рабочие SQL-объекты в galaxy НЕ изменяются |

**Команды:**
```bash
СБОРКА            # обычная сборка
СБОРКА GALAXY     # сборка для тестирования на сервере galaxy
СБОРКА DEBUG      # debug-сборка
```

---

### 4.2. ЭКСТРА (Экстренный однодневный режим SQL)

| Параметр | Значение |
|----------|----------|
| **Описание** | Экстренный режим (1 день), разрешающий LLM выполнять SELECT-запросы к БД для анализа и поиска решений по ТЗ |
| **Длительность** | Только день, объявленный «ЭКСТРА» |
| **Доступ** | Исключительно `SELECT` (только чтение); всё остальное запрещено |
| **Безопасность данных** | Без конфиденциальной информации: без имён, документов, номеров полисов/договоров, сумм, адресов, телефонов, email; текстовые поля не более 10 символов |
| **Назначение** | Анализ ТЗ, поиск решений, когда иначе не обойтись и время критически не хватает |

**Запрещено:** INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, TRUNCATE, EXEC и любые другие команды.

---

## Статистика

| Тип | Количество |
|-----|------------|
| Консольные сервисы | 5 |
| WPF приложения | 17 |
| Git хуки | 1 |
| Сервисы задач (TASK) | 2 |
| **Итого** | **24** |

---

## Связанные документы

- [Каталог документации](catalog.md) — MD/HTML/PDF каталог всей документации
- [rules/abbreviations.md](../rules/abbreviations.md) — Сокращения проекта
- [AGENTS.md](../AGENTS.md) — Правила проекта
