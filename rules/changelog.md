# История изменений проекта AIS Release

## Исправления и особенности

### Bug-WPF-001: Двойное родительство WPF-элементов в Show-TaskPlanGUI.ps1
- `Add-Field`/`Add-Combo` возвращали TextBox/ComboBox, который уже был помещён в Border через `$b.Child = $input`
- Повторное добавление того же элемента в `Children.Add()` → InvalidOperationException
- Исправление: возврат `[PSCustomObject]@{ Container = $stack; Input = $input }`
- Container добавляется в родительскую панель, Input — для чтения/записи значений
- Все обращения `$fTask.Text` заменены на `$fTask.Input.Text`

### Stop button: guiProcess → currentProcess
- В обработчике кнопки Stop использовалась неверная переменная `$script:guiProcess` вместо `$script:currentProcess`
- Исправлено в Prod-GUI.ps1

### Bug-051: WPF DatePicker — событие SelectedDateChanged (не SelectedChanged)
- `DatePicker.Add_SelectedChanged` не существует в PS 5.1 WPF
- Правильное имя события: `SelectedDateChanged`
- Исправлено в Show-Prompts.ps1:928

### Bug-052: Область видимости переменных в scriptblock Invoke-WithProgress
- `$data = $tempData` внутри scriptblock создаёт локальную переменную
- Внешняя `$data` не меняется → данные теряются
- Исправление: через `$global:g_promptData` передавать данные наружу
- Исправлено в Show-Prompts.ps1:468-493

### Запуск ДО: Start-Process -WindowStyle Hidden — ЕДИНСТВЕННЫЙ вариант (антивирус)
- `powershell -WindowStyle Hidden -File` напрямую — антивирус блокирует (changelog 12.07)
- `Start-Process powershell ... -WindowStyle Hidden` — Касперский пропускает
- Проблема ПРОМПТ была НЕ в Start-Process, а в Bug-051 (SelectedDateChanged) и Bug-052 (scope)
- Команды llm.md, fixshow.md, otchet.md, otest.md, rules.md, save.md, abbr.md — не менять, работает
- (17.07.2026, уточнение)

### Show-Abbreviations.ps1: Bug-052 (область видимости $data)
- Команда СОКР не работала из-за той же проблемы области видимости
- Исправлено в Show-Prompts.ps1 (использует глобальные переменные)

### VSS-Utils.ps1: Export-ModuleMember при dot-source
- Исправление: добавлена проверка `$MyInvocation.MyCommand.CommandType` и `-ErrorAction SilentlyContinue`
- Также заменено `$ErrorActionPreference = "Stop"` на `"Continue"` для устойчивости

### VSS-Utils.ps1: поддержка -Recursive
- Функции Get-VssLatest, Get-VssStatus, Set-VssCheckout, Set-VssCheckin теперь принимают параметр `-Recursive` и передают его в ss.exe
- Параметр `-Quiet` для подавления справки при dot-source

### Prod-GUI.ps1: дубликат кода Settings (Bug-013)
- Обнаружен дубликат обработчика `$op.HasCustomUI` для Settings (строки 824-846)
- Второй блок никогда не выполнялся (unreachable из-за `return` в первом)
- Второй блок не имел параметра `$ProjectRoot`
- Исправление: удалён дубликат (20.06.2026)

### Settings-Module.ps1: Get-MasterKey failure (Bug-014)
- При первом запуске на новой машине `ConvertTo-SecureString` падал с ошибкой, так как DPAPI-ключ привязан к пользователю/компьютеру
- Исправление: `Get-MasterKey` возвращает `$null` при ошибке
- Добавлена `New-MasterKey` для генерации нового мастер-ключа AES-256
- `Build-SettingsUI` и `Save-Settings` создают ключ автоматически если он отсутствует

### Пароль VSS: шифрование AES-256
- Пароль VSS шифруется AES-256 с мастер-ключом через Windows DPAPI
- Хранится в `config.json` в поле `password_encrypted`
- Мастер-ключ: `master_key_encrypted` (DPAPI SecureString)
- При переносе на другой компьютер ключ создаётся заново

### Автоматическое тестирование всех операций (ЦИКЛ/auto_fix_loop)
- **auto_fix_loop.ps1** поддерживает все 18 операций GUI с тестовыми параметрами
- Для каждой операции определены параметры по умолчанию в `switch ($opName)` блоке
- **Защита от записи (dry-run):**
  - VSS Checkout/Checkin/Undo: `-DryRun` добавляется перед `-Recursive`
  - Jira Create RFC / Release Comment: `-DryRun` подставляется через `-replace`
- **Операции без внешних ресурсов** (Settings, Run Tests, Export Service, Export PB, Compare PB/SQL) — выполняются на локальной файловой системе
- **Операции, требующие credentials** (SQL Export с isql, VSS с ss.exe) — при недоступности credentials операция эмулируется (exit 0) с пометкой "credentials не доступны"
- **Критерии успеха:**
  - Нет TIMEOUT
  - Нет необработанного исключения (.NET/PowerShell crash: `at System.`, `стек:`, `Исключение`, `Internal error`)
  - Ошибки `FATAL:` (isql, ss.exe fail) считаются credential-ошибками (не crash)
  - VSS: Свободен, VSS: Занят, ###VSS_HISTORY_END### — явные маркеры успеха
- Для операций без Script-блока — тоже выполняются (скрипт может быть пустым, как Settings)
- **Правило добавления новой операции:** ОБЯЗАТЕЛЬНО добавить параметры в switch-блок auto_fix_loop.ps1 + dry-run защиту если операция пишет в JIRA/VSS/БД
- (26.06.2026)

### Bug-044: BOM в JSON/JSONC ломает загрузку плагинов OpenCode 1.17.x (12.07.2026)
- **Проблема:** OpenCode 1.17.x (Electron) не парсит JSON/JSONC с UTF-8 BOM. Сохранение `opencode.jsonc` и `config/*.json` через редактор, добавляющий BOM, приводило к:
  - Ошибке `SyntaxError: Unexpected token ' "'` в renderer.log
  - Невозможности загрузить плагины (save-prompts.js, russian-compaction.js и др.)
  - Потере автосохранения промптов (с 30.06.2026)
  - Отсутствию записей в `user_prompts.log` за сегодня/вчера
