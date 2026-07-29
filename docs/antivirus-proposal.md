# Предложение для отдела технической поддержки
## Исключения антивируса для проекта AIS Release Preparation

### Контекст

Проект **AIS Release Preparation** — внутренний инструмент для подготовки релизов страхового продукта "Ренессанс". Инструмент автоматизирует сравнение SQL-объектов, выгрузку из PowerBuilder, работу с Jira/RFC и контроль версий (VSS). Проект написан на PowerShell 5.1, Python 3.12 и BAT-скриптах.

**Антивирус на рабочей станции разработчика уже вызывал проблемы** — пришлось переписывать код, чтобы избежать ложных срабатываний.

---

### Что уже было изменено из-за антивируса

| Проблема | Что сделано |
|----------|------------|
| `user32.dll` P/Invoke (ShowWindow) в скрытии консоли | Заменён на чистый .NET `Start-Process -WindowStyle Hidden` |
| P/Invoke в всех Show-*.ps1 скриптах | Удалён `Invoke-HiddenDialog` из Show-OpStatus, Show-Prompts и др. |
| WPF-код с `Add-Type -TypeDefinition` (Win32 API) | Заменён на управляемые .NET-аналоги |

**Файл:** `scripts\Hide-ConsoleWindow.ps1` (строка 3: `# НЕ использует P/Invoke — антивирус не детектит`)

---

### Рекомендуемые исключения для антивируса

#### 1. Директории (сканирование исключить)

| Директория | Назначение |
|------------|-----------|
| `C:\AIS\AI\Prod\` | Корень проекта (PowerShell-скрипты, BAT-файлы, Python-сервер) |
| `C:\AIS\1 Release\` | Релизы (SQL-файлы, .sr* файлы PowerBuilder) |
| `C:\SRC125\gold` | Исходники PowerBuilder (PBL-библиотеки, только чтение) |
| `C:\Work\gold` | Текущая рабочая копия PowerBuilder |

#### 2. Исполняемые файлы (не удалять/не блокировать)

| Файл | Назначение | Почему может сработать |
|------|-----------|------------------------|
| `C:\AIS\AI\Prod\tools\pbldump-1.3.1stable\PblDump.exe` | Экспорт объектов PowerBuilder из PBL-библиотек | Неизвестная утилита, может детектиров как PUA |
| `C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe` | Microsoft Visual SourceSafe — контроль версий | Старое ПО (2005), может срабатывать эвристика |
| `C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe` | Программа сравнения/слияния файлов | Вызывается скриптами для просмотра различий |

#### 3. Python-зависимости (MCP-серверы базы знаний)

| Директория | Назначение |
|------------|-----------|
| `C:\AIS\AI\Prod\scripts\ais_catalog_mcp\` | MCP-сервер каталога проекта AIS (Python) |
| `C:\AIS\AI\Prod\scripts\ais_catalog_mcp\lib\` | Python-пакеты: cryptography, pywin32, mcp, uvicorn и др. |
| `C:\AIS\AI\Prod\scripts\opencode_mcp\` | MCP-сервер знаний об OpenCode (Python) |
| `C:\AIS\AI\Prod\scripts\opencode_mcp\lib\` | Python-пакеты MCP-сервера |

Python-пакеты содержат `.exe`-файлы (uvicorn.exe, mcp.exe, pythonservice.exe), которые антивирус может ошибочно классифицировать как подозрительные.

> ПРИМЕЧАНИЕ: сервер `knowledge_mcp` удалён (рудимент, БД пуста, 17.07.2026). Его исключать НЕ нужно.

#### 4. BAT-файлы (не блокировать запуск)

| Файл | Назначение |
|------|-----------|
| `bin\Prod-GUI.bat` | Лончер GUI-приложения |
| `bin\SQL_exp_single.bat` | Экспорт одного SQL-объекта из БД |
| `bin\SQL_exp_param.bat` | Полный SQL-экспорт |
| `bin\SQL_exp_ready.bat` | SQL-экспорт из папки Ready |
| `bin\prepare_release.bat` | Главный оркестратор подготовки релиза |
| `bin\AIS_export.bat` / `bin\AIS_export_flexible.bat` | Выгрузка проекта |
| `bin\Export-Service.bat` / `bin\Export.bat` | Сервис экспорта |
| `bin\Claude-PB-SQL.bat` | Интеграция с Claude (AI-ассистент) |

#### 4.1. OpenCode (AI-ассистент) — КРИТИЧНО

| Объект | Назначение | Почему срабатывает |
|--------|-----------|--------------------|
| `C:\Users\vchaga\AppData\Local\Programs\@opencode-aidesktop\OpenCode.exe` | Главный исполняемый файл OpenCode (Electron/Node) | Поведенческий анализ `PDM:Trojan.Win32.Generic` — легитимно запускает powershell, пишет файлы, ходит в сеть к LLM API |
| `C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\` | Кэш и настройки OpenCode (в т.ч. `Cache\Cache_Data\`) | Эвристика `HEUR:Trojan.PowerShell.Obfus.b` на бинарный кэш (содержит фрагменты веб-контента/кода, которые рендерит приложение) |
| `C:\Users\vchaga\AppData\Local\Programs\@opencode-aidesktop\` | Папка установки OpenCode | Исключить из сканирования целиком |

**Факт проверки (17.07.2026):** SHA256 `OpenCode.exe` = `673025C27F2FDDD129D22DFAC9F5755BA3455C7F2C3830D12F11F91BD49E3BCA` — совпадает с хэшем из отчёта антивируса. Файл легитимный, не изменён. Оба срабатывания — FALSE POSITIVE.

**Исключить из сканирования:**
- Директорию `C:\Users\vchaga\AppData\Local\Programs\@opencode-aidesktop\` (целиком)
- Директорию `C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\` (целиком)
- Процесс `OpenCode.exe` из поведенческого (HIPS/PDM) мониторинга

**Важно:** файлы кэша (`Cache_Data\f_xxxxxx`) удалять/восстанавливать вручную НЕ нужно — OpenCode пересоздаёт кэш автоматически при запуске.

#### 5. PowerShell-скрипты (не блокировать выполнение)

| Файл/Директория | Назначение |
|-----------------|-----------|
| `bin\Prod-GUI.ps1` | Основной GUI (4600+ строк, WPF) |
| `scripts\*.ps1` | Все рабочие скрипты (выгрузка, сравнение, экспорт) |
| `scripts\ais_catalog_mcp\server.py` | Python MCP-сервер каталога (запускается из OpenCode) |
| `scripts\opencode_mcp\server.py` | Python MCP-сервер знаний об OpenCode |

#### 6. Сетевые ресурсы (не блокировать доступ)

| Ресурс | Назначение |
|--------|-----------|
| `\\ren-msksf01\VSS2005\` | База VSS (совместный доступ к файлам версий) |
| `localhost:4096` | Локальный HTTP-сервер OpenCode API |
| `https://mytask.renins.com` | Jira Cloud (создание RFC и комментариев) |

