---
name: plugin-skill
description: Плагины OpenCode проекта AIS: файлы .opencode\plugins\*.js, хуки, интеграция claude_pb/claude_sql, watchdog, сохранение промптов, enforcer PB/SQL. Используй при разработке, настройке или отладке плагинов OpenCode (.js), при вопросах о хуках типов plugin. Не используй для обычных задач.
---

# Плагины OpenCode

> Полный источник: `C:\AIS\AI\Prod\docs\services\plugins.md`

## Общее

Плагины — JavaScript/Node.js модули, расширяют OpenCode. Конфигурация: `opencode.jsonc` → `plugin`. Автообнаружение: `*.ts`/`*.js` в `.opencode\plugin\` и `.opencode\plugins\`.

Плагин экспортирует `default = (input, options?) => Hooks`.

## Хуки

- `event(input)`, `config(cfg)`
- `chat.message`, `chat.params`, `chat.headers`
- `tool.execute.before`, `tool.execute.after`, `tool.definition`
- `command.execute.before`
- `shell.env`, `permission.ask`
- `experimental.chat.messages.transform`, `experimental.chat.system.transform`

Спец-объекты: `tool: { имя: {...} }`, `auth`, `provider`.

## Плагины проекта

| Плагин | Файл | Назначение |
|--------|------|-----------|
| save-prompts | `.opencode\plugins\save-prompts.js` | Автосохранение промптов >20 символов в `temp\user_prompts.log` |
| russian-compaction | `.opencode\plugins\russian-compaction.js` | Русские сводки сжатия сессии |
| claude-code | `.opencode\plugins\claude-code.js` | Инструменты `claude_pb`, `claude_sql` (Claude Code для .sr*/SQL) |
| loop-guard | `.opencode\plugin\loop-guard.js` | Защита от бесконечных циклов правок |
| task-progress | `.opencode\plugin\task-progress.js` | Прогресс задач через todowrite |
| pb-sql-enforcer | `.opencode\plugins\pb-sql-enforcer.js` | Блокировка запрещённых идиом PB/SQL (`iif(`, `??`, `?.`, `=>`) |
| @betterspec/opencode | npm | Улучшенная спецификация промптов |
| @relf108/opencode-watchdog | npm | Scope enforcement, baseline-тесты, commit gate |

## Экономическая выгода

- Автосохранение промптов: восстановление контекста после сбоя
- Русские сводки: экономия токенов на переводе
- Watchdog: предотвращение случайных правок вне scope