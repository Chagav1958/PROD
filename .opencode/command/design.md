# ИЗМДИЗАЙН — Apply Design Changes

Синхронизирует дизайн всех окон проекта с шаблонными изменениями.

## Использование

```
ИЗМДИЗАЙН [тир] [действие] [файл_изменений]
```

## Параметры

| Параметр | Описание | Пример |
|----------|----------|--------|
| `тир` | Тип дизайна: `APPL2`, `APPL3`, `APPL`, `Standard`, `ALL` | `APPL2` |
| `действие` | `отчёт` (ShowReport) или `применить` (ApplyTemplate) | `отчёт` |
| `файл_изменений` | JSON-файл с новыми значениями параметров | `changes.json` |

## Примеры

### Показать все окна APPL2
```
ИЗМДИЗАЙН APPL2
```

### Показать все окна всех типов
```
ИЗМДИЗАЙН ALL
```

### Применить изменения из файла
```
ИЗМДИЗАЙН APPL применить changes\appl_new_style.json
```

## Формат файла изменений (JSON)

```json
{
    "APPL2_CornerRadius": "50",
    "APPL2_Color": "#2A4A70",
    "APPL2_ProgressTop": "#1A3A60",
    "APPL2_ProgressBottom": "#2B6CB0",
    "APPL2_ProgressStepTop": "#0F2440",
    "APPL2_ProgressStepBottom": "#1A5276",
    "APPL2_ProgressCornerRadius": "5",
    "APPL_GlossyTop": "#3A6090",
    "APPL_CornerRadius": "14"
}
```

## Тиры дизайна

### APPL2
Овальное окно (CornerRadius=60), AllowsTransparency=True, WindowStyle=None,
двухслойный 3D-текст (#1A3A60 + белый смещённый слой),
кастомный title bar с кнопками ━ ▣ ✕.
ResizeMode=CanResizeWithGrip (системный grip).
Прогресс-бары: Apply-GlossyProgressStyle, CornerRadius=5, градиент #1A3A60→#2B6CB0 (фаза) / #0F2440→#1A5276 (шаг).

Окна: МОРДА (Prod-GUI.ps1), Show-TestMsg.ps1 (ОТЕСТ), Show-Abbreviations.ps1 (СОКР),
Settings History (Prod-GUI.ps1)

### APPL3
APPL2 + невидимая resize-область (30×30, цвет #05FFFFFF) в правом нижнем углу,
динамическая разметка Grid (Row * / Auto) — таблица заполняет, кнопки внизу,
сохранение/восстановление размера и позиции окна (config/fixshow_layout.json).

Окна: Show-OpStatus.ps1 (FIXSHOW)

### APPL
MetroWindow + Apply-GrayWindowStyle (серый градиент + тень),
Border CornerRadius=12, msgBorder CornerRadius=12,
Apply-GlossyButtonStyle (градиент #2A5080 → #87CEEB).

Окна: Show-ResultPopup, Show-ValidationErrorWindow, Show-VssStatusTableWindow,
Show-PbObjectTableWindow, Show-ProdCompareResult, Show-DiffSelectWindow,
Show-PbCompareTableWindow — все в bin\Prod-GUI.ps1

### Standard
MetroWindow с Border CornerRadius=12, без Apply-GrayWindowStyle.

Окна: Save-Snapshot.ps1, VSS-History-Show.ps1, Show-Prompts.ps1

## Примечания

- Все окна перечислены в `config/ui_design_registry.json`
- Перед применением изменений запустите `ИЗМДИЗАЙН ALL отчёт`
- После применения — запустите тесты: `test_gui_params.ps1`
- ОТЕСТ (Show-TestMsg.ps1) — эталонный образец APPL2
