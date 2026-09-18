---
description: Запустить пайплайн оркестратора визуализации (A+B → wiki → C → агрегация)
---

Запусти пайплайн визуализации через MCP-оркестратор (инструмент `orchestrator_orchestrate`).

Выполни:
1. `project-a` (Project-Visualization-Dev) и `project-b` (Project-Visualization-BP) — **параллельно** в одной `parallelGroup`;
2. проверка **wiki MCP-сервера** (health-check) перед project-c — оркестратор авто-запустит wiki, если нужно;
3. `project-c` (Project-Visualization-Final) — только после успешного `project-a` и готового wiki;
4. **агрегацию** диаграмм (A+B) + отчётов (C) + маркеров в `C:\AIS\AI\Orchestrator\Final-Report\aggregated_<timestamp>`.

Дождись результата и сообщи кратко: статус каждого проекта, результат health-check wiki, путь к папке агрегированного отчёта и количество скопированных файлов. Если проект провален — укажи причину из `detail`.
