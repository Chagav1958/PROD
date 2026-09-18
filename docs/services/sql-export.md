# Сервис SQL Export — детальное описание

> **Версия:** 1.0 от 07.08.2026
> **Родительский том:** [Главный том документации](../master-index.md)

> **Спецификация восстановления (01.09.2026):** [sql-export-restore-spec.md](../sql-export-restore-spec.md) — причины отказа сервиса, исправления, параметры вызова и результаты тестов.

---

## 1. Назначение

Сервис выгрузки SQL-объектов из Sybase ASE 15.5 в формат, полностью совместимый с аналитическим инструментом **dbArtesan**. Поддерживает выгрузку процедур, функций, триггеров, таблиц, представлений, индексов, ключей и грантов.

---

## 2. Компоненты сервиса

| Компонент | Тип | Назначение |
|-----------|-----|-----------|
| `bin\SqlExport.exe` | C# (.NET) | Координатор выгрузки: запускает bat, форматирует ###PHASE###/###STEP### |
| `bin\SQL_exp_param.bat` | BAT | Массовая выгрузка всех объектов заданного типа |
| `bin\SQL_exp_single.bat` | BAT | Выгрузка одного конкретного объекта |
| `scripts\Rebuild-Object.ps1` | PowerShell | Сборка тела объекта из HEX-фрагментов isql |
| `scripts\Convert-ExportEncoding.ps1` | PowerShell | Нормализация кодировки (ANSI для .sql, UTF-8 BOM для .sr*) |
| `bin\gen_single_grant.sql` | SQL | Генерация GRANT для одного объекта |

---

## 3. Стандарт формата выгрузки (dbArtesan)

Формат выгружаемых `.sql` файлов должен в точности соответствовать выводу Sybase dbArtesan:

### 3.1. Кодировка
**Windows-1251 (ANSI) без BOM.** Файлы с BOM (UTF-8/UTF-16) не соответствуют стандарту и не должны использоваться.

### 3.2. Структура файла

```
USE golden
go
IF OBJECT_ID('dbo.usp_example') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.usp_example
    IF OBJECT_ID('dbo.usp_example') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE dbo.usp_example >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE dbo.usp_example >>>'
END
go
CREATE PROCEDURE dbo.usp_example
    @param1 int
AS
BEGIN
    -- тело процедуры
END
go
EXEC sp_procxmode 'dbo.usp_example', 'unchained'
go
IF OBJECT_ID('dbo.usp_example') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.usp_example >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.usp_example >>>'
go
GRANT EXECUTE ON dbo.usp_example TO r_web_ais
go
```

### 3.3. Типы объектов и различия в обёртке

| Тип | DROP | sp_procxmode | GRANT |
|-----|------|-------------|-------|
| Procedure | `DROP PROCEDURE` | да | `GRANT EXECUTE` |
| Function | `DROP FUNCTION` | нет | `GRANT EXECUTE` |
| Trigger | `DROP TRIGGER` | нет | нет |
| View | `DROP VIEW` | нет | `GRANT SELECT` |

---

## 4. HEX-метод выгрузки тела

### 4.1. Проблема прямого SELECT text

Прямой запрос `SELECT text FROM syscomments` через `isql` приводит к:
- **Word-wrap:** isql обрезает строки на 80-м символе (даже с `-w 65535`)
- **Потеря форматирования:** длинные строки разбиваются произвольными переносами
- **Искажение кириллицы:** при конвертации кодировок

### 4.2. Решение: HEX-фрагменты

```sql
-- Запрос HEX-фрагментов (SQL_exp_single.bat, стр. 57-59)
SELECT CONVERT(VARBINARY(255), text) AS hx, number, colid
FROM syscomments
WHERE id = OBJECT_ID('usp_example')
ORDER BY number, colid
```

Результат — набор строк вида `0xHEX_STRING  number  colid`. Эти фрагменты собираются скриптом `Rebuild-Object.ps1`:

1. Чтение `isql` вывода в кодировке Latin-1 (28591)
2. Парсинг регулярным выражением `0x([0-9a-fA-F]+)\s+(\d+)\s+(\d+)`
3. Сортировка по (number, colid)
4. Конкатенация HEX-строк
5. Запись байтов в выходной файл (CP1251)

