---
name: vss-skill
description: Работа с Microsoft Visual SourceSafe (VSS) в проекте: команды ss.exe, история версий, получение OLDPB, известные ошибки VSS. Используй ТОЛЬКО при работе с VSS, ss.exe, checkout/checkin, истории версий. Не используй для других тем.
---

# Правила работы с VSS

> Полный источник: `C:\AIS\AI\Prod\.opencode\vss-rules.mdc`

## Инструменты

- `ss.exe` — командная утилита VSS (`C:\Program Files (x86)\Microsoft Visual SourceSafe\ss.exe`)
- БД VSS: `\\ren-msksf01\VSS2005\srcsafe.ini`
- `$env:SSDIR` — папка с `srcsafe.ini`
- Авторизация: `-I-Y -Y"user,pass"`

## Основные команды

| Команда | Пример |
|---------|--------|
| Status | `ss.exe Status $/SRC125/gold/lib/obj.srw -I-Y -Y"user,pass"` |
| History | `ss.exe History $/SRC125/gold/lib/obj.srw -I-Y -Y"user,pass"` |
| Get | `ss.exe Get $/SRC125/gold/lib/obj.srw -V5 -I-Y -Y"user,pass" -G` |
| Checkout | `ss.exe Checkout $/SRC125/gold/lib/obj.srw -I-Y -Y"user,pass"` |
| Checkin | `ss.exe Checkin $/SRC125/gold/lib/obj.srw -I-Y -Y"user,pass"` |
| UndoCheckout | `ss.exe UndoCheckout $/SRC125/gold/lib/obj.srw -I-Y -Y"user,pass"` |

## История

Формат вывода History: `***  Version N  ***`, `User: name  Date: DD.MM.YY`. Парсинг версии: `\*{3,}\s*Version\s+(\d+)\s*\*{3,}`, автора: `^User:\s*(\S+)`.

## Получение OLDPB из VSS

1. **Занят мной** → VSS History, последняя версия (Git_* использовать НЕЛЬЗЯ — там может лежать изменённая версия)
2. **Не занят мной** → Git_* (если есть) → PB_Main

## Известные ошибки

| Баг | Причина | Решение |
|-----|---------|---------|
| Bug-VSS-001: NativeCommandError при `& $exe ... 2>&1` | stderr оборачивается в ErrorRecord при `$ErrorActionPreference="Stop"` | `System.Diagnostics.ProcessStartInfo` + `Process.Start()` вместо `&` |
| Bug-VSS-002: `Sort-Object Version` даёт случайный порядок | hashtable: обращение к .NET-свойству | `Sort-Object { $_.Version } -Descending` |
| Bug-VSS-003: `GetFileName('$/...obj.sr*')` возвращает `sr*` | VSS использует wildcard `sr*` | Удалять `\*$` перед `GetFileNameWithoutExtension` |
| Bug-VSS-004: `& $exe Get` в функции не создаёт файл | область видимости $env:SSDIR | Всегда `System.Diagnostics.Process` для `ss.exe Get` |

## Скрипты

- `C:\AIS\AI\Prod\scripts\VSS-History.ps1` — функции истории (вкл. `Find-VssOldPbPath`)
- `C:\AIS\AI\Prod\scripts\VSS-Utils.ps1` — Checkout/Checkin/Status