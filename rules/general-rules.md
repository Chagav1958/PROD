# rules/general-rules.md — Общие правила проекта

## Структура проекта
```
C:\AIS\AI\Prod\
├── bin/                    # Исполняемые BAT-файлы
├── scripts/                # PowerShell скрипты
├── config/                 # Конфигурация (config.json, vss_object_history.json)
├── docs/                   # Документация (html, pdf, screenshots)
├── reports/                # Отчёты
├── temp/                   # Временные файлы
├── rules/                  # Файлы правил (index.md, *-rules.md)
├── BD/                     # SQL-экспорты
├── PB_Current/             # PB-экспорт Current
└── PB_Main/                # PB-экспорт Main
```

## Кодировка
- SQL-файлы: Windows-1251 (ANSI)
- Документация (HTML, MD, PDF): UTF-8
- PowerShell скрипты: UTF-8 с BOM (для корректной работы с русским текстом в PS 5.1)
- Конфигурация (JSON): UTF-8

## Именование
- Скрипты: CamelCase для PowerShell (.ps1), snake_case для BAT (.bat)
- Документация: snake_case с префиксом типа
- Отчёты: snake_case с префиком типа

## Безопасность
- ️ Пароли никогда не хранятся в файлах
- ⚠️ Пароли передаются только как параметры командной строки
- ️ Все скрипты должны поддерживать передачу пароля через параметры

## Портативность
- Проект организован так, что копированием корневой папки весь функционал может быть перенесён
- Все пути настраиваются через `config/config.json`
- Скрипт `scripts/Initialize-Project.ps1` автоматически настраивает пути

## Серверы и базы данных
| Имя | Тип | Назначение |
|-----|-----|------------|
| dev_golden | Сервер Sybase ASE | Разрабатываемая БД (Current) |
| galaxy | Сервер Sybase ASE | Промышленная БД (Main) |
| golden | База данных | Имя БД на обоих серверах |

## Каталоги
| Сокращение | Путь | Назначение |
|------------|------|------------|
| Current | `C:\Work\gold` | Рабочая версия исходников PB |
| Main | `C:\SRC125\gold` | Эталонная версия исходников PB |
| PB_Current | `C:\AIS\AI\Prod\PB_Current` | Экспортированные PB-объекты из Current |
| PB_Main | `C:\AIS\AI\Prod\PB_Main` | Экспортированные PB-объекты из Main |
| BD/dev_golden | `C:\AIS\AI\Prod\BD\dev_golden\golden` | SQL-экспорт Current |
| BD/galaxy | `C:\AIS\AI\Prod\BD\galaxy\golden` | SQL-экспорт Main |

## Версия документации
- HTML: `docs/sql_export_instructions.html`
- PDF: `docs/sql_export_instructions_v29.pdf`
- Версия: 2.9
