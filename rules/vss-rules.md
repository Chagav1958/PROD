# rules/vss-rules.md — Правила VSS (Visual SourceSafe)

## Баги и исправления

### BUG-001: SSDIR устанавливается в путь к файлу вместо каталога
**Дата обнаружения:** 19.06.2026
**Симптом:** `ss.exe : No VSS database (srcsafe.ini) found`
**Причина:** `$env:SSDIR = $VssPath` где `$VssPath` = `\\server\share\srcsafe.ini`. SSDIR должен указывать на **каталог**, а не на файл.
**Исправление:** В `scripts/VSS-Utils.ps1` добавить проверку:
```powershell
if ($VssPath -match 'srcsafe\.ini$') {
    $VssPath = [System.IO.Path]::GetDirectoryName($VssPath)
}
$env:SSDIR = $VssPath
```
**Статус:** ✅ Исправлено

### BUG-002: Поля VSS не отображаются в GUI
**Дата обнаружения:** 19.06.2026
**Симптом:** При выборе VSS-операции панель параметров пустая, видны поля SQL-экспорта
**Причина:** `BuildParams` падал с ошибкой при создании Hint TextBlock (WPF TextBlock.Text issue в PowerShell 5.1)
**Исправление:** Отключить Hint функциональность в `New-ParamField`, `New-ParamComboField`, `New-ParamCheckbox`. Использовать `[System.Windows.Media.Brushes]::Black` вместо `BrushConverter`.
**Статус:** ✅ Исправлено

### BUG-003: WPF TextBlock.Text ошибка в PowerShell 5.1
**Дата обнаружения:** 19.06.2026
**Симптом:** `Не удается задать свойство "Text" для объекта типа "System.Windows.Controls.TextBlock"`
**Причина:** PowerShell 5.1 не может установить Text property на TextBlock при создании через `New-Object` с UTF-8 BOM файлом
**Исправление:** Временно отключить Hint. Использовать `[System.Windows.Media.Brushes]::Black` вместо `BrushConverter::new().ConvertFromString()`
**Статус:** ✅ Исправлено (Hint отключен)

### BUG-004: ComboBox.Text не работает в WPF через PowerShell
**Дата обнаружения:** 19.06.2026
**Симптом:** Ошибка при установке `$cb.Text = $Default` на editable ComboBox
**Причина:** WPF ComboBox в PowerShell не поддерживает прямую установку Text property
**Исправление:** Добавлять Default значение в Items и устанавливать SelectedItem
**Статус:** ✅ Исправлено

## Конфигурация VSS

### Параметры подключения
- **VSS DB Path:** `\\ren-msksf01\VSS2005\srcsafe.ini` (или каталог `\\ren-msksf01\VSS2005`)
- **VSS Username:** `User` (из config.json)
- **VSS Password:** Вводится в GUI, не сохраняется в файлах
- **VSS Project:** `$/SRC125` (для PowerBuilder объектов)

### Операции VSS в GUI
| Операция | RusName | Описание |
|----------|---------|----------|
| VSS: Get Latest Version | VSS: Получить последнюю версию | Обновление одного объекта или всех библиотек из .pbt |
| VSS: Check Status | VSS: Проверить статус | Проверка Checked In/Out |
| VSS: Who Is Using | VSS: Кто использует | Кто извлёк объект |
| VSS: Checkout | VSS: Checkout (Извлечь) | Извлечение для редактирования |
| VSS: Checkin | VSS: Checkin (Сохранить) | Сохранение изменений |

### Поля VSS-операций
- **VssPath** — Путь к БД VSS (история не сохраняется)
- **VssUser** — Пользователь VSS
- **VssPass** — Пароль VSS (НЕ сохраняется в файлах!)
- **Project** — Объект VSS (ComboBox с историей в `config/vss_object_history.json`)
- **PbtFile** — PBT-файл для массового обновления (только для Get Latest)
- **Comment** — Комментарий (для Checkout/Checkin)
- **Recursive** — Чекбокс рекурсии

