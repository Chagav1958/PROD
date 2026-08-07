# MCP-сервера проекта AIS — детальное описание

> **Версия:** 1.0 от 07.08.2026
> **Родительский том:** [Главный том документации](../master-index.md)

---

## 1. Общая информация

MCP (Model Context Protocol) — протокол, позволяющий LLM-моделям взаимодействовать с внешними инструментами. Проект AIS использует 7 MCP-серверов, каждый из которых предоставляет специализированный набор инструментов.

Все сервера работают в режиме `stdio` (стандартный ввод/вывод) и запускаются процессом OpenCode Desktop автоматически при старте. Конфигурация задаётся в файле `opencode.jsonc` (секция `mcp`).

---

## 2. Сводная таблица серверов

| Сервер | Тип | Порт | База данных | Инструментов | Назначение |
|--------|-----|------|------------|-------------|-----------|
| **ais-catalog** | Python | stdio | SQLite (knowledge.db) | 15 | База знаний проекта |
| **ais-objects** | Python | stdio | SQLite (objects.db) | 15 | Каталог объектов PB/SQL |
| **opencode-mcp** | Python | stdio | SQLite (knowledge.db) | 8 | Знания по работе с OpenCode |
| **rules-mcp** | Python | stdio | Файловая система | 8 | Правила проекта |
| **sybase-docs** | Python | stdio | ChromaDB/FTS | 5 | Документация Sybase/PB |
| **atlassian** | Python (mcp-atlassian) | stdio | Jira/Confluence API | 4 | Jira и Confluence (чтение) |
| **ews** | Python | stdio | Exchange EWS API | 80+ | Exchange/Outlook |

---

## 3. Сервер `ais-catalog` — база знаний проекта

### 3.1. Назначение
Хранилище корпоративных знаний: бизнес-правила, опыт работы с объектами, результаты анализа задач, связи между сущностями.

### 3.2. Инструменты

| Инструмент | Описание | Пример |
|-----------|----------|--------|
| `search_knowledge` | Поиск знаний по запросу (FTS5) | `search_knowledge("SYBASE-11523")` |
| `save_knowledge` | Сохранить знание в базу | `save_knowledge(text="...", tags="SQL,export")` |
| `knowledge_stats` | Статистика базы знаний | `knowledge_stats()` |
| `get_business_rules` | Получить бизнес-правила для процесса/таблицы | `get_business_rules("commission_calc")` |
| `add_business_rule` | Добавить/обновить бизнес-правило (YAML) | `add_business_rule(...)` |
| `get_object_metadata` | Метаданные объекта (структура, зависимости, теги) | `get_object_metadata("usp_policy_lk_list_1tst")` |
| `find_dependencies` | Граф вызовов объектов | `find_dependencies("w_policy_main", depth=2)` |
| `check_cross_project_impact` | Используется ли объект в других проектах | `check_cross_project_impact("u_entity", "AIS")` |
| `search_codebase` | Семантический поиск по коду | `search_codebase("oss_policy")` |
| `tag_object` | Проставить тег проекта объекту | `tag_object("usp_...", "AIS", "AIS_CORE")` |
| `delete_knowledge` | Удалить запись по ID | `delete_knowledge(id=100)` |
| `get_knowledge` | Получить запись по ID | `get_knowledge(id=100)` |
| `list_recent` | Последние сохранённые знания | `list_recent(limit=10)` |
| `list_tags` | Список всех тегов | `list_tags()` |
| `reindex_knowledge` | Переиндексация FTS | `reindex_knowledge()` |

### 3.3. Структура БД (knowledge.db)

- **knowledge:** текст знания, теги, дата создания
- **knowledge_fts:** полнотекстовый индекс (FTS5)
- **business_rules:** правила в формате YAML
- **object_metadata:** структура объектов с тегами проектов (AIS_CORE, SHARED_AIS, GLOBAL_DB)

### 3.4. Экономическая выгода

- **Сокращение времени поиска информации** по объекту/задаче с часов до секунд (ранее: ручной просмотр .sru/.sql файлов)
- **Передача опыта между сессиями LLM:** любая модель мгновенно получает контекст через `search_knowledge`
- **Автоматический анализ:** при импорте объектов формируются сводки параметров, таблиц и задач Jira

---

## 4. Сервер `ais-objects` — каталог объектов

### 4.1. Назначение
Каталогизация всех объектов PowerBuilder и SQL с их зависимостями, анализами и метаданными.

### 4.2. Инструменты

| Инструмент | Описание |
|-----------|----------|
| `search_objects` | Поиск объектов по имени/типу |
| `list_objects` | Список объектов с фильтрацией (lib, kind, src, obj_type) |
| `get_object` | Полная информация об объекте (свойства, анализы, зависимости) |
| `get_analyses` | Все анализы объекта |
| `find_dependencies` | Граф зависимостей (forward/reverse/both, глубина 1-3) |
| `save_analysis` | Сохранить анализ объекта (привязывается к объекту) |
| `search_analyses` | Поиск по тексту анализов (FTS5) |
| `compare_objects` | Сравнить Main vs Current |
| `set_property` | Установить свойство (description, status, purpose, notes) |
| `import_objects` | Импорт PB/SQL из файловой системы |
| `add_dependency` | Добавить связь между объектами |
| `object_stats` | Статистика каталога |

