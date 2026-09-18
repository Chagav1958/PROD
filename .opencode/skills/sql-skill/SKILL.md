---
name: sql-skill
description: Работа с SQL Sybase ASE 15.5: написание и правка хранимых процедур, функций, триггеров, SELECT-запросов, диагностических запросов. Используй ТОЛЬКО когда задача касается SQL-кода (Golden, dev_golden, isql, .sql-файлы БД). Ключевые слова: процедура, SELECT, хранимая процедура, usp_, dbo., golden.
---

# SQL Sybase ASE 15.5 — правила

> Полный источник: `C:\AIS\AI\Prod\.opencode\sql-rules.mdc`

## ПРАВИЛО 0 (КРИТИЧНО): Читай MCP ПЕРЕД написанием SQL

**ОБЯЗАТЕЛЬНО** перед написанием ЛЮБОГО SQL-кода (даже простого SELECT):
1. `sybase-docs_search_docs` — найти документацию по функциям/конструкциям
2. `sybase-docs_validate_code(product="ase15.5")` — проверить синтаксис
3. НЕ полагаться на память — синтаксис ASE отличается от T-SQL, PostgreSQL, Oracle

Типичные ошибки из-за памяти: `i.rowcnt` (нет в sysindexes ASE), `data_pgs()`/`index_pgs()` не документированы, `CONVERT(..., 120)` может не поддерживаться.

## Запрещённые идиомы
- `iif(`, `??`, `?.`, `=>`, `Switch(` — отсутствуют в ASA SQL и PowerScript

## Ключевые функции

| Функция | Вместо (MS SQL) | Пример |
|---------|-----------------|--------|
| `STR_REPLACE()` | `REPLACE()` | `SET @s = STR_REPLACE(@s, 'a', 'b')` |
| `CHARINDEX(s, s2)` | только 2 аргумента (без start) | `CHARINDEX(',', @str)` |
| `CHAR_LENGTH()` | `LEN()` / `LENGTH()` | `IF CHAR_LENGTH(@s) > 0` |
| `SUBSTRING()` | 1-based индексация | `SUBSTRING(p.date_sale, 9, 2)` |
| `ISNULL(x, def)` | основной способ | `SELECT ISNULL(date_cancel, date_to)` |
| `SUSER_NAME()` | `USER_NAME()` | для текущего пользователя СЕРВЕРА |

Даты: `current_date()`, `GetDate()`, `DATEADD(dd|yy|dy|ms, n, d)`, `DATEDIFF(ms, s, f)`, `DATEPART(dw|yy, d)`, `CONVERT(VARCHAR(10), @d, 23|102|105|111)`.

## Ограничение строк
- `SELECT TOP N` или `SET ROWCOUNT N ... SET ROWCOUNT 0` (LIMIT/OFFSET НЕ поддерж.)
- `IDENTITY` (не AUTO_INCREMENT), `@@IDENTITY` (не LAST_INSERT_ID)
- Временные таблицы: `CREATE TABLE #tmp` / `SELECT ... INTO #tmp`
- Транзакции: `BEGIN TRAN / COMMIT TRAN / ROLLBACK TRAN` (+ гарантированный откат `WHILE (@@TRANCOUNT > 0) ROLLBACK TRAN`)
- Ошибки: `@@ERROR` + `@@ROWCOUNT` всегда парой; `RAISERROR 99999, 'текст'` или `RAISERROR 99999 'текст'`; `GOTO метка`; `PRINT '... %1!', @var`
- Динамический SQL: `EXECUTE (@tmp_sql)`
- Курсоры: `DECLARE cur CURSOR FOR`, `FETCH cur INTO @a, @b`, `WHILE (@@SQLSTATUS = 0)`, `CLOSE`, `DEALLOCATE CURSOR`
- Процедуры: `CREATE PROCEDURE dbo.usp_name;1` (суффикс `;1` — версия ASE), `WITH RECOMPILE`

## Деквалификатор dbo. — ошибка 107 (ОБЯЗАТЕЛЬНО)

Если во FROM/JOIN таблица с владельцем (`dbo.таблица`) — **обязательно алиас**, и использовать его во ВСЕХ префиксах колонок. Рассинхрон `dbo.` в FROM без алиаса в SELECT → ошибка 107 «The column prefix does not match...». У пользователя-разработчика (маппится на dbo) работает, у остальных падает — user-зависимый баг.

```sql
-- ПРАВИЛЬНО
SELECT p.product_id, p.name FROM dbo.ais_cat_product p
-- НЕПРАВИЛЬНО
SELECT ais_cat_product.product_id FROM dbo.ais_cat_product
```

## ASA SQL vs T-SQL — таблица соответствий

| Конструкция | ASA SQL | T-SQL |
|-------------|---------|-------|
| Имя пользователя | `SUSER_NAME()` | `USER_NAME()` |
| Разделитель пакетов | `go` | `GO` |
| Даты (ais_entity_basis) | `date_from`, `date_to` | `date_begin`, `date_end` |
| Полисы AVT/еОСАГО | `oss_agreement` | `ais_policy` |
| Посредники | `oss_middleman` (mid_name_id, business_role; НЕТ subj_id) | — |
| Транзакции | `BEGIN TRAN` | `BEGIN TRANSACTION` |

## Безопасность данных — ЗАПРЕЩЕНО выводить конфиденциальную информацию

При диагностических запросах НЕ выводить:
- Имена: `entity_name`, `mid_name`, `insurant`, `per_last_name/first_name`
- Номера: `num_agreement`, `policy_number`
- Суммы: `com_sum`, `pp_sum`, `premium`, `paym_sum`
- Адреса/телефоны/email, номера счетов

РАЗРЕШЕНО: внутренние ID (`com_id`, `entity_id`, `ag_id`, `os_policy_id`), коды/статусы (`com_type`, `system`, `state`, `business_role`), ссылки (`cover_id`, `mid_name_id`), даты без привязки к клиенту, техполя (`update_foundation`, `update_user`).

## Кодировка и оформление
- `BD\**\*.sql` — **Windows-1251** (не UTF-8!)
- Имена таблиц `dbo.имя`, поля snake_case, алиасы 1-3 буквы (`p`, `a`, `e`), ключевые слова SELECT заглавными