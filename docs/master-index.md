# Проект AIS Release Preparation — Главный том документации

> **Версия:** 1.0 от 07.08.2026
> **Назначение:** единая точка входа в документацию проекта. Содержит указатели на все сервисы, объекты, правила, MCP-сервера, плагины и подсистемы.

---

## 1. Общая информация о проекте

| Параметр | Значение |
|----------|----------|
| Название | AIS Release Preparation |
| Назначение | Автоматизация подготовки релизов страхового продукта «Ренессанс» |
| Язык разработки | PowerShell 5.1, Python 3.12, C#, BAT |
| База данных | Sybase ASE 15.5 |
| Контроль версий | VSS (ss.exe) + Git (GitHub) |
| Задачи | Jira (mytask.renins.com) |
| Стандарт GUI | СТАНДАРТ2 (WPF) |

---

## 2. Сервисы (исполняемые подсистемы)

### 2.1. Основные сервисы GUI

| Сервис | Файл | Назначение | Документация |
|--------|------|-----------|-------------|
| **МОРДА2** (СТАНДАРТ2) | `bin\Prod-GUI_STANDART2.ps1` | Главное окно подготовки релизов (19 операций) | [morda2.html](services/morda2.html) + [.pdf](services/morda2.pdf) |
| **DLLM** | `scripts\Show-LLMs.ps1` | Диалоговое окно управления LLM-моделями | `services/dllm.md` (планируется) |
| **TaskPlan** | `scripts\Show-TaskPlanGUI.ps1` | Планировщик задач с WPF-интерфейсом | `services/taskplan.md` (планируется) |
| **ПРОДОБР** | `scripts\Show-ProdObr-GUI.ps1` | Мониторинг обработки задач с прогресс-барами | `services/prodobr.md` (планируется) |
| **ObjectInfo** | `bin\Show-ObjectInfo.bat` | Справочник объектов PB/SQL с зависимостями | `services/objinfo.md` (планируется) |

### 2.2. Сервисы выгрузки

| Сервис | Файл | Назначение | Документация |
|--------|------|-----------|-------------|
| **SQL Export** | `bin\SQL_exp_param.bat`, `bin\SQL_exp_single.bat`, `bin\SqlExport.exe` | Выгрузка SQL-объектов из Sybase ASE | [sql-export.html](services/sql-export.html) + [.pdf](services/sql-export.pdf) |
| **PB Export** | `scripts\Export-PB.ps1` | Выгрузка PowerBuilder-объектов через pbldump | `services/pb-export.md` (планируется) |

### 2.3. Сервисы сравнения и верификации

| Сервис | Файл | Назначение |
|--------|------|-----------|
| **Compare SQL** | `scripts\Compare-SQL.ps1`, `scripts\Compare-SQL-Task.ps1` | Сравнение SQL-объектов Current vs Main |
| **Compare PB** | Встроен в МОРДА2 | Сравнение PB-объектов Current vs Main (MD5) |
| **Compare & Verify** | `scripts\Compare-Export.ps1` | Сравнение выгрузок, отчёт готовности, RFC в Jira |

---

## 3. MCP-сервера

| Сервер | Команда запуска | Назначение | Документация |
|--------|----------------|-----------|-------------|
| **ais-catalog** | `.venv\python.exe server.py` | База знаний проекта (объекты, бизнес-правила, опыт) | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **ais-objects** | `.venv\python.exe server.py` | Каталог PB/SQL объектов с зависимостями и анализом | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **opencode-mcp** | `.venv\python.exe server.py` | База знаний по работе с OpenCode (баги, скрипты, настройки) | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **rules-mcp** | `run.py` | Доступ к правилам проекта (сокращения, кодировки, баги) | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **sybase-docs** | `-m sybase_mcp.server` | Документация Sybase ASE 15.5 и PB 12.5 | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **atlassian** | `mcp-atlassian` | Доступ к Jira и Confluence (только чтение) | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |
| **ews** | `run_server.py` | Доступ к Exchange/Outlook (почта, календарь, контакты) | [mcp-servers.html](services/mcp-servers.html) + [.pdf](services/mcp-servers.pdf) |

---

## 4. LSP-сервер

| Сервер | Файл | Расширения | Документация |
|--------|------|------------|-------------|
| **PB-LSP** | `scripts_pb_lsp\LspServer.exe` | `.sru`, `.srw`, `.srm`, `.srs`, `.srd`, `.srp`, `.pbj` | [lsp-pb.html](services/lsp-pb.html) + [.pdf](services/lsp-pb.pdf) |