### 4.3. Проверка корректности

Сверка с эталоном dbArtesan для процедуры `usp_policy_lk_list_1tst` (3672 строки, 229125 байт тела) подтвердила полную идентичность:

```
MATCH! SQL export follows the Standard Format (dbArtesan).
```

Скрипт сравнения: `temp\compare_exact.ps1` (нормализация BOM, whitespace, сравнение текста).

---

## 5. Архитектура выгрузки

### 5.1. Путь без TaskName (массовая выгрузка)

```
МОРДА2 (ОП7) → Start-OpAsync → Invoke-OpSqlExport
    → SqlExport.exe
        → SQL_exp_param.bat
            → isql: список объектов (sysobjects)
            → Параллельный HEX-экспорт каждого объекта
            → Rebuild-Object.ps1 (сборка тела)
            → Convert-ExportEncoding.ps1 (нормализация)
```

### 5.2. Путь с TaskName (выборочная выгрузка)

```
МОРДА2 (ОП7) → Start-OpAsync → Invoke-OpSqlExport
    → Сканирование Ready_*/Git_* папок задачи
    → Определение типа объекта по CREATE header
    → SQL_exp_single.bat (для каждого объекта)
        → isql: HEX-фрагменты
        → Rebuild-Object.ps1
        → Convert-ExportEncoding.ps1
    → Обновление PhaseProgress/StepProgress
```

---

## 6. Мониторинг прогресса (ПБ)

### 6.1. Верхний ПБ (PhaseProgress)

Показывает текущий тип объекта и прогресс по типам:

| Тип | % заполнения | Текст |
|-----|-------------|-------|
| Процедуры | 11% | `Тип: Процедуры` |
| Функции | 22% | `Тип: Функции` |
| Триггеры | 33% | `Тип: Триггеры` |
| ... | ... | ... |
| Гранты | 100% | `Тип: Гранты` |

### 6.2. Нижний ПБ (StepProgress)

Показывает текущий объект и общий прогресс:

| Этап | Текст |
|------|-------|
| Начало | `0 из 1046` |
| Объект X | `523 из 1046 — usp_example_proc` |
| Завершение | `1046 из 1046` |

### 6.3. Реализация в коде

Данные передаются через синхронизированные хеши (`[hashtable]::Synchronized()`), доступные UI-потоку и Runspace одновременно:

```powershell
# В Start-OpAsync
$syncPhase = [hashtable]::Synchronized(@{Value=0; Text=''})
$syncStep  = [hashtable]::Synchronized(@{Value=0; Text=''})

# В хендлере (Invoke-OpSqlExport)
$script:PhaseProgress.Value = [Math]::Round(($ti + 1) * 100 / $totalTypes)
$script:PhaseProgress.Text = "Тип: Процедуры"
$script:StepProgress.Value = [Math]::Round($objIdx * 100 / $total)
$script:StepProgress.Text = "$objIdx из $total — usp_..."
```

---

## 7. Экономическая выгода

### 7.1. Сокращение времени

| Показатель | Ручной способ | Автоматизированный |
|-----------|--------------|-------------------|
| Выгрузка 1046 процедур | ~4 часа (isql + форматирование) | ~3 минуты |
| Поиск объекта в БД | ~5 минут | ~1 секунда (через ОП7) |
| Сравнение с эталоном | ~30 минут (визуально) | ~5 секунд (MD5) |

### 7.2. Предотвращение ошибок

- **HEX-метод** исключает word-wrap и искажение текста (ранее: 100% выгруженных процедур имели ошибки форматирования)
- **Стандарт dbArtesan** гарантирует идентичность с аналитическими инструментами
- **Нормализация кодировки** предотвращает кракозябры при передаче файлов

### 7.3. Масштабируемость

- **Массовая выгрузка:** параллельный HEX-экспорт 1000+ объектов
- **Выборочная выгрузка:** только объекты конкретной задачи (Ready_*/Git_*)
- **Повторное использование:** все выгруженные объекты кешируются в `BD\`
