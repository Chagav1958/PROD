# AIS Release Preparation - Портативный пакет

## Структура проекта

```
AIS_Release_Preparation/
── bin/                    # Исполняемые файлы (BAT)
│   ├── Prod-GUI.bat     # Запуск GUI
│   ├── prepare_release.bat # Главный оркестратор
│   ├── SQL_exp_param.bat  # Полный SQL-экспорт
│   ├── SQL_exp_single.bat # Экспорт одного объекта
│   ├── SQL_exp_ready.bat  # Экспорт из Ready
│   └── ...
├── scripts/               # PowerShell скрипты
│   ├── Prod-GUI.ps1     # GUI приложение
│   ├── Compare-Export.ps1 # Сравнение и RFC
│   ├── Compare-PB.ps1     # Сравнение PB
│   ├── Compare-SQL.ps1    # Сравнение SQL
│   ├── Create-RFC.ps1     # Создание RFC
│   ├── Find-JiraFields.ps1 # Поиск полей Jira
│   ├── VSS-Utils.ps1      # Утилиты VSS
│   └── ...
├── config/                # Конфигурация
│   ├── config.json        # Основные настройки
│   └── Task.txt           # Методика и план работ
├── docs/                  # Документация
│   ├── sql_export_instructions.html
│   ├── sql_export_instructions.pdf
│   └── screenshots/
├── reports/               # Отчеты (генерируются автоматически)
│   ├── release_report.txt
│   ├── compare_pb_report.txt
│   └── compare_sql_report.txt
├── temp/                  # Временные файлы
├── BD/                    # SQL-экспорты (создается автоматически)
├── PB_Current/            # PB-экспорт Current (создается автоматически)
── PB_Main/               # PB-экспорт Main (создается автоматически)
```

## Быстрый старт

### 1. Настройка конфигурации

Отредактируйте `config/config.json`:

```json
{
  "paths": {
    "bd_current_export": "C:\\AIS\\AI\\Prod\\BD\\dev_golden",
    "bd_main_export": "C:\\AIS\\AI\\Prod\\BD\\galaxy",
    "pb_current_export": "C:\\AIS\\AI\\Prod\\PB_Current",
    "pb_main_export": "C:\\AIS\\AI\\Prod\\PB_Main",
    "ready_folder": "C:\\AIS\\1 Release",
    "merged_ready": "C:\\Temp\\ReadyMerged"
  },
  "jira": {
    "base_url": "https://mytask.renins.com",
    "project_key": "RFC",
    "issue_type": "RFC",
    "custom_fields": {
      "release_start": "customfield_XXXXX",
      "release_end": "customfield_XXXXX",
      "task_ref_field": "customfield_XXXXX"
    },
    "task_link_field": "customfield_XXXXX"
  }
}
```

### 2. Запуск

**Вариант 1: GUI (рекомендуется)**
```
bin\Prod-GUI.bat
```

**Вариант 2: Консольное меню**
```
bin\prepare_release.bat
```

**Вариант 3: Прямой запуск скриптов**
```powershell
# Сравнение PB
powershell -ExecutionPolicy Bypass -File scripts\Compare-PB.ps1

# Сравнение SQL
powershell -ExecutionPolicy Bypass -File scripts\Compare-SQL.ps1

# Создание RFC
powershell -ExecutionPolicy Bypass -File scripts\Create-RFC.ps1 -TaskName SYBASE-19337
```

## Перенос на другой проект

### Шаг 1: Копирование папки

Скопируйте всю папку `AIS_Release_Preparation` в новое расположение.

### Шаг 2: Обновление конфигурации

Отредактируйте `config/config.json`:
- Укажите пути к вашим базам данных (BD)
- Укажите пути к экспортам PowerBuilder (PB_Current, PB_Main)
- Настройте параметры Jira (если используется)

### Шаг 3: Проверка зависимостей

Убедитесь, что установлены:
- **PowerShell 5.1** (встроен в Windows 10/11)
- **Sybase ASE Client** (для isql)
- **Microsoft Visual SourceSafe 8.0** (опционально, для VSS)
- **Google Chrome** (для генерации PDF)

### Шаг 4: Тестирование

Запустите тестовый скрипт:
```
bin\Prod-GUI.bat
```

Выберите операцию "Run Tests" и введите тестовые данные.

## Требования к системе

| Компонент | Версия | Назначение |
|-----------|--------|------------|
| Windows | 10/11 | Операционная система |
| PowerShell | 5.1+ | Выполнение скриптов |
| Sybase ASE Client | 15.5+ | Работа с БД (isql) |
| PowerBuilder | 12.5 | Экспорт PB-объектов (pbldump) |
| Microsoft VSS | 8.0 | Контроль версий (опционально) |
| Google Chrome | Любой | Генерация PDF из HTML |

## Переменные окружения

Скрипты используют следующие переменные окружения:

| Переменная | Описание | Пример |
|------------|----------|--------|
| `SYBASE` | Путь к установке Sybase | `C:\Sybase` |
| `SSDIR` | Путь к базе данных VSS | `\\server\vss` |

## Логирование

Все скрипты записывают логи в:
- **GUI**: `C:\Users\<User>\AppData\Local\Temp\ais_gui_debug.log`
- **Отчеты**: папка `reports/`

## Поддержка

При возникновении проблем:
1. Проверьте `config/config.json` на корректность путей
2. Запустите тесты через GUI
3. Изучите логи в папке `reports/`
4. Обратитесь к документации в `docs/`

## Лицензия

Внутренний инструмент разработки. Не для распространения.
