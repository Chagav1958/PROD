# rules/tool-usage.md — Правила использования инструментов

## ️ ЗАПРЕЩЁННЫЕ ИНСТРУМЕНТЫ
- **НЕ использовать `list_directory`** — этот инструмент НЕ существует в системе
- При попытке вызова `list_directory` возникает ошибка: "Model tried to call unavailable tool 'list_directory'"

## ✅ ПРАВИЛЬНЫЕ ИНСТРУМЕНТЫ ДЛЯ РАБОТЫ С ФАЙЛАМИ

### Чтение содержимого директории
- Используйте `read` с путем к директории: `read(filePath="C:\path\to\dir")`
- Используйте `glob` для поиска файлов по шаблону: `glob(pattern="**/*.ps1")`
- Используйте `bash` с командой `dir` или `Get-ChildItem` для листинга

### Чтение файлов
- `read(filePath="C:\path\to\file.txt")` — чтение файла
- `grep(pattern="search", path="C:\path")` — поиск по содержимому

### Запись файлов
- `write(filePath="C:\path\to\file.txt", content="...")` — создание/перезапись файла
- `edit(filePath="C:\path\to\file.txt", oldString="...", newString="...")` — редактирование

## ✅ ДОСТУПНЫЕ ИНСТРУМЕНТЫ
- `bash` — выполнение команд PowerShell
- `edit` — редактирование файлов
- `glob` — поиск файлов по шаблону
- `grep` — поиск по содержимому файлов
- `list_mcp_resource_templates` — шаблоны ресурсов MCP
- `list_mcp_resources` — ресурсы MCP
- `question` — вопросы пользователю
- `read` — чтение файлов и директорий
- `read_mcp_resource` — чтение ресурсов MCP
- `skill` — загрузка навыков
- `task` — запуск подзадач
- `todowrite` — управление списком задач
- `webfetch` — получение веб-контента
- `write` — запись файлов

## ПРАВИЛО ПРОВЕРКИ
- Перед вызовом любого инструмента убедиться, что он есть в списке доступных
- Если нужен листинг директории — использовать `read` или `glob` или `bash` с `Get-ChildItem`
- НИКОГДА не использовать `list_directory`
