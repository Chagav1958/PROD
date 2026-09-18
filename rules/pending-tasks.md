# Отложенные задачи

### dwDebug — сервис снимка/сравнения состояния объекта w_dwdebug (18.09.2026)

- **Статус:** [~] в работе — этап 1 (анализ и проектирование XML-схемы снимка) выполнен; ждёт утверждения схемы.
- **Задача:** доработать `w_dwdebug` (библиотека `dwdebugger`/`_dwdebugger`): сервис выгрузки состояния объекта в XML + сервис сравнения двух снимков (норма/баг) с отчётом «какой параметр изменился и на сколько».
- **Ключевое ограничение PB:** `Describe`/`Attributes`/`DataWindow.Objects` только для DataWindow; для контролов/окна/instance variables рефлексии в PB 12.5 нет — фиксированный список свойств или явный хук окна.
- **Папка задачи:** `C:\AIS\AI\Prod\tasks\dwDebug` (`Describe\ПЛАН_РЕАЛИЗАЦИИ.txt`, `Describe\w_dwdebug_анализ.txt`, `Git_2026_09_18\_dwdebugger` — 25 файлов оригиналов).
- **Точка возобновления:** утвердить XML-схему + перечень свойств контролов → этап 2 (`n_cst_debug_snapshot`).
- **Продолжение только по команде:** «продолжить dwDebug».
- **MCP:** `ais-catalog_search_knowledge("dwDebug")`.

### DOKI — Документация по сервисам PFC в проекте AIS (17.09.2026)

