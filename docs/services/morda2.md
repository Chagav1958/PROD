# МОРДА2 — главное окно подготовки релизов

> **Версия:** 1.0 от 07.08.2026
> **Родительский том:** [Главный том документации](../master-index.md)

---

## 1. Назначение

МОРДА2 (СТАНДАРТ2) — главное WPF-окно автоматизации подготовки релизов AIS. Предоставляет 19 операций, панель параметров, прогресс-бары и окно результата.

**Файл:** `bin\Prod-GUI_STANDART2.ps1` (1664 строки)
**Хелперы:** `scripts\Standard2-Helpers.ps1` (600 строк)
**Техжурнал:** `%TEMP%\tech_journal_*.log`

---

## 2. Структура окна (сверху вниз)

| Ряд | Элемент | Назначение |
|-----|---------|-----------|
| 0 | ComboBox `cmbOp` | Выбор операции (19 пунктов) |
| 0 | `txtDesc` | Описание выбранной операции |
| 1 | `ParamsPanel` | Динамическая панель параметров |
| 2 | **ПБ** (2 уровня) | Верхний (типы), нижний (объекты) |
| 3 | Кнопки | Выполнить, История, Выход |

---

## 3. Прогресс-бары (ПБ)

### 3.1. Дизайн

Стиль: **GlossyProgress** (как в Prod-GUI.ps1):
- Вертикальный градиент `#2A5080 → #87CEEB`
- Скругление 5px, глянцевый блик
- Высота 14px
- Лейблы слева (140px, Foreground `#4A5568`)
- Фон панели: `#E2E8F0`, верхняя граница `#CBD5E0`

### 3.2. Механизм передачи данных

```powershell
# Синхронизированные хеши (общие для UI-потока и Runspace)
$syncPhase = [hashtable]::Synchronized(@{Value=0; Text=''})
$syncStep  = [hashtable]::Synchronized(@{Value=0; Text=''})

# Хендлер операции (в Runspace)
$script:PhaseProgress.Value = 50
$script:PhaseProgress.Text = "Тип: Процедуры"

# UI-таймер (чтение напрямую, каждые 300мс)
$script:PhaseBar.Value = $script:PhaseProgress.Value
$script:PhaseLabel.Text = $script:PhaseProgress.Text
```

**Нижний ПБ** стартует в `IsIndeterminate = true` (бегущая полоса) и переключается в обычный режим при получении `StepProgress.Value > 0`.

---

## 4. 19 операций

| № | Имя | Русское название | Пароль | Обработчик |
|---|-----|-----------------|--------|-----------|
| 0 | Settings | Настройки параметров | нет | `Invoke-OpSettings` |
| 1 | Run Tests | Запуск тестов | нет | `Invoke-OpRunTests` |
| 2 | Export Service | Export Service | нет | `Invoke-OpExportService` |
| 3 | Collect PROD Objects | Собрать объекты для ПРОД | нет | `Invoke-OpCollectProd` |
| 4 | Export PB | Выгрузка PB | нет | `Invoke-OpExportPb` |
| 5 | Compare PB | Сравнение PB | нет | `Invoke-OpComparePb` |
| 6 | **SQL Export** | Выгрузка SQL | **да** | `Invoke-OpSqlExport` |
| 7 | Compare SQL | Сравнение SQL | **да** | `Invoke-OpCompareSql` |
| 8 | Compare & Verify | Сравнение и проверка | **да** | `Invoke-OpCompareVerify` |
| 9 | Create RFC | Создание RFC в Jira | **да** | `Invoke-OpCreateRfc` |
| 10 | Jira Release Comment | Комментарий в Jira | **да** | `Invoke-OpJiraComment` |
| 11 | VSS: Get Latest | VSS: Получить | нет | `Invoke-OpVssGetLatest` |
| 12 | VSS: Check Status | VSS: Статус | нет | `Invoke-OpVssCheckStatus` |
| 13 | VSS: Who Is Using | VSS: Кто использует | нет | `Invoke-OpVssWhoIsUsing` |
| 14 | VSS: Checkout | VSS: Извлечь | нет | `Invoke-OpVssCheckout` |
| 15 | VSS: Checkin | VSS: Сохранить | нет | `Invoke-OpVssCheckin` |
| 16 | VSS: Undo Check Out | VSS: Отмена | нет | `Invoke-OpVssUndo` |
| 17 | VSS: Object History | VSS: История | нет | `Invoke-OpVssHistory` |

---

## 5. Ключевые технические решения

### 5.1. Асинхронное выполнение (Runspace)

Операции выполняются в фоновом Runspace через `Start-OpAsync`, НЕ блокируя UI-поток. DispatcherTimer опрашивает завершение и прогресс каждые 300мс.

### 5.2. Синхронизированные хеши для ПБ

Вместо `SessionStateProxy.GetVariable` (возвращает копию) используются `[hashtable]::Synchronized()` — единый объект в памяти для UI и Runspace. Любое изменение мгновенно видно.

### 5.3. Защита от мультиэкземплярности

При запуске проверяется `MainWindowTitle = "МОРДА — Подготовка релизов"`. Второй экземпляр не создаётся (`exit 0`).

### 5.4. Скругление углов и перетаскивание

C# `RoundedWindow` (CreateRoundRectRgn, SetWindowRgn, радиус 36). Перетаскивание через `WM_NCHITTEST` (зона заголовка Y < 42px).

---

## 6. Плагины и расширения

| Плагин | Назначение |
|--------|-----------|
| `@betterspec/opencode` | Улучшенная спецификация промптов |
| `@relf108/opencode-watchdog` | Защита правок (scope, baseline, commit gate) |
| `save-prompts.js` | Автосохранение промптов |
| `russian-compaction.js` | Сводки сессий на русском |
| `claude-code.js` | Интеграция с Claude Code для PB/SQL |
| `loop-guard.js` | Защита от бесконечных циклов |
| `task-progress.js` | Отслеживание прогресса |

---

## 7. Экономическая выгода

| Показатель | Ручной способ | МОРДА2 | Экономия |
|-----------|--------------|--------|----------|
| Выгрузка SQL (1046 процедур) | ~4 часа | ~3 минуты | **98.8%** |
| Сравнение PB-объектов | ~2 часа | ~30 секунд | **99.6%** |
| Создание RFC в Jira | ~30 минут | ~10 секунд | **99.4%** |
| VSS: Check Status (100+ объектов) | ~20 минут | ~10 секунд | **99.2%** |
| Выгрузка PB (2617 объектов) | ~6 часов | ~5 минут | **98.6%** |

**Годовая экономия** (при 20 релизах в год): **~200 часов** или **~25 рабочих дней** аналитика.
