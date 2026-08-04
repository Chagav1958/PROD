# Отложенные задачи

### ais-objects-init — наполнение MCP-сервера ais-objects (папка: ais-objects-init, 02.08.2026)

- **Статус:** [x] завершена (КТ-0..7 все выполнены, КТ-8 отложена)
- **Суть:** Наполнить БД objects.db анализами, связями, свойствами для всех 8464 объектов PB/SQL. 8 контрольных точек.
- **MCP:**
  - `ais-catalog_search_knowledge("ais-objects-init")` → знание id 194, 195
  - `ais-objects` — сам сервер (объекты, сравнение, анализ)
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\ais-objects-init`
- **Как возобновить:**
  1. `ais-catalog_search_knowledge("ais-objects-init")`
  2. Прочитать `tasks\ais-objects-init\ПЛАН_РЕАЛИЗАЦИИ.txt` + `work_journal.md`
  3. Продолжить с раздела «СЛЕДУЮЩИЙ ШАГ»
- **Продолжение только по команде** «продолжить ais-objects-init». Автопродолжение запрещено.
- **Следующий шаг:** КТ-1 — анализ PB-библиотек (описание 33 библиотек, ключевые объекты)

### TASKPLAN-001 — переработка TaskPlan в диспетчер задач (папка: TASKPLAN-001, 19.07.2026)

- **Статус:** [x] завершена (03.08.2026, все этапы выполнены)
- **Суть:** текущий TaskPlan — трекер этапов одной задачи. Нужен диспетчер множества задач: создание с промптом, переключение, остановка/возобновление, список невыполненных, удаление/редактирование промпта.
- **Реализация:**
  - `TaskPlan-Tracker.ps1` — ядро логики (actions: new, add, set, show, next, sync)
  - `TaskPlan-Manager.ps1` — консольный менеджер множества задач (create, list, show, switch, suspend, resume, edit-prompt, delete) + `task_index.json`
  - `Show-TaskPlanGUI.ps1` — WPF ДО с 4 вкладками: «Список задач», «Управление», «Тесты», «Импорт из TASK»
  - `Show-TaskPlan.ps1` — лаунчер
  - `TaskPlan-PrepareBrief.ps1` — подготовка брифов для дорогих LLM
  - `TaskPlan-Tests.ps1` — 15 автотестов (трекер + GUI Automation)
  - `TaskPlan-Logger.ps1` — логирование для OUTPL
  - `TaskPlan-Import.ps1` — импорт TASK-задач в TaskPlan
- **Документация:** `docs\taskplan-gui-guide.md` / `.html` / `.pdf`
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\TASKPLAN-001`
- **Продолжение только по команде** «продолжить TASKPLAN-001»

### TASKFIX — TimeFIX (Show-TimeFIX.ps1) (папка: TASKFIX, 23.07.2026)

- **Статус:** восстановление после удаления антивирусом (Bug-063/064/065)
- **Суть:** WPF-календарь "TimeFIX" с интеграцией Outlook OLE, weekly view, автопроверка Дейли AIS 9:30
- **Файлы:** `bin\Show-TimeFIX.ps1` (BOM), `bin\Show-TimeFIX.vbs`, `bin\Show-TimeFIX.bat` (base64)
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\TASKFIX`
- **Как возобновить:**
  1. `ais-catalog_search_knowledge("TASKFIX")` + `opencode-mcp_get_knowledge(83)`
  2. Прочитать `tasks\TASKFIX\Describe\TASKFIX_analysis.txt`
  3. Продолжить с раздела "СЛЕДУЮЩИЙ ШАГ"
- **Продолжение только по команде** «продолжить TASKFIX»
- **Следующий шаг:** запустить Show-TimeFIX.ps1, проверить загрузку календаря, Дейли AIS, привязку DatePicker

### SYBASE-19371-MORDA2 — Миграция МОРДА в СТАНДАРТ2 (МОРДА2) (папка: SYBASE-19371_19365, 31.07.2026)

- **Статус:** [x] завершена (03.08.2026, все этапы выполнены)
- **Суть:** Миграция функционала МОРДА (СТАНДАРТ1, Prod-GUI.ps1) в МОРДА2 (СТАНДАРТ2, Prod-GUI_STANDART2.ps1). Новое окно WPF с полным набором операций.
- **Решение блокировки UI:** async-версия — операции в фоновом Runspace (Start-OpAsync), UI-поток опрашивает завершение через DispatcherTimer, прогресс читается из Runspace (PhaseProgress/StepProgress) + пульс до 90%. Автотест 9/9 PASS (0 failed, 0 blocked), ПБ работает в реальном времени (10%→16%→22%→...→100%).
- **Файлы:**
  - `bin\Prod-GUI_STANDART2.ps1` — основной скрипт (async-версия, 01.08.2026)
  - `bin\Prod-GUI_STANDART2.vbs` — VBS-лаунчер
  - `bin\Prod-GUI_STANDART2.bat` — бат-лаунчер
  - `scripts\Standard2-Helpers.ps1` — хелперы СТАНДАРТ2
  - `scripts\Settings-Module.ps1` — модуль настроек
  - `temp\AutoTest-Morda2-Real.ps1` — автотест (9/9 PASS)
- **MCP:** `ais-catalog_search_knowledge("SYBASE-19371")` → знания id 192, 193 (описание проблемы до async-решения)
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\SYBASE-19371_19365`
- **Опционально (не обязательно):** запустить Export Service с -IncludeLong (~41 мин) для полного покрытия