---

## 5. Плагины OpenCode

| Плагин | Файл | Назначение | Документация |
|--------|------|-----------|-------------|
| **save-prompts** | `.opencode\plugins\save-prompts.js` | Автосохранение промптов пользователя | `services/plugins.md` (планируется) |
| **russian-compaction** | `.opencode\plugins\russian-compaction.js` | Сводки сессий на русском языке | `services/plugins.md` (планируется) |
| **claude-code** | `.opencode\plugins\claude-code.js` | Интеграция с Claude Code для анализа PB/SQL | `services/plugins.md` (планируется) |
| **loop-guard** | `.opencode\plugin\loop-guard.js` | Защита от бесконечных циклов правок | `services/plugins.md` (планируется) |
| **task-progress** | `.opencode\plugin\task-progress.js` | Отслеживание прогресса задач | `services/plugins.md` (планируется) |
| **@betterspec/opencode** | npm-пакет | Улучшенная спецификация промптов | `services/plugins.md` (планируется) |
| **@relf108/opencode-watchdog** | npm-пакет | Система безопасности правок (scope, baseline, commit gate) | `services/plugins.md` (планируется) |

---

## 6. Правила и соглашения

| Документ | Назначение |
|----------|-----------|
| `AGENTS.md` | Ядро правил: язык, пути, безопасность, кодировки, команды, антивирус |
| `.opencode\preflight.mdc` | Предварительные проверки перед записью файлов |
| `.opencode\knowledge-first.mdc` | Правило поиска знаний (сначала MCP, потом файлы) |
| `.opencode\russian-language.mdc` | Обязательный русский язык |
| `.opencode\sql-rules.mdc` | Правила SQL для Sybase ASE 15.5 |
| `.opencode\pb-object-rules.mdc` | Правила работы с PB-объектами |
| `.opencode\standard2-gui.mdc` | Эталон стилей GUI СТАНДАРТ2 |
| `.opencode\gui-testing-rule.mdc` | Правило трёх этапов тестирования GUI |
| `rules\abbreviations.md` | Сокращения проекта |
| `rules\changelog.md` | История изменений и исправленных багов |
| `rules\pending-tasks.md` | Отложенные задачи |
| `rules\testing-rules.md` | Правила тестирования |

---

## 7. Ключевые файлы и конфигурация

| Файл | Назначение |
|------|-----------|
| `opencode.jsonc` | Основная конфигурация OpenCode (провайдеры, модели, MCP, плагины, LSP) |
| `config\config.json` | Конфигурация путей и параметров проекта |
| `config\.local_secrets.json` | Хранилище секретов (пароли, токены) — НИКОГДА в Git |
| `pb_lsp_config.json` | Конфигурация PB-LSP сервера |

---

## 8. Экономическая выгода от применения

### 8.1. Сокращение времени подготовки релиза

| Операция | Ручной способ | Автоматизированный (МОРДА2) | Экономия |
|----------|--------------|---------------------------|----------|
| Выгрузка SQL (1046 процедур) | ~4 часа (ручной isql + форматирование) | ~3 минуты | **98.8%** |
| Сравнение PB-объектов | ~2 часа (визуальное сравнение) | ~30 секунд | **99.6%** |
| Создание RFC в Jira | ~30 минут | ~10 секунд | **99.4%** |
| Выгрузка PB (2617 объектов) | ~6 часов | ~5 минут | **98.6%** |
| VSS-операции | ~15 минут на объект | ~5 секунд | **99.4%** |

### 8.2. Предотвращение ошибок

- **Кодировка:** автоматическая нормализация (ANSI ↔ UTF-8) предотвращает кракозябры
- **Формат dbArtesan:** единый стандарт выгрузки исключает расхождения с аналитиками
- **HEX-метод:** предотвращает word-wrap и обрезание текста в isql
- **Валидация:** автотесты (Run-Tests.ps1) проверяют целостность кода, BOM, пути

### 8.3. Снижение зависимости от ключевых сотрудников

- Все знания зафиксированы в `ais-catalog` (164 записи)
- Документация по каждому сервису с примерами и скриншотами
- MCP-сервера обеспечивают доступ к знаниям из любой LLM-сессии
- TaskPlan позволяет продолжить работу с любой контрольной точки

---

## 9. Схема взаимодействия компонентов

