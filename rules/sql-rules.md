# rules/sql-rules.md — Правила SQL (Sybase ASE)

## Экспорт
- Утилита: `isql` (Sybase ASE)
- Кодировка: Windows-1251 (ANSI)
- Серверы: dev_golden (Current), galaxy (Main)
- База данных: golden

## Скрипты
- `SQL_exp_param.bat` — полный экспорт с параметрами
- `SQL_exp_single.bat` — экспорт одного объекта
- `SQL_exp_ready.bat` — экспорт из Ready папки

## Сравнение
- `Compare-SQL.ps1` — сравнение SQL экспортов
- `Compare-Export.ps1` — сравнение и создание RFC

## Тестирование
- `test_sql_export.ps1` — проверка целостности экспорта
- Проверка: хеши, структура, кодировка