### 4.3. Типы зависимостей

| Тип | Обозначение | Пример |
|-----|------------|--------|
| `calls` | PB → PB (вызов функции) | `w_policy → uf_get_entity` |
| `sql_ref` | PB → SQL (ссылка на процедуру) | `w_policy → usp_policy_select` |
| `pb_ref` | SQL → PB | редко |
| `dddw` | DropDown DataWindow | `dddw_insure_kind` |
| `contains` | Композиция | `w_main → u_tab_policy` |
| `inherits` | Наследование | `w_child ← w_base` |

### 4.4. Экономическая выгода

- **Анализ влияния изменений:** перед правкой объекта видно, кто его вызывает и кого вызывает он (4600 зависимостей)
- **Сокращение ошибок:** автоматическая проверка `Contains в` для 44% PB-объектов (ранее было 3.6%)
- **Импорт из PB IDE:** массовая загрузка метаданных (2473 PB + 2243 SQL объекта)

---

## 5. Сервер `opencode-mcp` — знания об OpenCode

### 5.1. Назначение
Хранилище опыта работы с OpenCode как инструментом: настройка провайдеров, баги, решения, скрипты PowerShell.

### 5.2. Инструменты

| Инструмент | Описание |
|-----------|----------|
| `search_knowledge` | Поиск по базе знаний OpenCode |
| `save_knowledge` | Сохранить знание |
| `get_knowledge` | Получить запись по ID |
| `delete_knowledge` | Удалить запись |
| `list_recent` | Последние сохранённые знания |
| `knowledge_stats` | Статистика |

### 5.3. Экономическая выгода

- **Повторное использование решений:** 124 записи опыта (баги, настройки, скрипты)
- **Быстрая диагностика:** поиск по ключевому слову за секунды (ранее требовал чтения changelog.md)

---

## 6. Сервер `rules-mcp` — доступ к правилам

### 6.1. Назначение
Читает файлы правил напрямую из `.opencode/*.mdc` и `rules/*.md`. **Никогда не используется для сохранения** (read-only).

### 6.2. Инструменты

| Инструмент | Описание | Пример |
|-----------|----------|--------|
| `get_abbreviation` | Расшифровка сокращения | `get_abbreviation("ПБ")` |
| `get_encoding_rule` | Требования к кодировке файла | `get_encoding_rule("test.ps1")` |
| `get_rule` | Текст правила по теме | `get_rule("sql")` |
| `get_full_rule` | Полный текст правила из .mdc | `get_full_rule("pb")` |
| `preflight_check` | Preflight-проверка перед записью | `preflight_check("test.ps1")` |
| `search_bug` | Поиск по истории багов | `search_bug("BOM")` |

---

## 7. Сервер `sybase-docs` — документация Sybase/PB

### 7.1. Назначение
Документация Sybase ASE 15.5 и PowerBuilder 12.5, загруженная в векторную базу для быстрого поиска.

### 7.2. Инструменты

| Инструмент | Описание |
|-----------|----------|
| `search_docs` | Поиск по документации (snippet + metadata) |
| `get_section` | Полный текст раздела по chunk_id |
| `read_context` | N блоков до/после для контекста |
| `validate_code` | Проверка кода по документированным паттернам |
| `list_docs_tool` | Список индексированных документов |

---

## 8. Сервер `atlassian` — Jira и Confluence

### 8.1. Назначение
Доступ к задачам Jira и страницам Confluence. **Только чтение** (READ_ONLY_MODE=true).

### 8.2. Инструменты

| Инструмент | Описание |
|-----------|----------|
| `jira_search` | Поиск задач Jira по JQL |
| `jira_get_issue` | Получение задачи по ключу |
| `confluence_search` | Поиск страниц Confluence |
| `confluence_get_page` | Получение страницы по ID |

---

## 9. Сервер `ews` — Exchange/Outlook

### 9.1. Назначение
Работа с корпоративной почтой через Exchange Web Services (EWS).

### 9.2. Инструменты (основные из 80+)

| Группа | Инструменты |
|--------|------------|
| **Почта** | `search_emails`, `read_emails`, `send_email`, `reply_email`, `forward_email`, `get_email_details` |
| **Папки** | `list_folders`, `find_folder`, `manage_folder`, `move_email` |
| **Календарь** | `get_calendar`, `create_appointment`, `find_meeting_times`, `check_availability` |
| **Контакты** | `create_contact`, `find_person`, `analyze_contacts` |
| **Задачи** | `create_task`, `get_tasks`, `complete_task` |
| **Управление** | `oof_settings`, `rule_create`, `briefing`, `memory_set/get` |

### 9.3. Экономическая выгода

- **Автоматическая обработка почты:** правила пересылки, автоответы (OOF)
- **Создание встреч:** анализ доступности участников
- **Поиск контактов:** GAL + личные контакты + история переписки
