# Единый документ требований МОРДА / МОРДА2 (СТАНДАРТ2)

> **Назначение:** единственный источник истины по требованиям к приложению МОРДА (главное окно подготовки релизов) и МОРДА2 (`Prod-GUI_STANDART2.ps1`, сборка СТАНДАРТ2). Документ создан 06.08.2026 для того, чтобы МОРДА восстанавливалась заново после антивирусных атак (Kaspersky/Defender удаляют `.ps1`, Bug-063/064/065) без потери накопленных требований.
>
> **Дубли:** во всех остальных источниках требований (`.opencode/*.mdc`, `rules/*.md`, описания задач) вместо дублирования текста давать ссылку на этот файл: `docs\morda-requirements.md`.

---

## 1. Общие сведения

| Параметр | Значение |
|----------|----------|
| Приложение | МОРДА — Подготовка релизов (AIS Release GUI) |
| Реализация 1 (СТАНДАРТ1) | `Prod-GUI.ps1` / `bin\Prod-GUI.ps1` |
| Реализация 2 (СТАНДАРТ2) | `bin\Prod-GUI_STANDART2.ps1` (МОРДА2, актуальная, ~1615 строк) |
| Хелперы СТАНДАРТ2 | `scripts\Standard2-Helpers.ps1` (стили ПБ, окна, сообщения, DataGrid, кнопки) |
| Эталон внешнего вида | `scripts\Show-Appl2Standard-CS\MainWindow.xaml` (C#/WPF, официальный образец СТАНДАРТ2) |
| Техжурнал | `%TEMP%\tech_journal_<дата>_<время>_<PID>.log`, первая строка `[..] [INFO] MORDA started (ST2)` |
| Мультиэкземплярность | запрещена; признак окна — `MainWindowTitle -eq "МОРДА — Подготовка релизов"` |
| Конфигурация | `config\config.json` (пути `bd_main_export`, `bd_current_export`, `release_root`, `vss.*`, `paths.*`, `jira.*`) |
| Секреты | `config\.local_secrets.json` (никогда не в Git; пароли/токены передаются в операциях, не хранятся) |

### 1.1. Иерархия требований

1. Этот документ — **единственный источник истины** по требованиям к GUI МОРДА/МОРДА2.
2. `.opencode\standard2-gui.mdc` — эталон СТАНДАРТ2 (детали стилей окна; ссылается на этот документ).
3. `scripts\Show-Appl2Standard-CS\MainWindow.xaml` — канонические XAML-стили (кнопки, ПБ, поля).
4. Остальные файлы правил — только ссылки, без дублирования.

---

## 2. Требования к GUI (СТАНДАРТ2)

### 2.1. Окно

| Требование | Значение |
|-----------|----------|
| Прозрачность окна | Окно **непрозрачное**; полупрозрачны только Title bar и элементы (`#CC` = 80 %, `#80` = 50 %) |
| Размер по умолчанию | 520 × 580 (эталон); главное окно МОРДА2 — 620 × 620 |
| `WindowStyle` | `None` (без системной рамки) |
| `ResizeMode` | `CanResizeWithGrip` |
| `Topmost` | `True` |
| Расположение | `CenterScreen` |
| Фон окна | `#E8ECF0` |
| Скругление углов | Win32 `CreateRoundRectRgn`, радиус 18 px (18,18,36,36): `RoundedWindow::Apply` при `Loaded` и `SizeChanged` |
| Тень | `DropShadowEffect Color=#404040 Direction=270 ShadowDepth=4 BlurRadius=10 Opacity=0.5` |
| Рамка | `BorderBrush=#1A3A60`, `Thickness=1` |
| `AllowsTransparency` | `True` (эталон) |
| Перетаскивание | Title bar → `MouseLeftButtonDown` (WM_NCHITTEST: если `pt.Y < 42`, `pt.X >= 8`, `pt.X <= ActualWidth-8` → `HT_CAPTION` = 2) |

### 2.2. Title bar (шапка окна)

| Требование | Значение |
|-----------|----------|
| Высота | 40 px |
| Фон | `#807080B0` (полупрозрачный 50 %, глубокий сине-серый) |
| Скругление | `17,17,0,0` |
| Нижняя граница | `BorderBrush=#1A3A60`, `Thickness=0,0,0,1` |
| Заголовок | «МОРДА — Подготовка релизов» (главное окно); для ДО — название ДО |
| Стиль текста | 3D: белый сдвинутый слой (White, Opacity 0.9, Margin 3,2,0,0) + тёмно-синий передний слой `#1A3A60`; шрифт Segoe UI, Bold, 14 |
| Кнопки управления | `━` (свернуть), `☐` (развернуть), `✕` (закрыть) — прозрачный фон, `Foreground=#1A3A60`, ширина 40, высота 36 |

### 2.3. Кнопки (Glossy 3D)

| Требование | Значение |
|-----------|----------|
| Базовая кнопка | 120 × 38, Bold 11, `Cursor=Hand`, текст белый, `Margin=4,0` |
| Шаблон | Внешний `Border CornerRadius=10 Background=#CC0F3050`; внутренний `Border CornerRadius=9 Margin=1.5` с вертикальным градиентом `#CC9DC8F0 → #CC3B7BBF → #CC1A4A7A`; верхний блик `Height=7 CornerRadius=9 Margin=2,2,2,20` градиент `#E0FFFFFF → #00FFFFFF` |
| Отмена (Cancel) | Серый: внешний `#CC404040`, градиент `#CCD0D0D0 → #CC909090 → #CC606060` |
| Малая кнопка (поиск ▼/▲) | 30 × 26, FontSize 11 |
| Главные кнопки МОРДА2 | `btnRun` («Выполнить»), `btnHistory` («История»), `btnExit` («Выход») — в панели `New-Standard2ButtonPanel` |

### 2.4. Поля ввода, пароль, выпадающие списки

| Элемент | Требование |
|---------|-----------|
| Подпись поля | `FontSize=10`, `Foreground=#4A5568`, `Margin=3,0,0,1` |
| Рамка поля | `BorderBrush=#CBD5E0`, `Thickness=1`, `CornerRadius=10`, `Padding=6,4` |
| TextBox/ComboBox внутри | `BorderThickness=0`, `Background=Transparent`, `FontSize=11` |
| PasswordBox | внутри такой же рамки; **пароль никогда не выводится в журнал/отчёты** (в техжурнале `pwd=***`) |
| ComboBox операций | `Name="cmbOp"`, FontSize 12, Height 30 |

### 2.5. DataGrid

| Требование | Значение |
|-----------|----------|
| Режим | `AutoGenerateColumns=False`, `IsReadOnly=True`, `HeadersVisibility=Column`, `RowHeaderWidth=0` |
| Фон | чередование `White` / `AlternatingRowBackground=#F5F7FA`; `GridLinesVisibility=None` |
| Сортировка | `CanUserSortColumns=True` |
| Выбор | `SelectionMode=Single`, `SelectionUnit=FullRow` |
| Прокрутка | вертикальная и горизонтальная — `Visible` |
| Шрифт | 11 |

### 2.6. Панель поиска

`lblMatch` (счётчик «0 - 0»), `txtSearch` (высота 26, `KeyDown` Enter/WM_CHAR, `TextChanged`), кнопки `▼` / `▲` (малый Glossy 3D) — переход к следующему/предыдущему совпадению.

### 2.7. Прогресс-бары (ПБ) — детальные требования

Стиль `New-Standard2ProgressStyle` (в `Standard2-Helpers.ps1`), основан на эталонном `GlossyProgress`.

| Требование | Значение |
|-----------|----------|
| Форма | **Овальные** (скруглённые), `CornerRadius` 12 (индикатор) / 10 (трек) |
| Фон (трек) | Полупрозрачный `#990F3050` (эталон: `#CC0F3050` внешний + `#E2E8F0` дорожка) |
| Объёмность (3D) | **ГОРИЗОНТАЛЬНЫЙ объём**: блик и тень идут по горизонтали (слева→справа), создавая эффект трубы/стержня; **не** вертикальный объём (блик сверху — запрещено, Bug ОП7) |
| Градация цвета индикатора | **ГОРИЗОНТАЛЬНАЯ**: `LinearGradientBrush StartPoint=0,0 EndPoint=1,0` (слева направо), голубой → фиолетовый → синий (пример: `#CCB8D8F8 → #CC3B7BBF → #CC1A4A7A → #CC0F3050`) |
| Высота | 18 px (эталон) |
| Блик | Белый глосс по верхней части ПБ, градиент `#C0FFFFFF → #00FFFFFF` |
| Тень | Нижняя тень для глубины, `IsHitTestVisible=False`, градиент `#30000000 → #80000000` |
| Минимум/максимум | `Minimum=0`, `Maximum=100` |
| **Текст поверх ПБ** | Обязателен: подписи фаз и шагов отображаются ПОВЕРХ самого ПБ (белый текст с тенью), а не рядом. Обновление через `DispatcherTimer` из Runspace; **текст обновляется всегда, включая `Value=0`** |
| Подписи | `lblPhase` («Фаза: …»), `lblStep` («Шаг: (3 - 10)»), FontSize 11, `Foreground=#4A5568`; в МОРДА2 — `PhaseProgress`/`StepProgress` с полями `Value` и `Text` |
| Обработка `###PHASE###` / `###STEP###` | При парсинге вывода операций обновлять ПБ: фаза → `Value` по индексу типа, шаг → `Value = step/total`, `Text = "N из M"` |
| Текст шага при экспорте | `StepProgress.Text += " — <имя объекта>"` по строке `Exporting <тип>: <имя>` |

**Требование восстановления:** при перерисовке/смене операции текст поверх ПБ не должен пропадать; значение и текст ПБ выставляются в начало операции и обновляются по мере поступления прогресса.

---

## 3. Главное окно МОРДА2 (`Prod-GUI_STANDART2.ps1`)

### 3.1. Структура (сверху вниз)

1. **Строка «Операция»** — ComboBox `cmbOp` с 19 операциями + описание выбранной операции (`txtDesc`).
2. **Панель параметров** `ParamsPanel` — динамически строится из `Fields`/`Checkboxes` выбранной операции (TextBox, PasswordBox, ComboBox с `Items`).
3. **ПБ фаз и шагов** (`PhaseProgress`, `StepProgress`).
4. **Кнопки**: `btnRun` (Выполнить), `btnHistory` (История), `btnExit` (Выход).

### 3.2. Поведение

- Выбор операции в `cmbOp` → `Select-Operation` (пересборка полей; PasswordBox для `NeedsPassword=$true`).
- `btnRun` → `Run-SelectedOperation`: валидация обязательных полей (`Required=$true`), чтение пароля, запуск Handler в Runspace (не блокировать UI), обновление ПБ через `DispatcherTimer`.
- `btnHistory` → `Show-HistoryWindow` («История операций — в разработке»).
- `btnExit` → закрытие окна.
- При закрытии — запись `Write-TechJournal "INFO" "Application closed"`.

### 3.3. Защита от мультиэкземплярности

```
Get-Process | Where-Object { $_.MainWindowTitle -eq "МОРДА — Подготовка релизов" -and $_.Id -ne $PID }
```
- обычный запуск → `exit 0` (не создавать второй экземпляр);
- режим `--autotest` → старые процессы принудительно завершаются (`Stop-Process -Force`).

### 3.4. Скругление углов и перетаскивание

`Add-Type` C# `RoundedWindow` (`CreateRoundRectRgn`, `SetWindowRgn`, радиус 36/36). Применяется на `Loaded` и пересчитывается на `SizeChanged`. Перетаскивание — hook `WM_NCHITTEST` (0x0084): зона `Y<42`, `X∈[8, ActualWidth-8]` → `HT_CAPTION`.

---

## 4. Операции (19) — полный перечень

Индексы в ComboBox `cmbOp` — с 0 в порядке списка ниже.

| № | Имя (`Name`) | Русское название | Пароль | Поля | Обработчик |
|---|--------------|------------------|--------|------|------------|
| 0 | Settings | Настройки параметров | нет | — | `Invoke-OpSettings` |
| 1 | Run Tests | Запуск тестов | нет | Чекбокс `QuickMode` | `Invoke-OpRunTests` |
| 2 | Export Service | Export Service (выгрузка проекта) | нет | `DestPath` | `Invoke-OpExportService` |
| 3 | Collect PROD Objects | Собрать объекты для вывода в ПРОД | нет | `TaskName`*, `CollectPath` | `Invoke-OpCollectProd` |
| 4 | Export PB | Выгрузка PB: Current или Main | нет | `Source`(Current/Main), `TaskName` | `Invoke-OpExportPb` |
| 5 | Compare PB | Сравнение PB: Current и Main | нет | `TaskName`, `OutputFile` | `Invoke-OpComparePb` |
| 6 | **SQL Export** | Выгрузка SQL | **да** | `Source`, `Server`, `Db`, `ObjectType`, `TaskName` | `Invoke-OpSqlExport` |
| 7 | Compare SQL | Сравнение SQL: Current и Main | **да** | `TaskName` | `Invoke-OpCompareSql` |
| 8 | Compare & Verify | Сравнение и проверка | **да** | `TaskName`*; чекбоксы `ShowDiff`, `CreateRFC` | `Invoke-OpCompareVerify` |
| 9 | Create RFC | Создание RFC в Jira | **да** | `TaskName`* | `Invoke-OpCreateRfc` |
| 10 | Jira Release Comment | Комментарий в Jira | **да** | `TaskName`*, `ProjectName`(AIS) | `Invoke-OpJiraComment` |
| 11 | VSS: Get Latest | VSS: Получить последнюю версию | нет | `VssPath`, `VssUser`, `TaskName`, `Project`, `PbtFile`; чекбокс `Recursive` | `Invoke-OpVssGetLatest` |
| 12 | VSS: Check Status | VSS: Проверить статус | нет | `VssPath`, `VssUser`, `Project`, `TaskName`; чекбокс `Recursive` | `Invoke-OpVssCheckStatus` |
| 13 | VSS: Who Is Using | VSS: Кто использует | нет | `VssPath`, `VssUser`, `Project`, `TaskName`; чекбокс `Recursive` | `Invoke-OpVssWhoIsUsing` |
| 14 | VSS: Checkout | VSS: Checkout (Извлечь) | нет | `VssPath`, `VssUser`, `Project`, `Comment`; чекбокс `Recursive` | `Invoke-OpVssCheckout` |
| 15 | VSS: Checkin | VSS: Checkin (Сохранить) | нет | `VssPath`, `VssUser`, `Project`, `Comment`*; чекбокс `Recursive` | `Invoke-OpVssCheckin` |
| 16 | VSS: Undo Check Out | VSS: Undo Check Out | нет | `VssPath`, `VssUser`, `Project`, `Comment`; чекбокс `Recursive` | `Invoke-OpVssUndo` |
| 17 | VSS: Object History | VSS: История объекта | нет | `VssPath`, `VssUser`, `TaskName`, `Project` | `Invoke-OpVssHistory` |

Примечания:
- `*` — поле обязательно (`Required=$true`).
- Пароль (`NeedsPassword=$true`) читается из PasswordBox; в техжурнале и аргументах маскируется как `***`.
- Валидация VSS Checkin: пустой `Comment` → `throw` «Комментарий обязателен для Checkin».
- Папки задач ищутся по префиксу `TaskName*` (правило TASK, суффикс `_<число>` = родительская задача), `Ready_*` — последняя по имени.

### 4.1. SQL-типы выгрузки (ОП7)

`SQL_exp_param.bat` / `SQL_exp_single.bat` из `bin\`, типы: `Procedures`, `Functions`, `Triggers`, `Tables`, `Views`, `Indexes`, `PrimaryKeys`, `ForeignKeys`, `Grants`. Выбор `ObjectType` из списка `("", "Procedure", "Functions", "Triggers", "Tables", "Views", "Indexes", "PK", "FK", "Grants")`.

---

## 5. Операция SQL Export (ОП7) — детальные требования и зафиксированные баги

### 5.1. Режим «полной выгрузки» (без TaskName)

- Источник `Source` → сервер: **Current → `dev_golden`**, **Main → `galaxy`**.
- **Баг ОП7-1 (зафиксирован, требует проверки):** при смене `Source` (Current/Main) в интерфейсе наименование `Server` **не меняется автоматически**. Требование: смена `Source` должна автоматически выставлять `Server = dev_golden` (Current) или `galaxy` (Main), а также цель выгрузки: `bd_current_export` (dev_golden) или `bd_main_export` (galaxy).
- `Db` по умолчанию `golden`.
- Пароль передаётся в `SqlExport.exe`; в техжурнал — `pwd=***` (без раскрытия).
- `SqlExport.exe` (`scripts\SqlExport\Program.cs`) вызывает `cmd /c bin\SQL_exp_param.bat <server> <db> <password> "" <exportPath> [objectType]`, транслирует `###PHASE###<имя>|<N>###` и `###STEP###` → `###STEP###N|M###`.
- МОРДА2 парсит вывод: `###PHASE###` → обновление `PhaseProgress` (фаза «Тип: …», Value по индексу в `knownTypes`), `###STEP###N|M###` → `StepProgress` (`N из M`), строка `Exporting <тип>: <имя>` → дописывает имя в текст шага.
- Итог: статистика «Выгружено: <тип>: <кол-во>… Всего файлов: N».

### 5.2. Режим «по задаче» (с TaskName)

- Сканируются папки задачи `Ready_*` и `Git_*` на `*.sql`.
- Определение типа по первым 20 строкам (`CREATE PROC/EDURE`, `CREATE FUNCTION`, `CREATE TRIGGER`, `CREATE TABLE`, `CREATE VIEW`).
- Каждый объект выгружается через `SQL_exp_single.bat <тип> <имя> <server> <db> <password>` в `bd_main_export\<тип>\<имя>.sql` или `bd_current_export\<тип>\<имя>.sql`.
- Отчёт: `Успешно: N, Ошибок: M, Всего: K`. Пусто → `###SQL_TASK_NONE###`.

### 5.3. Связанные операции (индексы 7-8, 6-7 в MCP-знании id 99)

- «Выгрузка SQL» — индекс 6, «Сравнение SQL: Current и Main» — индекс 7. Ручная регрессия SQL-операций — PASS; пароль вводится через SendKeys в PasswordBox `pwdField` (эталонное имя поля).

### 5.4. Баги ОП7 (непроверенные, внести в `rules/changelog.md` после подтверждения)

| № | Баг | Требование |
|---|-----|------------|
| ОП7-1 | Сервер не меняется при смене источника | Автоподстановка `Server` из `Source` (Current→dev_golden, Main→galaxy) и целевой папки выгрузки |
| ОП7-2 | У ПБ вертикальный объём | **Горизонтальный** объём (блик/тень по горизонтали) |
| ОП7-3 | Нет градации цвета | Горизонтальная градация голубой→фиолетовый→синий (`StartPoint=0,0 EndPoint=1,0`) |
| ОП7-4 | Нет текста у ПБ | Текст поверх ПБ виден всегда, обновление при любом `Value` (включая 0) |

### 5.5. Требования к формату выгрузки SQL (Стандарт dbArtesan)

Для обеспечения версионности и корректного сравнения объектов, выгружаемых разными способами, установлен единый стандарт формирования `.sql` файлов:

1.  **Кодировка:** Windows-1251 (ANSI) без BOM.
2.  **Заголовок (Wrapper):** 
    - `USE <database>`
    - `go`
    - Блок `IF OBJECT_ID('dbo.<object_name>') IS NOT NULL BEGIN DROP ... END`
    - `go`
3.  **Метод получения тела:** запрещено использовать прямой `SELECT text` из `syscomments` (из-за word-wrap и обрезания строк в `isql`). Выгрузка производится только через конвертацию в HEX (`convert(varbinary(255), text)`) с последующей сборкой на клиенте (скрипт `Rebuild-Object.ps1`).
4.  **Подвал (Footer):**
    - `go`
    - Установка режима: `EXEC sp_procxmode 'dbo.<object_name>', 'unchained'` (для процедур).
    - `go`
    - Выдача прав: блоки `GRANT ...` на основе `sysprotects`.
    - `go`

### 5.6. Требования к формату объектов PowerBuilder (PB)

1.  **Инструмент выгрузки:** `pbldump` (версия 1.3.1 stable).
2.  **Кодировка (Локально):** файлы в папках `PB_Current`, `PB_Main`, `Test_*`, `Ready_*` должны быть в **UTF-8 с BOM** для корректной работы с Git и внешними редакторами.
3.  **Кодировка (VSS):** при импорте/экспорте из VSS (ss.exe) используется кодировка **Windows-1251 (ANSI) без BOM**.
4.  **Нормализация:** все файлы должны иметь окончания строк **CRLF**.

**Реализация в проекте:** скрипты `scripts\Export-PB.ps1` и `scripts\Convert-ExportEncoding.ps1`.

---

## 6. Требования к результату операций

### 6.1. Кодировки (обязательно)

| Файл | Кодировка | BOM |
|------|-----------|-----|
| `.ps1` | UTF-8 | **с BOM** (PS 5.1 читает как CP1251 без BOM → кракозябры) |
| `.json` / `.jsonc` | UTF-8 | **без BOM** (Bug-044) |
| `.sql` | Windows-1251 | нет |
| `.bat` | Windows-1251 | нет |
| `.md` | UTF-8 | без BOM |
| Отчёты/результаты операций | UTF-8 без BOM (`[System.IO.File]::WriteAllText(path, text, UTF8Encoding($false))`) | без BOM |
| Вывод консольных операций | Сохранять через `| Out-String`, показывать в ДО результата | — |

### 6.2. Отображение результата

- Результат операции показывать в **диалоге результата** (`Show-ResultWindow` / `Build-ResultWindowUI`, СТАНДАРТ2): заголовок, многострочный текст результата, кнопка закрытия.
- **Фрагменты кода не вставлять в отчёты** — только ссылки на файлы и описания.
- SQL-дампы и PB-экспорт — **только справочные**, сами файлы не изменять.
- Запрещён доклад «успешно» без трёх этапов тестирования (см. раздел 8).

### 6.3. Логирование (Tech Journal)

- Файл: `%TEMP%\tech_journal_yyyyMMdd_HHmmss_<PID>.log`, формат строки `[ЧЧ:ММ:СС.fff] [УРОВЕНЬ] сообщение`.
- Уровни: `INFO`, `ERROR`, `CLICK`, `SHOT`, `CHECK`, `FIELDS`, `OPS`, `OVERLAP`, `AUTOTEST`.
- Обязательно логировать: запуск (`MORDA started (ST2)`, `EXE path`, `Args`), загрузку конфига, каждую операцию (входные параметры **без пароля**), ошибки, нажатия кнопок, завершение.
- При сбое записи — fallback-файл `<журнал>.fallback`.
- МОРДА (СТАНДАРТ1) пишет в `temp\last_output.log` (заголовок `=== AIS Output Log ===`) — читается командой OUT/ОБР.

### 6.4. Отчёты операций

| Операция | Файл отчёта |
|----------|-------------|
| Compare PB | `compare_pb_report.txt` (по умолчанию `C:\AIS\AI\Prod\compare_pb_report.txt`) |
| SQL Export | статистика в ДО результата + файлы в `bd_main_export` / `bd_current_export` |
| Compare & Verify | отчёт готовности + (опционально) RFC в Jira |
| VSS: Object History | вывод через `VSS-History-Show.ps1` (окно TortoiseMerge, поиск текста) |

---

## 7. Автотестирование (--autotest) и проверка GUI

### 7.1. Режим `--autotest <файл>`

Файл команд (по строке, `#` — комментарий). Команды:
`log <текст>`, `wait <мс>`, `click <кнопка>`, `set_search <текст>`, `select_op <N>`, `resize <W>,<H>`, `shot <имя>`, `check_visible <имя>`, `check_fields`, `check_overlap`, `expect_ops <N>`, `close`,
`check_file <путь>`, `check_files <путь> <мин>`, `expect_result <паттерн>`, `expect_output <паттерн>`, `run_op <индекс> <таймаут_сек>`, `assert <паттерн>`, `exit_ok`, `exit_fail`.

Скриншоты: `%TEMP%\autotest_shots\<имя>.png`, анализ пустоты (порог заполнения ≥ 1 % → OK, иначе `EMPTY`).

### 7.2. Правило трёх этапов тестирования (gui-testing-rule.mdc)

Нельзя сообщать об успехе, пока не выполнены все три этапа:
1. **Открытие** окна и его элементов (`check_visible`, `check_fields`, `check_overlap`, `expect_ops`).
2. **Новая функциональность** (проверка конкретной доработки).
3. **Регрессия** всех ранее работавших функций.

Автоматическое тестирование ввода — SendKeys (пароль в `pwdField`). Проверка результата — `check_file`/`check_files`/`expect_result`/`expect_output`.

### 7.3. Автотесты проекта

- `scripts\Run-Tests.ps1` — парсер PS, кодировка BOM, операции, пути (быстрый режим `-Quick`).
- `scripts\TaskPlan-Tests.ps1`, `scripts\Out-TaskPlan-Tests.ps1` — тесты TaskPlan (отдельный сервис).

---

## 8. Требования безопасности и антивирус (Bug-063/064/065)

- `.ps1` — всегда UTF-8 **с BOM**; после записи запускать `scripts\Add-Bom.ps1 <файл>` или `Preflight-Antivirus.ps1 -AutoFix`.
- **Запрещено:** `-ExecutionPolicy Bypass` (только `RemoteSigned`), скрытый запуск `WindowStyle Hidden`, `IEX` от подозрительных строк, base64 в `.bat` (детект HEUR:Trojan.PowerShell.Obfus), P/Invoke-обфускация.
- VBS-обёртки — только `Shell.Application.ShellExecute …, "open", 1`.
- Секреты — только в `config\.local_secrets.json`, никогда в Git/GitHub.
- Исключения антивируса: `C:\AIS\AI\Prod\`, `%APPDATA%\ai.opencode.desktop\Cache\`.
- STELLS — скрытие консоли PS чистыми методами .NET (антивирус не детектит).

---

## 9. Процесс восстановления МОРДЫ после атаки

1. Проверить/пересоздать `.ps1` по этому документу: `bin\Prod-GUI_STANDART2.ps1`, `scripts\Standard2-Helpers.ps1`.
2. Добавить BOM всем `.ps1`: `scripts\Add-Bom.ps1`.
3. Запустить `scripts\Preflight-Antivirus.ps1 -AutoFix`.
4. Убедиться в отсутствии запрещённых паттернов (раздел 8).
5. Проверить синтаксис: `powershell -NoLogo -File <файл>` → SYNTAX_OK.
6. Запустить МОРДА2 и прогнать автотест `--autotest` (раздел 7).
7. Обновить MCP-знания `opencode-mcp`/`ais-catalog`.

---

## 10. Источники требований (ссылки)

- `docs\morda-requirements.md` — **этот документ (источник истины)**.
- `.opencode\standard2-gui.mdc` — эталон стилей СТАНДАРТ2.
- `scripts\Show-Appl2Standard-CS\MainWindow.xaml` — канонические XAML-стили.
- `.opencode\gui-testing-rule.mdc` — правило трёх этапов тестирования.
- `rules\gui-rules.md` — история багов GUI (BUG-004…007 и далее).
- `rules\abbreviations.md`, `rules\pending-tasks.md`, `rules\changelog.md`.
- `tasks\TASK-MORDA2\ПЛАН_РЕАЛИЗАЦИИ.txt` — план восстановления МОРДА2 (19 пунктов).
- MCP: `opencode-mcp` (id 96-102, 118 — реестр ДО; id 84 — антивирус), `ais-catalog` (id 188).