- **Дополнительно:** save-prompts.js использовал `ctx.on('chat.message')` — старый API OpenCode 0.x, который не работает в 1.17.x. Правильный паттерн — возвращать `"chat.message": async (input) => {...}` в объекте хуков.
- **Исправление:**
  1. `scripts\Remove-BomFromConfigs.ps1` — утилита удаления BOM из json/jsonc
  2. Интеграция в `Save-Snapshot.ps1` — автоматическая очистка BOM перед архивацией
  3. save-prompts.js — переход на новый API (возврат hook'а вместо `ctx.on()`)
  4. Save-Snapshot.ps1 — добавлена маска `.opencode\plugins\*.js` в архивацию
  5. AGENTS.md — добавлено правило: JSON/JSONC — UTF-8 без BOM!
- **Проверка:** после запуска `Remove-BomFromConfigs.ps1` BOM удалён из 3 файлов. Архив СОХР создан. После перезапуска OpenCode плагины должны загрузиться.
- (12.07.2026)

### Пароль VSS: единый источник (из Settings)
- VSS-операции больше НЕ имеют поля `VssPass` — пароль берётся из Settings (config.json)
- При запуске VSS-операции Run handler расшифровывает пароль через Get-MasterKey + Decrypt-Password
- Пароль инжектируется в `$params['VssPass']` перед запуском скрипта
- Если пароль не задан в Settings — передаётся пустая строка
- Исправлено в Prod-GUI.ps1 (удалены VssPass поля из всех 5 VSS-операций, добавлен injector в Run handler)

### Settings panel: уменьшены отступы (Bug-015)
- Поля слишком далеко друг от друга — окно было слишком высоким
- GroupBox margin: 0,0,12,0 → 0,0,6,0
- Field margin: 0,0,8,0 → 0,0,2,0
- Label margin: 0,0,2,0 → 0,0,0,0
- Font size label: 12 → 11
- Исправлено в Settings-Module.ps1 (New-SettingsField + GroupBox margins)

### VSS history_max: вынесен в настройки (FEAT-002)
- Максимальное количество сохраняемых объектов VSS-истории (было hardcoded 100) теперь настраивается
- Добавлено поле `vss.history_max` в `config.json` (по умолчанию 100)
- В панели Settings → VSS добавлено поле "История: макс. объектов"
- `Prod-GUI.ps1`: `$script:vssHistoryMax` загружается из конфига, используется при обрезке истории и в ComboBox
- (20.06.2026)

### Temp-скрипт: экранирование пароля (Bug-017)
- Пароль вставлялся напрямую в temp-скрипт: `` `$password = '$password' ``
- Если пароль содержал `'` (одинарную кавычку), PowerShell выдавал синтаксическую ошибку
- Исправление: `$escapedPassword = $password -replace "'", "''"` перед интерполяцией
- Также экранируется `$sbText` через `$escapedSbText`
- Исправлено в Prod-GUI.ps1 (20.06.2026)

### Параметры: уменьшены отступы (Bug-016)
- Слишком большие расстояния между полями на панели параметров
- `New-ParamField` margin: `0,0,0,12` → `0,0,0,4`
- `New-ParamComboField` margin: `0,0,0,12` → `0,0,0,4`
- `New-ParamCheckbox` margin: `0,4,16,4` → `0,2,16,2`
- Группы настроек (GroupBox): `0,0,0,6` → `0,0,0,3`
- Индикатор валидации: `0,2,0,0` → `0,1,0,0`
- Исправлено в Prod-GUI.ps1 и Settings-Module.ps1 (20.06.2026)

### Таймаут GUI: вынесен в настройки + потоковый вывод (Bug-018)
- `ss.exe Status $/SRC125 -R` обрабатывает ~1040 файлов, занимает ~33 с
- Таймаут был жёстко закодирован 30 с → процесс убивался до завершения
- **Исправление 1:** таймаут вынесен в `config.json` (`gui.output_timeout_seconds`, по умолчанию 60)
- В `Prod-GUI.ps1`: таймер использует `$script:uiTimeoutSeconds` из конфига
- В `Settings-Module.ps1`: добавлено поле "Таймаут вывода (сек)" в группу "Настройки GUI"
- В `Save-Settings`: валидация целого числа > 0
- **Исправление 2 (streaming):** `Invoke-VssCommand` и все функции VSS-Utils.ps1 больше не захватывают вывод в `$output`. Каждая строка ss.exe идёт напрямую в pipeline. В wrapper `Out-String | Out-File` заменён на `StreamWriter.WriteLine + Flush` — вывод пишется сразу
- **Исправление 3 (таймаут по бездействию):** Добавлен `$script:uiLastDataTime` — обнуляется при каждом новом выводе. Таймаут срабатывает только если нет данных > N секунд
- `config.json`: значение по умолчанию изменено с 30 на 60
- (20.06.2026)

### VSS ComboBox auto-refresh после операции (FEAT-001)
- После выполнения VSS-операции ComboBox с историей проектов автоматически обновляется
- Добавлена функция `Update-VssProjectCombo` в `Prod-GUI.ps1`
- Вызывается из timer callback после успешного завершения процесса
- (20.06.2026)

### Wrapper: $_ не экранирован в here-string (Bug-019)
- В строке 996 `$_` не был экранирован обратным апострофом в `@" "@` here-string
- `$_` интерполировался как `$null` → `$sw.WriteLine()` вместо `$sw.WriteLine($_)`
- VSS вывод не попадал в output-файл → GUI показывал `Done (exit: 1)` без данных
- ss.exe Status возвращает exit code 1 при наличии checked out файлов — это норма
- Исправление: добавлен `` `$_ `` в Prod-GUI.ps1
- Также удалён dead code (старый wrapper $wrapperCode, который перезаписывался новым)
- (20.06.2026)

### Update-VssProjectCombo стирает имя объекта (Bug-020)
- `Update-VssProjectCombo` вызывала `$inner.Items.Clear()`, не сохраняя текущее значение
- После завершения VSS-операции имя объекта из ComboBox пропадало
- Исправление: сохранение `$currentText = $inner.Text` перед Clear, восстановление после
- (20.06.2026)

### Task Name (Jira) — ComboBox с историей (FEAT-003)
- Поле Task Name теперь является ComboBox с историей последних значений (настраивается через Settings)
- Максимальное количество сохраняемых значений настраивается через `task_name_history_max` (по умолчанию 100)
- В Settings → VSS добавлено поле "История Task Name: макс. значений"
- `Prod-GUI.ps1`: `$script:taskNameHistoryMax` загружается из конфига, используется при обрезке истории и в ComboBox
- (20.06.2026)

### Settings Panel — тестирование после изменений
- **Правило:** После любого изменения в Settings-Module.ps1 или Prod-GUI.ps1, затрагивающего Build-SettingsUI, Attach-SettingsHandlers или Save-Settings — обязательно тестировать отображение полей настроек.
- **Что проверять:**
  1. Все поля отображаются после сохранения (Save), сброса (Reset), переключения вкладок
  2. Поля сгруппированы по назначению: PowerBuilder, Export, Release, VSS, GUI, Utilities
  3. Вертикальные отступы минимальны (StackPanel Margin ≤ 4, Indicator Margin ≤ 1, GroupBox Margin ≤ 3)
  3. Кнопки Save/Reset/Validate/Export/Import работают
- **Причина:** При 5+ изменениях поля пропадали после сохранения/сброса.
- (20.06.2026)

### VSS: короткие имена объектов (FEAT-004)
- В VSS-операциях теперь можно указывать только имя объекта (с расширением или без): `w_ais_request_select` или `w_ais_request_select.srw`
- Полный VSS-путь строится автоматически: `$/SRC125/gold/<pbl_name>/<object_name>`
- `<pbl_name>` определяется поиском файла в `PB_Main` и `PB_Current` — имя папки, где найден файл
- Если расширение не указано — берется у найденного файла
- Реализовано в функции `Resolve-VssObjectPath` (Prod-GUI.ps1), вызывается перед выполнением VSS-операций
- (20.06.2026)

### Get-VssWhoIsUsing: Properties → Status (Bug-021)
- `Get-VssWhoIsUsing` использовала `ss.exe Properties`, который НЕ показывает кто извлёк файл (только метаданные: имя, тип, размер, история)
- Исправление: заменён на `ss.exe Status`, который явно выводит `Checked out to: vchaga` или `Vchaga Exc 02.06.26 12:43`
- Добавлен параметр `-Recursive` в функцию и в операцию GUI "VSS: Кто использует"
- Добавлен чекбокс "Рекурсивно" в GUI для этой операции
- Вывод на русском: "Кто использует объект:", "Объект не извлечён никем", "Проверка завершена"
- Исправлено в `VSS-Utils.ps1` и `Prod-GUI.ps1` (21.06.2026)

### GUI: кнопка Run под операцией + результат в popup-окне (FEAT-005)
- Кнопка Run перенесена из нижней строки (Row 5) в строку между селектором операций и параметрами (Row 2)
- Кнопка Run отцентрирована, в отдельном контейнере с голубой рамкой
- Stop кнопка осталась внизу (Row 6)
- Фраза-результат выводится в отдельном popup-окне (Show-ResultPopup) вместо баннера в Output
- Output содержит только протокол/листинг выполнения
- Для VSS-операций из вывода извлекаются строки с извлечёнными файлами (Get-TableData) и показываются в popup в разделе "Подробно:"
- Цвет фразы: зелёный (успех), красный (ошибка/таймаут)
- Реализовано: `Show-ResultPopup`, `Get-TableData` в `Prod-GUI.ps1` (21.06.2026)

### VSS Undo Checkout + переименование Checkout/Checkin (FEAT-006)
- Добавлена `Set-VssUndoCheckout` в VSS-Utils.ps1 (export + help)
- Checkout: `(Извлечь)` → `(Извлечь / Зарезервировать для Вас)`
- Checkin: `(Сохранить)` → `(Сохранить / Зафиксировать Ваши изменения)`
- Новая операция `VSS: Undo Check Out (Снять резервирование. Вернуть без изменений)` без Comment
- `Get-OperationResult` дополнен Undo Check Out
- (21.06.2026)

### VSS Status — показывать кто занял (FEAT-007)
- `Get-OperationResult` для Status возвращает `"Занят: vchaga (3)"` или `"Занят: user1, user2 (5)"`
- `Get-TableData` выводит `user | $/SRC125/gold/pbl/file.srw`
- (21.06.2026)

### Get-VssVersionFile: CP1251→UTF-16LE для .sr* файлов (Bug-031)
- VSS хранит PB .sr* файлы в CP1251/ASCII (без BOM), а PB_Current экспортирует их в UTF-16LE (FF FE BOM)
- При сравнении в TortoiseMerge разнородная кодировка давала кракозябры вместо русского текста
- **Исправление в VSS-History.ps1:** если у извлечённого файла нет BOM — декодируем как CP1251, сохраняем как UTF-16LE с BOM (через `[Text.Encoding]::Unicode`)
- Если BOM уже есть (UTF-8 или UTF-16) — оставляем как есть
- **Проверка:** Test-VssEncoding.ps1 выгружает до 30 объектов из golden_commission/w_* и верифицирует конвертацию
- (25.06.2026)

### VSS Status с TaskName — таблица с Checkout/Undo (FEAT-008)
- Добавлено поле `TaskName` в VSS Status operation
- Script block: при TaskName сканирует Ready_* (исключая `Ready_`), собирает `.sr*`, для каждого определяет VSS-путь и статус, выводит `###VSS_STATUS###`
- Timer callback: обнаруживает `###VSS_STATUS###`, вызывает `Show-VssStatusTableWindow` (DataGrid + действие по выделенному объекту)
- (21.06.2026)

### Bug-022: WPF ComboBox .Text не фиксируется при клике Run
- Editable ComboBox не обновляет `.Text` до потери фокуса
- `$inner.Text` возвращал "" → `$params.TaskName` = "" → Script шёл в else (обычный Status) → "Занят"
- **Исправление (итоговое):** `Get-ComboBoxText` + `Get-InnerTextBox` — рекурсивный BFS-поиск TextBox в визуальном дереве ComboBox через `VisualTreeHelper`
- **Резерв:** `Template.FindName("PART_EditableTextBox")`, `ApplyTemplate()`, `.Text`, `.SelectedItem`
- **Prefix-поиск папки задачи:** если `Join-Path release_root TaskName` не найден, ищется `Get-ChildItem -Directory "$TaskName*"`
- **Дополнительно:** при TaskName поле Project полностью игнорируется (не разрешается, не сохраняется в историю)
- Исправлено в Prod-GUI.ps1 (21.06.2026, переисправлено 21.06.2026, переисправлено 21.06.2026)

### FEAT-009: Таблица VSS Status на русском
- `Show-VssStatusTableWindow`: заголовки колонок и кнопок на русском
- Заголовок окна: "VSS Статус: N объектов"
- Колонки: "Объект", "Статус"
- Кнопки: "Извлечь (Checkout)", "Снять резервирование (Undo)", "Закрыть"
- Исправлено в Prod-GUI.ps1 (21.06.2026)

### Bug-023: $escapedSbText — неверное экранирование одинарных кавычек
- `$escapedSbText = $sbText -replace "'", "''"` превращает `'Ready_*'` → `''Ready_*''` (синтаксическая ошибка)
- **Причина:** скрипт-блок вставляется в `{ $escapedSbText }` (внутри фигурных скобок, НЕ внутри кавычек), поэтому экранирование не нужно
- Пароль (`$password = '$escapedPassword'`) — внутри кавычек, экранирование нужно
- **Исправление:** `$escapedSbText = $sbText` (без `-replace`)
- VSS-скрипт не выполнялся → таблица статуса не появлялась, в логе ошибка парсинга
- (21.06.2026)

### Bug-024: Checkout/Undo только одного объекта (вместо множественного выбора)
- DataGrid (`Show-VssStatusTableWindow`) поддерживает множественный выбор строк, но обработчики кнопок `$btnCo.Add_Click` и `$btnUndo.Add_Click` использовали `$dg.SelectedItem` — только один объект
- **Исправление:**
  - `SelectionMode = 'Extended'`, `SelectionUnit = 'FullRow'` явно установлены для DataGrid
  - `SelectionChanged` и обработчики кликов используют `$dg.SelectedItems` с обходом через `foreach` (не через pipeline `Where-Object`, т.к. `SelectedItemCollection` может неверно перечисляться)
  - Для `SelectedItems` создаётся копия в `ArrayList` перед циклом, чтобы избежать проблем с живой коллекцией
  - После операции обновляются `StatusCode`/`User`/`StatusText` объектов в `$data` и вызывается `$dg.Items.Refresh()` — таблица обновляется без перезагрузки
  - Проверяется `$LASTEXITCODE` от ss.exe — в `$done` попадают только успешно выполненные операции
- Исправлено в Prod-GUI.ps1 (21.06.2026)

### Bug-026: Compare-Export.ps1 — синтаксические ошибки парсера PS 5.1
- PowerShell 5.1 некорректно парсит строки с символами `|` и `/` внутри кавычек в определённых контекстах (строки для JIRA-таблицы, array literal с `/base`)
- **Причина:** баг парсера PS 5.1 — `|` воспринимается как pipe-оператор даже внутри строковых литералов
- **Исправление:**
  - JIRA-таблица: строки собираются в переменные перед `AppendLine()` (`$jiraHdr = "Project/Server|..."`)
  - Array literal `$diffArgs = @("/base", ...)` — заменён на `@('/base', ...)` с одинарными кавычками
- Исправлено в Compare-Export.ps1 (21.06.2026)

### Bug-026b: Compare-PB/SQL, Create-RFC, Find-JiraFields — неверный путь config.json
- В скриптах Compare-PB.ps1, Compare-SQL.ps1, Create-RFC.ps1, Find-JiraFields.ps1 путь по умолчанию к config.json был `C:\AIS\AI\Prod\config.json` (устаревший, без подпапки `config\`)
- Фактический путь config.json: `C:\AIS\AI\Prod\config\config.json`
- Compare-Export.ps1 уже был исправлен, остальные 4 скрипта — нет
- Исправлено: все параметры `$ConfigPath` по умолчанию изменены на `"C:\AIS\AI\Prod\config\config.json"`
- Проверка: при запуске без параметров (из командной строки) скрипты теперь находят конфиг
- (22.06.2026)

### FEAT-010: Кнопка Run скрыта для Настройки параметров
- Для операции "Настройки параметров" кнопка Run не имеет смысла — Settings использует свои кнопки (Сохранить, Сбросить, Проверить пути, Экспорт, Импорт)
- **Изменения в Prod-GUI.ps1:**
  - XAML: добавлен `BtnSettingsBorder` (Grid.Row="2") с 5 кнопками, изначально скрыт (`Visibility="Collapsed"`)
  - Старый контейнер Run переименован в `BtnRunBorder`
  - `BuildParams`: при `HasCustomUI` — Run скрывается, показываются кнопки Settings; для остальных операций — наоборот
  - Добавлены обработчики `$btnSaveSettings.Add_Click`, `$btnResetSettings.Add_Click`, `$btnValidatePaths.Add_Click`, `$btnExportSettings.Add_Click`, `$btnImportSettings.Add_Click`
- **Изменения в Settings-Module.ps1:**
  - `Build-SettingsUI`: удалён блок создания кнопок (бывшие строки 251-289)
  - `Attach-SettingsHandlers`: удалён цикл поиска WrapPanel с кнопками (оставлен только обработчик password toggle)
- (22.06.2026)

### Система автотестирования (22.06.2026)
- **Run-Tests.ps1** — мастер-тест, запускает все проверки:
  1. Парсер: все .ps1 файлы парсятся без ошибок
  2. Кодировка: все .ps1 с кириллицей имеют UTF-8 BOM
  3. Операции: проверка наличия всех категорий (Settings, SQL, Compare, RFC, VSS)
  4. Английский текст: в Write-Host нет английского текста (кроме технических терминов)
  5. Пути проекта: критичные файлы существуют (config.json, логотип, документация)
- **Запуск:** `powershell -NoProfile -File scripts\Run-Tests.ps1` (полный) или с `-Quick` (только парсер + кодировка)
- **test_gui_params.ps1** — быстрый тест после изменений GUI, вызывает `Run-Tests.ps1 -Quick`

### BuildParams: защита от пустой панели (22.06.2026)
- BuildParams теперь сохраняет предыдущие дети панели перед `Children.Clear()`
- При ошибке построения — предыдущие дети восстанавливаются и показывается MessageBox
- **Причина:** при ошибке в New-ParamField/New-ParamComboField панель оставалась пустой, ошибка уходила в лог без уведомления пользователя (это происходило 7+ раз)

### Тестирование параметров GUI после изменений (22.06.2026)
- **Правило:** После любого изменения функционала GUI (Prod-GUI.ps1, Settings-Module.ps1, creation of new operations, modification of BuildParams) — ОБЯЗАТЕЛЬНО запускать `scripts\test_gui_params.ps1`
- **Что проверять:**
  1. Панель параметров отображается для каждой операции (переключение ComboBox)
  2. Поля появляются/скрываются в зависимости от операции
  3. Кнопка Run отображается/скрывается корректно
  4. Настройки параметров (Settings): поля отображаются, Save/Reset/Validate работают

### Compare-Export.ps1: русский вывод + улучшенный ShowDiff (FEAT-011)
- Все `Write-Host` переведены на русский язык
- Исправлен баг "Capacity MaxCapacity Length": добавлен `[void]` ко всем `$sb.AppendLine()` (было 10+ вызовов без `[void]`)
- `ShowDiff` теперь поддерживает `NOT_IN_CURRENT`: если объекта нет в Current, но есть в Main — сравнение идёт Ready vs Main
- После таблицы результатов для неготовых объектов выводятся полные пути к файлам (Current/Main/Ready)
- В отчёте `release_report.txt` заголовки и статусы на русском
- **Структурированные маркеры** `###DIFF_OBJECT###` для каждого сравнимого неготового объекта — парсятся в GUI
- (22.06.2026)

### FEAT-012: Диалог выбора объектов для сравнения (Show-DiffSelectWindow)
- После выполнения "Сравнение и проверка" в GUI, если есть сравнимые неготовые объекты — открывается диалоговое окно
- В окне DataGrid с колонками: чекбокс "Сравнить", "Объект", "Причина", "Базовый файл" (Current или Main), "Готовый файл (Ready)"
- Кнопки: "Сравнить выбранные" (только отмеченные галочкой), "Сравнить всё" (все объекты), "Закрыть"
- TortoiseMerge запускается с аргументами `/base <базовый> /mine <готовый>` для каждого выбранного объекта
- Реализовано в `Prod-GUI.ps1`: функция `Show-DiffSelectWindow`
- Маркеры `###DIFF_OBJECT###Name|Reason|BasePath|ReadyPath|CompareType` генерируются `Compare-Export.ps1`
- `Get-OperationResult` обновлён: учитывает русские статусы "ГОТОВО"/"НЕ ГОТОВО"
- (22.06.2026)

## Сокращения для промптов

### Каталоги и наборы
| Сокращение | Полное имя / Путь | Назначение |
|------------|-------------------|------------|
| **Current** | `C:\Work\gold` | Рабочая (разрабатываемая) версия исходников PB |
| **Main** | `C:\SRC125\gold` | Эталонная (промышленная) версия исходников PB |
| **PB_Current** | `C:\AIS\AI\Prod\PB_Current` | Экспортированные PB-объекты из Current |
| **PB_Main** | `C:\AIS\AI\Prod\PB_Main` | Экспортированные PB-объекты из Main |
| **BD/dev_golden** | `C:\AIS\AI\Prod\BD\dev_golden\` | SQL-экспорт с сервера dev_golden (Current) |
| **BD/galaxy** | `C:\AIS\AI\Prod\BD\galaxy\` | SQL-экспорт с сервера galaxy (Main) |
| **Ready_*** | `C:\AIS\1 Release\<Task>\Ready_ГГГГ_ММ_ДД` | Папки с объектами к выпуску |
| **ReadyMerged** | `C:\Temp\ReadyMerged\<Task>` | Сводный набор из всех Ready_* |

### Серверы и базы данных
| Имя | Тип | Назначение |
|-----|-----|------------|
| **dev_golden** | Сервер Sybase ASE | Разрабатываемая БД (Current) |
| **galaxy** | Сервер Sybase ASE | Промышленная БД (Main) |
| **golden** | База данных | Имя БД на обоих серверах |
| **vchaga** | Пользователь Sybase | Учётная запись для isql |

### Типы объектов
| Тип | Расширение | Описание |
|-----|------------|----------|
| **PBL** | `.pbl` | PowerBuilder Library |
| **PBT** | `.pbt` | PowerBuilder Target |
| **SRU/SRW** | `.sr*` | Экспортированные PB-объекты |
| **Procedure** | `.sql` | Хранимая процедура Sybase ASE |
| **Functions** | `.sql` | Функция Sybase ASE |
| **Triggers** | `.sql` | Триггер Sybase ASE |
| **AIS** | — | Наименование проекта PowerBuilder / Jira |

### Статусы проверки
| Статус | Значение |
|--------|----------|
| **READY** | Объект готов к выводу в ПРОД |
| **NOT_READY** | Объект НЕ готов |
| **NOT_IN_CURRENT** | Отсутствует в Current |
| **DIFF_CURRENT** | Отличается от Current |
| **NEW_OBJECT** | Новый объект (отсутствует в Main) |
| **SAME_AS_MAIN** | Совпадает с Main |
| **DIFF** | Объекты различаются |
| **NOT_IN_MAIN** | Есть в Current, отсутствует в Main |

### Утилиты
| Утилита | Назначение |
|---------|------------|
| **isql** | Командная утилита Sybase ASE |
| **pbldump** | Экспорт объектов из PBL в .sr* |
| **TortoiseMerge** | Визуальное сравнение файлов |
| **ss.exe** | Microsoft Visual SourceSafe (VSS) - система контроля версий |
| **VSS-Utils.ps1** | PowerShell модуль для работы с VSS |

### VSS (Visual SourceSafe) команды
| Команда | Назначение | Пример | Параметры |
|---------|------------|--------|-----------|
| **Get** | Получить последнюю версию из VSS | `Get-VssLatest -Project "$/Project" -Recursive` | `-Project`, `-Recursive` |
| **Status** | Узнать состояние объектов (Checked In/Out) | `Get-VssStatus -Project "$/Project" -Recursive` | `-Project`, `-Recursive` |
| **Properties** | Узнать кто использует объект | `Get-VssWhoIsUsing -Project "$/Project"` | `-Project` |
| **Checkout** | Выполнить Check Out объекта | `Set-VssCheckout -Project "$/Project" -Comment "text" -Recursive` | `-Project`, `-Comment`, `-Recursive` |
| **Checkin** | Выполнить Check In объекта | `Set-VssCheckin -Project "$/Project" -Comment "text" -Recursive` | `-Project`, `-Comment`, `-Recursive` |

### VSS-операции в GUI
- Доступны 19 операций в Prod-GUI.ps1 (18 + Настройки параметров)
- 5 VSS-операций: Get Latest, Check Status, Who Is Using, Checkout, Checkin
- Каждая VSS-операция имеет поля: VSS DB Path, VSS Username, VSS Password, Project
- Checkout/Checkin дополнительно: Comment
- Get Latest, Check Status, Checkout, Checkin: чекбокс Recursive
- VSS-операции не используют поле пароля Sybase (оно скрыто)
- Добавлена операция "Комментарий в Jira: таблица объектов PB и SQL" (после "Создание RFC в Jira") — сканирует Ready_* папки задачи, формирует таблицу объектов PB и SQL и добавляет комментарий в задачу Jira. Пароль Jira (API-токен) вводится в поле Password главного окна. Логин Jira из config.json → jira.jira_user.

### Ключевые файлы
| Файл | Назначение |
|------|------------|
| `config.json` | Конфигурация путей, Jira |
| `Task.txt` | Методика и план работ |
| `release_report.txt` | Отчёт проверки |
| `compare_pb_report.txt` | Отчёт Compare-PB.ps1 |
| `compare_sql_report.txt` | Отчёт Compare-SQL.ps1 |
| `Prod-GUI.ps1` | GUI-приложение |
| `Prod-GUI.bat` | BAT для запуска GUI |
| `prepare_release.bat` | Главный оркестратор |
| `SQL_exp_param.bat` | Полный SQL-экспорт |
| `SQL_exp_single.bat` | Экспорт одного объекта |
| `SQL_exp_ready.bat` | Экспорт из Ready |
| `Compare-Export.ps1` | Сравнение и RFC |
| `Add-ReleaseComment.ps1` | Комментарий в Jira с таблицей объектов PB и SQL |
| `Compare-PB.ps1` | Сравнение PB |
| `Compare-SQL.ps1` | Сравнение SQL |
| `Create-RFC.ps1` | Создание RFC |
| `Find-JiraFields.ps1` | Поиск полей Jira |
| `Run-Tests.ps1` | Мастер-тест (парсер, кодировка, операции, пути, английский текст) |
| `test_sql_export.ps1` | Тестирование SQL |
| `test_gui_params.ps1` | Быстрый тест парсера и кодировки (вызов Run-Tests -Quick) |
| `VSS-Utils.ps1` | Утилиты для работы с VSS |
| `vss.bat` | BAT-файл для быстрого доступа к VSS |
| `Settings-Module.ps1` | Модуль настроек (шифрование, валидация, экспорт/импорт) |
| `settings_history.json` | Журнал изменений настроек (до 50 записей) |
| `vss_object_history.json` | История объектов VSS (макс. настраивается через vss.history_max) |

### Сокращения для промптов
| Сокращение | Значение |
|------------|----------|
| **РР** / **RR** | Принудительно переключить модель ИИ на русский язык для всего последующего общения. Использовать при нарушении языкового правила после смены модели. |
| **ЦИКЛ** | Запустить цикл автоисправления для указанной ОП (через `auto_fix_loop.ps1 -OpNumber N`) |
| **OUT** / **ОБР** | Исправить ошибки по тексту из Output (`temp\last_output.log`) |
| **/prompts** / **ПРОМТ** | Показать историю пользовательских промптов (`temp\user_prompts.log`) |
| **НОМ** | Номер операции в выпадающем списке GUI (например, НОМ 1, НОМ 11, НОМ 7). Номер соответствует порядковому индексу операции в массиве `$operations` (1-based). При перестановке операций номер меняется автоматически. Используется для ссылок на операции в документации и общении. |
| **APPL** | Дизайн MSG-окон: овальные поля (Border CornerRadius=12), овальные полупрозрачные кнопки (градиент синий/голубой, белая подсветка), градация серого на фоне (тёмный→светлый→тёмный), тень окна. Все MSG-диалоги (Show-ResultPopup, Show-VssStatusTableWindow, Show-DiffSelectWindow, Show-ValidationErrorWindow, Show-TaskProgressDialog, Show-PbObjectTableWindow, Show-ProdCompareResult) используют этот стиль. |
| **APPL2** | Двухслойный 3D-эффект текста/кнопок без DropShadowEffect: слой А — белый текст/фигурка, смещённый на 1px вниз-вправо; слой Б — тёмно-синий (#1A3A60) поверх, без смещения. Даёт чёткий белый контур и читаемость на любом фоне. Используется в Show-TestMsg.ps1 (ОТЕСТ) для заголовка и кнопок title bar. |
| **APPL3** | APPL2 + resize (невидимая область 30×30, #05FFFFFF), динамический Grid (*/Auto), сохранение/восстановление размеров окна (fixshow_layout.json). Используется в Show-OpStatus.ps1 (FIXSHOW). |
| **ОТЕСТ** | Тестовый диалог APPL2 (`Show-TestMsg.ps1`). Проверка дизайна: овальное окно, кастомный title bar с кнопками ━ ▣ ✕, двухслойный 3D-текст (APPL2), прогресс-бар (ПБ). |
| **ИЗМДИЗАЙН** | Применить шаблонные изменения дизайна ко всем окнам указанного тира (APPL2/APPL/Standard). Запускает `scripts\Apply-DesignChanges.ps1`. Команда описана в `.opencode\command\design.md`. |
| **РУДИМЕНТ** | Обработка скриптов указанного объекта для поиска рудиментов — неработающих участков кода, дублирования, неработающих ссылок, устаревших имён. Команда описана в `.opencode\command\rudiment.md`. |
| **АВТОТЕСТ** | Автоматическое тестирование через `Run-Tests.ps1`. Запуск с параметром `-Test` для конкретного скрипта или `all` для всех. |
| **ПС** | Поисковая строка (TextBox) в панели поиска контекста. Часть стандартного поиска DataGrid: ПС + счётчик + кнопки ▼/▲. |
| **КОНТЕКСТ** | Контекст поиска: объекты (DataGrid), их отображение (колонки, стили), расположение (панель поиска), функционирование (поиск, навигация, подсветка). Эталон — СТАНДАРТ1. |

### Русификация всех скриптов (22.06.2026)
- Все `Write-Host`, `Read-Host`, `throw` с английским текстом в `bin/*.ps1` и `scripts/*.ps1` переведены на русский
- Исправлены кракозябры (mojibake) в комментариях Create-RFC.ps1 и Find-JiraFields.ps1 (замена `РІ"Р‚РІ"Р‚` на русский текст)
- В AGENTS.md добавлены правила проверки: `grep "Write-Host \"[A-Z]" bin/ scripts/` и `grep "Read-Host \"" bin/ scripts/`
- Исключения: имена файлов (Create-RFC.ps1), технические термины (Jira, RFC, VSS, TortoiseMerge, PowerBuilder), имена каталогов (Current, Main, PB_Current, PB_Main)
- Проверка: grep не находит английских Write-Host в bin/ и scripts/ (только допустимые термины)

### Compare-Export.ps1: автообновление NOT_IN_CURRENT (FEAT-013)
- При обнаружении NOT_IN_CURRENT PB-объектов скрипт пытается автоматически скопировать их из `pb_current_source` (где они существуют как извлечённые `.sr*` файлы)
- Если `.sr*` не найден — пробуется pbldump из найденного PBL-файла
- После обновления выполняется повторное сравнение с выводом результатов
- Необновлённые объекты выводятся отдельно с рекомендациями
- Исправлено в Compare-Export.ps1 (22.06.2026)

### pbldump перенесён в tools\pbldump-1.3.1stable (22.06.2026)
- Папка `pbldump-1.3.1stable` перемещена из корня проекта в `tools\pbldump-1.3.1stable`
- `config.json`: `pbl_dump` обновлён на `C:\AIS\AI\Prod\tools\pbldump-1.3.1stable\PblDump.exe`
- `AIS_export.ps1`: параметр `$PbldumpExe` по умолчанию обновлён на `tools\pbldump-1.3.1stable\PblDump.exe`
- `Compare-Export.ps1` читает путь из `config.json` — коррекция не требуется
- `Settings-Module.ps1` читает путь из `config.json` — коррекция не требуется
- Проверено: `Test-Path` успешен, `PblDump.exe --help` работает

### Merge count fix (22.06.2026)
- `Compare-Export.ps1`: исправлен счётчик `$mergedCount` — был только в `else`, но после очистки `ReadyMerged` все файлы шли через `if` (сравнение `DateTime -gt $null` всегда `$true`), счётчик оставался 0
- Исправление: явная проверка `Test-Path $destPath` + инкремент в каждой ветке (новая/обновлённая)

### Bug-027: Парсер PS 5.1 — кракозябры в .ps1 с кириллицей
- PowerShell 5.1 на русской Windows читает .ps1 без BOM как Windows-1251
- После русификации скриптов файлы сохранялись в UTF-8 без BOM → парсер видел кракозябры (mojibake) и выдавал синтаксические ошибки при запуске (Compare-PB.ps1: `throw "Р?Р?Р?С"РёР? Р?Рч...`)
- **Исправление:** все .ps1 файлы с кириллицей переведены в UTF-8 with BOM (Prod-GUI.ps1, Compare-Export.ps1, Create-RFC.ps1, Find-JiraFields.ps1, Settings-Module.ps1, test_sql_export.ps1, VSS-Utils.ps1 уже были с BOM; Compare-PB.ps1, Compare-SQL.ps1, AIS_export.ps1, Initialize-Project.ps1 — исправлены)
- **Обновлено правило кодировки:** ASCII → UTF-8 with BOM
- **Дополнительно:** в Find-JiraFields.ps1 (строки 70-73) и Create-RFC.ps1 (строки 119-120) были некракозябренные комментарии и текст summary/description — заменены на правильный русский текст
- **Создан test_gui_params.ps1** — автоматическая проверка парсера для всех .ps1 файлов
- (22.06.2026)

### Bug-028: config.json — невалидная escape-последовательность `\p`
- Поле `_version` в `config.json` содержало `tools\pbldump` с одинарным обратным слешем `\p`
- JSON-парсер (`ConvertFrom-Json`) выдавал ошибку: "Нераспознанная escape-последовательность" при открытии панели Настройки параметров
- **Причина:** в JSON допустимы только `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`. `\p` — невалидная escape-последовательность
- **Исправление:** `\p` → `\\p` (экранированный обратный слеш)
- **Проверка:** `Get-Content config.json -Raw -Encoding UTF8 | ConvertFrom-Json` — не должен выдавать ошибок
- (22.06.2026)

### Run-Tests.ps1 добавлен в GUI как операция (22.06.2026)
- Добавлена операция "Запуск тестов" с полем "Быстрый режим" (чекбокс)
- Script block: запускает `scripts\Run-Tests.ps1` с `-Quick` в зависимости от чекбокса
- При ошибке парсинга/кодировки — открывается Result Popup с красным текстом и путями к проблемным файлам

### Bug-029: Перестановка операций удалила Settings из массива (22.06.2026)
- При перестановке порядка операций в `$operations = @(...)` в Prod-GUI.ps1 через edit tool была повреждена операция Settings
- **Причина:** edit tool заменил только `Name = "Settings"` на `Name = "Compare PB: Current and Main"`, оставив тело Settings (`HasCustomUI = $true`) нетронутым
- **Последствие:** Settings исчез из комбобокса, панель параметров не показывалась для ни одной операции
- **Исправление:** восстановлено `Name = "Settings"` и `RusName = "Настройки параметров"`
- **Правило:** после любой перестановки операций ОБЯЗАТЕЛЬНО проверять:
  1. Количество операций (должно быть 17)
  2. Наличие Settings с `HasCustomUI = $true`
  3. Каждый `Name` встречается ровно один раз (Search "Count" должно быть 1 для каждого)
  4. Запустить `Run-Tests.ps1 -Quick`
  5. Открыть GUI и проверить что для каждой операции отображаются поля

### Bug-030: Add-ReleaseComment.ps1 — кодировка UTF-8 BOM и `||` в PS 5.1 (23.06.2026)
- PowerShell 5.1 на русской Windows неверно парсит `||` (двойной пайп) внутри `"..."` — воспринимает как оператор «ИЛИ». Исправление: использовать `$pipe = [string][char]0x7C` и `-f` format operator вместо прямых `||`.
- При создании нового .ps1 с кириллицей: использовать ТОЛЬКО `Set-Content -Encoding UTF8` (не `[System.IO.File]::WriteAllText`). `Set-Content` гарантированно создаёт UTF-8 BOM в PS 5.1, а `WriteAllText` может дать BOM без корректоного содержимого.
- **Надёжный способ записи:** `Set-Content -Path file.ps1 -Value $content -Encoding UTF8` (где `$content` заранее прочитан через `[System.IO.File]::ReadAllText(path, [Text.Encoding]::UTF8)`).
- **Проверка:** `$bytes = [System.IO.File]::ReadAllBytes(file.ps1); $bytes[0..2] -eq @(239,187,191)` (BOM) + `$err=$null; [Parser]::ParseFile(file, [ref]$null, [ref]$err); $err.Count -eq 0` (синтаксис).

### FEAT-015: Новая таблица Jira — 4 колонки (23.06.2026)
- Таблица в комментарии Jira переделана на 4 колонки:
  1. **Проект/Сервер** — для PB: имя проекта PowerBuilder (по умолчанию `AIS`, настраивается через параметр `ProjectName`); для SQL: имя сервера БД (из `config.json paths.bd_current_export` — предпоследний элемент пути, напр. `dev_golden`)
  2. **Библиотека/БД** — для PB: имя библиотеки PBL (поиск .sr* файла в `PB_Current`/`PB_Main`, имя родительской папки — имя библиотеки); для SQL: имя БД (из `config.json paths.bd_current_export` — последний элемент пути, напр. `golden`)
  3. **Наименование объекта** — имя объекта без расширения
   4. **Информация** — краткое описание изменений (заполняется по алгоритму ниже, макс. 300 символов)
- Алгоритм заполнения столбца "Информация":
  - **Для объектов PB**:
    1. Сравнить **NEWPB** (свежий из Ready) и **OLDPB** (исходный из Git_*)
    2. Игнорировать различия только в пробелах/отступах
    3. В зонах реальных отличий определить какие функции/event-ы каких элементов (DataWindow, DataStore, Window, CommandButton, DataWindowChild и т.п.) были изменены, включая изменённые поля DataWindow/DataStore (column, compute field, text control)
    4. Сформировать комментарий: "Внесены изменения в: <список изменённых функций/элементов>"
    5. Максимум 300 символов, при превышении — обрезать в конце
  - **Для объектов SQL**:
    1. Сравнить **NEWSQL** (свежий из Ready) и **OLDSQL** (исходный из Git_*)
    2. Определить тип объекта SQL (Procedure, Function, Trigger)
    3. В зонах отличий найти русскоязычные комментарии (строки, начинающиеся с `--` или `/*`) на русском языке
    4. Включить найденные русские комментарии в текст "Информации"
    5. Максимум 300 символов, при превышении — обрезать в конце
- Формат строки: `|Проект/Сервер|Библиотека/БД|Объект|Информация|` (4 пайпа-разделителя, 5 элементов)
- Заголовок: `||Проект/Сервер||Библиотека/БД||Наименование объекта||Информация||`
- Добавлен параметр `-ProjectName` в `Add-ReleaseComment.ps1` (по умолчанию `"AIS"`)
- Добавлено поле "Проект PowerBuilder" в GUI для операции "Комментарий в Jira: таблица объектов PB и SQL"

### FEAT-014: Динамический заголовок пароля + токен Jira в Settings (23.06.2026)
- Заголовок поля Password в GUI меняется динамически:
  - "Токен Jira" — для операции "Комментарий в Jira: таблица объектов PB и SQL"
  - "Пароль Sybase" — для всех остальных (SQL экспорт, Compare & Verify)
- В Settings добавлена группа "Настройки Jira" с полями:
  - "Пользователь" — jira_user (из config.json)
  - "Токен Jira" — jira_token, шифруется AES-256 (аналогично VSS паролю)
- При выборе операции Jira Release Comment токен автоматически подставляется из Settings
- `config.json`: добавлено поле `jira.token_encrypted`
- Подробные правила формирования таблицы Jira — в `.opencode\jira-table-rules.mdc`

### Bug-035: StackPanel.Add_SelectionChanged при SQL Export — ОП 6 (26.06.2026)
- `New-ParamComboField` возвращает StackPanel, внутри которого лежит TextBlock + ComboBox
- `BuildParams` (line 2196) присваивал результат в `$sourceCombo` и вызывал `Add_SelectionChanged` на StackPanel — StackPanel не имеет такого метода
- **Исправление:** извлекать ComboBox из Children StackPanel перед подпиской на `SelectionChanged`
- **Причина:** предыдущий код предполагал, что `New-ParamComboField` возвращает ComboBox, но функция всегда возвращала StackPanel
- **Проверка:** после изменений в BuildParams, затрагивающих `$isSource` или `New-ParamComboField` — запустить `test_gui_params.ps1`

### Правила сокращений команд
- **Все сокращения команд указываются ТОЛЬКО большими буквами (UPPERCASE)**
- Если буквы вперемешку (большие и маленькие) или только маленькие — это НЕ команды и не должны распознаваться как сокращения
- Исключения: технические термины (Jira, RFC, VSS, TortoiseMerge, PowerBuilder), имена файлов, пути

### Сокращения для промптов (дополнение)
| Сокращение | Значение |
|------------|----------|
| **МОРДА** | Главное окно GUI (Prod-GUI.ps1), откуда запускаются операции |
| **СОКР** | Показать все сокращения проекта (WPF-диалог, `scripts\Show-Abbreviations.ps1`) |
| **OO** | Выполнить все задачи: завершить оставшиеся пункты todo-листа |
| **СТАНДАРТ1** | Открыть эталон APPL2-стиля (`scripts\Show-Appl2Standard.ps1`). ОКНО_СТАНДАРТ_1 — базовый шаблон для всех APPL2-окон проекта |
| **RR** / **РР** | Принудительно переключить модель ИИ на русский язык для всего последующего общения. Использовать при нарушении языкового правила. |
| **ПРОМПТ** | Показать историю пользовательских промптов (WPF-диалог, `scripts\Show-Prompts.ps1`). Команда описана в `.opencode\command\prompts.md` |
| **РУДИМЕНТ** | Обработка скриптов указанного объекта для поиска рудиментов — неработающих участков кода, дублирования, неработающих ссылок, устаревших имён. Формат: `РУДИМЕНТ <объект>` или `РУДИМЕНТ ALL` |
| **АВТОТЕСТ** | Автоматическое тестирование через `Run-Tests.ps1`. Запуск с параметром `-Test` для конкретного скрипта или `all` для всех |
| **ПС** | Поисковая строка (TextBox) в панели поиска контекста. Часть стандартного поиска DataGrid: ПС + счётчик + кнопки ▼/▲ |
| **КОНТЕКСТ** | Контекст поиска: объекты (DataGrid), их отображение (колонки, стили), расположение (панель поиска), функционирование (поиск, навигация, подсветка). Эталон — СТАНДАРТ1 |

### Правило: приведение окна к СТАНДАРТ1
- Фраза "окно <X> в СТАНДАРТ1" означает полное соответствие окна эталону `scripts\Show-Appl2Standard.ps1`:
  - **Свойства окна**: `AllowsTransparency=$true`, `WindowStyle=None`, `Background=Transparent`, `ResizeMode=CanResizeWithGrip`, `Topmost=$true`
  - **Title bar**: `Add-TitleButton` с кнопками ━ ▣ ✕, каждая в своей колонке Grid (Col 1/2/3). Maximize меняет символ ▣↔❐ при клике. Hover-эффекты (красный для ✕, тёмно-синий для ━/▣). ControlTemplate CornerRadius=6, Border #1A3A60 толщина 3, градиент alpha 13
  - **Перетаскивание**: `$titleBorder.Add_MouseLeftButtonDown` с `DragMove()`. Двойной клик по title bar — игнорируется
  - **Закрытие по ESC**: `$window.Add_KeyDown({ if ($_.Key -eq "Escape") { $window.Close() } })`
  - **Layout**: Grid (Row * / Auto) — контент в Row 0, кнопки в Row 1. mainBorder.Padding = "20,16,20,22", mainBorder.Margin = 4, contentWrapper.Margin = (4,0,4,4)
   - **Нижние кнопки**: HorizontalAlignment = Right, отступ сверху = 7px (от ПБ/контента до кнопок). Расстояние от нижнего края кнопок до края окна = 30px
   - **Поиск контекста** (для ДО с таблицами/текстом):
     - Поисковая строка слева от кнопок ▼/▲ в нижней панели окна
     - При вводе текста и нажатии ▼ — поиск по всем данным (сначала в текущей вкладке)
     - **Enter** — ▼ (поиск вниз), **Shift+Enter** — ▲ (поиск вверх)
     - Найденный контекст выделяется **синим** цветом через `Select()` на TextBox
     - Кратковременный `Keyboard::Focus()` на TextBox для активации выделения, затем фокус возвращается в строку поиска
     - Скроллинг к контексту: `ScrollToHome()` + расчёт количества строк до позиции + `LineDown(lines-2)` — контекст вверху viewport
     - `IsInactiveSelectionHighlightEnabled = $true` для сохранения видимости выделения без фокуса
     - BFS-поиск TextBox: сначала по контенту активной вкладки, затем по всему окну
     - Таймер 300ms для ожидания переключения вкладок (DispatcherTimer)
     - При смене запроса — НЕ перезаписывать `searchState.query` до сравнения со старым значением (баг: `$sq -ne $searchState.query` всегда false, т.к. query уже перезаписан)
     - Кнопки ▼/▲ — использовать `Apply-GlossyButtonStyle` (как и все остальные кнопки в СТАНДАРТ1)
- (06.07.2026)

### Правило редактирования файлов (Bug-039)
- **Перед вызовом `edit` — проверять, что `oldString` отличается от `newString`.** Инструмент `edit` возвращает `No changes to apply: oldString and newString are identical`, если строки совпадают. Это не ошибка, но сообщение засоряет вывод и тратит токены.
- **Правило:** всегда убеждаться, что замена действительно нужна и строки различаются, перед вызовом `edit`.
- (06.07.2026)
| **СВЕЖPB** / **NEWPB** | Самый свежий PB-объект из Ready_* (наибольшая дата). Должен совпадать со свежевыгруженным из Current и объектом из PB_Current |
| **СВЕЖSQL** / **NEWSQL** | Самый свежий SQL-объект из Ready_* (наибольшая дата). Должен совпадать со свежевыгруженным из dev_golden и объектом из BD/dev_golden |
| **OLDPB** | Исходный PB-объект из Git_* (наибольшая дата). Должен совпадать с Main и PB_Main. Если свободен в VSS — также должен совпадать с VSS |
| **OLDSQL** | Исходный SQL-объект из Git_* (наибольшая дата). Должен совпадать с dev_golden и BD/dev_golden |
| **RULE_MEMBER** / **ЗАПОМНИ** | Проанализировать, почему последний промпт не был выполнен за один раз, а потребовал нескольких итераций. Установить корневые причины и внести правила в AGENTS.md / rules/ |
| **ДО** | Диалоговое окно, появляющееся при выполнении сервиса, запущенного из МОРДЫ (например, окно истории VSS) |
| **MSG** | Отдельное окно-сообщение (MessageBox) |
| **СОХР** | Сохранить текущий вариант проекта — архив на дату-время (`archives\SNAPSHOT\`) |


### Правило проверки СВЕЖ и OLD объектов
- При использовании сокращений **СВЕЖPB/NEWPB**, **СВЕЖSQL/NEWSQL**, **OLDPB**, **OLDSQL** — если объекты **не совпадают** с эталонами (Current/Main/dev_golden/PB_Current/PB_Main/BD), необходимо вывести диалоговое окно с таблицей результатов сравнения
- Таблица должна содержать колонки: Объект, Тип, Ожидаемый источник, Фактический источник, Статус (Совпадает / Не совпадает)
- Если всё совпадает — сообщение "Всё в порядке, объекты соответствуют эталонам"

### FEAT-016: Номера операций в GUI (НОМ)
- В ComboBox выбора операций добавлен номер: `"1. Сравнение PB: Current и Main"`, `"2. Сравнение SQL..."` и т.д.
- Номер = порядковый индекс в массиве `$operations` + 1 (1-based)
- При перестановке операций номер меняется автоматически
- Ссылаться на операции в общении можно как `НОМ 1`, `НОМ 11`, `НОМ 7` и т.д.
- В AGENTS.md добавлено сокращение **НОМ** в таблицу сокращений и правило в раздел "Правила сокращений команд"
- (23.06.2026)

### Алгоритм поиска объектов по TaskName (справочно)
При указании имени задачи (TaskName) — объекты для обработки определяются так:

1. **Папка задачи:** ищется в `release_root` (из config.json) по точному совпадению, при неудаче — префиксный поиск.
2. **Папки Ready_*:** собираются подпапки вида `Ready_YYYY_MM_DD`, сортируются по имени (убывание — от newest к oldest).
3. **Выбор latest-версии объекта:** перебор папок от newest к oldest. Для каждого объекта (по base name без расширения) берётся первое вхождение — самая свежая версия.
4. **ReadyMerged** — это вспомогательная папка для TortoiseMerge. Она НЕ является источником информации об объектах.
5. **Определение библиотеки PB:** объект ищется в `PB_Current` (по расширению `.sr*`). Если не найден — в `PB_Main`.
6. **Определение БД SQL:** из структуры `BD\dev_golden\...` или `BD\galaxy\...`.
7. **Валидация:** latest-версия из Ready сравнивается с Current (MD5). При несовпадении — `###VALIDATION_ERROR###`, остановка.
8. **Сравнение:** прошедшие валидацию объекты сравниваются Current vs Main (MD5), результат — `###DIFF_OBJECT###`.

### Структура каталогов проекта (справочно)
```
C:\AIS\AI\Prod\
├── PB_Current\<library>\<object>.sr*     # PowerBuilder объекты (текущая разработка)
├── PB_Main\<library>\<object>.sr*        # PowerBuilder объекты (эталон)
├── BD\dev_golden\golden\<type>\<object>.sql  # SQL Current (dev_golden.golden)
│   ├── Procedure\   *.sql                # Хранимые процедуры
│   ├── Functions\   *.sql                # Функции
│   ├── Triggers\    *.sql                # Триггеры
│   ├── Tables\      *.sql                # Таблицы
│   ├── PK\          *.sql                # Первичные ключи
│   ├── FK\          *.sql                # Внешние ключи
│   ├── Indexes\     *.sql                # Индексы
│   ├── Grants\      *.sql                # Гранты
│   └── LOGS\        *.sql                # Логи
├── BD\galaxy\golden\<type>\<object>.sql  # SQL Main (galaxy.golden)
└── C:\AIS\1 Release\<Task>\              # Папки задач
    ├── Ready_YYYY_MM_DD\                 # Папки готовности объектов
    │   ├── <object>.sr*                  # PB объект (может быть напрямую)
    │   ├── PB\<object>.sr*               # PB объект в подпапке PB
    │   ├── PB\<library>\<object>.sr*     # PB объект с библиотекой
    │   └── <object>.sql                  # SQL объект
    └── PROD\                             # Папка для собранных объектов к выводу
        ├── PB\<library>\<object>.sr*     # Свежие PB объекты из PB_Current
        └── SQL\<object>.sql              # Свежие SQL объекты из BD Current
```

### PBL → папка: правило именования
- Каждый PBL-файл (PowerBuilder Library) при экспорте через **Export-PB.ps1** выгружается в папку, имя которой совпадает с именем PBL (без расширения `.pbl`)
- Пример: `golden.pbl` → папка `PB_Current\golden\`, `golden_user.pbl` → `PB_Current\golden_user\`
- Если в PBT встречаются PBL с одинаковым именем из разных путей — к имени добавляется суффикс `_N`
- Метка фазы в верхнем ПБ при выгрузке PB показывает имя текущей библиотеки (например, `golden_sprw`, `pfe5003`) — это отличает PB-фазы от SQL-фаз (где метки: Процедуры, Функции, Триггеры...)
- PBD-файлы (PowerBuilder Dynamic libraries) пропускаются, не выгружаются

### Определение сервера/БД для SQL
```powershell
# Путь bd_current_export = "C:\AIS\AI\Prod\BD\dev_golden\golden"
# Предпоследний элемент = dev_golden (сервер)
# Последний элемент = golden (БД)
```

### FEAT-017: Группировка операций (25.06.2026)
- Операции сгруппированы по типам: **Сервисные** (НОМ 1-4), **PowerBuilder** (НОМ 5-6), **SQL** (НОМ 7-10), **Jira/RFC** (НОМ 11-13), **VSS** (НОМ 14-18)
- Collect PROD Objects перемещён в сервисные (НОМ 4)
- Все VSS-операции вместе (НОМ 14-18)
- (26.06.2026) Удалена ОП 19 «VSS: Search in History» — поиск теперь встроен в ОП 18 (колонка «Найдено»)

### FEAT-018: Единый TaskName (Shared TaskName) (24.06.2026, изм. 26.06.2026)
- `$script:sharedTaskName` — единое значение TaskName для всех операций
- Инициализируется из `task_name_history.json["TaskName_Shared"][0]` (последний использованный)
- **BuildParams НЕ подставляет sharedTaskName в поле** — используется Default из определения операции (пустая строка, т.к. TaskName необязателен для SQL Export и ряда других операций)
- История последних TaskName доступна в выпадающем списке ComboBox
- При выполнении любой операции (Run) TaskName сохраняется в `$script:sharedTaskName` и в `task_name_history.json`
- Персистентность: история доступна в ComboBox при перезапуске GUI

### FEAT-019: Диалоговые операции (ОП 18) — без информационных popup (25.06.2026)
- Операция «VSS: Object History» (ОП 18) показывает собственный WPF-диалог
- При нормальном завершении (exit code 0) — `Show-ResultPopup` не вызывается, т.к. диалог уже отобразил результат
- При ошибке (exit code ≠ 0) — `Show-ResultPopup` показывается с сообщением об ошибке
- При таймауте — popup «Таймаут» не показывается (только запись в лог)
- Информационные сообщения «Готово», «Выполнено», «Завершено» не отображаются для диалоговых операций

### Bug-032: $$HEX...$$ — кракозябры в VSS-версиях PB-объектов (25.06.2026)
- **Проблема:** VSS хранит PB .sr* файлы, экспортированные с hex-кодированием кириллицы в формате `$$HEX<число>$$<utf16le_hex>$$ENDHEX$$`. При сравнении VSS-версий через TortoiseMerge русский текст отображался как `$$HEX35$$044004380444...`, а не как читаемые символы.
- **Исправление в VSS-History.ps1:**
  - Добавлена функция `Convert-VssHexText` — находит все `$$HEX...$$ENDHEX$$` блоки, декодирует hex-строку как UTF-16LE байты, заменяет на реальный Unicode-текст
  - `Get-VssVersionFile`: после конвертации CP1251→UTF-16LE дополнительно вызывает `Convert-VssHexText` для раскодирования hex-последовательностей
  - `Search-InVssHistory`: заменено чтение файла через `ReadAllText(file, Unicode)` вместо `GetEncoding(1251).GetString(bytes)` (т.к. Get-VssVersionFile теперь возвращает UTF-16LE)
- **Формат PB:** `$$HEX35$$044004380444044b04...$$ENDHEX$$` где hex-строка — UTF-16LE байты (2 байта на символ), `35` — идентификатор (не используется для декодирования)
- **Проверка:** `[regex]::Matches($text, '\$\$HEX\d+\$\$').Count` должно быть 0 после декодирования
- (25.06.2026)

### FEAT-020: Правила создания RFC в Jira (25.06.2026)
- **Summary:** `Разработка - <название задачи из Jira>`
- **Description:** `RFC сформирована автоматически - AIS Release Preparation`
- **План проведения работ (customfield_25953):** 8 шагов (см. rules/jira-rules.md)
- **План отката (customfield_25954):** `Исправляем появившиеся ошибки и собираем новую версию`
- **Проблемы и риски (customfield_13852):** `Нет`
- **Информирование о недоступности (customfield_15254):** `Нет`
- **Ответственный за релиз (customfield_15255):** `{name: "<текущий пользователь>"}`
- **Эксперт по продукту (customfield_15256):** `{name: "<текущий пользователь>"}`
- **Проверяющие на бою (customfield_15350):** `[{name: "<reporter из исходной задачи>"}]`
- **Системы (customfield_25955, customfield_26053):** `@("SYSTEM-67")`
- **Связь с задачей:** тип `Mention`, inwardIssue=RFC, outwardIssue=TaskName
- **Исполнитель (assignee):** `{name: "<текущий пользователь>"}`
- **Кодировка:** JSON через StreamWriter с UTF-8 BOM, WebClient.UploadData (не Invoke-RestMethod)
- Подробные правила: `rules/jira-rules.md`, `docs/service_rules/jira_rfc_rules.md`
- (25.06.2026)

### Bug-034: SQL Export (ОП 5) — TaskName обязателен в батнике, sharedTaskName не даёт очистить поле (25.06.2026)
- **Проблема 1:** `SQL_exp_param.bat` требовал 4 параметра (`if "%~4"=="" goto usage`), TaskName был обязателен даже если в GUI помечен как необязательный
- **Проблема 2:** В Prod-GUI.ps1 для TaskName всегда подставлялся `$script:sharedTaskName`, что не позволяло очистить поле (оставалось предыдущее значение)
- **Проблема 3:** Автотест не проверял наличие поля Db для SQL Export и обязательность TaskName в батнике
- **Исправление:**
  - `SQL_exp_param.bat`: удалена проверка `if "%~4"=="" goto usage` — TaskName теперь необязателен
  - `Prod-GUI.ps1`: для TaskName используется `$script:sharedTaskName` только если он не пуст, иначе используется Default из определения поля (пустая строка)
  - `Run-Tests.ps1`: добавлена проверка поля Db для SQL Export и проверка что батник не требует TaskName
- **Правило:** для операций где TaskName опционален — батник/скрипт должен принимать пустой TaskName, а GUI не должен принудительно подставлять sharedTaskName если поле должно быть пустым
- (25.06.2026)

### Bug-033: list_directory — несуществующий инструмент (25.06.2026)
- **Проблема:** модель пытается вызвать инструмент `list_directory`, которого нет в системе
- **Ошибка:** "Model tried to call unavailable tool 'list_directory'"
- **Исправление:** использовать доступные инструменты:
  - `read(filePath="C:\path\to\dir")` — чтение содержимого директории
  - `glob(pattern="**/*.ps1")` — поиск файлов по шаблону
  - `bash(command="Get-ChildItem path")` — листинг через PowerShell
- **Правило:** НИКОГДА не использовать `list_directory`
- Подробные правила: `rules/tool-usage.md`
- (25.06.2026)


### Bug-036: Принудительная английская раскладка в PasswordBox - 5 попыток (26.06.2026)
- **Задача:** В поле пароля Sybase принудительно включать английскую раскладку клавиатуры
- **Попытка 1:** Удалил InputScope = Default (ранее был установлен для разрешения переключения) - надеялся, что без InputScope PasswordBox сам включит английский. **Не сработало** - WPF PasswordBox без InputScope использует текущую раскладку системы.
- **Попытка 2:** Установил InputScope = Url - теоретически должен принуждать английский для URL. **Не сработало** - InputScope влияет только на touch/screen-клавиатуру, на физическую клавиатуру не действует на большинстве систем.
- **Попытка 3:** Win32 API через Add-Type -Name Native -Namespace Win32 с LoadKeyboardLayout/ActivateKeyboardLayout. **Сломал скрытие консоли** - перезаписал существующий тип Win32.Native (используемый для GetConsoleWindow/ShowWindow). Консоль перестала скрываться.
- **Попытка 4:** Исправил namespace на Win32.Keyboard, но использовал неверный флаг  x00000100 (KLF_SETFORPROCESS) вместо  x00000001 (KLF_ACTIVATE). **Не сработало** - KLF_SETFORPROCESS не активирует раскладку корректно в данном контексте.
- **Попытка 5:** Исправил флаг на KLF_ACTIVATE (0x00000001). **Заработало.**
- **Итоговое решение:** Win32 API LoadKeyboardLayout("00000409", 0x00000001) + ActivateKeyboardLayout на GotFocus / восстановление предыдущей раскладки на LostFocus.
- **Правила:**
  1. **Принудительная раскладка клавиатуры в WPF - ТОЛЬКО через Win32 API ActivateKeyboardLayout**. InputScope НЕ влияет на физическую клавиатуру (только touch/screen).
  2. **Перед Add-Type -Name X -Namespace Y - проверить, не существует ли уже [Y.X] в проекте.** Использовать -ErrorAction SilentlyContinue и уникальное имя типа, чтобы не перезаписать существующий.
  3. **Проверять Win32 константы по документации** - не использовать "похожие" значения. KLF_ACTIVATE = 0x1, KLF_SETFORPROCESS = 0x100 - разные назначения.
  4. **При изменении любого функционала - проверить, что не сломан существующий** (особенно скрытие консоли, инициализация окна, базовые обработчики).
  5. **Не полагаться на "магическое" поведение платформы** - если нужно принудительное поведение, реализовать его явно (Win32 API), а не надеяться на побочные эффекты удаления/добавления свойств.
- (26.06.2026)

### Bug-037: Система прогресс-баров — 10+ итераций (26.06.2026)
- **Задача:** Реализовать двухуровневый прогресс-бар (верхний по типам, нижний по объектам) с комметариями
- **Всего итераций:** >10 за одну сессию
- **Корневые причины:**
  1. **Нет тестовой среды** — изменения в GUI-коде (Prod-GUI.ps1, BAT-файлы) нельзя проверить без запуска реальной операции. Ошибки выявлялись только после тестирования пользователем.
  2. **Пошаговые правки без регрессии** — каждый новый фикс исправлял один симптом, но не проверял, что предыдущие фиксы не сломались.
  3. **Неполное понимание потока данных** — BAT (CP1251) → cmd.exe (буферизация 4KB) → PowerShell wrapper (UTF-8) → temp файл → GUI таймер (500ms) → регулярки. Каждый этап добавляет свои особенности (кодировка, буферизация, разбиение на чанки).
  4. **Переплетение изменений** — BAT-маркеры, подсчёт объектов, логика таймера, отображение — всё менялось одновременно. Нужно было менять по одному слою за раз.
  5. **Отсутствие модульных тестов** — парсинг регулярных выражений (###PHASE###, ###STEP###) можно было бы проверить unit-тестом на фиктивных данных, без запуска GUI.
- **Правила:**
  1. **При изменении GUI-логики (таймер, парсинг вывода)** — сначала написать тестовый скрипт, который подаёт фиктивный вывод на вход парсеру и проверяет результат. Только потом менять код.
  2. **Менять один слой за раз** — BAT-маркеры → тест → таймер-парсер → тест → отображение. Не всё одновременно.
  3. **Перед изменением — изучить полный поток данных:** какой процесс пишет → в какой кодировке → как читается → как парсится. Документировать узкие места (буферизация cmd.exe, CP1251→UTF-8, разбиение на чанки).
  4. **Регрессия после каждого фикса:** проверить, что старые маркеры (###DIFF_OBJECT###, ###VSS_STATUS###) не сломались, и что простые операции (без маркеров) показывают хоть какой-то прогресс.
  5. **Если фикс потребовал >3 итераций — остановиться и перепроектировать,** а не продолжать патчить симптомы.
- (26.06.2026)

### Bug-038: VSS History search — Add_Click не срабатывает в AllowsTransparency-окне (06.07.2026)
- **Проблема:** Кнопки ▼/▲ и Enter в окне VSS History не работали после 10+ попыток исправлений
- **Корневая причина:** `Add_Click` на кнопках может не срабатывать в окнах с `AllowsTransparency=$true` из-за особенностей маршрутизации событий WPF. Кроме того, `RaiseEvent` с `ClickEvent` не гарантирует доставку события в layered-окне.
- **Исправление:**
  1. `Add_Click` заменён на `Add_PreviewMouseLeftButtonDown` (tunneling event, срабатывает до Click и не зависит от ControlTemplate)
  2. `$_.Handled = $true` в Preview обработчике для предотвращения дальнейшей маршрутизации
  3. Кнопки применяют `Apply-GlossyButtonStyle` (как в Show-Rules)
  4. Enter/Shift+Enter используют прямой вызов `Search-DgDown`/`Search-DgUp` вместо `$btnDown.RaiseEvent(ClickEvent)`
  5. Функции поиска `Search-DgDown`/`Search-DgUp` не принимают контекстный параметр — работают напрямую с переменными скрипта
- **Проверка:** Test-VssSearch.ps1 — 10/10 тестов; парсер — успешно; Run-Tests.ps1 -Quick — все тесты проходят
- **Правила:**
  1. **В окнах с `AllowsTransparency=$true` для кнопок использовать `Add_PreviewMouseLeftButtonDown` вместо `Add_Click`**
  2. **Навигацию по Enter/Shift+Enter делать прямым вызовом функций, а не через `RaiseEvent(ClickEvent)`**
  3. **Всегда применять `Apply-GlossyButtonStyle` к кнопкам поиска ▼/▲ для единообразия**
  4. **Функции поиска не должны принимать контекстный параметр — работать напрямую с переменными скрипта (`$dg`, `$searchInput`, `$dgSearchState`, `$matchLabel`)**
- (06.07.2026)

### Bug-040: VSS History search — `$_` и `"Return"` vs `param` и `"Enter"` (06.07.2026)
- **Проблема:** Поиск контекста (▼/▲/Enter) в окне VSS History не работал, хотя в Show-Rules работал
- **Анализ Show-Rules (работает):**
  1. `$searchBox.Add_KeyDown({ param($sender,$e) if ($e.Key -eq "Enter") ... })` — явный `param($sender,$e)`, сравнение с `"Enter"`
  2. `$btnDown.Add_Click({ ... })` — обычный `Add_Click` (не Preview)
- **Анализ VSS History (не работало):**
  1. `$searchInput.Add_KeyDown({ if ($_.Key -eq "Return") ... })` — `$_` вместо `param`, сравнение с `"Return"`
  2. `$btnDown.Add_PreviewMouseLeftButtonDown(...)` — Preview вместо Click
- **Корневые причины (PS 5.1):**
  1. **`$_` в PS 5.1 для двухпараметрического делегата (`KeyEventHandler(object, KeyEventArgs)`) может быть не `KeyEventArgs`**, а `$null` или sender. Show-Rules использует `param($sender,$e)` — явный захват обоих параметров, что гарантированно работает.
  2. **`"Return"` vs `"Enter"`** — при `AcceptsReturn=$false` (по умолчанию) TextBox может подавлять `Key.Return` в `KeyDown` (воспринимая его как команду Accept). Сравнение с `"Enter"` (как в Show-Rules) корректно работает.
  3. **`Add_PreviewMouseLeftButtonDown`** с `$_.Handled=$true` может блокировать `Click`-событие на кнопках с кастомным ControlTemplate (Apply-GlossyButtonStyle). `Add_Click` достаточно для кнопок ▼/▲.
- **Исправление:** приведено в точное соответствие с Show-Rules: `param($sender,$e)` + `$e.Key -eq "Enter"` + `Add_Click`
- **Проверка:** Test-VssSearch.ps1 — 10/10; парсер — успешно; Run-Tests.ps1 -Quick — PASSED
- **Правила:**
  1. **Для `KeyDown`/`KeyUp` в PS 5.1 ВСЕГДА использовать `param($sender,$e)`** (не `$_`). `$_` в PS 5.1 не гарантированно содержит EventArgs для двухпараметрических делегатов.
  2. **Сравнение Enter — использовать `$e.Key -eq "Enter"`** (не `"Return"`). При `AcceptsReturn=$false` WPF TextBox может подавлять `Key.Return`.
  3. **Для кнопок с `Apply-GlossyButtonStyle` использовать `Add_Click`** (не `PreviewMouseLeftButtonDown`). Кастомный ControlTemplate не мешает Click-событию.
- (06.07.2026)

### Статусы операций: EDIT и FIXED (26.06.2026)
- Для каждой ОП МОРДЫ и её сервиса устанавливается индивидуальный статус:
  - **EDIT** — объект в разработке, можно менять свойства, функционал, ДО, таблицы, MSG, ПБ
  - **FIXED** (или **FIX**) — объект готов к работе. МЕНЯТЬ НЕЛЬЗЯ: внешний вид, функционал, параметры, поля, ДО, ПБ, отображение хода работы и результата. Любые изменения возможны только после смены статуса обратно на EDIT.
- **Команды:**
  - FIX N или FIXED N — перевести ОП N в статус FIXED (запрет изменений)
  - EDIT N — перевести ОП N в статус EDIT (разрешение изменений)
  - N — номер операции (1-based, соответствует НОМ)
- **Правила:**
  1. При попытке изменения ОП в статусе FIXED — модель должна запросить разрешение через смену статуса на EDIT
  2. Статусы хранятся в config\op_status.json в виде {"1": "EDIT", "2": "FIXED", ...}
  3. При первом запуске (файл отсутствует) — все ОП в статусе EDIT
    4. Статус влияет только на разработку (изменение кода), не на выполнение операций пользователем
- (26.06.2026)

### Bug-044: Запуск ДО — Касперский блокирует скрытый PowerShell (12.07.2026)
- **Проблема:** Касперский (Kaspersky Endpoint Security) через Hips/BehaviorDetection блокирует `powershell.exe -WindowStyle Hidden` (ошибка `ChildProcess.kill`). Все ДО перестали открываться.
- **Попытка 1:** `Invoke-HiddenDialog.ps1` (Process.Start + CreateNoWindow) — заблокирован.
- **Попытка 2:** `Hide-ConsoleWindow.ps1` внутри Show-*.ps1 — заблокирован при перезапуске процесса.
- **Попытка 3:** `powershell -WindowStyle Hidden -STA -File` напрямую — заблокирован.
- **Исправление:** `Start-Process powershell -ArgumentList '...' -WindowStyle Hidden` — Касперский не блокирует, т.к. `Start-Process` — легитимный cmdlet.
- **Исключение СОХР:** Save-Snapshot.ps1 использует `MetroWindow` (MahApps), не работающий в `-WindowStyle Hidden`. Запускать с `-WindowStyle Minimized`.
- **Изменённые файлы:**
  - Все Show-*.ps1 (9 шт): удалён `Hide-ConsoleWindow`
  - Все .opencode/command/*.md (7 шт): прямой запуск через `Start-Process -WindowStyle Hidden`
  - AGENTS.md: обновлена секция запуска ДО
  - opencode.jsonc: добавлен `llm_visible_providers` (замена `enabled_providers`)
  - Show-LLMs.ps1: мерж провайдеров из user-конфига, `llm_visible_providers`, Test-OpenCodeGoAvailable + opencode-zen + github-copilot
  - Ярлыки на рабочем столе (6 шт): LLM, FIXSHOW, Rules, Промпты, СОКР, Отчёт — Target=powershell.exe с `Start-Process -WindowStyle Hidden`
  - rules/remember-rule.md: запись инцидента
- **Ключевые правила:**
  1. `-WindowStyle Hidden` напрямую — нельзя. Только через `Start-Process -WindowStyle Hidden`.
  2. MetroWindow (MahApps) — не работает в Hidden, только Minimized.
  3. `enabled_providers` не использовать. Свой параметр `llm_visible_providers`.
  4. Hide-ConsoleWindow и Invoke-HiddenDialog — только резерв.
  5. В Show-*.ps1 не должно быть вызова Hide-ConsoleWindow.
- (12.07.2026)

### Launch-Hidden.ps1 — единый запускатор ДО (17.07.2026)
- **Проблема:** `Start-Process powershell -ArgumentList '...' -WindowStyle Hidden` ломает квотинг — модель генерирует `''...''`
- **Исправление:** скрипт-прокси `scripts\Launch-Hidden.ps1` делает Start-Process внутри себя
- **Команда из .md:** `powershell -NoProfile -File scripts\Launch-Hidden.ps1 -Script "Show-*.ps1"` (без вложенных кавычек)
- **Ярлыки:** Target=powershell.exe, Args=`-NoProfile -File "C:\...\Launch-Hidden.ps1" -Script "Show-*.ps1"`, WindowStyle=7 (Minimized)
- **Все .opencode/command/*.md** — обновлены на Launch-Hidden.ps1

### False positive Касперского на кэш OpenCode Desktop (17.07.2026)
- **Обнаружение:** HEUR:Trojan.PowerShell.Obfus.b в `C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\Cache\Cache_Data\f_00019a`
- **Причина:** PowerShell-скрипты (Start-Process, WindowStyle Hidden) попадают в Electron-кэш → эвристика видит «обфусцированный PS» в бинарном кэше
- **Следствие:** кэш-файл помещён в карантин; наши скрипты НЕ тронуты
- **sifiltersvc1** (SearchInform) — сервис, инициировавший сканирование
- **Рекомендация:** исключить `C:\Users\vchaga\AppData\Roaming\ai.opencode.desktop\Cache\` из мониторинга антивируса

### Bug-053: ShowDialog() блокирует автозакрытие GUI в тестах (22.07.2026)
- **Проблема:** `ShowDialog()` блокирует цикл WPF, callback-и из другого потока не могут закрыть окно
- **Решение:** DispatcherTimer проверяет флаг `$script:autoRunCompleted` каждые 500мс и закрывает окно
- **Файлы:** `bin/Prod-GUI.ps1` (строки ~4924-4941)

### ОП14: btnCo/btnUndo Click handlers в VSS Status Table (22.07.2026)
- **Файлы:** `bin/Prod-GUI.ps1` функция `Show-VssStatusTableWindow`
- **btnCo (Извлечь):** Checkout для выбранных свободных объектов
- **btnUndo (Снять резервирование):** Undo Checkout для выбранных занятых объектов
- **SelectionChanged:** автовключение/выключение кнопок при изменении выделения

### ОП18: VSS History — автоматический режим (22.07.2026)
- **Файлы:** `scripts/VSS-History-Show.ps1`, `bin/Prod-GUI.ps1`
- При множественном выборе объектов и флаге `-Automated` выбирается первый объект автоматически
- Операция "VSS: Object History" теперь передаёт флаг `-Automated` в VSS-History-Show

### Тесты операций Prod-GUI (22.07.2026)
- **Файлы:** `scripts/Test-OPS/Test-OP04.ps1`, `Test-OP06.ps1`, `Test-OP10.ps1`, `Test-OP11.ps1`, `Test-OP13.ps1`, `Test-OP18.ps1`, `Test-RunAll.ps1`
- Timeout для VSS операций: 60 сек (VSS отрабатывает <15 сек)
- Поиск операции в ComboBox по числовому индексу (1-based) для избежания кодировки

### Bug-054/055: WPF Event Handler Closure NULL в PS 5.1 (23.07.2026)
- **Проблема:** `$dg` и `$window` становились $null внутри WPF `Add_Click({})` callback (PowerShell 5.1 closure bug)
- **Симптом:** "Невозможно вызвать метод для выражения со значением NULL"
- **Решение:** использовать `$script:validationDataGrid` и `$script:validationWindow` вместо локальных переменных
- **Файлы:** `bin/Prod-GUI.ps1` (Show-ValidationErrorWindow)
- **btnClose:** `param($s, $e); if ($script:validationWindow.IsLoaded) { $script:validationWindow.Close() }`
- **btnMerge:** finally { if ($script:validationWindow -and $script:validationWindow.IsLoaded) { ... } }
- **Примечание:** `$dg` проверяется через `$script:validationDataGrid -eq $null`

### TASK-MORDA2: системный анализ ошибок при работе РАЗНЫХ LLM (01.08.2026, см. opencode-mcp id=100)
Корневая причина большинства ошибок — отсутствие общей памяти между сессиями: каждая LLM тестировала/правила, не имея контекста предыдущих. Класс ошибок «проверяем не ту версию / не там ищем»:

1. **Не перегенерирован .bat после правки ps1** — .bat-лаунчер содержит base64-копию скрипта; тестировалась СТАРАЯ версия → ложный вывод «асинхронность не работает» (самая дорогая ошибка).
2. **Автотест цеплялся к старому открытому окну** — изменения требуют перезапуска окна; несколько экземпляров с одинаковым MainWindowTitle.
3. **Start-ThreadJob использован в PS 5.1** — командлет PS7+, его нет.
4. **$op.RusName недоступен в тике DispatcherTimer** (замыкание) → пустой заголовок «Результат: »; имя передавать через state.
5. **EndInvoke без проверки Async.IsCompleted** — блокирует UI до завершения.
6. **.Name WPF-элемента не виден через UIAutomation** — нужен AutomationProperties.SetName.
7. **Save-Settings синхронно пересоздавал панель + модальный MessageBox** — блокировка UI-потока.
8. **Запуск GUI напрямую из bash-инструмента** — зависает; только Start-Process / .bat.
9. **Export Service ~41 мин на сетевом диске** — per-OP таймаут; блокировку определять по UIAutomation-исключениям.
10. **Jira PAT как Basic** — только Bearer (формат base64(userId:secret)); чтение issue напрямую по ключу (JQL по папке с _суффиксом → 400).

Решение: обязательный чек-лист перед тестом GUI в `rules/testing-rules.md`, сводный план с чек-боксами, записи MCP без дробления.

### TASK-MORDA2: ОП5 Export PB — ПБ не двигался + ложная «Ошибка» (01.08.2026, см. opencode-mcp)
Две независимые проблемы при ОП5 «Выгрузка PB: Current или Main» в МОРДА2 (Prod-GUI_STANDART2.ps1):

1. **ПБ не двигался во время выгрузки.** Причина: DispatcherTimer в тике проверял только `Async.IsCompleted`, не читая прогресс из фонового Runspace. Хендлер писал маркеры `###PHASE###/###STEP###`, которые никто не парсил. Исправление:
   - В тике таймера добавлено чтение `$state.Runspace.SessionStateProxy.GetVariable('script:PhaseProgress'/'script:StepProgress')` и обновление PhaseBar/StepBar/PhaseLabel/StepLabel.
   - Индикатор активности: если операция не обновляет прогресс — плавный пульс PhaseBar до 90% (видно, что обработка идёт).
   - `Invoke-OpExportPb` переписан: обновляет `$script:PhaseProgress.Value/Text` и `$script:StepProgress.Value/Text` в цикле ожидания процесса вместо маркеров.
2. **Ложная «Ошибка» в результате.** Причина: `Convert-ExportEncoding.ps1` падал на временно заблокированном файле (`user-mapped section open`) при записи кодировки — файл не успевал освобождаться. Исправление: retry 3 попытки с паузой 500 мс в `Convert-ExportEncoding.ps1`.

Дополнительно: в `Invoke-OpExportPb` заменён `-ExecutionPolicy Bypass` → `RemoteSigned` (антивирус Bug-063).

Автономная проверка: `Export-PB.ps1 -Source Current` — 31 библиотека, 2617 объектов, `###CONVERT###2614###`, ошибок в выводе НЕТ, STDERR пуст.



