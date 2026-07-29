# Правила сервиса VSS (Visual SourceSafe)

## Состав сервиса

| Файл | Назначение |
|------|------------|
| `scripts\VSS-Utils.ps1` | Модуль функций для работы с VSS (dot-source) |
| `scripts\vss.bat` | BAT-обёртка для быстрого вызова ss.exe из командной строки |
| `config\config.json` (секция `vss`) | Настройки VSS: путь к БД, пользователь, пароль (зашифрован) |
| `config\vss_object_history.json` | История введённых объектов VSS для ComboBox |

## Внешние зависимости

- **ss.exe** — Microsoft Visual SourceSafe command line
  - Путь: `C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe`
  - Должен быть установлен отдельно (не входит в проект)
- **srcsafe.ini** — файл базы данных VSS
  - Путь: `\\ren-msksf01\VSS2005\srcsafe.ini`

## Известные ошибки и их предотвращение

### VSS-Utils.ps1

1. **`Export-ModuleMember` при dot-source** (Bug-005)
   - `Export-ModuleMember` вызывает ошибку при dot-sourcing скрипта
   - **Исправление:** добавлена проверка `$MyInvocation.MyCommand.CommandType` и `-ErrorAction SilentlyContinue`
   - **Правило:** при dot-source не полагаться на `Export-ModuleMember`

2. **`$ErrorActionPreference = "Stop"` → `"Continue"`** (Bug-005)
   - `Stop` приводит к остановке при minor-ошибках (например, ss.exe exit code 1)
   - **Исправление:** установлено `"Continue"` в начале скрипта

3. **ss.exe exit code 1 — это норма** (Bug-019)
   - `ss.exe Status` возвращает exit code 1 при наличии checked out файлов
   - `ss.exe Checkout` возвращает exit code 100 при успехе (не 0)
   - **Правило:** не проверять `$LASTEXITCODE` на `0` для ss.exe

4. **`$_` не экранирован в here-string** (Bug-019)
   - В `${ @` "`n`$_\`r\`n"@ }` `$_` интерполировался как `$null`
   - **Исправление:** использовать `` `$_ `` с обратным апострофом

5. **Get-VssWhoIsUsing: Properties → Status** (Bug-021)
   - `ss.exe Properties` показывает только метаданные (не показывает кто извлёк)
   - **Исправление:** заменён на `ss.exe Status`, который выводит `Checked out to: username`
   - **Важно:** при добавлении новых VSS-функций не использовать `ss.exe Properties` для определения владельца

6. **Короткие имена объектов** (FEAT-004)
   - Можно указывать только имя файла (с расширением или без): `w_ais_request_select.srw`
   - Полный VSS-путь строится через поиск в `PB_Main` и `PB_Current`
   - **Правило:** функция `Resolve-VssObjectPath` (в Prod-GUI.ps1) вызывается перед выполнением VSS-операций
   - Если объект не найден в PB_Main/PB_Current — используется исходное значение (полный путь)

7. **Пароль из Settings — единый источник** (FEAT-005)
   - VSS-операции не имеют поля `VssPass` — пароль берётся из config.json
   - При запуске VSS-операции пароль расшифровывается через `Get-MasterKey` + `Decrypt-Password`
   - **Правило:** если пароль не задан в Settings — передаётся пустая строка (может вызвать ошибку аутентификации ss.exe)

### ss.exe особенности

8. **`-I-Y` флаг обязателен**
   - `ss.exe` без `-I-Y` запрашивает подтверждение (Yes/No) на интерактивном вводе
   - **Правило:** всегда добавлять `-I-Y` ко всем командам VSS

9. **Параметр `-R` для рекурсии**
   - **Правило:** добавлять после всех остальных параметров

10. **Формат `-Yuser,password`**
    - Пользователь и пароль разделяются запятой: `-Yvchaga,mypassword`
    - Вся строка без пробелов
    - Если пароль содержит запятую — возможны проблемы

11. **Комментарий через `-C"текст"`**
    - Комментарий оборачивается в двойные кавычки
    - **Важно:** если комментарий содержит двойные кавычки — экранировать их обратным слешем: `\"`

12. **Потоковый вывод в GUI** (Bug-018)
    - VSS-Utils.ps1 не захватывает вывод — каждая строка ss.exe идёт напрямую
    - GUI пишет через StreamWriter.WriteLine + Flush — вывод появляется сразу
    - Таймаут вывода: `gui.output_timeout_seconds` (по умолчанию 60)
    - Таймаут срабатывает только если нет данных > N секунд

13. **ss.exe Status с TaskName — таблица статуса** (FEAT-008)
    - При указании TaskName сканируются папки `Ready_*` (исключая `Ready_`)
    - Для каждого `.sr*` файла определяется VSS-путь и статус
    - Результат выводится через `###VSS_STATUS###` маркер
    - GUI обнаруживает маркер и показывает `Show-VssStatusTableWindow`

14. **Auto-refresh ComboBox после VSS-операции** (FEAT-001)
    - `Update-VssProjectCombo` вызывается после завершения процесса
    - Сохраняет текущий текст перед обновлением, восстанавливает после (Bug-020)
    - **Правило:** не стирать `$inner.Text` без сохранения

## Рекомендации

- Для диагностики проблем: `$env:SSDIR` — указывает на директорию БД
- `Invoke-VssCommand` автоматически устанавливает `$env:SSDIR` если передан `VssPath`
- Все функции принимают `-Recursive` — передаётся в ss.exe как `-R`
- Команды VSS, доступные через VSS-Utils.ps1:
  - `Get-VssLatest`: получение последней версии
  - `Get-VssStatus`: статус (Checked In/Out)
  - `Get-VssWhoIsUsing`: кто использует (через Status)
  - `Set-VssCheckout`: извлечение с комментарием
  - `Set-VssCheckin`: сохранение с комментарием
  - `Set-VssUndoCheckout`: отмена извлечения
