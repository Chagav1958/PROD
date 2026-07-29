# Руководство по TaskPlan — управление объёмными задачами

## Назначение

TaskPlan — сервис для управления планами объёмных задач в проекте AIS.

## Архитектура

```
Show-TaskPlanGUI.ps1   → ДО (WPF, 3 вкладки)
TaskPlan-Tracker.ps1   → ядро: ПЛАН_РЕАЛИЗАЦИИ.txt + plan_state.json
TaskPlan-Manager.ps1   → диспетчер: task_index.json
TaskPlan-Tests.ps1     → 15 автотестов
```

## Быстрый старт

### Запуск ДО
```powershell
TaskPl
powershell -NoLogo -File scripts\Show-TaskPlanGUI.ps1 -TaskName SYBASE-12345
```

### Создание плана
1. Вкладка «Управление»
2. Имя задачи — ввести или выбрать из истории
3. Цель (Goal) — описание
4. Этапы — по одному на строку: `Текст этапа` или `Текст|Исполнитель`
5. Кнопка «Новый план»

## Трекер напрямую
```powershell
& scripts\TaskPlan-Tracker.ps1 -Action new -TaskName TASK-1 `
    -Goal "Описание" -Stages @("S1","S2|llama-3-70b","S3") -Force
```

## Диспетчер задач
```powershell
& scripts\TaskPlan-Manager.ps1 -Action create -Name TASK-2 -Prompt "Описание"
& scripts\TaskPlan-Manager.ps1 -Action switch -Name TASK-2
```

## Поля ДО

| Поле | Тип | Описание |
|------|-----|----------|
| Имя задачи | ComboBox + ввод | История из task_index.json |
| Корень задач | TextBox | C:\AIS\1 Release или C:\AIS\AI\Prod\tasks |
| Цель (Goal) | TextBox | Описание задачи |
| Этапы | Multi-line | По одному на строку |
| LLM / исполнитель | ComboBox | Бесплатные первыми |
| Статус этапа | ComboBox | не начато / в работе / готово / отложено |
| Номер этапа | TextBox | 1-based |

## Статусы этапов

| Чек-бокс | Статус | Значение |
|----------|--------|----------|
| [ ] | todo | Не начато |
| [~] | wip | В работе |
| [x] | done | Готово |
| [!] | defer | Отложено на дорогую LLM |

## Стратегия LLM
- Основная обработка — дешёвые LLM (deepseek-v3, llama-3-70b, gpt-4o-mini)
- Дорогая LLM — только для [!]-этапов, только с готовым брифом
- Оценка применимости в DLLM — колонка PROD (0–100)