---
name: gui-wpf-skill
description: СТАНДАРТ2 — единый дизайн диалоговых окон (ДО) и сообщений проекта: WPF окно, Title bar, кнопки, Progress Bar, DataGrid, поиск, автотестирование --autotest, tech_journal. Используй ТОЛЬКО при разработке/правке GUI-окон (WPF, C#, Python tkinter замена, PS), ДО сервисов, стандартов СТАНДАРТ1/СТАНДАРТ2. Не используй для backend-логики.
---

# СТАНДАРТ2 — Дизайн диалоговых окон (ДО)

> Полный источник: `C:\AIS\AI\Prod\.opencode\standard2-gui.mdc`
> Эталон: `C:\AIS\AI\Prod\scripts\Show-Appl2Standard.exe` (исходники — папка `Show-Appl2Standard-CS\`)
> Единый документ требований МОРДА/МОРДА2: `C:\AIS\AI\Prod\docs\morda-requirements.md`

## Общие принципы

1. Технология любая (C#, Python, PS), но внешний вид — СТАНДАРТ2
2. Окно непрозрачное; полупрозрачность — только Title bar
3. Элементы (кнопки, ПБ) — полупрозрачные (альфа `#CC` = 80% или `#80` = 50%)
4. Title bar темнее окна и полупрозрачный

## Окно

`AllowsTransparency=True`, `WindowStyle=None`, `Background=#E8ECF0`, `ResizeMode=CanResizeWithGrip`, `Topmost=True`, размер 520×580.
Скругление углов — `CreateRoundRectRgn` + `SetWindowRgn` (радиус 18px). Тень — `DropShadowEffect`. Рамка `BorderBrush=#1A3A60 BorderThickness=1`.

## Title bar

Высота 40px, `Background=#807080B0` (50% deep blue-gray), `CornerRadius=17,17,0,0`, нижняя рамка `#1A3A60` `0,0,0,1`. Drag: `MouseLeftButtonDown → DragMove()`, DoubleClick → `ToggleMaximize()`.
Текст 3D (нижний слой белый+смещение Opacity 0.9, верхний `#1A3A60`). Шрифт Segoe UI 14px Bold.
Кнопки окна (40×36): Свернуть `━`, Развернуть `☐`, Закрыть `✕`.

## Кнопки

**Primary** (OK/Сохранить): `CornerRadius=10`, рамка `#CC0F3050`, градиент 3-stop `#CC9DC8F0→#CC3B7BBF→#CC1A4A7A`, блик сверху, текст White Bold 11px, размер 120×38.
**Secondary** (Отмена): рамка `#CC404040`, градиент `#CCD0D0D0→#CC909090→#CC606060`.
**Small**: 30×26, FontSize=11.

## Progress Bar (ПБ)

Height 18px, рамка `#CC0F3050` Padding=1.5, трек `#E2E8F0`. Indicator: `PART_Track`=Grid (вся ширина), `PART_Indicator`=Border HorizontalAlignment=Left, градиент 4-stop `#CCB8D8F8→#CC3B7BBF→#CC1A4A7A→#CC0F3050`, правая рамка `#CC1A3A60`, блик и тень снизу.

## DataGrid + фиксация низа (КРИТИЧНО)

- DataGrid в строке `Height="*"` (заполняет остаток, вертикальный скролл)
- ПБ и кнопки — в строках `Height="Auto"` ПОСЛЕ DataGrid → всегда внизу, на фикс. расстоянии
- `AlternatingRowBackground=#F5F7FA`, `RowBackground=White`, `BorderBrush=#CBD5E0`, `SelectionMode=Single, FullRow`
- Колонки фиксированные, сумма > ширины (горизонтальный скролл активен): Объект 180, Тип 140, Статус 100, Описание 280

## Поиск (панель)

Счётчик «N - M» (#4A5568 11px), поле Height=26, кнопки ▼/▲ (Glossy3DButtonSmall), Enter → search_down. Поиск case-insensitive по всем колонкам с подсветкой.

## Поля ввода

Рамка `#CBD5E0`, CornerRadius=10, Padding=6,4, шрифт 11px, подпись 10px `#4A5568`.

## Цветовая схема

Окно `#E8ECF0`; title `#807080B0`; рамка/текст заголовка `#1A3A60`; поля/таблица `#CBD5E0`; текст `#4A5568`; Primary `#CC0F3050`; Secondary `#CC404040`; ПБ трек `#E2E8F0`.

## Технический журнал (tech_journal)

Каждое ДО создаёт `tech_journal_yyyyMMdd_HHmmss.log` рядом с exe. Формат `[HH:mm:ss.fff] [LEVEL] сообщение`; уровни INFO/ERROR/CLICK/AUTOTEST. Обязательно: `[INFO] Window constructed`, CLICK-записи взаимодействия, ERROR в try-catch всех обработчиков, потокобезопасность (lock).

## Автотестирование (ОБЯЗАТЕЛЬНО)

Каждое ДО поддерживает `--autotest <file>` (команды построчно, пауза 300ms, автозакрытие через 500ms).

Команды: `log`, `wait`, `click` (ok/cancel/search_down/search_up/min/max/close), `set_text`, `set_pwd`, `set_search`, `search_down/up`, `move`, `resize`, `scroll`, `close`.

**3 обязательных этапа перед сдачей:** 1) тест открытия (tech_journal создан, нет ERROR), 2) тест новой функциональности (каждый пункт ТЗ), 3) регрессия (базовые функции не сломаны, нет исключений). Отчёт в формате «Результаты тестирования» с галочками ✅.

## Сборка

C# WPF: `dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true ...` (размер ~150-180 KB; `--self-contained true` даёт ~150 MB — НЕ использовать). Python: `pyinstaller --onefile --windowed`.

## Дополнительно

- СТАНДАРТ1 (старая) — см. `scripts\Show-Appl2Standard.ps1`
- Правила тестирования GUI: `C:\AIS\AI\Prod\.opencode\gui-testing-rule.mdc`
- Правила GUI-сервиса PowerShell: `C:\AIS\AI\Prod\docs\service_rules\gui_rules.md`