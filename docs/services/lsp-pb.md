# PB-LSP — Language Server для PowerBuilder

> **Версия:** 1.0 от 07.08.2026
> **Родительский том:** [Главный том документации](../master-index.md)

---

## 1. Назначение

PB-LSP (PowerBuilder Language Server Protocol) — фоновый сервер, обеспечивающий глубокий анализ кода PowerBuilder в редакторе OpenCode Desktop. Предоставляет функции навигации, автодополнения и диагностики для файлов `.sru`, `.srw`, `.srd` и других PB-расширений.

---

## 2. Архитектура

### 2.1. Компоненты

| Компонент | Тип | Назначение |
|-----------|-----|-----------|
| `LspServer.exe` | C# (.NET 8) | Основной LSP-сервер (stdio) |
| `LspProxy.cs` | C# | Прокси для отладки и мониторинга |
| `LspQuery.dll` | C# (.NET 8) | Библиотека запросов к LSP |
| `PbParser.exe` | C# | Парсер синтаксиса PowerBuilder |
| `SqlParser.cs` | C# | Парсер встроенного SQL |
| `WatchParser.exe` | C# | Мониторинг изменений файлов |
| `MonitoringDialog.exe` | C# | Окно мониторинга работы LSP |
| `run_lsp.ps1` | PowerShell | Лаунчер с переменными окружения БД |

### 2.2. Схема взаимодействия

```
OpenCode Desktop
    │
    ├── languages.powerbuilder.lsp
    │       │
    │       └── запускает run_lsp.ps1
    │               │
    │               └── LspServer.exe (stdio)
    │                       │
    │                       ├── PbParser.exe (анализ .sru)
    │                       ├── SqlParser (анализ SQL)
    │                       └── WatchParser.exe (мониторинг)
    │
    └── Status Tab → показывает PB-LSP (Running/Stopped)
```

---

## 3. Возможности

### 3.1. Анализ кода

| Функция | Описание | Статус |
|---------|----------|--------|
| `textDocument/didOpen` | Анализ при открытии файла | ✅ |
| `textDocument/didChange` | Инкрементальный анализ при изменении | ✅ |
| `textDocument/documentSymbol` | Символы документа (функции, переменные) | ✅ |
| `workspace/symbol` | Символы по всему workspace | ✅ |
| `textDocument/hover` | Информация при наведении | 🔄 |
| `textDocument/completion` | Автодополнение | 🔄 |
| `textDocument/definition` | Переход к определению | ✅ |

### 3.2. Валидация SQL

Сервер проверяет встроенный SQL (DataWindow SQL, embedded SQL в скриптах) на соответствие синтаксису Sybase ASE 15.5, используя подключение к БД.

### 3.3. Инкрементальная индексация

При изменении файла переиндексируется только изменённая часть, а не весь workspace.

---

## 4. Конфигурация

### 4.1. Файл `pb_lsp_config.json`

```json
{
  "server": {
    "host": "localhost",
    "port": 6091,
    "logLevel": "verbose",
    "environment": "production"
  },
  "database": {
    "provider": "EnvDbProvider"
  },
  "paths": {
    "scripts": "C:\\AIS\\AI\\Prod\\scripts_pb_lsp",
    "logs": "C:\\AIS\\AI\\Prod\\logs\\pb_lsp",
    "backups": "C:\\AIS\\AI\\Prod\\backups\\pb_lsp"
  },
  "features": {
    "sqlValidation": true,
    "incrementalIndex": true,
    "documentSymbols": true,
    "workspaceSymbols": true
  }
}
```

### 4.2. Регистрация в `opencode.jsonc`

```jsonc
"languages": {
  "powerbuilder": {
    "extensions": [".sru", ".srw", ".srm", ".srs", ".srd", ".srp", ".pbj"],
    "lsp": {
      "type": "stdio",
      "command": ["powershell", "-NoLogo", "-File", "C:\\AIS\\AI\\Prod\\scripts_pb_lsp\\run_lsp.ps1"],
      "name": "PB-LSP",
      "enabled": true
    }
  }
}
```

### 4.3. Переменные окружения БД

Сервер использует переменные окружения для подключения к Sybase ASE:

| Переменная | Источник | Назначение |
|-----------|---------|-----------|
| `PB_LSP_DB_SERVER` | `.local_secrets.json → pb_lsp.db_server` | Сервер БД |
| `PB_LSP_DB_DATABASE` | `.local_secrets.json → pb_lsp.db_database` | База данных |
| `PB_LSP_DB_UID` | `.local_secrets.json → pb_lsp.db_uid` | Логин |

---

## 5. Запуск и мониторинг

### 5.1. Автоматический запуск

LSP-сервер запускается OpenCode Desktop автоматически при открытии файла с расширением `.sru`/`.srw`/`.srd`.

### 5.2. Мониторинг

```powershell
# Проверка статуса LSP
powershell -File C:\AIS\AI\Prod\scripts_pb_lsp\monitor_lsp.ps1

# Окно мониторинга
C:\AIS\AI\Prod\scripts_pb_lsp\MonitoringDialog.exe
```

### 5.3. Логи

Логи сервера сохраняются в `C:\AIS\AI\Prod\logs\pb_lsp\`.

---

## 6. Процесс восстановления после сбоя

```powershell
# 1. Перезапуск LSP
powershell -File C:\AIS\AI\Prod\scripts_pb_lsp\run_lsp.ps1

# 2. Очистка логов (при необходимости)
Remove-Item C:\AIS\AI\Prod\logs\pb_lsp\* -Force -ErrorAction SilentlyContinue

# 3. Перезапуск OpenCode Desktop (если LSP не поднимается)
Get-Process OpenCode | Stop-Process -Force
Start-Process "C:\Users\vchaga\AppData\Local\ai.opencode.desktop\OpenCode.exe"
```

---

## 7. Экономическая выгода

### 7.1. Сокращение времени анализа кода

| Задача | Без LSP | С LSP | Экономия |
|--------|---------|-------|----------|
| Поиск определения функции | Открытие PB IDE + поиск (~2 мин) | `Ctrl+Click` (~1 сек) | **99%** |
| Проверка синтаксиса SQL | Ручная проверка (~10 мин) | Автоматически при сохранении | **100%** |
| Навигация по проекту | Открытие PBL в IDE + поиск (~5 мин) | `workspace/symbol` (~2 сек) | **99%** |

### 7.2. Предотвращение ошибок

- **Валидация SQL:** синтаксические ошибки обнаруживаются до компиляции
- **Поиск неиспользуемого кода:** символы без ссылок (в разработке)
- **Контроль зависимостей:** видно, кто вызывает объект