- **Статус:** [~] в работе — **серия собрана** (md+html+pdf+chm). Блок 1 (parmlinkage/resize/sort/rowmanager/extra/**rowselection**/**printpreview**) и Блок 2 (общее использование PFC) готовы. **Задача A (18.09.2026):** CHM через `hhc.exe` 4.74 — панели «Содержание» (иерархическая) / «Указатель» / «Поиск», русский заголовок. **Доработка (18.09.2026):** документы разбиты на темы (как PB docs), указатель/поиск ведут на страницы разделов. **Задача B (18.09.2026):** ревизия 8 документов (5 исправлений), перегенерация, 0 проблем ссылок. **Этап 13 (18.09.2026, ВЫПОЛНЕН):** новый документ **rowselection** (Блок 1.6). **Этап 14 (18.09.2026, ВЫПОЛНЕН):** новый документ **printpreview** (Блок 1.7) + проверка оставшихся dwsrv (фильтр/поиск/отчёт/reqcolumn не используются, свои окна).
- **Продукт:** `C:\AIS\AI\Prod\DOKI\Docs\` (index, pfc-dwsrv-overview, pfc-dwsrv-parmlinkage, pfc-dwsrv-resize, pfc-dwsrv-sort, pfc-dwsrv-rowmanager, **pfc-dwsrv-rowselection**, **pfc-dwsrv-printpreview**, pfc-dwsrv-extra, pfc-overview — каждый .md/.html/.pdf; CHM `Docs\chm_out\pfc-docs.chm`).
- **Инструменты:** `C:\AIS\AI\Prod\DOKI\Script\` (PfcDocs.Build.exe — C# MD→HTML, au_audit_dwsrv.py, au_dump_signatures.py, gen_pdf.py, build_pfc_chm.py, check_links.py; набор `_hhw\` — hhc.exe+hha.dll+itcc.dll+itircl.dll).
- **Ключ CHM (18.09.2026):** hhc.exe требует регистрации `itcc/itircl` (SysWOW64 regsvr32) и CRLF в `.hhp/.hhc/.hhk`; на этой система возвращает `rc=1` и при успехе (норма). Секция `[WINDOWS]` `0x2420` даёт панель навигации. См. Bug-077.
- **MCP:** `ais-catalog_search_knowledge("DOKI")` — id 98 (спека), 99 (аудит), сводка v1.0.
- **Сервисное MCP-знание (18.09.2026):** atlassian MCP починен (Bug-078, `C:\AIS\AI\atlassian-mcp\.venv` вместо uvx; требуется перезапуск OpenCode и проверка появления `jira_*/confluence_*`). Диагностика — `C:\AIS\AI\Prod\MCP_DIAG\Script\`.
- **Этап 13 (18.09.2026):** ВЫПОЛНЕН. Выбор сервиса по grep-паттернам (не по `inv_*`): `of_SetRowSelect(TRUE)` — 202 строки в 160 файлах (186 активных), `of_setstyle` — 203, `of_selectedcount` — 22, `of_rowselect` — 32, `inv_rowselect` — 261. Выпущен `pfc-dwsrv-rowselection.md` (Блок 1.6) во всех форматах; CHM пересобран (229 898 байт, 16 подтем). Реестр `index.md` и отчёт обновлены.
- **Этап 14 (18.09.2026):** ВЫПОЛНЕН. Проверены остальные dwsrv: filter/find/report/reqcolumn — прикладных обращений 0 (их функции — собственные окна `w_find_dw`/`w_print_parameters`, меню `m_dw` → `n_cst_dw_manager`). Реально используется **printpreview**: `of_SetPrintPreview` — 4 включения (`w_gold_*`), печать `pfc_printImmediate` — 3 окна `golden_report`, `Print.Preview.*` — 8. Выпущен `pfc-dwsrv-printpreview.md` (Блок 1.7); HTML/PDF 10/10, check_links 0 проблем, CHM пересобран (255 962 байт, 13 подтем printpreview). Реестр `index.md` дополнен.
- **Папка задачи:** `C:\AIS\AI\Prod\DOKI\`
- **Точка возобновления (Этап 15):** продолжить по команде «продолжить DOKI». Состав Блока 1 исчерпан (новых dwsrv с подтверждённым использованием нет). Возможные направления: (а) ревизия/читка Блока 2 и index; (б) справочная тема «фильтрация и поиск в проекте» (собственные окна `w_find_dw`, `w_print_parameters`, меню `m_dw`/`n_cst_dw_manager`); (в) закрытие задачи с финальным отчётом. Обновить MCP `ais-catalog` после следующего этапа (id 108).
- **Продолжение только по команде** «продолжить DOKI». Автопродолжение запрещено.

### SUPRT-19132 — Ошибка отправки акта ДВОУ в ЛК (rep_id=2614404) (папка: SUPRT-19132, 16.09.2026)

- **Статус:** [~] в работе — анализ кода выполнен, подготовлена спека для продолжения в новой сессии (MCP не был доступен в сессии 16.09.2026).
- **Ошибка:** «Контроль Итоговой суммы КВ не прошёл: ld_total_excel = 64007,00 ld_total = 32016,00» при «Отправить PDF» акта ДВОУ в ЛК.
- **Суть:** проверка в `uf_print_dvou2020` (n_cst_golden.sru, стр. 17507-17519) сверяет SUM Excel (колонка D, строка 10+ll_rowcount) с `premium_sum_all[1]` из `usp_dvou_final @mode=2`. Расхождение ≈2x. Комментарий SUPRT-16767 (стр. 17512-17514): в `ais_dvou_final` для одного rep_id может быть НЕСКОЛЬКО строк sort_id=1 (старые данные не чистятся), предложен `@mode = 7`.
- **MCP:** знания НЕ сохранены (MCP недоступен). После решения — `ais-catalog_save_knowledge` (теги: SUPRT-19132, uf_print_dvou2020, usp_dvou_final, ais_dvou_final).
- **Папка задачи:** `C:\AIS\1 Release\SUPRT-19132\`
- **Точка возобновления:** `C:\AIS\1 Release\SUPRT-19132\Describe\СПЕКА_SUPRT-19132.md` (Шаги 1-5: Knowledge First → прочитать usp_dvou_final.sql → SELECT по ais_dvou_final для rep_id=2614404 → выбрать вариант исправления A/B/C/D → реализовать).
- **Продолжение только по команде** «продолжить SUPRT-19132». Автопродолжение запрещено.

### OPENCODE-ENFORCER-PLAN — антивирус-устойчивость + энфорсер валидации (09.09.2026)

- **Статус:** [~] в работе — плагин pb-sql-enforcer.js создан и подключён в opencode.jsonc (режим block), выполнен СОХР (archives\SNAPSHOT\2026_09_09_121022). Утверждён план из 4 пунктов, требуется выполнение в НОВОЙ сессии после перезапуска opencode.
- **MCP:** `opencode-mcp_get_knowledge(44)` — описание плагина; `opencode-mcp_get_knowledge(45)` — точка возобновления с полным планом.
- **Как возобновить:** продолжение ТОЛЬКО по промпту пользователя (см. файл `temp\continue_prompt.txt`, сформирован в этой сессии). Knowledge First: `opencode-mcp_get_knowledge(45)`.
- **План (все 4 пункта):**
  1. Заменить base64-лаунчеры `scripts\Add-Bom.bat`, `scripts\Save-Snapshot.bat` (HEUR:Trojan.PowerShell.Obfus) на чистый `.bat`+`.ps1` (без `[ScriptBlock]::Create`, base64, IEX);
  2. Добавить в `.opencode\preflight.mdc` список запрещённых идиом PB/SQL (iif(, ??, ?., =>, Switch();
  3. Расширить `pb-sql-enforcer.js`: протухание кредитов (validate старше ~10 мин → сброс, повторная валидация);
  4. Интегрировать LSP `pb_lsp` (LspProxy.exe) как источник быстрой валидации.
- **ВАЖНО:** после перезапуска opencode правки `.sr*/.sql` без `sybase-docs_validate_code` блокируются плагином. Пользователь НЕ может управлять антивирусом (Kaspersky) — писать код без AV-опасных паттернов.
- **Продолжение только по явной команде** пользователя. Автопродолжение запрещено.
- **Следующий шаг:** прочитать `temp\continue_prompt.txt` и выполнить пункты 1-4 по порядку, с проверкой каждого (node --check, BOM, антивирус-паттерны).

### SYBASE-19922 — BSI-9729 «Дата акта» (external_date) (папка: SYBASE-19922, 02.09.2026)

- **Статус:** [~] в работе — **НОВЫЙ раунд замечаний тестировщика** (Jira SYBASE-19922, комментарии с 08/сен/26 18:35 и позже). Предыдущие замечания (07.09) устранены, смоук-тест 08.09 пройден.
- **Суть:** Внешняя «дата акта» (ais_cat_pdf_location.external_date='1') в автогенерацию и ручную генерацию отчётов: параметр @external_date_override, отсев КВ по paym_date, расчёт даты = последний день пред. месяца.
- **MCP:** `ais-catalog_search_knowledge("SYBASE-19922")` → знание **id 106** (ТОЧКА ВОЗОБНОВЛЕНИЯ 18.09.2026, полный контекст: ShareData dw_card, ue_refresh vs pfc_retrieve, dblclick parmlinkage, кодировки, комплект Test_2026_09_18__13_00). Также id 19, 62-66.
- **MCP atlassian:** Bug-078 решён — venv `C:\AIS\AI\atlassian-mcp\.venv` вместо uvx, конфиги обновлены. **Перед работой с Jira — перезапуск OpenCode** (иначе старые процессы uvx без jira_*/confluence_*). Диагностика: `C:\AIS\AI\Prod\MCP_DIAG\Script\`.
- **Папка задачи:** `C:\AIS\1 Release\SYBASE-19922`; актуальный комплект `Test_2026_09_18__13_00`, исходники Extract `Extract_2026_09_18__13_00` (w_sprw_all.srw 163297 б, правлен 18.09 13:33).
- **Следующий шаг:** 1) прочитать знание id 106 (Knowledge First); 2) `jira_get_issue(key="SYBASE-19922")` — прочитать комментарии тестировщика с 08/сен 18:35 и позже; 3) разобрать замечания по объектам; 4) внести правки в объекты папки Test_ (или свежую Test_YYYY_MM_DD__hh_mm); 5) пересинхронизировать копии, обновить Describe\ и план; 6) обновить знание id 106 (не дробить).
- **Продолжение только по команде** «продолжить SYBASE-19922». Автопродолжение запрещено.

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
- **Ключ:** хранится в `config\.local_secrets.json`, в git НЕ хранить (ключ был опубликован — сменить)
- **Модели:** `claude-3-5-sonnet-20241022`, `claude-3-7-sonnet-latest`
- **Статус:** не работает — SSL/TLS connection timeout (firewall блокирует artemox.com)
- **Для решения:** открыть доступ к api.artemox.com в корпоративном firewall или получить другой ключ

#### 2. Единый API-ключ (OpenAI/Claude/Gemini/DeepSeek/xAI) через прокси artemox.com
- **Провайдер:** `artemox` в `opencode.jsonc` (npm: `@ai-sdk/openai-compatible`)
- **URL:** `https://api.artemox.com/v1`
- **Ключ:** хранится в `config\.local_secrets.json`, в git НЕ хранить (ключ был опубликован — сменить)
- **Модели:** deepseek-chat, deepseek-coder, gpt-4o, gpt-4o-mini, claude-3-5-sonnet, claude-3-7-sonnet, gemini-1.5-pro, grok-1
- **Панель управления:** https://artemox.com/ui (user: z2036w9gjzce5r-20jcjq6@artemox.com)
- **Статус:** не работает — SSL/TLS connection timeout (firewall блокирует artemox.com)
- **Для решения:** открыть доступ к api.artemox.com в корпоративном firewall или получить другой ключ
