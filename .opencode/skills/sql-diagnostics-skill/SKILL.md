---
name: sql-diagnostics-skill
description: Диагностика SQL и PB через временные объекты: диагностические SELECT-запросы, DIAG-N MessageBox, объекты DIAG_YYYY_MM_DD_hh_mm, режим ЭКСТРА (только чтение). Используй ТОЛЬКО при создании диагностических объектов, отладочных запросов, команде ЭКСТРА, сообщений DIAG. Соблюдает защиту конфиденциальных данных. Не используй для боевых правок.
---

# Диагностика SQL — правила

> Полный источник: `C:\AIS\AI\Prod\AGENTS.md` (раздел ЭКСТРА) и `.opencode\sql-rules.mdc` (раздел «Безопасность данных»)

## Безопасность диагностических запросов (СТРОГО)

**НЕ выводить** (SELECT/PRINT/сообщения/логи):
- Имена клиентов/посредников: `entity_name`, `mid_name`, `insurant`, `per_last_name/first_name`
- Номера полисов/договоров: `num_agreement`, `policy_number`
- Суммы: `com_sum`, `pp_sum`, `premium`, `paym_sum`
- Адреса, телефоны, email, номера счетов

**Можно выводить** (только для диагностики):
- Внутренние ID: `com_id`, `entity_id`, `ag_id`, `os_policy_id`, `mis_ag_id`
- Коды/статусы: `com_type`, `system`, `state`, `business_role`, `blocked`
- Ссылки: `cover_id`, `mid_name_id`, `dep_id`
- Даты без привязки к клиенту: `date_from`, `date_to`, `paym_date`
- Технические поля: `update_foundation`, `update_user`, `check_info`

```sql
-- НЕПРАВИЛЬНО
SELECT c.com_id, e.entity_name, c.com_sum, p.num_agreement FROM dbo.ais_commission c ...
-- ПРАВИЛЬНО
SELECT c.com_id, c.entity_id, c.ag_id, c.com_type, c.system, c.state, c.os_policy_id
FROM dbo.ais_commission c WHERE c.com_id IN (186262303, 187671845)
```

Перед выполнением проверить SELECT-список; при сохранении в MCP/файлы — только ID и коды.

## Объекты для диагностики

- `DIAG_YYYY_MM_DD_hh_mm` — папка с объектами для диагностики (с временными MessageBox DIAG-N). Дата И время в имени (отличать итерации одного дня)
- Внутри папки — `ИНСТРУКЦИЯ.md` с инструкцией по тестированию
- Диагностические объекты НЕ класть в `Test_` (только ГОТОВЫЕ, без DIAG)

## Режим ЭКСТРА (экстренный однодневный)

- Разрешены ТОЛЬКО `SELECT` (чтение), без конфиденциальных данных (текстовые поля ≤10 символов)
- Для анализа ТЗ при критической нехватке времени
- Спека: `C:\AIS\AI\Prod\docs\services\extra.md`

## Перед написанием SQL

1. Проверить имена колонок: `SELECT name FROM syscolumns WHERE id = object_id('таблица') ORDER BY colid`
2. Валидировать через `sybase-docs_validate_code(product="ase15.5")`