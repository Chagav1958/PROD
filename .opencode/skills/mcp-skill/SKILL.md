---
name: mcp-skill
description: MCP-серверы проекта AIS: настройка в opencode.jsonc, инструменты ais-catalog, ais-objects, opencode-mcp, rules-mcp, sybase-docs, atlassian, ews; правило сохранения знаний (куда и что); диагностика «MCP не подключился». Используй при вопросах о MCP, настройке серверов, сохранении знаний, использовании поиска по базам знаний. Не используй для обычных задач.
---

# MCP-серверы проекта

> Полный источник: `C:\AIS\AI\Prod\docs\services\mcp-servers.md`

## Серверы (stdio, конфиг в `opencode.jsonc` → `mcp`)

| Сервер | База | Инструментов | Назначение |
|--------|------|-------------|-----------|
| **ais-catalog** | SQLite knowledge.db | 15 | База знаний проекта (search_knowledge, save_knowledge, get_business_rules, add_business_rule, get_object_metadata, find_dependencies, check_cross_project_impact, search_codebase, tag_object, ...) |
| **ais-objects** | SQLite objects.db | 15 | Каталог объектов PB/SQL (search_objects, list_objects, get_object, get_analyses, find_dependencies, save_analysis, search_analyses, compare_objects, import_objects) |
| **opencode-mcp** | SQLite knowledge.db | 8 | Опыт работы с OpenCode (search_knowledge, save_knowledge) |
| **rules-mcp** | Файловая система | 8 | Правила проекта, **только чтение** (get_abbreviation, get_rule, get_full_rule, preflight_check, search_bug) |
| **sybase-docs** | ChromaDB/FTS | 5 | Документация ASE/PB (search_docs, get_section, validate_code) |
| **atlassian** | Jira/Confluence API | 4 | Jira/Confluence, чтение (jira_search, jira_get_issue, confluence_search, confluence_get_page) |
| **ews** | Exchange EWS API | 80+ | Почта/календарь/контакты Exchange |

## Сохранение знаний (куда и что — решает модель)

| Сервер | Что сохранять |
|--------|---------------|
| **ais-catalog** | Всё о проекте: объекты PB/SQL, бизнес-логика, задачи SYBASE-*/SUPRT-* |
| **opencode-mcp** | Всё об OpenCode: скрипты PS, ДО, провайдеры, MCP, баги |
| **rules-mcp / sybase-docs / atlassian** | НИКОГДА не сохранять (только чтение) |

Дисциплина: одна сводная запись на задачу (не дробить!), явные теги, проверять дубли перед сохранением.

## Диагностика отсутствующего MCP

Если инструмент (`jira_get_issue`, `jira_search`, `confluence_search`, ...) **НЕТ в списке доступных** → НЕ искать альтернативные скрипты; сообщить: «MCP-сервер atlassian не подключился. Проверьте переменную окружения JIRA_PERSONAL_TOKEN и перезапустите OpenCode». Это проблема подключения MCP, не «доступа нет».

## Token Economy — приоритет источников

1. wiki-mcp (локальная вики) → 2. ais-catalog → 3. sybase-docs → 4. rules-mcp → 5. atlassian (последний резерв). Ограничивать параметры: `limit=5`, `limit=3`. НЕ начинать с atlassian при наличии локальных источников.