### История объектов VSS
- Файл: `config\vss_object_history.json`
- Формат: `{ "VSS: Check Status": ["$/SRC125/file.pbl", ...], ... }`
- Максимум 100 записей на операцию
- Пароль VSS НЕ сохраняется в истории
- ComboBox с автодополнением: фильтрация по введённому тексту, показ последних 100 объектов при пустом поле

### BUG-012: ss.exe зависает при проверке статуса
**Дата обнаружения:** 20.06.2026
**Симптом:** Программа зависает при выполнении "VSS: Проверить статус"
**Причина:** `ss.exe` ждёт ввода пользователя (подтверждение), GUI не передаёт ввод. Таймаут был 600 сек.
**Исправление:** 
- Добавлен флаг `-I-` во все команды ss.exe (подавление запросов)
- Таймаут сокращён с 600 до 30 секунд
- Вывод команды ss.exe теперь показывает выполняемую команду
**Статус:** ✅ Исправлено

## Команды ss.exe

| Команда | Синтаксис | Пример |
|---------|-----------|--------|
| Get | `ss Get $/Project/File -I- -Yuser,pass [-R]` | `ss Get $/SRC125/app.pbl -I- -YUser,12345` |
| Status | `ss Status $/Project/File -I- -Yuser,pass [-R]` | `ss Status $/SRC125/folder/file.srd -I- -YUser,12345` |
| Properties | `ss Properties $/Project/File -I- -Yuser,pass` | `ss Properties $/SRC125/app.pbl -I- -YUser,12345` |
| Checkout | `ss Checkout $/Project/File -I- -Yuser,pass -C"comment"` | `ss Checkout $/SRC125/app.pbl -I- -YUser,12345 -C"fix"` |
| Checkin | `ss Checkin $/Project/File -I- -Yuser,pass -C"comment"` | `ss Checkin $/SRC125/app.pbl -I- -YUser,12345 -C"done"` |

**Важно:** Флаг `-I-` подавляет все запросы к пользователю (предотвращает зависание).

## Формат пути VSS

✅ **Правильно:** `$/SRC125/golden_collection/d_dvou2020_rep_data.srd`
❌ **Неправильно:** `d_dvou2020_rep_data` (нет `$/`)
❌ **Неправильно:** `$/SRC125/gold/...` (`gold` — это БД, а не папка в VSS)

**Структура:** `$/SRC125/<папка>/<файл.расширение>`

### BUG-005: VSS Status -R на $/SRC125 превышает таймаут + отсутствие потокового вывода
**Дата обнаружения:** 20.06.2026
**Симптом:** VSS Check Status с Project=$/SRC125 и Recursive=true → таймаут через 30/60 секунд
**Причина:**
1. `ss.exe Status $/SRC125 -R` обрабатывает ~1040 файлов (~33 секунды), превышая hardcoded таймаут 30с
2. `Invoke-VssCommand` возвращал массив `$output`, из-за чего pipeline получал весь вывод одним куском
**Исправление:**
- Таймаут вынесен в `config.json` (`gui.output_timeout_seconds`, по умолчанию 60). Добавлен в панель Settings → GUI.
- **Streaming:** `Invoke-VssCommand` и все wrapper-функции (Get-VssLatest, Get-VssStatus и т.д.) теперь не захватывают вывод в `$output` — каждая строка ss.exe идёт напрямую в pipeline
- **Защита от зависания:** Таймаут теперь ждёт НЕ стартовое время, а время с последнего вывода (`uiLastDataTime`)
**Статус:** ✅ Исправлено

## Правила безопасности
- ⚠️ **Пароль VSS никогда не сохраняется в файлах**
- ️ **Пароль передаётся только как параметр командной строки**
- ⚠️ **История объектов VSS не содержит паролей**