---

### SYBASE-19371-v_rule — рефакторинг v_rule_dim_dictionary (папка: SYBASE-19371_19365, 17.07.2026)

- **Статус:** анализ завершён, реализация отложена (возможно на другой LLM)
- **Суть:** `w_rule_dimension` — задуманный единый центр настройки параметров правил (таблица `rule_dimension`). View `v_rule_dim_dictionary` стал параллельной точкой ручной правки в обход центра, т.к. штатный механизм `dictionary_table/key_column/name_column` в `rule_dimension` нигде не читается кодом, а значения захардкожены в view.
- **Вывод:** полностью удалить view нельзя (унифицирующий слой для 68 SQL + ~20 DataWindow, есть «виртуальные» значения без таблицы-источника). Нужно оздоровить: оживить `dictionary_table` и генерировать view автоматически.
- **Как возобновить (Knowledge First):**
  1. `ais-catalog_search_knowledge("SYBASE-19371")` → знания id 164 (архитектура), 165 (вывод + варианты A/B/C), 166 (карта воздействия), 167 (точка возобновления)
  2. `ais-catalog_get_business_rules("rule_dimension")`
  3. Файлы: `C:\AIS\1 Release\SYBASE-19371_19365\Describe\v_rule_dim_dictionary_анализ.txt`, `ПЛАН_РЕАЛИЗАЦИИ.txt`
- **Папка задачи:** `C:\AIS\1 Release\SYBASE-19371_19365` (второе имя `_19365` = родительская задача SYBASE-19365 с описанием ТЗ). НЕ создавать `SYBASE-19371` — использовать существующую папку с префиксом.
- **Продолжение только по команде** «продолжить SYBASE-19371-v_rule». Автопродолжение запрещено. Выбор варианта A/B/C — за аналитиком.
- **Следующий шаг:** уточнить у аналитика вариант A/B/C и сверить постановку (по коду `w_rule_dimension_select` читает `rule_dimension`, а не view); по правилу TASK выгрузить оригиналы в `Git_YYYY_MM_DD`; реализовать; регресс расшифровки условий ДО/ПОСЛЕ.
- **Рекомендация:** Вариант B (нормализовать значения в таблицу `rule_dim_dictionary_values` + задействовать `dictionary_table`, настройка только через `w_rule_dimension`).

### Отложенные задачи (08.07.2026)

#### 1. API-ключ Anthropic (Claude) через прокси artemox.com
- **Провайдер:** `anthropic` в `opencode.jsonc` (npm: `@ai-sdk/anthropic`)
- **URL:** `https://api.artemox.com/v1`
- **Ключ:** `sk-77IeZV8I3oiR4k5xtxLmlw` (сохранён в `ANTHROPIC_API_KEY`)
- **Модели:** `claude-3-5-sonnet-20241022`, `claude-3-7-sonnet-latest`
- **Статус:** не работает — SSL/TLS connection timeout (firewall блокирует artemox.com)
- **Для решения:** открыть доступ к api.artemox.com в корпоративном firewall или получить другой ключ

#### 2. Единый API-ключ (OpenAI/Claude/Gemini/DeepSeek/xAI) через прокси artemox.com
- **Провайдер:** `artemox` в `opencode.jsonc` (npm: `@ai-sdk/openai-compatible`)
- **URL:** `https://api.artemox.com/v1`
- **Ключ:** `sk-y2qskw8url1cuaULWvKJcg` (сохранён в `ARTEMOX_API_KEY`)
- **Модели:** deepseek-chat, deepseek-coder, gpt-4o, gpt-4o-mini, claude-3-5-sonnet, claude-3-7-sonnet, gemini-1.5-pro, grok-1
- **Панель управления:** https://artemox.com/ui (user: z2036w9gjzce5r-20jcjq6@artemox.com)
- **Статус:** не работает — SSL/TLS connection timeout (firewall блокирует artemox.com)
- **Для решения:** открыть доступ к api.artemox.com в корпоративном firewall или получить другой ключ