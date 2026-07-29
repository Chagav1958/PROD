# Сводка сервисов проекта AIS Release Preparation

## Архитектура

Проект состоит из 8 групп сервисов, оркестрируемых через WPF-приложение `Prod-GUI.ps1`:

```
┌─────────────────────────────────────────────────────┐
│                    Prod-GUI.ps1                    │
│                  (WPF-приложение)                    │
├──────────┬──────────┬──────────┬────────────────────┤
│ SQL-    │ VSS     │ Compare  │ Jira RFC & Tests    │
│ экспорт │ сервис  │ сервисы  │ сервисы             │
├──────────┴──────────┴──────────┴────────────────────┤
│              Settings-Module.ps1                     │
│         (шифрование, валидация, экспорт/импорт)      │
└─────────────────────────────────────────────────────┘
```

## Группы сервисов

| Группа | Файлы | Документация |
|--------|-------|-------------|
| **SQL-экспорт** | `bin\SQL_exp_param.bat` | `sql_export_rules.md` |
| | `bin\SQL_exp_ready.bat` | |
| | `bin\SQL_exp_single.bat` | |
| **VSS** | `scripts\VSS-Utils.ps1` | `vss_rules.md` |
| | `scripts\vss.bat` | |
| **Сравнение** | `scripts\Compare-Export.ps1` | `compare_rules.md` |
| | `scripts\Compare-PB.ps1` | |
| | `scripts\Compare-SQL.ps1` | |
| **Jira RFC** | `scripts\Create-RFC.ps1` | `jira_rfc_rules.md` |
| | `scripts\Find-JiraFields.ps1` | |
| **Тестирование** | `scripts\test_sql_export.ps1` | `test_rules.md` |
| **GUI** | `bin\Prod-GUI.ps1` | `gui_rules.md` |
| | `scripts\Settings-Module.ps1` | |
| **PB-экспорт** | `scripts\AIS_export.ps1` | `pb_export_rules.md` |
| | `bin\Export.bat` | |
| | `bin\AIS_export.bat` | |
| | `bin\AIS_export_flexible.bat` | |
| **Инициализация** | `scripts\Initialize-Project.ps1` | `init_rules.md` |
| **Оркестратор** | `bin\prepare_release.bat` | — (использует SQL-экспорт и Compare) |

## Операции в GUI

| № | Операция | Сервис | Тип |
|---|----------|--------|-----|
| 0 | Settings | GUI (Settings-Module.ps1) | Встроенная панель |
| 1 | SQL Export — Current | SQL-экспорт (SQL_exp_param.bat) | BAT |
| 2 | SQL Export — Main | SQL-экспорт (SQL_exp_param.bat) | BAT |
| 3 | SQL Export from Ready | SQL-экспорт (SQL_exp_ready.bat) | BAT |
| 4 | Compare & Verify | Сравнение (Compare-Export.ps1) | PS1 |
| 5 | Create RFC in Jira | Jira RFC (Create-RFC.ps1) | PS1 |
| 6 | Compare PB | Сравнение (Compare-PB.ps1) | PS1 |
| 7 | Compare SQL | Сравнение (Compare-SQL.ps1) | PS1 |
| 8 | Run Tests | Тестирование (test_sql_export.ps1) | PS1 |
| 9-14 | VSS * (6 операций) | VSS (VSS-Utils.ps1 + ss.exe) | PS1 + EXE |

## Ключевые правила (из AGENTS.md)

### Кодировка
- SQL-файлы: Windows-1251
- Документация (HTML, MD): UTF-8
- PowerShell скрипты: ASCII (для совместимости с Windows PowerShell 5.1)

### Безопасность
- Пароли не хранятся в файлах (кроме VSS — зашифрован AES-256)
- Пароли передаются только как параметры командной строки

### Именование
- Скрипты: CamelCase для PowerShell (.ps1), snake_case для BAT (.bat)
- Документация: snake_case с префиксом типа

### MCP-серверы
- Документация PowerBuilder и Sybase ASE (ASA) подключается только при необходимости
- MCP-серверы для внутренних сервисов проекта НЕ создаются (вся информация в файлах правил)

> **Полный свод всех правил проекта — в `C:\AIS\AI\Prod\AGENTS.md`**

## Быстрый старт

```powershell
# 1. На новом компьютере
.\scripts\Initialize-Project.ps1

# 2. Запуск GUI
.\bin\Prod-GUI.bat

# 3. Настройка путей и VSS пароля
# Открыть Settings → Paths / VSS

# 4. Выполнить операцию
# Выбрать операцию → ввести параметры → Run
```
