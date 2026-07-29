# Сокращения проекта AIS Release Preparation

Полный свод всех сокращений. Дублирует и дополняет данные из `scripts/Show-Abbreviations.ps1`. Все пути — относительно `C:\AIS\AI\Prod\`.

## Каталоги и наборы

| Сокращение | Полное имя / Путь | Назначение |
|------------|-------------------|------------|
| **Current** | `C:\Work\gold` | Рабочая (разрабатываемая) версия исходников PB |
| **Main** | `C:\SRC125\gold` | Эталонная (промышленная) версия исходников PB |
| **PB_Current** | `PB_Current` | Экспортированные PB-объекты из Current |
| **PB_Main** | `PB_Main` | Экспортированные PB-объекты из Main |
| **BD/dev_golden** | `BD\dev_golden\` | SQL-экспорт с сервера dev_golden (Current) |
| **BD/galaxy** | `BD\galaxy\` | SQL-экспорт с сервера galaxy (Main) |
| **Ready_\*** | `C:\AIS\1 Release\<Task>\Ready_ГГГГ_ММ_ДД` | Папки с объектами к выпуску |
| **ReadyMerged** | `C:\Temp\ReadyMerged\<Task>` | Сводный набор из всех Ready_\* |
| **Git_\*** | `C:\AIS\1 Release\<Task>\Git_ГГГГ_ММ_ДД` | Исходные версии объектов (для сравнения) |

## Серверы и базы данных

| Имя | Тип | Назначение |
|-----|-----|------------|
| **dev_golden** | Сервер Sybase ASE | Разрабатываемая БД (Current) |
| **galaxy** | Сервер Sybase ASE | Промышленная БД (Main) |
| **golden** | База данных | Имя БД на обоих серверах |
| **vchaga** | Пользователь Sybase | Учётная запись для isql |

## Типы объектов

| Тип | Расширение | Описание |
|-----|------------|----------|
| **PBL** | `.pbl` | PowerBuilder Library |
| **PBT** | `.pbt` | PowerBuilder Target |
| **SRU/SRW** | `.sr\*` | Экспортированные PB-объекты |
| **Procedure** | `.sql` | Хранимая процедура Sybase ASE |
| **Functions** | `.sql` | Функция Sybase ASE |
| **Triggers** | `.sql` | Триггер Sybase ASE |
| **Views** | `.sql` | Представление Sybase ASE |
| **AIS** | — | Наименование проекта PowerBuilder / Jira |

## Статусы проверки

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

## Утилиты

| Утилита | Назначение |
|---------|------------|
| **isql** | Командная утилита Sybase ASE |
| **pbldump** | Экспорт объектов из PBL в .sr\* |
| **TortoiseMerge** | Визуальное сравнение файлов |
| **ss.exe** | Microsoft Visual SourceSafe (VSS) — система контроля версий |
| **VSS-Utils.ps1** | PowerShell модуль для работы с VSS |

## VSS команды

| Команда | Назначение | Пример | Параметры |
|---------|------------|--------|-----------|
| **Get** | Получить последнюю версию из VSS | `Get-VssLatest -Project "$/Project" -Recursive` | `-Project`, `-Recursive` |
| **Status** | Узнать состояние объектов | `Get-VssStatus -Project "$/Project" -Recursive` | `-Project`, `-Recursive` |
| **Properties** | Узнать кто использует объект | `Get-VssWhoIsUsing -Project "$/Project"` | `-Project` |
| **Checkout** | Выполнить Check Out | `Set-VssCheckout -Project "$/Project" -Comment "text" -Recursive` | `-Project`, `-Comment`, `-Recursive` |
| **Checkin** | Выполнить Check In | `Set-VssCheckin -Project "$/Project" -Comment "text" -Recursive` | `-Project`, `-Comment`, `-Recursive` |

## Ключевые файлы

| Файл | Назначение | Расположение |
|------|-----------|-------------|
| **config.json** | Конфигурация путей, Jira | `config/` |
| **AGENTS.md** | Центральный файл правил проекта | корень |
| **Launch-GUI.ps1** | GUI-приложение | `bin/` |
| **prepare_release.bat** | Главный оркестратор | `bin/` |
| **Compare-Export.ps1** | Сравнение и RFC | `scripts/` |
| **Add-ReleaseComment.ps1** | Комментарий в Jira | `scripts/` |
| **Create-RFC.ps1** | Создание RFC | `scripts/` |
| **Run-Tests.ps1** | Мастер-тест | `scripts/` |
| **VSS-Utils.ps1** | Утилиты VSS | `scripts/` |
| **Settings-Module.ps1** | Модуль настроек | `scripts/` |

## Сокращения для промптов

| Сокращение | Значение | Подробнее |
|------------|----------|-----------|
| **ЦИКЛ** | Запустить цикл автоисправления для указанной ОП | `auto_fix_loop.ps1 -OpNumber N` |
| **OUT / ОБР** | Исправить ошибки по тексту из Output | `temp\last_output.log` |
| **/prompts / ПРОМПТ** | Показать историю пользовательских промптов | `temp\user_prompts.log` |
| **СТАНДАРТ1** | Открыть эталон APPL2-стиля (ОКНО_СТАНДАРТ_1) | `scripts\Show-Appl2Standard.ps1` |
| **НОМ** | Номер операции в GUI (1-based) | Массив `$operations` |
| **МОРДА** | Главное окно GUI | `Launch-GUI.ps1` |
| **ДО** | Диалоговое окно сервиса | Пример: VSS History |
| **DLLM** | Диалоговое окно LLM — список и статус всех моделей ИИ | `Show-LLMs.ps1` |
| **ALL_LLM** | DLLM + СПИСОК LLM — все представления моделей | Совместное упоминание DLLM и списка LLM |
| **СОКР** | Показать все сокращения | `Show-Abbreviations.ps1` |
| **СВЕЖPB / NEWPB** | Самый свежий PB-объект из Ready_\* | Должен совпадать с Current/PB_Current |
| **СВЕЖSQL / NEWSQL** | Самый свежий SQL-объект из Ready_\* | Должен совпадать с dev_golden/BD/dev_golden |
| **OLDPB** | Исходный PB-объект из Git_\* | Должен совпадать с Main/PB_Main |
| **OLDSQL** | Исходный SQL-объект из Git_\* | Должен совпадать с dev_golden/BD/galaxy |
| **СТАРТ** | Выполнить preflight-проверку | `get_rule("preflight")` |
| **TaskPl** | Запустить ДО управления TaskPlan | `Show-TaskPlanGUI.ps1` — вкладки Обзор/Управление |
| **STELLS** | Безопасное скрытие консоли PS через чистый .NET (без P/Invoke) — антивирус не детектит. Методы: Invoke-StellsHide (само-скрытие), Invoke-StellsLaunch (лаунчер), Invoke-StellsCapture (с захватом вывода) | `Stells-HideConsole.ps1` — единый модуль. Встроен в СТАНДАРТ1 через Set-MetroTheme.ps1. Команда `STELLS <имя_ДО>` = применить к диалогу |
| **RR / РР** | Принудительно переключить модель на русский язык | При нарушении языкового правила |
| **OO / ОО** | Выполнить все задачи / продолжить при переполнении | Завершить todo-лист |
| **FIXSHOW** | Показать/изменить статусы EDIT/FIXED | `Show-OpStatus.ps1` |
| **ЗАПОМНИ / RULE_MEMBER** | Проанализировать ошибку, запомнить причину | Внести правило в AGENTS.md |
| **MSG** | Отдельное окно-сообщение (MessageBox) | Для уведомлений |
| **FIX N / FIXED N** | Перевести ОП N в FIXED (запрет изменений) | N — номер операции |
| **EDIT N** | Перевести ОП N в EDIT (разрешение изменений) | N — номер операции |
| **ПБ** | Прогресс-бар — индикатор выполнения | Двухуровневый: по типам и по объектам |
| **PB** | PowerBuilder — среда разработки | PowerBuilder IDE |

## Термины

| Термин | Описание |
|--------|----------|
| **PB** | PowerBuilder — среда разработки клиент-серверных приложений |
| **ПБ** | Прогресс-бар — индикатор выполнения операции |
| **SQL** | Structured Query Language — язык запросов к БД |
| **VSS** | Microsoft Visual SourceSafe — система контроля версий |
| **RFC** | Request For Change — заявка на изменение в Jira |
| **Jira** | Система управления задачами |
| **PBL** | PowerBuilder Library — файл .pbl |
| **PBD** | PowerBuilder Dynamic Library — пропускается при экспорте |
| **PBT** | PowerBuilder Target — файл .pbt |
| **SR\*** | Экспортированные PB-объекты (.srw, .sru, .srd и др.) |
| **PROD** | Папка собранных объектов к выводу в продуктив |
| **ОП** | Операция в GUI (например, ОП 1, ОП 7) |
| **TaskName** | Имя задачи Jira |
| **SYS** | Префикс системной задачи Jira (SYSTEM-67) |
| **Golden** | Основная БД проекта (набор библиотек golden_\*) |

## Правила работы с todowrite

| Сокращение | Описание |
|------------|----------|
| **TODOWRITE** | Встроенный инструмент модели для отслеживания прогресса задач. Создаёт структурированный список. |
| **Как завершить** | Всегда отмечать все пункты `completed` или `cancelled` перед завершением работы. Незакрытые задачи «виснут» в интерфейсе. |
| **Копирование** | Вывод `todowrite` — системный JSON, не копируется. Нужно просить модель вывести задачи **обычным текстом** (например, `[√] задача`). |
| **Сохранение в файл** | Можно попросить модель записать задачи в `temp\todo_list.txt` — файл открывается в Блокноте. |
| **Команда для модели** | `Выведи список задач простым текстом с маркерами [ ] и [√]` |
