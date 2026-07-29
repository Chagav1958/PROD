# Правила сервиса GUI (Prod-GUI.ps1 + Settings-Module.ps1)

## Состав сервиса

| Файл | Назначение |
|------|------------|
| `bin\Prod-GUI.bat` | Точка входа: запускает Prod-GUI.ps1 |
| `bin\Prod-GUI.ps1` | Основное WPF-приложение с 15 операциями |
| `scripts\Settings-Module.ps1` | Модуль настроек (шифрование, валидация, экспорт/импорт) |
| `config\config.json` | Конфигурация путей и параметров |

## Зависимости

- **PowerShell 5.1** (Windows PowerShell, не PowerShell 7)
- **WPF** (Windows Presentation Foundation) — для GUI
- **DPAPI** (Data Protection API) — для шифрования мастер-ключа (только Windows)
- **Google Chrome** — для генерации PDF из HTML-документации
- **TortoiseSVN** (TortoiseMerge) — опционально, для сравнения файлов

## Известные ошибки и их предотвращение

### Prod-GUI.ps1 — общее

1. **Stop button: guiProcess → currentProcess** (Bug-012)
   - В обработчике кнопки Stop использовалась неверная переменная `$script:guiProcess` вместо `$script:currentProcess`
   - **Правило:** всегда использовать `$script:currentProcess` для доступа к запущенному процессу

2. **Дубликат кода Settings** (Bug-013)
   - Найден дубликат обработчика `$op.HasCustomUI` для Settings
   - Второй блок никогда не выполнялся (unreachable из-за `return` в первом)
   - **Правило:** при добавлении новых операций проверять нет ли дубликатов

3. **$_ не экранирован в here-string wrapper** (Bug-019)
   - В `@" "@` here-string `$_` интерполируется как `$null`
   - **Правило:** использовать `` `$_ `` в here-string для экранирования

4. **Таймаут вывода** (Bug-018)
   - Добавлен `$script:uiLastDataTime` — обнуляется при каждом новом выводе
   - Таймаут срабатывает только если нет данных > N секунд
   - Настраивается через `gui.output_timeout_seconds` в config.json
   - **Правило:** не уменьшать таймаут ниже 60 секунд для VSS-операций

5. **Пароль в temp-скрипте** (Bug-017)
   - Пароль экранируется: `$escapedPassword = $password -replace "'", "''"`
   - **Важно:** пароль не должен выводиться в лог в открытом виде

6. **Экранирование одинарных кавычек в script block** (Bug-023)
   - Скрипт-блок вставляется в `{ $escapedSbText }` (НЕ в кавычки)
   - Экранирование `' → ''` НЕ нужно внутри фигурных скобок
   - **Правило:** `$escapedSbText = $sbText` (без `-replace`)

### Prod-GUI.ps1 — VSS операции

7. **VSS пароль из Settings** (FEAT-005)
   - VSS-операции не имеют поля `VssPass` — пароль расшифровывается из config.json
   - Run handler injector: `$params['VssPass'] = $vssPwd`
   - **Правило:** при изменении VSS-операций не добавлять поле для пароля

8. **Update-VssProjectCombo стирает имя объекта** (Bug-020)
   - `$inner.Items.Clear()` — сохранять `$currentText = $inner.Text` перед очисткой
   - **Правило:** всегда сохранять и восстанавливать `$inner.Text`

9. **ComboBox Text не фиксируется при клике Run** (Bug-022)
   - Editable ComboBox не обновляет `.Text` до потери фокуса
   - **Исправление:** `Get-ComboBoxText` + `Get-InnerTextBox` — рекурсивный BFS-поиск TextBox через `VisualTreeHelper`
   - **Резерв:** `Template.FindName("PART_EditableTextBox")`, `ApplyTemplate()`

10. **Multi-select в DataGrid VSS Status** (Bug-024)
    - `SelectionMode = 'Extended'`, `SelectionUnit = 'FullRow'`
    - Обработчики Checkout/Undo используют `$dg.SelectedItems` с обходом через `foreach`
    - Для `SelectedItems` создаётся копия в `ArrayList` перед циклом (проблемы с живой коллекцией)
    - После операции — `$dg.Items.Refresh()` для обновления без перезагрузки

11. **$LASTEXITCODE теряется после Out-Null** (Bug-025)
    - `Out-Null` после вызова `ss.exe` теряет `$LASTEXITCODE`
    - **Правило:** вызывать VSS-функцию напрямую и проверять `$LASTEXITCODE` сразу после, без конвейера

### Settings-Module.ps1

12. **Get-MasterKey failure при первом запуске** (Bug-014)
    - `ConvertTo-SecureString` падает при первой загрузке на новой машине (DPAPI ключ привязан к пользователю/компьютеру)
    - **Исправление:** `Get-MasterKey` возвращает `$null` при ошибке
    - `Build-SettingsUI` и `Save-Settings` создают ключ автоматически

13. **Пароль VSS: шифрование AES-256** (Bug-014)
    - Пароль VSS шифруется AES-256 с мастер-ключом через Windows DPAPI
    - Хранится в `config.json` в поле `password_encrypted`
    - Мастер-ключ: `master_key_encrypted` (DPAPI SecureString)
    - **При переносе на другой компьютер:** мастер-ключ создаётся заново

14. **Отступы в полях настроек** (Bug-015, Bug-016)
    - GroupBox margin: `0,0,6,0`
    - Field margin: `0,0,2,0`
    - Label margin: `0,0,0,0`
    - **Правило:** не увеличивать отступы без необходимости — окно станет слишком высоким

15. **Тестирование после изменений Settings**
    - После любого изменения Build-SettingsUI, Attach-SettingsHandlers или Save-Settings:
      1. Все поля отображаются после Save, Reset, переключения вкладок
      2. Поля сгруппированы по назначению
      3. Вертикальные отступы минимальны

### WPF особенности

16. **WPF в PowerShell 5.1**
    - Загрузка сборок: `[System.Reflection.Assembly]::LoadWithPartialName`
    - XML-разметка: `[xml]` — разбор XAML
    - **Правило:** не использовать функционал из WPF 4.5+, только то, что доступно в .NET 3.5/4.x

17. **Потокобезопасность**
    - UI-элементы обновляются ТОЛЬКО из UI-потока
    - Для фоновых задач используется `System.Windows.Forms.Timer`
    - Вывод в `$outputBox.Text += "..."` только из callback таймера

18. **Ссылка на PDF в HTML-документации**
    - HTML содержит ссылку на PDF и наоборот
    - При изменении HTML нужно перегенерировать PDF через Chrome headless

## Рекомендации

- Все пути настраиваются через config.json (никаких hardcoded путей в GUI)
- История операций хранится в `vss_object_history.json` (макс. объектов настраивается)
- История Task Name хранится в том же файле по ключу `"TaskName_Shared"`
- После любого изменения GUI — тестировать все 15 операций
- Кнопка Run находится под селектором операций (Run per operation); Stop — внизу окна
- Результат операции выводится в popup-окне; Output содержит только протокол выполнения
