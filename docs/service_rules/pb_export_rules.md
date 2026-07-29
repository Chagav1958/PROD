# Правила сервиса PB-экспорт (PowerBuilder Export)

## Состав сервиса

| Файл | Назначение |
|------|------------|
| `scripts\AIS_export.ps1` | Основной скрипт: экспорт объектов из PBL через pbldump |
| `bin\Export.bat` | Универсальная BAT-обёртка с параметрами SRC, OUT, PBT |
| `bin\AIS_export.bat` | BAT с жёсткими путями (Main → PB) |
| `bin\AIS_export_flexible.bat` | BAT с параметрами SRC, OUT, PBT (аналог Export.bat) |

## Внешние зависимости

- **pbldump.exe** — утилита экспорта PowerBuilder-объектов из PBL
  - Ожидается в `bin\pbldump-1.3.1stable\PblDump.exe`
  - **Важно:** не входит в проект, должна быть установлена отдельно
- **PBL** — библиотеки PowerBuilder в `C:\SRC125\gold` (Main) или `C:\Work\gold` (Current)
- **PBT** — файл проекта PowerBuilder (содержит LibList)

## Известные ошибки и их предотвращение

### AIS_export.ps1

1. **PowerShell 5.1 — `$PSScriptRoot` может быть пустым**
   - Если скрипт выполняется через `powershell -File` из BAT — `$PSScriptRoot` заполняется
   - Если скрипт выполняется вручную через `.\script.ps1` — тоже заполняется
   - **Правило:** не полагаться на `$PSScriptRoot` при вызове скрипта из нестандартных сред

2. **LibList в PBT-файле**
   - Парсинг: `$raw -match 'LibList\s+"([^"]+)"'`
   - Строка имеет формат: `LibList "lib1.pbl;lib2.pbl;..."`
   - Разделитель `;`
   - **Ошибка:** если формат отличается — `$matches[1]` будет `$null`, функция кинет `throw`

3. **Полные пути в LibList**
   - `GetFullPath((Join-Path $MisRoot $rel))` — разрешает относительные пути относительно MisRoot
   - **Важно:** если LibList содержит полные пути — будет дублирование с MisRoot

4. **pbldump exit code**
   - `$null -eq $LASTEXITCODE` — защита от ситуаций, когда `$LASTEXITCODE` не установлен
   - **Правило:** проверять `$null -eq $LASTEXITCODE` перед `[int]$LASTEXITCODE`

5. **Удаление `HA`-префикса**
   - `Remove-HaPrefix` — проверяет первые 4 байта файла на `HA` и удаляет их
   - Это legacy-формат PowerBuilder
   - **Правило:** функция удаления префикса должна быть вызвана для всех .sr* файлов

6. **Декодирование HEX-текста**
   - `Convert-HexEncodedText` — ищет `$$HEX<length>$$<hex>$$ENDHEX$$` и декодирует в UTF-16
   - Это русский текст, закодированный в hex-формате
   - **Правило:** при изменении экспорта не забывать про пост-обработку .sr* файлов

7. **Локальный overlay SCC-файлов**
   - `Copy-LocalSrOverlay` — копирует .sr* файлы из папки с PBL (SCC checkout) в экспорт
   - Это перекрывает дамп pbldump
   - **Правило:** overlay должен выполняться после pbldump, чтобы локальные изменения не были потеряны

### AIS_export.bat / Export.bat / AIS_export_flexible.bat

8. **Путь к PowerShell 5.1**
   - `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` — явный путь к Windows PowerShell
   - **Важно:** НЕ использовать просто `powershell.exe` — может запуститься PowerShell 7 (Core)

9. **`%~dp0` для путей к pbldump и AIS_export.ps1**
   - `%~dp0pbldump-1.3.1stable\PblDump.exe` — путь относительно BAT-файла
   - **Правило:** pbldump должен находиться в `bin\pbldump-1.3.1stable\`

10. **Чистка артефактов Export.bat**
    - `for %%E in (pbw pbt pbp pbr ini cfg txt log sql)` — копируются вспомогательные файлы из SRC в OUT

11. **Отсутствие `PBT_NAME` в AIS_export.bat**
    - В `AIS_export.bat` (hardcoded) `PBT_NAME` не задана — переменная пустая
    - Команда `"%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AIS_export.ps1" -MisRoot "%SRC%" -OutRoot "%OUT%" -PbldumpExe "%PBLDUMP%" -PbtPath "%SRC%\%PBT_NAME%.pbt" -LogDir "%LOG%"`
    - Результат: `-PbtPath "C:\SRC125\gold\.pbt"` — несуществующий файл → ошибка
    - **Исправление:** `AIS_export.bat` явно не работоспособен без `PBT_NAME`, нужно использовать `Export.bat` или `AIS_export_flexible.bat`

## Рекомендации

- Для экспорта Main использовать: `Export.bat C:\SRC125\gold C:\AIS\AI\Prod\PB_Main gold`
- Для экспорта Current использовать: `Export.bat C:\Work\gold C:\AIS\AI\Prod\PB_Current gold`
- Логи экспорта сохраняются в `bin\Log\` (временная папка рядом с исполняемыми файлами)
- Скрипт `Export.bat` является универсальной заменой для `AIS_export.bat` и `AIS_export_flexible.bat`
