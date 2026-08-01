# Отложенные задачи

### TASKPLAN-001 — переработка TaskPlan в диспетчер задач (папка: TASKPLAN-001, 19.07.2026)

- **Статус:** план создан, реализация не начата
- **Суть:** текущий TaskPlan — трекер этапов одной задачи. Нужен диспетчер множества задач: создание с промптом, переключение, остановка/возобновление, список невыполненных, удаление/редактирование промпта.
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\TASKPLAN-001`
- **Продолжение только по команде** «продолжить TASKPLAN-001»
- **Следующий шаг:** Этап 2 — переписать TaskPlan-Tracker.ps1 в TaskPlan-Manager.ps1 (actions: create, list, switch, suspend, resume, edit-prompt, delete)

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

- **Статус:** в работе (блокировка UI при выполнении операций)
- **Суть:** Миграция функционала МОРДА (СТАНДАРТ1, Prod-GUI.ps1) в МОРДА2 (СТАНДАРТ2, Prod-GUI_STANDART2.ps1). Новое окно WPF с полным набором операций.
- **Проблема:** Окно блокируется при выполнении операций, PhaseBar = 0%
- **Возможная причина:** $script:PhaseBar не инициализирован или операция блокирует UI-поток
- **Файлы:**
  - `bin\Prod-GUI_STANDART2.ps1` — основной скрипт
  - `bin\Prod-GUI_STANDART2.vbs` — VBS-лаунчер
  - `bin\Prod-GUI_STANDART2.bat` — бат-лаунчер
  - `scripts\Standard2-Helpers.ps1` — хелперы СТАНДАРТ2
  - `scripts\Background-Runner.ps1` — фоновое выполнение (НЕ используется)
  - `scripts\Settings-Module.ps1` — модуль настроек
  - `temp\AutoTest-Morda2-Real.ps1` — автотест
- **Как возобновить (Knowledge First):**
  1. `ais-catalog_search_knowledge("SYBASE-19371")` → знание id 192
  2. Прочитать `tasks\SYBASE-19371_19365\ПЛАН_РЕАЛИЗАЦИИ.txt`
  3. Продолжить с раздела "СЛЕДУЮЩИЙ ШАГ"
- **Продолжение только по команде** «продолжить SYBASE-19371». Автопродолжение запрещено.
- **Следующий шаг:** проверить инициализацию $script:PhaseBar, добавить логирование ДО и ПОСЛЕ установки PhaseBar.Value

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