---

### Дополнительные рекомендации

1. **Не включать "облачное сканирование"** для `.ps1`-файлов — PowerShell-скрипты с шифрованием паролей (AES) могут детектироваться как "-script obfuscation"

2. **Не сканировать `.sql`-файлы** в `C:\AIS\AI\Prod\BD\` — это экспорты из Sybase ASE, содержат SQL-команды (CREATE PROCEDURE, GRANT и т.д.)

3. **Не блокировать `Start-Process -WindowStyle Hidden`** — используется для скрытия вспомогательных консолей (legitimate use)

4. **Не блокировать network-запросы** на `localhost:4096` (OpenCode API) и `\\ren-msksf01\VSS2005\` (VSS-база)

---

### Последствия блокировки

| Если заблокировано | Чему мешает |
|-------------------|-------------|
| `PblDump.exe` | Невозможность выгрузки объектов PowerBuilder из PBL |
| `ss.exe` | Невозможность работы с контролем версий (checkout/checkin/status) |
| `TortoiseMerge.exe` | Невозможность визуального сравнения файлов |
| BAT-файлы | Полная неработоспособность инструмента |
| PowerShell-скрипты | Полная неработоспособность инструмента |
| Python-пакеты | Неработоспособность MCP-сервера базы знаний |
| Сеть `\\ren-msksf01` | Невозможность доступа к VSS |
| Сеть `localhost:4096` | Невозможность AI-ассистента (OpenCode) |

---

### Итого

| Тип исключения | Кол-во |
|----------------|--------|
| Директории | 4 (+2 OpenCode) |
| Исполняемые файлы | 3 (+1 OpenCode.exe) |
| BAT-файлы | 10 |
| Python-директория | 2 (ais_catalog_mcp, opencode_mcp) |
| Сетевые ресурсы | 3 |
| **Всего** | **~22 исключения** |

---

*Подготовлено: AIS Release Preparation*
*Дата: 17.07.2026 (обновлено: добавлены исключения OpenCode, удалён knowledge_mcp)*
*Контакт: vchaga*