<style>
.schema { font-family: 'Segoe UI', sans-serif; font-size: 12px; }
.schema .box { border: 2px solid #1A3A60; border-radius: 8px; padding: 10px 14px; margin: 6px 0; display: inline-block; vertical-align: top; }
.schema .box h4 { margin: 0 0 5px 0; color: #1A3A60; font-size: 13px; }
.schema .box p { margin: 2px 0; color: #4A5568; font-size: 12px; }
.schema .outer { border: 3px solid #2B6CB0; border-radius: 10px; padding: 12px; margin: 10px 0; background: #F0F4F8; }
.schema .outer h3 { margin: 0 0 8px 0; color: #1A3A60; }
.schema .row { display: flex; flex-wrap: wrap; gap: 8px; justify-content: center; }
.schema .arrow { font-size: 18px; color: #2B6CB0; text-align: center; margin: 4px 0; }
</style>
<div class="schema">

<div class="outer">
<h3>OpenCode Desktop</h3>
<div class="row">
<div class="box"><h4>Плагины (7)</h4><p>save-prompts, russian-compaction, claude-code, loop-guard, task-progress, betterspec, watchdog</p></div>
<div class="box"><h4>MCP Server'ы (7)</h4><p>ais-catalog, ais-objects, opencode-mcp, rules-mcp, sybase-docs, atlassian, ews</p></div>
<div class="box"><h4>LSP Server (1)</h4><p>PB-LSP</p></div>
</div>
</div>

<div class="arrow">&#8595;</div>

<div class="outer">
<h3>МОРДА2 (WPF GUI)</h3>
<div class="row">
<div class="box"><h4>SQL Export</h4><p>SqlExport.exe + bat</p></div>
<div class="box"><h4>PB Export</h4><p>pbldump</p></div>
<div class="box"><h4>VSS</h4><p>ss.exe: Get, Status, Checkout</p></div>
<div class="box"><h4>Compare</h4><p>MD5, Diff, RFC</p></div>
<div class="box"><h4>Jira/RFC</h4><p>Jira API</p></div>
</div>
</div>

<div class="arrow">&#8595;</div>

<div class="outer">
<h3>Внешние системы</h3>
<div class="row">
<div class="box"><h4>Sybase ASE 15.5</h4><p>isql, golden БД</p></div>
<div class="box"><h4>VSS (ss.exe)</h4><p>Контроль версий</p></div>
<div class="box"><h4>Jira / Confluence</h4><p>mytask.renins.com</p></div>
<div class="box"><h4>pbldump</h4><p>Экспорт .sr*</p></div>
<div class="box"><h4>Exchange/Outlook</h4><p>EWS API</p></div>
<div class="box"><h4>RouterAI / Ollama</h4><p>LLM API</p></div>
</div>
</div>

</div>

---

---

## 10. Указатель томов документации

| Том | .md | .pdf | Содержание |
|-----|-----|-----|-----------|
| **Главный (этот)** | — | — | Обзор всех сервисов, MCP, плагинов, правил |
| МОРДА2 | [morda2.html](services/morda2.html) | [morda2.pdf](services/morda2.pdf) | Детальное описание главного окна, 19 операций |
| MCP-сервера | [mcp-servers.html](services/mcp-servers.html) | [mcp-servers.pdf](services/mcp-servers.pdf) | Каталог всех 7 MCP-серверов с API |
| SQL Export | [sql-export.html](services/sql-export.html) | [sql-export.pdf](services/sql-export.pdf) | Стандарт dbArtesan, HEX-метод, скрипты |
| PB Export | `services/pb-export.html` | — | pbldump, кодировки, структура |
| PB-LSP | [lsp-pb.html](services/lsp-pb.html) | [lsp-pb.pdf](services/lsp-pb.pdf) | Language Server для PowerBuilder |
| DLLM | `services/dllm.html` | — | Управление LLM-моделями |
| TaskPlan | `services/taskplan.html` | — | Планировщик задач |
| ПРОДОБР | `services/prodobr.html` | — | Обработка задач с прогресс-барами |
| ObjectInfo | `services/objinfo.html` | — | Справочник объектов PB/SQL |
| Плагины | `services/plugins.html` | — | Все плагины OpenCode |
| VSS-сервис | `services/vss-service.html` | — | Контроль версий (Get Latest, Checkout, History) |
| Требования МОРДА | [morda-requirements.html](../morda-requirements.html) | [morda-requirements.pdf](../morda-requirements.pdf) | Единый документ требований к GUI |
| Сокращения | `rules/abbreviations.md` | — | Все сокращения проекта |
| История багов | `rules/changelog.md` | — | Полная история исправлений |
